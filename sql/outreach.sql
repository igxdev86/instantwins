-- outreach.sql — affiliate prospecting. Store sites found in Ahrefs, find a contact, send a welcome, track status.
create table if not exists outreach (
  domain text primary key, name text, dr int, traffic int, source text, email text, contact_url text,
  status text not null default 'new' check (status in ('new','contacted','replied','joined','no')),
  notes text, aff_code text, emails_found text[], scanned_at timestamptz, contacted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz);
create index if not exists outreach_status on outreach(status);
alter table outreach enable row level security;

insert into site_settings (key,value) values
 ('outreach_subject','Partner with InstantWins.co.uk — £10 per player, free-entry prize competition'),
 ('outreach_body','Hi {{first}},

I run InstantWins.co.uk, a new UK prize competition site: 25p tickets, £1,185,000 in prizes per round, a free postal entry route, and a ticket reader that is actually fun to watch. I came across {{site}} and think your readers would like it.

We pay partners £10 CPA for every new player who deposits and buys a ticket. No revenue share, no negative carryover, paid monthly by bank transfer. Creatives, a rotating banner and a demo you can embed are ready to go.

Programme details: {{link}}

If you are up for it, reply with the code you would like (e.g. your site name) and I will set you up today.

Ryan Hughes
InstantWins.co.uk · IGX Ltd')
on conflict (key) do nothing;

create or replace function iw_admin_outreach_list(p_token uuid, p_status text default null, p_q text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(to_jsonb(o) order by case o.status when 'replied' then 0 when 'new' then 1 when 'contacted' then 2 when 'joined' then 3 else 4 end, o.dr desc nulls last, o.domain)
                      from outreach o where (p_status is null or p_status='' or o.status=p_status) and (p_q is null or p_q='' or o.domain ilike '%'||p_q||'%' or coalesce(o.email,'') ilike '%'||p_q||'%')),'[]'::jsonb),
    'counts', (select jsonb_object_agg(status,n) from (select status, count(*) n from outreach group by status) c),
    'subject', (select value from site_settings where key='outreach_subject'),
    'body', (select value from site_settings where key='outreach_body'));
end $$;

-- import: array of {domain, dr, traffic, name, email, source}
create or replace function iw_admin_outreach_import(p_token uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; v_dom text; n int := 0;
begin
  perform iw_admin(p_token);
  for r in select * from jsonb_array_elements(p_rows) loop
    v_dom := lower(regexp_replace(regexp_replace(coalesce(r->>'domain',''),'^https?://(www\.)?',''),'/.*$',''));
    v_dom := regexp_replace(v_dom,'^www\.','');
    -- a contact with no site of their own is keyed by their email address
    if v_dom = '' and coalesce(r->>'email','') <> '' then v_dom := lower(trim(r->>'email')); end if;
    if v_dom !~ '^[a-z0-9.-]+\.[a-z]{2,}$' and v_dom !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then continue; end if;
    insert into outreach (domain, name, dr, traffic, source, email)
      values (v_dom, nullif(r->>'name',''), nullif(r->>'dr','')::int, nullif(regexp_replace(coalesce(r->>'traffic',''),'[^0-9]','','g'),'')::int, coalesce(nullif(r->>'source',''),'ahrefs'), nullif(lower(r->>'email'),''))
      on conflict (domain) do update set dr=coalesce(excluded.dr,outreach.dr), traffic=coalesce(excluded.traffic,outreach.traffic), name=coalesce(outreach.name,excluded.name), email=coalesce(outreach.email,excluded.email), updated_at=now();
    n := n+1;
  end loop;
  return jsonb_build_object('imported',n);
end $$;

create or replace function iw_admin_outreach_set(p_token uuid, p_domain text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  update outreach set
    status=coalesce(p_fields->>'status',status), email=case when p_fields ? 'email' then nullif(lower(trim(p_fields->>'email')),'') else email end,
    name=case when p_fields ? 'name' then nullif(trim(p_fields->>'name'),'') else name end, notes=case when p_fields ? 'notes' then p_fields->>'notes' else notes end,
    contact_url=case when p_fields ? 'contact_url' then nullif(p_fields->>'contact_url','') else contact_url end,
    emails_found=case when p_fields ? 'emails_found' then (select array_agg(x) from jsonb_array_elements_text(p_fields->'emails_found') x) else emails_found end,
    scanned_at=case when p_fields ? 'emails_found' then now() else scanned_at end,
    aff_code=case when p_fields ? 'aff_code' then nullif(p_fields->>'aff_code','') else aff_code end, updated_at=now()
   where domain=p_domain;
  if not found then raise exception 'unknown domain'; end if;
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_outreach_delete(p_token uuid, p_domain text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin perform iw_admin(p_token); delete from outreach where domain=p_domain; return jsonb_build_object('ok',true); end $$;

create or replace function iw_admin_outreach_template(p_token uuid, p_subject text, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into site_settings (key,value,updated_at) values ('outreach_subject',p_subject,now()) on conflict (key) do update set value=excluded.value, updated_at=now();
  insert into site_settings (key,value,updated_at) values ('outreach_body',p_body,now()) on conflict (key) do update set value=excluded.value, updated_at=now();
  return jsonb_build_object('ok',true);
end $$;

-- render the welcome for a domain (used for both sending and the copy-to-clipboard version)
create or replace function iw_outreach_render(p_domain text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare o outreach%rowtype; v_sub text; v_body text; v_first text;
begin
  select * into o from outreach where domain=p_domain; if not found then raise exception 'unknown domain'; end if;
  v_first := coalesce(nullif(split_part(coalesce(o.name,''),' ',1),''),'there');
  v_sub := (select value from site_settings where key='outreach_subject'); v_body := (select value from site_settings where key='outreach_body');
  v_body := replace(replace(replace(replace(v_body,'{{first}}',v_first),'{{site}}',o.domain),'{{link}}','https://instantwins.co.uk/affiliate.html'),'{{email}}',coalesce(o.email,''));
  v_sub := replace(v_sub,'{{site}}',o.domain);
  return jsonb_build_object('subject',v_sub,'text',v_body);
end $$;

create or replace function iw_admin_outreach_send(p_token uuid, p_domain text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare o outreach%rowtype; r jsonb; v_html text;
begin
  perform iw_admin(p_token);
  select * into o from outreach where domain=p_domain; if not found then raise exception 'unknown domain'; end if;
  if o.email is null then raise exception 'no email on file — find a contact first'; end if;
  r := iw_outreach_render(p_domain);
  v_html := '<p>'||replace(replace(replace(replace(r->>'text','&','&amp;'),'<','&lt;'),E'\n\n','</p><p>'),E'\n','<br>')||'</p>';
  insert into outbox (user_id, to_email, subject, html) values (null, o.email, r->>'subject', v_html);
  insert into messages (user_id, sender, body, channel, email, subject, from_name) values (null, 'admin', r->>'text', 'email', o.email, r->>'subject', o.domain);
  update outreach set status=case when status in ('new','contacted') then 'contacted' else status end, contacted_at=now(), updated_at=now() where domain=p_domain;
  return jsonb_build_object('ok',true,'to',o.email);
end $$;

-- a reply from a prospect's address moves them to 'replied' automatically
create or replace function trg_outreach_reply() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.sender='user' and new.email is not null then
    update outreach set status='replied', updated_at=now() where status='contacted' and (lower(email)=lower(new.email) or lower(new.email) like '%@'||domain);
  end if;
  return new;
end $$;
drop trigger if exists outreach_reply on messages;
create trigger outreach_reply after insert on messages for each row execute function trg_outreach_reply();

grant execute on function iw_admin_outreach_list(uuid,text,text), iw_admin_outreach_import(uuid,jsonb), iw_admin_outreach_set(uuid,text,jsonb), iw_admin_outreach_delete(uuid,text), iw_admin_outreach_template(uuid,text,text), iw_outreach_render(text), iw_admin_outreach_send(uuid,text) to service_role;
notify pgrst, 'reload schema';
