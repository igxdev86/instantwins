-- THE SPINS — one shared pool behind all twenty slot themes. Run once.
insert into games (tag, name, cap, price_p, tiers) values
 ('SP','The Spins',500,200,'[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]')
on conflict (tag) do nothing;
select open_pool('SP');
