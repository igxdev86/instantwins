-- =====================================================================
-- AFFILIATE PROGRAM — rev-share % OR CPA per acquisition. Run once.
-- Rev-share: % of net house hold from your referred players.
-- CPA: fixed £ per qualifying player (one who places ≥1 paid entry).
-- Referral: users who sign up via  /?ref=CODE  are tagged to that code.
-- =====================================================================

create table if not exists affiliates (
  code       text primary key,
  name       text not null,
  email      text,
  model      text not null check (model in ('revshare','cpa')),
  rate       int  not null,            -- revshare: whole % (30=30%) · cpa: pence (2500=£25)
  status     text not null default 'active' check (status in ('active','paused')),
  created_at timestamptz not null default now()
);
alter table affiliates enable row level security;
alter table users add column if not exists ref_code text;

-- sign-up now accepts an optional ?ref code and tags the user
create or replace function iw_signup(p_email text, p_pass text, p_name text, p_dob date, p_ref text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_tok uuid; v_ref text;
begin
  if length(trim(p_email)) < 5 or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  if length(p_pass) < 8 then raise exception 'password must be at least 8 characters'; end if;
  if length(trim(p_name)) < 2 then raise exception 'name required'; end if;
  if p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over'; end if;
  if exists (select 1 from users where lower(email)=lower(trim(p_email))) then
    raise exception 'an account with that email already exists';
  end if;
  select code into v_ref from affiliates where lower(code)=lower(trim(coalesce(p_ref,''))) and status='active';
  insert into users (email, pass, name, dob, ref_code)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob, v_ref)
  returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (v_id, 2000, 'welcome play credit');
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token',v_tok,'name',trim(p_name),'email',trim(p_email),'is_admin',false,'balance_p',2000);
end $$;

-- per-affiliate stats + commission (shared by admin list and affiliate dashboard)
create or replace function iw_aff_row(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare a affiliates%rowtype; v_signups int; v_players int; v_rev int; v_comm int;
begin
  select * into a from affiliates where code=p_code;
  if not found then raise exception 'no such code'; end if;
  select count(*) into v_signups from users where ref_code=a.code;
  select count(distinct u.id) into v_players from users u
    where u.ref_code=a.code and exists (
      select 1 from ledger l where l.user_id=u.id and l.delta_p<0 and l.reason not like 'welcome%');
  select greatest(-coalesce(sum(l.delta_p),0),0)::int into v_rev
    from ledger l join users u on u.id=l.user_id
    where u.ref_code=a.code and l.reason not like 'welcome%';
  v_comm := case a.model when 'revshare' then (v_rev*a.rate/100)::int else v_players*a.rate end;
  return jsonb_build_object('code',a.code,'name',a.name,'email',a.email,'model',a.model,'rate',a.rate,
    'status',a.status,'signups',v_signups,'players',v_players,'revenue_p',v_rev,'commission_p',v_comm,
    'created_at',a.created_at);
end $$;

-- admin: create / list / update
create or replace function iw_admin_aff_create(p_token uuid,p_name text,p_email text,p_code text,p_model text,p_rate int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  if p_model not in ('revshare','cpa') then raise exception 'model must be revshare or cpa'; end if;
  if length(trim(p_code))<2 then raise exception 'code too short'; end if;
  insert into affiliates(code,name,email,model,rate)
  values (lower(regexp_replace(trim(p_code),'[^a-zA-Z0-9_-]','','g')), trim(p_name), nullif(trim(p_email),''), p_model, greatest(p_rate,0));
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_aff_update(p_token uuid,p_code text,p_model text,p_rate int,p_status text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  update affiliates set
    model = coalesce(nullif(p_model,''),model),
    rate  = coalesce(p_rate,rate),
    status= coalesce(nullif(p_status,''),status)
  where code=p_code;
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_aff_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return (select coalesce(jsonb_agg(iw_aff_row(code) order by created_at desc),'[]'::jsonb) from affiliates);
end $$;

-- affiliate self-serve: stats by code (no login; code is the key)
create or replace function iw_aff_stats(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from affiliates where code=lower(trim(p_code))) then raise exception 'no such code'; end if;
  return iw_aff_row(lower(trim(p_code)));
end $$;

revoke all on function iw_aff_row(text) from public;
do $$ declare f text; begin
  foreach f in array array['iw_signup(text,text,text,date,text)','iw_aff_row(text)',
    'iw_admin_aff_create(uuid,text,text,text,text,int)','iw_admin_aff_update(uuid,text,text,int,text)',
    'iw_admin_aff_list(uuid)','iw_aff_stats(text)']
  loop execute 'revoke all on function '||f||' from public'; execute 'grant execute on function '||f||' to service_role'; end loop;
end $$;
