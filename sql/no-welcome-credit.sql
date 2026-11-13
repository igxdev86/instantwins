-- no-welcome-credit.sql — new accounts start at £0. (Admins can still credit a player from Admin → Users for testing.)
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
  insert into users (email, pass, name, dob, ref_code, gb_resident, terms_version)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob, v_ref, true, (select value from site_settings where key='terms_version'))
  returning id into v_id;
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token',v_tok,'name',trim(p_name),'email',trim(p_email),'is_admin',false,'balance_p',0);
end $$;
-- code sign-in path (if ever switched back on): no credit either
create or replace function iw_code_request(p_email text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_email text; v_uid uuid; v_code text; v_new boolean := false;
begin
  v_email := lower(trim(p_email));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email'; end if;
  if (select count(*) from login_codes where email=v_email and created_at > now()-interval '10 minutes') >= 5 then raise exception 'too many codes — wait a few minutes'; end if;
  select id into v_uid from users where lower(email)=v_email;
  if v_uid is null then insert into users (email, pass, name) values (v_email, null, '') returning id into v_uid; v_new := true; end if;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  insert into login_codes (email, code) values (v_email, v_code);
  perform iw_mail(v_uid, v_code||' is your InstantWins sign-in code', '<p>Enter this code to sign in. It works for 10 minutes.</p><p><code>'||v_code||'</code></p><p>If you did not ask for it, ignore this email.</p>');
  return jsonb_build_object('ok',true,'new',v_new);
end $$;
-- remove the £20 from accounts that have not spent anything yet
delete from ledger l where l.reason='welcome play credit' and not exists (select 1 from ledger x where x.user_id=l.user_id and x.delta_p<0);
notify pgrst, 'reload schema';
