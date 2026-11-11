-- balance-admin.sql — admin-only: set the calling admin's own play balance
-- to a target amount (test tool). Adjusts via a ledger row so the pure-ledger
-- balance stays consistent. Admin is verified by iw_admin().

create or replace function iw_admin_my_balance(p_token uuid, p_target_p int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_cur int; v_delta int;
begin
  u := iw_admin(p_token);                 -- raises 'admin only' for non-admins
  v_cur := iw_balance(u.id);
  v_delta := p_target_p - v_cur;
  if v_delta <> 0 then
    insert into ledger (user_id, delta_p, reason)
    values (u.id, v_delta, 'admin balance set to '||p_target_p);
  end if;
  return jsonb_build_object('balance_p', iw_balance(u.id));
end $$;

grant execute on function iw_admin_my_balance(uuid,int) to anon, authenticated, service_role;
