-- inbox.sql — support mailbox. Emails sent to any @instantwins.co.uk address arrive through Resend Receiving -> /api/inbound
-- and land in the same support threads as site messages. Admin replies go out by email (and show on the site for members).
alter table messages alter column user_id drop not null;
alter table messages add column if not exists channel text not null default 'site';
alter table messages add column if not exists email text;
alter table messages add column if not exists from_name text;
alter table messages add column if not exists subject text;
alter table messages add column if not exists msg_id text;
alter table messages add column if not exists read_at timestamptz;
create unique index if not exists messages_msg_id on messages(msg_id) where msg_id is not null;
create index if not exists messages_email on messages(lower(email));

-- inbound email -> message (idempotent on the mail's Message-ID)
create or replace function iw_inbound_mail(p_from text, p_name text, p_subject text, p_body text, p_msg_id text, p_resend_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_email text; v_uid uuid; v_id bigint;
begin
  v_email := lower(trim(p_from));
  if p_msg_id is not null and exists (select 1 from messages where msg_id=p_msg_id) then return jsonb_build_object('dup',true); end if;
  select id into v_uid from users where lower(email)=v_email limit 1;
  insert into messages (user_id, sender, body, channel, email, from_name, subject, msg_id)
    values (v_uid, 'user', left(coalesce(nullif(trim(p_body),''),'(no text)'),8000), 'email', v_email, left(coalesce(p_name,''),120), left(coalesce(p_subject,''),200), coalesce(p_msg_id, 'resend:'||p_resend_id))
    returning id into v_id;
  return jsonb_build_object('id',v_id,'user',v_uid is not null);
end $$;

-- threads: one per member, or per outside email address
create or replace function iw_admin_threads(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return (select coalesce(jsonb_agg(t order by (t->>'unread')::int desc, t->>'last_at' desc),'[]'::jsonb) from (
    select jsonb_build_object('key', g.key, 'name', coalesce(u.name, nullif(g.from_name,''), g.mail), 'email', coalesce(u.email, g.mail), 'member', u.id is not null,
             'last_at', g.last_at, 'count', g.n, 'unread', g.unread,
             'subject', (select x.subject from messages x where coalesce(x.user_id::text,'mail:'||lower(x.email)) = g.key and coalesce(x.subject,'')<>'' order by x.created_at desc limit 1),
             'channel', case when g.any_email then 'email' else 'site' end) as t
      from (select coalesce(m.user_id::text, 'mail:'||lower(m.email)) as key, m.user_id as uid, lower(m.email) as mail, max(m.from_name) as from_name,
                   max(m.created_at) as last_at, count(*) as n, count(*) filter (where m.sender='user' and m.read_at is null) as unread, bool_or(m.channel='email') as any_email
              from messages m group by 1,2,3) g
      left join users u on u.id=g.uid) s);
end $$;

create or replace function iw_admin_thread(p_token uuid, p_key text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_out jsonb;
begin
  perform iw_admin(p_token);
  if p_key like 'mail:%' then
    update messages set read_at=now() where user_id is null and lower(email)=substr(p_key,6) and sender='user' and read_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('sender',sender,'body',body,'at',created_at,'channel',channel,'subject',subject) order by created_at),'[]'::jsonb) into v_out from messages where user_id is null and lower(email)=substr(p_key,6);
  else
    update messages set read_at=now() where user_id=p_key::uuid and sender='user' and read_at is null;
    select coalesce(jsonb_agg(jsonb_build_object('sender',sender,'body',body,'at',created_at,'channel',channel,'subject',subject) order by created_at),'[]'::jsonb) into v_out from messages where user_id=p_key::uuid;
  end if;
  return v_out;
end $$;

-- reply: stored on the thread, and emailed to the person
create or replace function iw_admin_reply(p_token uuid, p_key text, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_email text; v_subject text; v_html text; v_body text;
begin
  perform iw_admin(p_token);
  v_body := left(trim(p_body),4000);
  if v_body = '' then raise exception 'empty reply'; end if;
  if p_key like 'mail:%' then v_email := substr(p_key,6); else v_uid := p_key::uuid; select email into v_email from users where id=v_uid; end if;
  select subject into v_subject from messages where coalesce(user_id::text,'mail:'||lower(email))=p_key and coalesce(subject,'')<>'' order by created_at desc limit 1;
  insert into messages (user_id, sender, body, channel, email, subject) values (v_uid, 'admin', v_body, 'email', v_email, v_subject);
  v_html := '<p>'||replace(replace(replace(v_body,'&','&amp;'),'<','&lt;'),E'\n','<br>')||'</p><p>Reply to this email to carry on the conversation'||case when v_uid is not null then ', or see it in <a href="https://instantwins.co.uk/support.html">your support thread</a>' else '' end||'.</p>';
  v_subject := case when v_subject is null or v_subject='' then 'Reply from InstantWins support' when lower(v_subject) like 're:%' then v_subject else 'Re: '||v_subject end;
  insert into outbox (user_id, to_email, subject, html) values (v_uid, v_email, v_subject, v_html);
  return jsonb_build_object('ok',true,'emailed',v_email);
end $$;

-- member writes on the site: unchanged, but tell admin by email if MAIL_ADMIN_TO is set in site_settings
create or replace function iw_msg_send(p_token uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_admin text;
begin
  u := iw_user(p_token);
  if length(trim(p_body)) < 2 then raise exception 'say a little more'; end if;
  if (select count(*) from messages where user_id=u.id and sender='user' and created_at > now()-interval '1 hour') >= 20 then raise exception 'slow down a little'; end if;
  insert into messages (user_id, sender, body, channel, email, from_name) values (u.id, 'user', left(trim(p_body),4000), 'site', u.email, u.name);
  v_admin := (select value from site_settings where key='admin_notify_email');
  if v_admin is not null and v_admin<>'' then
    insert into outbox (user_id, to_email, subject, html) values (null, v_admin, 'Support: '||coalesce(u.name,u.email), '<p><b>'||coalesce(u.name,'')||'</b> ('||u.email||') wrote on the site:</p><p>'||replace(replace(replace(left(p_body,2000),'&','&amp;'),'<','&lt;'),E'\n','<br>')||'</p><p><a class="btn" href="https://instantwins.co.uk/admin.html#support">Open in admin</a></p>');
  end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_inbox_count(p_token uuid) returns int
language plpgsql security definer set search_path = public, extensions as $$
begin perform iw_admin(p_token); return (select count(*)::int from messages where sender='user' and read_at is null); end $$;

grant execute on function iw_inbound_mail(text,text,text,text,text,text), iw_admin_threads(uuid), iw_admin_thread(uuid,text), iw_admin_reply(uuid,text,text), iw_msg_send(uuid,text), iw_admin_inbox_count(uuid) to service_role;
notify pgrst, 'reload schema';
