-- =====================================================================
-- INSTANTWINS — pool engine (Supabase / Postgres)
-- Paste the whole file into SQL Editor and Run once.
--
-- What this builds, in plain English:
--   games      = the menu: 11 games, their entry price, pool size, prizes
--   pools      = one open pool per game; seed sealed (hashed) at open
--   allocation = the shuffled entry->prize map for each pool
--   RPCs       = pool_state (read the counter) and buy_entry (take the
--                next numbered entry, reveal its prize, settle on sell-out)
--
-- Fairness, for real: the shuffle order is derived FROM the seed
-- (md5(seed || position)). So when the seed is revealed at sell-out,
-- anyone can recompute the whole map and check it against the hash
-- that was published while the pool was live. No trust required.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------
-- the menu
-- ---------------------------------------------------------------
create table if not exists games (
  tag     text primary key,          -- 'PL', 'RC', ...
  name    text not null,
  cap     int  not null,             -- entries per pool
  price_p int  not null,             -- pence per entry
  tiers   jsonb not null             -- [[prize_pence, count], ...]
);

insert into games (tag, name, cap, price_p, tiers) values
 ('PL','Plinko Drop',   500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('RC','Rocket Cash',   500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('DD','Diamond Dig',   500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('CL','The Claw',      500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('SC','Safe Cracker',  200, 500, '[[25000,1],[5000,1],[2500,4],[1000,5],[500,10]]'),
 ('PR','Pack Rip',      500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('PF','Photo Finish',  500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('BB','Balloon Burst', 500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('PP','Penny Pusher',  500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('HL','Lucky Ladder',  500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('CG','Cash Grab',     500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]')
on conflict (tag) do nothing;

-- ---------------------------------------------------------------
-- pools + allocation
-- ---------------------------------------------------------------
create table if not exists pools (
  id         uuid primary key default gen_random_uuid(),
  game       text not null references games(tag),
  pool_no    int  not null,
  cap        int  not null,
  price_p    int  not null,
  seed       text not null,           -- SECRET until settled
  seed_hash  text not null,           -- published while live
  sold       int  not null default 0,
  status     text not null default 'open',   -- open | settled
  opened_at  timestamptz not null default now(),
  settled_at timestamptz,
  unique (game, pool_no)
);

create table if not exists allocation (
  pool_id    uuid not null references pools(id) on delete cascade,
  entry_no   int  not null,
  prize_p    int  not null,           -- 0 = no win
  claimed_by text,                    -- 'web' for now; user id later
  claimed_at timestamptz,
  primary key (pool_id, entry_no)
);

create table if not exists postal_entries (
  id          uuid primary key default gen_random_uuid(),
  game        text,
  details     text not null,
  received_at timestamptz not null default now(),
  processed   boolean not null default false
);

-- Lock the doors: nobody talks to tables directly. Everything goes
-- through the two functions below, called by the server with the
-- service key. (This is what stops anyone peeking at unsold prizes.)
alter table games          enable row level security;
alter table pools          enable row level security;
alter table allocation     enable row level security;
alter table postal_entries enable row level security;

-- ---------------------------------------------------------------
-- open a fresh pool: seal the seed, build the shuffled map
-- ---------------------------------------------------------------
create or replace function open_pool(p_game text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  g       games%rowtype;
  v_no    int;
  v_seed  text;
  v_id    uuid;
  t       jsonb;
  prizes  int[] := '{}';
  i       int;
begin
  select * into g from games where tag = p_game;
  if not found then raise exception 'unknown game %', p_game; end if;

  select coalesce(max(pool_no),0)+1 into v_no from pools where game = p_game;
  v_seed := p_game || '-P' || lpad(v_no::text,4,'0') || '|' || gen_random_uuid();

  insert into pools (game, pool_no, cap, price_p, seed, seed_hash)
  values (p_game, v_no, g.cap, g.price_p, v_seed,
          encode(digest(v_seed,'sha256'),'hex'))
  returning id into v_id;

  -- flat prize list: all winners, then zeros up to cap
  for t in select * from jsonb_array_elements(g.tiers) loop
    for i in 1..(t->>1)::int loop
      prizes := prizes || (t->>0)::int;
    end loop;
  end loop;
  while coalesce(array_length(prizes,1),0) < g.cap loop
    prizes := prizes || 0;
  end loop;

  -- the shuffle IS the seed: order positions by md5(seed || position).
  -- Reveal the seed and anyone can rebuild this exact map.
  insert into allocation (pool_id, entry_no, prize_p)
  select v_id,
         row_number() over (order by md5(v_seed || ':' || idx)),
         prizes[idx]
  from generate_subscripts(prizes,1) idx;

  return v_id;
end $$;

-- ---------------------------------------------------------------
-- read the counter (safe: reveals nothing about which entries win)
-- ---------------------------------------------------------------
create or replace function pool_state(p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p pools%rowtype; v_tiers jsonb;
begin
  select * into p from pools
   where game = p_game and status = 'open'
   order by pool_no desc limit 1;
  if not found then
    perform open_pool(p_game);
    select * into p from pools
     where game = p_game and status = 'open'
     order by pool_no desc limit 1;
  end if;

  select jsonb_agg(jsonb_build_object('prize_p', prize_p, 'left', cnt)
                   order by prize_p desc)
    into v_tiers
  from ( select prize_p, count(*) as cnt
           from allocation
          where pool_id = p.id and claimed_by is null and prize_p > 0
          group by prize_p ) s;

  return jsonb_build_object(
    'pool',      p.game || '-P' || lpad(p.pool_no::text,4,'0'),
    'sold',      p.sold,
    'cap',       p.cap,
    'price_p',   p.price_p,
    'seed_hash', p.seed_hash,
    'tiers',     coalesce(v_tiers,'[]'::jsonb));
end $$;

-- ---------------------------------------------------------------
-- buy the next entry: reveal its prize; settle + reopen on sell-out
-- ---------------------------------------------------------------
create or replace function buy_entry(p_game text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p pools%rowtype; v_entry int; v_prize int; v_extra jsonb := '{}'::jsonb;
begin
  select * into p from pools
   where game = p_game and status = 'open'
   order by pool_no desc limit 1
   for update;                        -- one buyer at a time per pool
  if not found then
    perform open_pool(p_game);
    select * into p from pools
     where game = p_game and status = 'open'
     order by pool_no desc limit 1
     for update;
  end if;

  v_entry := p.sold + 1;
  select prize_p into v_prize
    from allocation where pool_id = p.id and entry_no = v_entry;

  update allocation
     set claimed_by = 'web', claimed_at = now()
   where pool_id = p.id and entry_no = v_entry;
  update pools set sold = v_entry where id = p.id;

  if v_entry >= p.cap then
    update pools set status = 'settled', settled_at = now() where id = p.id;
    perform open_pool(p_game);
    v_extra := jsonb_build_object('sold_out', true, 'seed', p.seed);
  else
    v_extra := jsonb_build_object('sold_out', false);
  end if;

  return v_extra || jsonb_build_object(
    'entry_no',  v_entry,
    'prize_p',   v_prize,
    'pool',      p.game || '-P' || lpad(p.pool_no::text,4,'0'),
    'sold',      v_entry,
    'cap',       p.cap,
    'seed_hash', p.seed_hash);
end $$;

-- Only the server (service key) may pull these levers.
revoke all on function open_pool(text)  from public;
revoke all on function pool_state(text) from public;
revoke all on function buy_entry(text)  from public;
grant execute on function pool_state(text) to service_role;
grant execute on function buy_entry(text)  to service_role;
grant execute on function open_pool(text)  to service_role;

-- Optional: open the first pool for every game right now.
select open_pool(tag) from games;
