-- admin-credit.sql — admin: credit (or debit) any user's balance by account number / email, with a note. Blocked once payments are live unless flagged as a refund.
create or replace function iw_admin_credit(p_token uuid, p_ref text, p_amount_p int, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; v_name text;
begin
  perform iw_admin(p_token);
  if p_amount_p = 0 or abs(p_amount_p) > 100000000 then raise exception 'amount out of range'; end if;
  select id, name into v_uid, v_name from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) or id::text=trim(p_ref) limit 1;
  if v_uid is null then raise exception 'no account matches %', p_ref; end if;
  if iw_payments_live() and p_amount_p > 0 and coalesce(p_note,'') not ilike 'refund%' then raise exception 'payments are live — credits must be refunds (start the note with "refund")'; end if;
  insert into ledger (user_id, delta_p, reason) values (v_uid, p_amount_p, 'admin: '||case when p_amount_p>0 then 'credit' else 'debit' end||coalesce(' — '||nullif(trim(p_note),''),''));
  return jsonb_build_object('name',v_name,'balance_p',iw_balance(v_uid));
end $$;
grant execute on function iw_admin_credit(uuid,text,int,text) to service_role;
notify pgrst, 'reload schema';
