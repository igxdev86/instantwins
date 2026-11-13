-- admin-mail.sql — send email from the admin: one person (from the inbox) or a broadcast to everyone who opted in.
alter table users add column if not exists marketing_ok boolean not null default false;
alter table users add column if not exists marketing_at timestamptz;

-- consent: set from sign-up / onboarding / account page
create or replace function iw_set_profile(p_token uuid, p_county text, p_publish boolean, p_marketing boolean default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  update users set county=nullif(trim(coalesce(p_county,'')),''), publish_wins=coalesce(p_publish,true),
    marketing_ok=coalesce(p_marketing, marketing_ok), marketing_at=case when p_marketing is not null and p_marketing is distinct from marketing_ok then now() else marketing_at end
    where id=u.id;
  return jsonb_build_object('ok',true);
end $$;
drop function if exists iw_set_profile(uuid,text,boolean);

create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,'marketing_ok',coalesce(u.marketing_ok,false),'name',coalesce(u.name,''),'dob',to_char(u.dob,'YYYY-MM-DD'),
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'onboard',(u.dob is null or coalesce(u.name,'')='' or u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;

-- one-off email to a member or any address; also kept on their support thread
create or replace function iw_admin_mail_one(p_token uuid, p_to text, p_subject text, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_email text; v_html text;
begin
  perform iw_admin(p_token);
  if length(trim(coalesce(p_subject,'')))<2 or length(trim(coalesce(p_body,'')))<2 then raise exception 'subject and message needed'; end if;
  select id, email into v_uid, v_email from users where lower(email)=lower(trim(p_to)) or acct_no=upper(trim(p_to)) limit 1;
  if v_email is null then
    if lower(trim(p_to)) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'no member with that account number or email'; end if;
    v_email := lower(trim(p_to));
  end if;
  v_html := '<p>'||replace(replace(replace(trim(p_body),'&','&amp;'),'<','&lt;'),E'\n','<br>')||'</p><p>Reply to this email if you have any questions.</p>';
  insert into outbox (user_id, to_email, subject, html) values (v_uid, v_email, left(trim(p_subject),140), v_html);
  insert into messages (user_id, sender, body, channel, email, subject) values (v_uid, 'admin', left(trim(p_body),4000), 'email', v_email, left(trim(p_subject),200));
  return jsonb_build_object('ok',true,'to',v_email,'member',v_uid is not null);
end $$;

-- broadcast: audience 'all' = everyone who opted in; 'buyers' = opted in and bought in the last 90 days; 'test' = admins only
create or replace function iw_admin_mail_all(p_token uuid, p_subject text, p_body text, p_audience text default 'all') returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_html text; v_n int;
begin
  perform iw_admin(p_token);
  if length(trim(coalesce(p_subject,'')))<2 or length(trim(coalesce(p_body,'')))<2 then raise exception 'subject and message needed'; end if;
  v_html := '<p>'||replace(replace(replace(trim(p_body),'&','&amp;'),'<','&lt;'),E'\n','<br>')||'</p><p style="font-size:12px;color:#7c8190">You are getting this because you ticked "email me about new rounds and prizes". <a href="https://instantwins.co.uk/account.html#profile">Turn it off</a> any time in your account.</p>';
  insert into outbox (user_id, to_email, subject, html)
    select u.id, u.email, left(trim(p_subject),140), v_html from users u
     where u.closed_at is null and u.email is not null
       and case p_audience when 'test' then coalesce(u.is_admin,false)
                           when 'buyers' then u.marketing_ok and exists (select 1 from ledger l where l.user_id=u.id and l.delta_p<0 and l.created_at>now()-interval '90 days')
                           else u.marketing_ok end;
  get diagnostics v_n = row_count;
  insert into announcements (title, body) select left(trim(p_subject),140), left(trim(p_body),2000) where p_audience<>'test';
  return jsonb_build_object('queued',v_n);
end $$;

create or replace function iw_admin_mail_counts(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object('members',(select count(*) from users where closed_at is null),'opted_in',(select count(*) from users where closed_at is null and marketing_ok),
    'buyers',(select count(*) from users u where u.closed_at is null and u.marketing_ok and exists (select 1 from ledger l where l.user_id=u.id and l.delta_p<0 and l.created_at>now()-interval '90 days')),
    'pending',(select count(*) from outbox where sent_at is null));
end $$;
grant execute on function iw_set_profile(uuid,text,boolean,boolean), c2_mine(uuid), iw_admin_mail_one(uuid,text,text,text), iw_admin_mail_all(uuid,text,text,text), iw_admin_mail_counts(uuid) to service_role;
notify pgrst, 'reload schema';
