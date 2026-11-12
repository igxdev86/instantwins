-- round-spread.sql — back to the £1m round, top prizes spread: 5 × £20,000 instead of 1 × £100,000, many more £5,000 / £2,000 / £1,000.
-- 2,000,000 tickets · £1,020,000 (51%) · 351,225 winning tickets (1 in 5.7) · 60-day close · £10,000 End Prize. Re-opens the round with a fresh seed.
begin;
update games set cap=2000000,
  tiers='[[2000000,5],[500000,20],[200000,50],[100000,50],[50000,100],[10000,500],[5000,1000],[2000,2500],[1000,7000],[500,20000],[200,60000],[100,100000],[50,160000]]',
  blurb='One round for the whole site: 2,000,000 tickets, £1,020,000 in prizes across 351,225 winning tickets, every prize on a ticket before the round opens.'
 where tag='MIL';
update site_settings set value='60', updated_at=now() where key='mil_round_days';
update site_settings set value='1000000', updated_at=now() where key='mil_end_prize_p';
delete from allocation a using pools p where p.id=a.pool_id and p.game='MIL';
delete from postal_log; delete from pools where game='MIL';
commit;
select open_pool_big('MIL');
select pool_no, sold, cap, closes_at, end_prize_p, (select count(*) from allocation a where a.pool_id=p.id) as winners from pools p where game='MIL' and status='open';
