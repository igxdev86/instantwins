-- launch.sql — going live. Run AFTER payments-bank.sql.
--   1. The £20 welcome play-credit stops the moment payments are live (it would be real money).
--   2. Every existing play-money balance is zeroed ONCE when you flip the switch (admin accounts too),
--      so nobody carries test credit into real money. Done by iw_go_live(), called from the admin switch.

create or replace function iw_signup(p_email text, p_pass text, p_name text, p_dob date)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_tok uuid; v_welcome int := case when iw_payments_live() then 0 else 2000 end;
begin
  if length(trim(p_email)) < 5 or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  if length(p_pass) < 8 then raise exception 'password must be at least 8 characters'; end if;
  if length(trim(p_name)) < 2 then raise exception 'name required'; end if;
  if p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over'; end if;
  if exists (select 1 from users where lower(email)=lower(trim(p_email))) then
    raise exception 'an account with that email already exists';
  end if;
  insert into users (email, pass, name, dob)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob)
  returning id into v_id;
  if v_welcome > 0 then insert into ledger (user_id, delta_p, reason) values (v_id, v_welcome, 'welcome play credit'); end if;
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', trim(p_name), 'email', trim(p_email), 'is_admin', false, 'balance_p', v_welcome);
end $$;

-- zero every play-money balance once, then switch payments on
create or replace function iw_go_live(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0;
begin
  perform iw_admin(p_token);
  if iw_payments_live() then return jsonb_build_object('already_live', true); end if;
  for r in select u.id, iw_balance(u.id) bal from users u loop
    if r.bal <> 0 then
      insert into ledger (user_id, delta_p, reason) values (r.id, -r.bal, 'admin: play-money balance cleared at launch'); n := n + 1;
    end if;
  end loop;
  insert into site_settings (key,value,updated_at) values ('payments_live','true',now()) on conflict (key) do update set value='true', updated_at=now();
  insert into site_settings (key,value,updated_at) values ('launched_at',now()::text,now()) on conflict (key) do update set value=now()::text, updated_at=now();
  return jsonb_build_object('live', true, 'balances_cleared', n);
end $$;

-- public: is the site live? (no token needed)
create or replace function iw_site() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('live', iw_payments_live(), 'launched_at', (select value from site_settings where key='launched_at')) $$;

grant execute on function iw_go_live(uuid), iw_site() to service_role;
notify pgrst, 'reload schema';
