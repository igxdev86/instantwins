-- fix-25p.sql — run AFTER round-25p.sql. (1) indexes so account/home queries stay fast with 1.4m prize rows,
-- (2) faster open_pool_big (same published-seed method, same result, ~3x quicker), (3) opens the round if round-25p.sql timed out before it could.
-- If this file itself times out in the SQL editor, run the LAST statement on its own.

-- 1. indexes
create index if not exists allocation_by_user on allocation (claimed_by, revealed) where claimed_by is not null;
create index if not exists allocation_open_prizes on allocation (pool_id, prize_p) where claimed_by is null and prize_p > 0;
create index if not exists allocation_claimed_at on allocation (pool_id, claimed_at desc) where claimed_by is not null;

-- 2. open_pool_big: pre-filter by hash so only ~1.2x the winners are sorted, not all 8m numbers
create or replace function open_pool_big(p_game text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare g games%rowtype; v_no int; v_seed text; v_id uuid; v_wins int; v_cut text; v_n bigint;
begin
  select * into g from games where tag=p_game; if not found then raise exception 'unknown game %', p_game; end if;
  select coalesce(max(pool_no),0)+1 into v_no from pools where game=p_game;
  v_seed := p_game||'-P'||lpad(v_no::text,4,'0')||'-S1|'||gen_random_uuid();
  insert into pools (game,pool_no,cap,price_p,seed,seed_hash,mult) values (p_game,v_no,g.cap,g.price_p,v_seed,encode(digest(v_seed,'sha256'),'hex'),1) returning id into v_id;
  select sum((x->>1)::int) into v_wins from jsonb_array_elements(g.tiers) x;
  create temp table if not exists c2_tiers (prize_p int, upto bigint) on commit drop;
  delete from c2_tiers;
  insert into c2_tiers select (x->>0)::int, sum((x->>1)::int) over (order by (x->>0)::int desc) from jsonb_array_elements(g.tiers) x;
  -- hashes are uniform: the lowest v_wins of them all sit below roughly v_wins/cap of the range. Take a 25% safety margin, sort only those.
  v_cut := lpad(to_hex(least(4294967295::bigint, ((v_wins::numeric / g.cap) * 1.25 * 4294967296)::bigint)), 8, '0');
  create temp table c2_cand (entry_no int, h text) on commit drop;
  insert into c2_cand select gs, md5(v_seed||':'||gs) from generate_series(1,g.cap) gs where md5(v_seed||':'||gs) < v_cut;
  select count(*) into v_n from c2_cand;
  if v_n < v_wins then -- astronomically unlikely; fall back to the full ranking
    delete from c2_cand; insert into c2_cand select gs, md5(v_seed||':'||gs) from generate_series(1,g.cap) gs;
  end if;
  insert into allocation (pool_id, entry_no, prize_p)
  select v_id, r.entry_no, (select t.prize_p from c2_tiers t where r.rn <= t.upto order by t.upto limit 1)
  from (select entry_no, row_number() over (order by h) rn from c2_cand) r
  where r.rn <= v_wins;
  drop table c2_cand;
  return v_id;
end $$;

-- 3. open the round if there is none, then set the close
select case when exists (select 1 from pools where game='MIL' and status='open') then 'already open'::text else open_pool_big('MIL')::text end;
update pools set closes_at = '2027-01-31 20:00:00 Europe/London'::timestamptz where game='MIL' and status='open' and (closes_at is null or closes_at <> '2027-01-31 20:00:00 Europe/London'::timestamptz);
select pool_no, sold, cap, price_p, closes_at at time zone 'Europe/London' as closes_uk, (select count(*) from allocation a where a.pool_id=p.id) as winners from pools p where game='MIL' and status='open';

-- whole balance: no artificial cap below 50,000 tickets
create or replace function c2_buy_balance(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_bal int; v_rate int; v_n int;
begin
  u := iw_user(p_token);
  v_bal := iw_balance(u.id);
  if v_bal < 25 then raise exception 'not enough funds for a ticket'; end if;
  v_rate := c2_rate_for(v_bal); v_n := least(v_bal / v_rate, 50000);
  return c2_issue(u.id, v_n, v_n * v_rate, '(whole balance @ '||v_rate||'p)');
end $$;
notify pgrst, 'reload schema';
