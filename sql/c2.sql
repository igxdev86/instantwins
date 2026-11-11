-- c2.sql — InstantWins Concept 2 backend: one master round ("MIL": 2,000,000 tickets at £1, £1,020,000 in prizes),
-- ticket packs with discounts, a ticket bank (bought, not yet revealed) and reveal-on-play. Run AFTER items.sql.
alter table allocation add column if not exists revealed boolean not null default true;
alter table allocation add column if not exists bought_at timestamptz;

insert into games (tag,name,cap,price_p,tiers,tier,code,sort,active,blurb) values
 ('MIL','Million Round',2000000,100,'[[10000000,1],[2500000,2],[500000,5],[100000,20],[25000,100],[5000,1000],[1000,10000],[500,50000],[200,100000],[100,200000]]','Million','MIL',0,true,
  'One round for the whole site: 2,000,000 tickets, £1,020,000 in prizes, every prize on a ticket before the round opens.')
on conflict (tag) do update set name=excluded.name,cap=excluded.cap,price_p=excluded.price_p,tiers=excluded.tiers,tier=excluded.tier,active=true,blurb=excluded.blurb;

-- allocator for very large rounds: only WINNING tickets get a row (a missing row = no prize).
-- Winning positions = the first 361,128 ticket numbers when ranked by md5(seed:n); prizes handed down that ranking.
create or replace function open_pool_big(p_game text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare g games%rowtype; v_no int; v_seed text; v_id uuid; v_wins int;
begin
  select * into g from games where tag=p_game; if not found then raise exception 'unknown game %', p_game; end if;
  select coalesce(max(pool_no),0)+1 into v_no from pools where game=p_game;
  v_seed := p_game||'-P'||lpad(v_no::text,4,'0')||'-S1|'||gen_random_uuid();
  insert into pools (game,pool_no,cap,price_p,seed,seed_hash,mult) values (p_game,v_no,g.cap,g.price_p,v_seed,encode(digest(v_seed,'sha256'),'hex'),1) returning id into v_id;
  select sum((x->>1)::int) into v_wins from jsonb_array_elements(g.tiers) x;
  create temp table if not exists c2_tiers (prize_p int, upto bigint) on commit drop;
  delete from c2_tiers;
  insert into c2_tiers select (x->>0)::int, sum((x->>1)::int) over (order by (x->>0)::int desc) from jsonb_array_elements(g.tiers) x;
  insert into allocation (pool_id, entry_no, prize_p)
  select v_id, r.entry_no, (select t.prize_p from c2_tiers t where r.rn <= t.upto order by t.upto limit 1)
  from (select gs as entry_no, row_number() over (order by md5(v_seed||':'||gs)) rn from generate_series(1,g.cap) gs) r
  where r.rn <= v_wins;
  return v_id;
end $$;
-- packs: n tickets -> price (pence)
create or replace function c2_pack_price(n int) returns int language sql immutable as $$
  select case n when 1 then 100 when 5 then 450 when 10 then 800 when 25 then 1800 when 50 then 3200 when 100 then 6000 else null end $$;

-- buy a pack: tickets go into the bank unrevealed; prizes are credited when revealed
create or replace function c2_buy(p_token uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; v_price int; v_from int; v_to int;
begin
  u := iw_user(p_token); v_price := c2_pack_price(p_n); if v_price is null then raise exception 'pick a pack'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.sold + p_n > p.cap then raise exception 'only % tickets left in the round', p.cap-p.sold; end if;
  if iw_balance(u.id) < v_price then raise exception 'insufficient credit'; end if;
  insert into ledger (user_id, delta_p, reason) values (u.id, -v_price, 'Million Round: '||p_n||' tickets #'||(p.sold+1)||'-#'||(p.sold+p_n));
  v_from := p.sold+1; v_to := p.sold+p_n;
  insert into allocation (pool_id, entry_no, prize_p) select p.id, gs, 0 from generate_series(v_from, v_to) gs on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=u.id::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no between v_from and v_to;
  update pools set sold=v_to where id=p.id;
  if v_to >= p.cap then update pools set status='settled', settled_at=now() where id=p.id; perform open_pool_big('MIL'); end if;
  return jsonb_build_object('from',v_from,'to',v_to,'n',p_n,'price_p',v_price,'balance_p',iw_balance(u.id),'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed));
end $$;

-- reveal the next unrevealed ticket (oldest first); credit its prize now
create or replace function c2_reveal(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; a allocation%rowtype; v_pool text;
begin
  u := iw_user(p_token);
  select al.* into a from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and not al.revealed order by al.bought_at, al.entry_no limit 1 for update;
  if not found then return jsonb_build_object('empty',true,'bank',0); end if;
  update allocation set revealed=true where pool_id=a.pool_id and entry_no=a.entry_no;
  select game||'-P'||lpad(pool_no::text,4,'0') into v_pool from pools where id=a.pool_id;
  if a.prize_p > 0 then insert into ledger (user_id, delta_p, reason) values (u.id, a.prize_p, 'win '||v_pool||' #'||a.entry_no); end if;
  return jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p,'pool',v_pool,'balance_p',iw_balance(u.id),
    'bank',(select count(*) from allocation x join pools q on q.id=x.pool_id where q.game='MIL' and x.claimed_by=u.id::text and not x.revealed));
end $$;

create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;

create or replace function c2_state() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('cap',p.cap,'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'price_p',p.price_p,
    'prizes_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'prize_left_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is null),
    'top_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p=10000000),
    'tiers',(select g.tiers from games g where g.tag='MIL'),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',split_part(coalesce(u.name,''),' ',1)) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;
grant execute on function c2_buy(uuid,int), c2_reveal(uuid), c2_mine(uuid), c2_state(), c2_pack_price(int), open_pool_big(text) to service_role;
notify pgrst, 'reload schema';
-- open the round (≈361k rows; run this statement on its own if the editor times out):
select open_pool_big('MIL') where not exists (select 1 from pools where game='MIL' and status='open');
