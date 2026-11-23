-- withdraw-min.sql — £5 minimum withdrawal, except a full-balance withdrawal is always allowed (nobody's money gets stuck).
create or replace function iw_withdraw_request(p_token uuid, p_amount_p int, p_name text, p_sort text, p_acct text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint; v_sort text; v_acct text; v_bal int;
begin
  u := iw_user(p_token);
  if not iw_payments_live() then raise exception 'payments are not open yet'; end if;
  v_sort := regexp_replace(coalesce(p_sort,''), '\D', '', 'g'); v_acct := regexp_replace(coalesce(p_acct,''), '\D', '', 'g');
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'account holder name required'; end if;
  if length(v_sort) <> 6 then raise exception 'sort code should be 6 digits'; end if;
  if length(v_acct) <> 8 then raise exception 'account number should be 8 digits'; end if;
  if p_amount_p < 1 then raise exception 'enter an amount'; end if;
  v_bal := iw_balance(u.id);
  if v_bal < p_amount_p then raise exception 'insufficient balance'; end if;
  if p_amount_p < 500 and p_amount_p <> v_bal then raise exception 'minimum withdrawal is £5 (or your whole balance)'; end if;
  insert into withdrawals (user_id, amount_p, account_name, sort_code, account_no) values (u.id, p_amount_p, trim(p_name), v_sort, v_acct) returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (u.id, -p_amount_p, 'withdrawal #'||v_id||' requested');
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'balance_p',iw_balance(u.id));
end $$;
notify pgrst, 'reload schema';
