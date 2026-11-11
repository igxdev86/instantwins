-- THE SPINS mega-pool — creates SP if missing, else resizes it. Run once.
-- 5,000 tickets × £2 = £10,000 take · £5,000 prize table · 50% hold · £1,000 top
insert into games (tag, name, cap, price_p, tiers) values
 ('SP','The Spins',5000,200,'[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]')
on conflict (tag) do update
   set cap = excluded.cap,
       price_p = excluded.price_p,
       tiers = excluded.tiers;

-- close any open SP pool (old size) and open a fresh one at the new size
update pools set status='settled', settled_at=now() where game='SP' and status='open';
select open_pool('SP');
