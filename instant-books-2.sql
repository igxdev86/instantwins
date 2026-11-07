-- instant-books-2.sql — four low-price Instant Win tickets. Reuses retired game tags. Run once.
insert into games (tag, name, cap, price_p, tiers) values
 ('LD','Penny Ticket',  200,  10, '[[500,1],[100,2],[50,3],[20,5],[10,10]]'),
 ('CL','Bronze Ticket', 250,  20, '[[1000,1],[200,3],[100,5],[50,8],[20,15]]'),
 ('PR','Silver Ticket', 300,  50, '[[2500,1],[500,3],[200,6],[100,10],[50,25]]'),
 ('PF','Lucky Ticket',  400, 100, '[[5000,1],[1000,3],[500,8],[200,20],[100,30]]')
on conflict (tag) do update set name=excluded.name, cap=excluded.cap, price_p=excluded.price_p, tiers=excluded.tiers;
update pools set status='settled', settled_at=now() where game in ('LD','CL','PR','PF') and status='open';
select open_pool('LD',1); select open_pool('CL',1); select open_pool('PR',1); select open_pool('PF',1);
notify pgrst, 'reload schema';
