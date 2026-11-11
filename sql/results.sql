-- Public results feed: recent settled Card draws + settled game pools.
create or replace function iw_results() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_card jsonb; v_pools jsonb;
begin
  select coalesce(jsonb_agg(c order by c->>'off_at' desc),'[]'::jsonb) into v_card from (
    select jsonb_build_object('kind',kind,'off_at',off_at,'prize_p',prize_p,'cap',cap,
      'sold',sold,'winner_entry',winner_entry,'seed',seed,'seed_hash',seed_hash) c
    from card_draws where status='settled' order by off_at desc limit 25) s;
  select coalesce(jsonb_agg(p order by p->>'settled_at' desc),'[]'::jsonb) into v_pools from (
    select jsonb_build_object('game',g.name,'tag',pl.game,'pool_no',pl.pool_no,
      'settled_at',pl.settled_at,'seed',pl.seed,'seed_hash',pl.seed_hash,'cap',pl.cap,
      'winners',(select count(*) from allocation a where a.pool_id=pl.id and a.prize_p>0),
      'top_p',(select max(a.prize_p) from allocation a where a.pool_id=pl.id)) p
    from pools pl join games g on g.tag=pl.game
    where pl.status='settled' order by pl.settled_at desc limit 25) s;
  return jsonb_build_object('card',v_card,'pools',v_pools,'server_now',now());
end $$;
revoke all on function iw_results() from public;
grant execute on function iw_results() to service_role;
