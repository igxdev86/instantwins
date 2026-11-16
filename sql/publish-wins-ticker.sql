-- Home ticker / 'last win' / end-draw name now respect the player's 'publish my wins' setting (shows 'A player' when off).
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
    'last_end',(select jsonb_build_object('round',q.pool_no,'entry',q.end_winner_entry,'prize_p',q.end_prize_p,'at',q.end_drawn_at,'name',case when coalesce(u.publish_wins,true) then split_part(coalesce(u.name,''),' ',1) else 'A player' end,'county',case when coalesce(u.publish_wins,true) then u.county end) from pools q left join users u on u.id=q.end_winner_user where q.game='MIL' and q.end_drawn_at is not null order by q.pool_no desc limit 1),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',case when coalesce(u.publish_wins,true) then split_part(coalesce(u.name,''),' ',1) else 'A player' end) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1),
    'recent',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',r.prize_p,'name',r.name,'at',r.at)),'[]'::jsonb) from (select a.prize_p, case when coalesce(u.publish_wins,true) then split_part(coalesce(u.name,'A player'),' ',1) else 'A player' end as name, a.claimed_at as at from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=500 order by a.claimed_at desc limit 8) r))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;
update state_cache set at=now()-interval '1 hour';
