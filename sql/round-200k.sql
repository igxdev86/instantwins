-- round-200k.sql — smaller rounds: 200,000 tickets, £102,000 in prizes (51%), 72,863 winning tickets (1 in 2.7), top instant £10,000, 30-day close, £2,500 End Prize.
-- Re-opens the round with a fresh seed (tickets/ledger should already be reset).
begin;
update games set cap=200000,
  tiers='[[1000000,1],[250000,2],[50000,10],[10000,50],[2500,200],[1000,600],[500,2000],[200,6000],[100,24000],[50,40000]]',
  blurb='One round for the whole site: 200,000 tickets, £102,000 in prizes across 72,863 winning tickets — more than one ticket in three — every prize on a ticket before the round opens.'
 where tag='MIL';
update site_settings set value='30', updated_at=now() where key='mil_round_days';
update site_settings set value='250000', updated_at=now() where key='mil_end_prize_p';
delete from allocation a using pools p where p.id=a.pool_id and p.game='MIL';
delete from postal_log; delete from pools where game='MIL';
commit;
-- top-prize counter now tracks the £10,000 ticket
create or replace function c2_state() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('cap',p.cap,'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'price_p',p.price_p,
    'closes_at',p.closes_at,'end_prize_p',p.end_prize_p,'closed',(p.closes_at is not null and p.closes_at <= now()),
    'prizes_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'prize_left_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'top_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p=(select max(prize_p) from allocation x where x.pool_id=p.id)),
    'left',(select coalesce(jsonb_object_agg(x.prize_p::text, x.n),'{}'::jsonb) from (select prize_p, count(*) n from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0 group by prize_p) x),
    'tiers',(select g.tiers from games g where g.tag='MIL'),
    'won_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>0),
    'postal',(select count(*) from postal_log l where l.status='accepted' and l.pool='MIL-P'||lpad(p.pool_no::text,4,'0')),
    'last_end',(select jsonb_build_object('round',q.pool_no,'entry',q.end_winner_entry,'prize_p',q.end_prize_p,'at',q.end_drawn_at,'name',split_part(coalesce(u.name,''),' ',1),'county',u.county) from pools q left join users u on u.id=q.end_winner_user where q.game='MIL' and q.end_drawn_at is not null order by q.pool_no desc limit 1),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',split_part(coalesce(u.name,''),' ',1)) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1),
    'recent',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',r.prize_p,'name',r.name,'at',r.at)),'[]'::jsonb) from (select a.prize_p, split_part(coalesce(u.name,'A player'),' ',1) as name, a.claimed_at as at from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=500 order by a.claimed_at desc limit 8) r))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;
select open_pool_big('MIL');
select pool_no, sold, cap, closes_at, end_prize_p, (select count(*) from allocation a where a.pool_id=p.id) as winners from pools p where game='MIL' and status='open';
