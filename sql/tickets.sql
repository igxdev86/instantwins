-- tickets.sql — Instant Wins become a catalogue: tiers by top prize, several entry prices per tier.
-- Lower price = more tickets in the round, same prize table, so the payout share stays ~50%.
-- Run AFTER pending.sql. Safe to re-run.

alter table games add column if not exists tier   text;
alter table games add column if not exists code   text;
alter table games add column if not exists sort   int not null default 100;
alter table games add column if not exists active boolean not null default false;

-- tier tables (pence): [[prize, count], ...]
-- Penny £5     : 1050p   Bronze £10 : 2900p   Silver £25 : 7450p   Lucky £50 : 19000p
-- Golden £100  : 50000p  Platinum £250 : 50000p  Mega £1,000 : 500000p  Diamond £2,500 : 530000p
insert into games (tag, name, cap, price_p, tiers, tier, code, sort, active) values
 -- Penny (top £5)
 ('LD','Penny Ticket',   200,  10, '[[500,1],[100,2],[50,3],[20,5],[10,10]]',                  'Penny','PEN',10,true),
 ('NT','Penny Ticket',   100,  20, '[[500,1],[100,2],[50,3],[20,5],[10,10]]',                  'Penny','PEN',11,true),
 -- Bronze (top £10)
 ('BH','Bronze Ticket',  500,  10, '[[1000,1],[200,3],[100,5],[50,8],[20,15]]',                'Bronze','BRZ',20,true),
 ('CL','Bronze Ticket',  250,  20, '[[1000,1],[200,3],[100,5],[50,8],[20,15]]',                'Bronze','BRZ',21,true),
 ('BF','Bronze Ticket',  120,  50, '[[1000,1],[200,3],[100,5],[50,8],[20,15]]',                'Bronze','BRZ',22,true),
 -- Silver (top £25)
 ('ST','Silver Ticket',  750,  20, '[[2500,1],[500,3],[200,6],[100,10],[50,25]]',              'Silver','SLV',30,true),
 ('PR','Silver Ticket',  300,  50, '[[2500,1],[500,3],[200,6],[100,10],[50,25]]',              'Silver','SLV',31,true),
 ('S1','Silver Ticket',  150, 100, '[[2500,1],[500,3],[200,6],[100,10],[50,25]]',              'Silver','SLV',32,true),
 -- Lucky (top £50)
 ('LF','Lucky Ticket',   750,  50, '[[5000,1],[1000,3],[500,8],[200,20],[100,30]]',            'Lucky','LKY',40,true),
 ('PF','Lucky Ticket',   400, 100, '[[5000,1],[1000,3],[500,8],[200,20],[100,30]]',            'Lucky','LKY',41,true),
 ('L2','Lucky Ticket',   200, 200, '[[5000,1],[1000,3],[500,8],[200,20],[100,30]]',            'Lucky','LKY',42,true),
 -- Golden (top £100)
 ('G1','Golden Ticket', 1000, 100, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]',         'Golden','GLD',50,true),
 ('PL','Golden Ticket',  500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]',         'Golden','GLD',51,true),
 ('G5','Golden Ticket',  200, 500, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]',         'Golden','GLD',52,true),
 -- Platinum (top £250)
 ('P1','Platinum Ticket',1000, 100, '[[25000,1],[5000,1],[2500,4],[1000,5],[500,10]]',         'Platinum','PLT',60,true),
 ('P2','Platinum Ticket', 500, 200, '[[25000,1],[5000,1],[2500,4],[1000,5],[500,10]]',         'Platinum','PLT',61,true),
 ('SC','Platinum Ticket', 200, 500, '[[25000,1],[5000,1],[2500,4],[1000,5],[500,10]]',         'Platinum','PLT',62,true),
 -- Mega (top £1,000)
 ('M1','Mega Ticket',  10000, 100, '[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]','Mega','MEG',70,true),
 ('SP','Mega Ticket',   5000, 200, '[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]','Mega','MEG',71,true),
 ('M5','Mega Ticket',   2000, 500, '[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]','Mega','MEG',72,true),
 ('MX','Mega Ticket',   1000,1000, '[[100000,1],[10000,5],[5000,10],[2500,20],[1000,50],[500,200],[200,500]]','Mega','MEG',73,true),
 -- Diamond (top £2,500)
 ('D1','Diamond Ticket',10000, 100, '[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]','Diamond','DIA',80,true),
 ('D2','Diamond Ticket', 5000, 200, '[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]','Diamond','DIA',81,true),
 ('D5','Diamond Ticket', 2000, 500, '[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]','Diamond','DIA',82,true),
 ('DD','Diamond Ticket', 1000,1000, '[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]','Diamond','DIA',83,true)
on conflict (tag) do update set name=excluded.name, cap=excluded.cap, price_p=excluded.price_p, tiers=excluded.tiers,
  tier=excluded.tier, code=excluded.code, sort=excluded.sort, active=excluded.active;

-- open a round for every active ticket that has none
do $$ declare g record; begin
  for g in select tag from games where active loop
    if not exists (select 1 from pools where game=g.tag and mult=1 and status='open') then perform open_pool(g.tag,1); end if;
  end loop;
end $$;

-- public catalogue with live round counters
create or replace function iw_tickets() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('tag',g.tag,'name',g.name,'tier',g.tier,'code',g.code,'price_p',g.price_p,'cap',g.cap,'tiers',g.tiers,'sort',g.sort,
           'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash) order by g.sort),'[]'::jsonb)
  from games g left join lateral (select sold, pool_no, seed_hash from pools where game=g.tag and mult=1 and status='open' order by pool_no desc limit 1) p on true
  where g.active $$;

-- admin switches for tickets
create or replace function iw_admin_tickets(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('tag',tag,'name',name,'tier',tier,'code',code,'price_p',price_p,'cap',cap,'sort',sort,'active',active,
    'sold',(select sold from pools where game=games.tag and mult=1 and status='open' order by pool_no desc limit 1)) order by sort) from games where tier is not null),'[]'::jsonb);
end $$;
create or replace function iw_admin_ticket_active(p_token uuid, p_tag text, p_tier text, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g record;
begin
  perform iw_admin(p_token);
  if p_tag is not null then update games set active=p_active where tag=p_tag;
  elsif p_tier is not null then update games set active=p_active where tier=p_tier;
  else raise exception 'tag or tier required'; end if;
  if p_active then
    for g in select tag from games where active and (tag=p_tag or tier=p_tier) loop
      if not exists (select 1 from pools where game=g.tag and mult=1 and status='open') then perform open_pool(g.tag,1); end if;
    end loop;
  end if;
  return iw_admin_tickets(p_token);
end $$;
grant execute on function iw_tickets(), iw_admin_tickets(uuid), iw_admin_ticket_active(uuid,text,text,boolean) to service_role;
notify pgrst, 'reload schema';
