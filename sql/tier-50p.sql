-- tier-50p.sql — add 100,000 × 50p prizes, £1 prizes 200,000 → 150,000. Pot stays £1,020,000; 411,128 winning tickets (1 in 4.9).
-- Re-opens the Million Round with a fresh seed (all tickets/ledger must already be reset — run reset-fresh.sql first if not).
begin;
update games set tiers='[[10000000,1],[2500000,2],[500000,5],[100000,20],[25000,100],[5000,1000],[1000,10000],[500,50000],[200,100000],[100,150000],[50,100000]]',
  blurb='One round for the whole site: 2,000,000 tickets, £1,020,000 in prizes across 411,128 winning tickets, every prize on a ticket before the round opens.'
 where tag='MIL';
delete from allocation a using pools p where p.id=a.pool_id and p.game='MIL';
delete from postal_log; delete from pools where game='MIL';
commit;
-- fresh round (≈411k rows; run on its own if the editor times out)
select open_pool_big('MIL');
select pool_no, sold, cap, closes_at, end_prize_p, (select count(*) from allocation a where a.pool_id=p.id) as winners from pools p where game='MIL' and status='open';
