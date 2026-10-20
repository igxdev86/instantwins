-- THE SPINS mega-pool: 40 slots feed one big pool. Run once.
-- 5,000 tickets × £2 = £10,000 take · £5,000 prize table · 50% hold
-- Headline £1,000 top. Odds unchanged per £2 (~1-in-6).
update games
   set cap = 5000,
       tiers = '[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]'
 where tag = 'SP';

-- close any open SP pool at the old size and open a fresh one at the new size
update pools set status='settled', settled_at=now() where game='SP' and status='open';
select open_pool('SP');
