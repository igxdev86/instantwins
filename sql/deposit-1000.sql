-- deposit-1000.sql — bank/ANNA deposits up to £1,000 (was £500)
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
notify pgrst, 'reload schema';
