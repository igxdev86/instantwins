-- c2-finish.sql — "Finish now": reveal every unopened Million Round ticket in one call.
create or replace function c2_reveal_all(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_pool text; v_rows jsonb; v_won bigint; v_n int;
begin
  u := iw_user(p_token);
  create temp table if not exists c2_fin (entry_no bigint, prize_p int, pool_id bigint) on commit drop;
  delete from c2_fin;
  with upd as (
    update allocation al set revealed=true
    from pools q where q.id=al.pool_id and q.game='MIL' and al.claimed_by=u.id::text and not al.revealed
    returning al.entry_no, al.prize_p, al.pool_id)
  insert into c2_fin select entry_no, prize_p, pool_id from upd;
  select count(*), coalesce(sum(prize_p),0) into v_n, v_won from c2_fin;
  if v_n = 0 then return jsonb_build_object('empty',true,'bank',0,'n',0,'won_p',0,'tickets','[]'::jsonb,'balance_p',iw_balance(u.id)); end if;
  insert into ledger (user_id, delta_p, reason)
    select u.id, f.prize_p, 'win '||q.game||'-P'||lpad(q.pool_no::text,4,'0')||' #'||f.entry_no from c2_fin f join pools q on q.id=f.pool_id where f.prize_p > 0;
  select coalesce(jsonb_agg(jsonb_build_object('no',entry_no,'prize_p',prize_p) order by entry_no),'[]'::jsonb) into v_rows from c2_fin;
  return jsonb_build_object('n',v_n,'won_p',v_won,'tickets',v_rows,'bank',0,'balance_p',iw_balance(u.id));
end $$;
grant execute on function c2_reveal_all(uuid) to service_role;
notify pgrst, 'reload schema';
