-- instant-books.sql — four Instant Win books. Golden (PL) and Platinum (SC) already exist; Mega (SP) exists;
-- Diamond reuses the DD tag with a new table. Run once.
update games set name='Golden Ticket'   where tag='PL';
update games set name='Platinum Ticket' where tag='SC';
update games set name='Mega Ticket'     where tag='SP';
insert into games (tag, name, cap, price_p, tiers) values
 ('DD','Diamond Ticket',1000,1000,'[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]')
on conflict (tag) do update set name=excluded.name, cap=excluded.cap, price_p=excluded.price_p, tiers=excluded.tiers;
update pools set status='settled', settled_at=now() where game='DD' and status='open';
select open_pool('DD', 1);
notify pgrst, 'reload schema';
