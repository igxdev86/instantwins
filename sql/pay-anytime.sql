-- pay-anytime.sql — bank-transfer deposits/withdrawals can be requested before go-live (they are only ever credited/paid by hand in admin).
-- Also: no minimum withdrawal, deposit ceiling £1,000, as the terms say.
create or replace function iw_deposit_request(p_token uuid, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint;
begin
  u := iw_user(p_token);
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if p_amount_p < 500 or p_amount_p > 100000 then raise exception 'deposit between £5 and £1,000'; end if;
  insert into deposits (user_id, amount_p, reference) values (u.id, p_amount_p, coalesce(u.acct_no, 'IW'||substr(u.id::text,1,8))) returning id into v_id;
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'reference',coalesce(u.acct_no,'IW'||substr(u.id::text,1,8)));
end $$;
create or replace function iw_withdraw_request(p_token uuid, p_amount_p int, p_name text, p_sort text, p_acct text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint; v_sort text; v_acct text;
begin
  u := iw_user(p_token);
  v_sort := regexp_replace(coalesce(p_sort,''), '\D', '', 'g'); v_acct := regexp_replace(coalesce(p_acct,''), '\D', '', 'g');
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'account holder name required'; end if;
  if length(v_sort) <> 6 then raise exception 'sort code should be 6 digits'; end if;
  if length(v_acct) <> 8 then raise exception 'account number should be 8 digits'; end if;
  if p_amount_p < 1 then raise exception 'enter an amount'; end if;
  if iw_balance(u.id) < p_amount_p then raise exception 'insufficient balance'; end if;
  insert into withdrawals (user_id, amount_p, account_name, sort_code, account_no) values (u.id, p_amount_p, trim(p_name), v_sort, v_acct) returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (u.id, -p_amount_p, 'withdrawal #'||v_id||' requested');
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'balance_p',iw_balance(u.id));
end $$;
grant execute on function iw_deposit_request(uuid,int), iw_withdraw_request(uuid,int,text,text,text) to service_role;
notify pgrst, 'reload schema';
