-- test-users.sql — five customer test accounts (user1@…user5@instantwins.co.uk, password 123456) with £5,000 play funds each,
-- plus "Sign in as" from the admin (iw_admin_impersonate) so you can hop into any account without a password.
do $$
declare i int; v_id uuid;
begin
  for i in 1..5 loop
    select id into v_id from users where lower(email)='user'||i||'@instantwins.co.uk';
    if v_id is null then
      insert into users (email, pass, name, dob, gb_resident, terms_version)
        values ('user'||i||'@instantwins.co.uk', crypt('123456', gen_salt('bf')), 'Test User '||i, date '1990-01-01' + (i*37), true, (select value from site_settings where key='terms_version'))
        returning id into v_id;
    else
      update users set pass=crypt('123456', gen_salt('bf')), name='Test User '||i, dob=date '1990-01-01' + (i*37), gb_resident=true, terms_version=(select value from site_settings where key='terms_version') where id=v_id;
    end if;
    if iw_balance(v_id) < 500000 then
      insert into ledger (user_id, delta_p, reason) values (v_id, 500000 - iw_balance(v_id), 'admin: test funds');
    end if;
  end loop;
end $$;

create or replace function iw_admin_impersonate(p_token uuid, p_ref text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_tok uuid;
begin
  perform iw_admin(p_token);
  select * into u from users where lower(email)=lower(trim(p_ref)) or acct_no=upper(trim(p_ref)) or id::text=p_ref limit 1;
  if not found then raise exception 'no account matching %', p_ref; end if;
  insert into sessions (user_id) values (u.id) returning token into v_tok;
  return jsonb_build_object('token',v_tok,'name',u.name,'email',u.email,'is_admin',coalesce(u.is_admin,false));
end $$;
grant execute on function iw_admin_impersonate(uuid,text) to service_role;
notify pgrst, 'reload schema';
select email, name, acct_no, iw_balance(id) as balance_p from users where email like 'user_@instantwins.co.uk' order by email;
