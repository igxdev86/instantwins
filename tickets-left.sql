-- tickets-left.sql — catalogue also reports prize money still unclaimed in each open round.
create or replace function iw_tickets() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('tag',g.tag,'name',g.name,'tier',g.tier,'code',g.code,'price_p',g.price_p,'cap',g.cap,'tiers',g.tiers,'sort',g.sort,
           'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'prize_left_p',p.prize_left_p,'prize_total_p',p.prize_total_p) order by g.sort),'[]'::jsonb)
  from games g left join lateral (
    select pl.sold, pl.pool_no, pl.seed_hash,
      (select coalesce(sum(a.prize_p),0) from allocation a where a.pool_id=pl.id and a.entry_no > pl.sold) prize_left_p,
      (select coalesce(sum(a.prize_p),0) from allocation a where a.pool_id=pl.id) prize_total_p
    from pools pl where pl.game=g.tag and pl.mult=1 and pl.status='open' order by pl.pool_no desc limit 1) p on true
  where g.active $$;
notify pgrst, 'reload schema';
