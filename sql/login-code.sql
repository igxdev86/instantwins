-- login-code.sql (v2) — passwordless sign-in for everyone: email → 6-digit code → in. New addresses get an account on first sign-in;
-- name, date of birth (18+) and terms acceptance are captured afterwards in an onboarding step, and buying is blocked until done.
alter table users alter column pass drop not null;
alter table users alter column name set default '';
alter table users alter column dob drop not null;
alter table users add column if not exists gb_resident boolean not null default false;

create table if not exists login_codes (id bigserial primary key, email text not null, code text not null, expires_at timestamptz not null, used_at timestamptz, tries int not null default 0, created_at timestamptz not null default now());
create index if not exists login_codes_email on login_codes (email, created_at desc);

create or replace function iw_code_request(p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_email text; v_code text; v_uid uuid; v_name text; v_new boolean := false;
begin
  v_email := lower(trim(p_email));
  if length(v_email) < 5 or position('@' in v_email)=0 or position('.' in split_part(v_email,'@',2))=0 then raise exception 'enter a valid email address'; end if;
  if (select count(*) from login_codes where email=v_email and created_at > now() - interval '15 minutes') >= 3 then raise exception 'too many codes requested — try again in a few minutes'; end if;
  select id, name into v_uid, v_name from users where lower(email)=v_email;
  if v_uid is null then
    insert into users (email, name) values (v_email, '') returning id into v_uid; v_new := true;
    if not iw_payments_live() then insert into ledger (user_id, delta_p, reason) values (v_uid, 2000, 'welcome play credit'); end if;
  elsif exists (select 1 from users where id=v_uid and closed_at is not null) then
    return jsonb_build_object('sent',true);
  end if;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  insert into login_codes (email, code, expires_at) values (v_email, v_code, now() + interval '10 minutes');
  perform iw_mail(v_uid, v_code||' is your InstantWins sign-in code',
    '<p>'||case when coalesce(v_name,'')='' then 'Hi,' else 'Hi '||split_part(v_name,' ',1)||',' end||' your one-time sign-in code is:</p><p style="font:900 34px/1 Arial,sans-serif;letter-spacing:8px;margin:14px 0">'||v_code||'</p><p>It works once and expires in 10 minutes. If you did not ask for it, ignore this email &mdash; nobody can sign in without the code.</p>');
  return jsonb_build_object('sent',true,'new',v_new);
end $$;

create or replace function iw_code_login(p_email text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; c login_codes%rowtype; v_tok uuid;
begin
  select * into c from login_codes where email=lower(trim(p_email)) and used_at is null and expires_at > now() order by created_at desc limit 1 for update;
  if not found then raise exception 'that code has expired — request a new one'; end if;
  if c.tries >= 5 then raise exception 'too many attempts — request a new code'; end if;
  if c.code <> regexp_replace(coalesce(p_code,''),'\D','','g') then update login_codes set tries=tries+1 where id=c.id; raise exception 'wrong code'; end if;
  update login_codes set used_at=now() where id=c.id;
  select * into u from users where lower(email)=lower(trim(p_email));
  if not found or u.closed_at is not null then raise exception 'account not available'; end if;
  insert into sessions (user_id) values (u.id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', u.name, 'email', u.email, 'is_admin', u.is_admin, 'balance_p', iw_balance(u.id),
    'onboard', (u.dob is null or coalesce(u.name,'')='' or u.terms_version is distinct from (select value from site_settings where key='terms_version')));
end $$;

-- onboarding: name + DOB + GB + terms, and an optional daily limit
create or replace function iw_onboard(p_token uuid, p_name text, p_dob date, p_gb boolean, p_limit_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'please enter your name'; end if;
  if p_dob is null or p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over to play'; end if;
  if p_dob < date '1900-01-01' then raise exception 'check your date of birth'; end if;
  if not coalesce(p_gb,false) then raise exception 'InstantWins is open to Great Britain residents only'; end if;
  update users set name=trim(p_name), dob=p_dob, gb_resident=true, terms_version=(select value from site_settings where key='terms_version'),
    daily_limit_p=case when p_limit_p is not null and p_limit_p >= 0 then p_limit_p else daily_limit_p end where id=u.id;
  return jsonb_build_object('ok',true,'name',trim(p_name));
end $$;

-- c2_mine: tell the client when onboarding is still needed
create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'onboard',(u.dob is null or coalesce(u.name,'')='' or u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;

-- no buying until onboarded (18+ confirmed)
create or replace function trg_need_onboard() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.delta_p < 0 and new.reason like 'Million Round:%' and exists (select 1 from users where id=new.user_id and (dob is null or coalesce(name,'')='')) then
    raise exception 'finish setting up your account first';
  end if;
  return new;
end $$;
drop trigger if exists need_onboard on ledger;
create trigger need_onboard before insert on ledger for each row execute function trg_need_onboard();

-- welcome email only once the name is known (the sign-in code email covers the first contact)
create or replace function trg_mail_welcome() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(new.name,'')<>'' then
    perform iw_mail(new.id,'Welcome to InstantWins','<p>Hi '||split_part(new.name,' ',1)||', your account is open. Your account number is <b>'||coalesce(new.acct_no,'')||'</b> &mdash; you need it on any free postal entry.</p><p><a href="https://instantwins.co.uk/free.html">How to enter free by post</a> &middot; <a href="https://instantwins.co.uk/account.html">Your account</a></p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_welcome on users;
create trigger mail_welcome after insert on users for each row execute function trg_mail_welcome();
drop trigger if exists mail_welcome_onboard on users;
create or replace function trg_mail_welcome_onboard() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(old.name,'')='' and coalesce(new.name,'')<>'' then
    perform iw_mail(new.id,'Welcome to InstantWins','<p>Hi '||split_part(new.name,' ',1)||', your account is set up. Your account number is <b>'||coalesce(new.acct_no,'')||'</b> &mdash; you need it on any free postal entry.</p><p><a href="https://instantwins.co.uk/free.html">How to enter free by post</a> &middot; <a href="https://instantwins.co.uk/account.html">Your account</a></p>');
  end if;
  return new;
end $$;
create trigger mail_welcome_onboard after update of name on users for each row execute function trg_mail_welcome_onboard();

grant execute on function iw_code_request(text), iw_code_login(text,text), iw_onboard(uuid,text,date,boolean,int), c2_mine(uuid) to service_role;
notify pgrst, 'reload schema';
