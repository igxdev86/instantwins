-- login-code.sql — passwordless sign-in: 6-digit one-time code by email, 10-minute life, single use, 5 attempts.
create table if not exists login_codes (id bigserial primary key, email text not null, code text not null, expires_at timestamptz not null, used_at timestamptz, tries int not null default 0, created_at timestamptz not null default now());
create index if not exists login_codes_email on login_codes (email, created_at desc);

create or replace function iw_code_request(p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_code text;
begin
  select * into u from users where lower(email)=lower(trim(p_email));
  -- always answer the same so addresses can't be probed
  if not found or u.closed_at is not null then return jsonb_build_object('sent',true); end if;
  if (select count(*) from login_codes where email=lower(trim(p_email)) and created_at > now() - interval '15 minutes') >= 3 then raise exception 'too many codes requested — try again in a few minutes'; end if;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  insert into login_codes (email, code, expires_at) values (lower(trim(p_email)), v_code, now() + interval '10 minutes');
  perform iw_mail(u.id, v_code||' is your InstantWins sign-in code',
    '<p>Hi '||split_part(u.name,' ',1)||', your one-time sign-in code is:</p><p style="font:900 34px/1 Arial,sans-serif;letter-spacing:8px;margin:14px 0">'||v_code||'</p><p>It works once and expires in 10 minutes. If you did not ask for it, ignore this email &mdash; nobody can sign in without the code.</p>');
  return jsonb_build_object('sent',true);
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
  return jsonb_build_object('token', v_tok, 'name', u.name, 'email', u.email, 'is_admin', u.is_admin, 'balance_p', iw_balance(u.id));
end $$;
grant execute on function iw_code_request(text), iw_code_login(text,text) to service_role;
notify pgrst, 'reload schema';
