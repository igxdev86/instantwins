-- c2-finish.sql (v2) — "Finish now": reveal every unopened Million Round ticket in one call. No temp table.
create or replace function c2_reveal_all(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_rows jsonb; v_won bigint; v_n int;
begin
  u := iw_user(p_token);
  with upd as (
    update allocation al set revealed=true
    from pools q where q.id=al.pool_id and q.game='MIL' and al.claimed_by=u.id::text and not al.revealed
    returning al.entry_no, al.prize_p, q.game, q.pool_no),
  led as (
    insert into ledger (user_id, delta_p, reason)
    select u.id, prize_p, 'win '||game||'-P'||lpad(pool_no::text,4,'0')||' #'||entry_no from upd where prize_p > 0
    returning 1)
  select count(*), coalesce(sum(prize_p),0), coalesce(jsonb_agg(jsonb_build_object('no',entry_no,'prize_p',prize_p) order by entry_no),'[]'::jsonb)
    into v_n, v_won, v_rows from upd;
  if v_n = 0 then return jsonb_build_object('empty',true,'bank',0,'n',0,'won_p',0,'tickets','[]'::jsonb,'balance_p',iw_balance(u.id)); end if;
  return jsonb_build_object('n',v_n,'won_p',v_won,'tickets',v_rows,'bank',0,'balance_p',iw_balance(u.id));
end $$;
grant execute on function c2_reveal_all(uuid) to service_role;
notify pgrst, 'reload schema';
