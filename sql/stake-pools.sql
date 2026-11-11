-- stake-pools.sql — each stake gets its OWN pool of tickets.
-- A pool is now keyed by (game, mult). Price and prizes are baked in per
-- pool at creation (base × mult), so a £50 pool genuinely holds £50-scaled
-- committed tickets, separate from the £2 pool. RTP is identical per tier.

alter table pools add column if not exists mult int not null default 1;

-- open a pool for a game + stake multiplier (price & prizes pre-scaled)
create or replace function open_pool(p_game text, p_mult int default 1) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare g games%rowtype; v_no int; v_seed text; v_id uuid; t jsonb; prizes int[] := '{}'; i int; m int;
begin
  select * into g from games where tag = p_game;
  if not found then raise exception 'unknown game %', p_game; end if;
  m := greatest(coalesce(p_mult,1),1);
  if g.price_p * m > 5000 then raise exception 'stake exceeds £50'; end if;

  -- pool_no is unique per game across all stakes, so refs never collide
  select coalesce(max(pool_no),0)+1 into v_no from pools where game = p_game;
  v_seed := p_game || '-P' || lpad(v_no::text,4,'0') || '-S' || m || '|' || gen_random_uuid();

  insert into pools (game, pool_no, cap, price_p, seed, seed_hash, mult)
  values (p_game, v_no, g.cap, g.price_p * m, v_seed,
          encode(digest(v_seed,'sha256'),'hex'), m)
  returning id into v_id;

  for t in select * from jsonb_array_elements(g.tiers) loop
    for i in 1..(t->>1)::int loop
      prizes := prizes || ((t->>0)::int * m);     -- prize scaled into the pool
    end loop;
  end loop;
  while coalesce(array_length(prizes,1),0) < g.cap loop prizes := prizes || 0; end loop;

  insert into allocation (pool_id, entry_no, prize_p)
  select v_id, row_number() over (order by md5(v_seed || ':' || idx)), prizes[idx]
  from generate_subscripts(prizes,1) idx;

  return v_id;
end $$;

-- keep the one-arg form working (defaults to the £1× pool)
create or replace function open_pool(p_game text) returns uuid
language sql security definer set search_path = public, extensions as $$
  select open_pool(p_game, 1);
$$;

-- read the counter for one game at one stake (prizes already scaled)
create or replace function pool_state(p_game text, p_mult int default 1) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; v_tiers jsonb; m int;
begin
  m := greatest(coalesce(p_mult,1),1);
  select * into p from pools where game = p_game and mult = m and status = 'open'
   order by pool_no desc limit 1;
  if not found then
    perform open_pool(p_game, m);
    select * into p from pools where game = p_game and mult = m and status = 'open'
     order by pool_no desc limit 1;
  end if;

  select jsonb_agg(jsonb_build_object('prize_p', prize_p, 'left', cnt) order by prize_p desc)
    into v_tiers
  from ( select prize_p, count(*) as cnt from allocation
          where pool_id = p.id and claimed_by is null and prize_p > 0
          group by prize_p ) s;

  return jsonb_build_object('pool', p.game || '-P' || lpad(p.pool_no::text,4,'0'),
    'sold', p.sold, 'cap', p.cap, 'price_p', p.price_p, 'mult', p.mult,
    'seed_hash', p.seed_hash, 'tiers', coalesce(v_tiers,'[]'::jsonb));
end $$;

create or replace function pool_state(p_game text) returns jsonb
language sql security definer set search_path = public, extensions as $$
  select pool_state(p_game, 1);
$$;

-- buy the next entry from THIS stake's pool (price & prize already scaled)
create or replace function buy_entry3(p_game text, p_token uuid, p_mult int default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; v_entry int; v_prize int;
        v_extra jsonb := '{}'::jsonb; v_label text; m int;
begin
  u := iw_user(p_token);
  m := greatest(coalesce(p_mult,1),1);
  select * into p from pools where game = p_game and mult = m and status = 'open'
   order by pool_no desc limit 1 for update;
  if not found then
    perform open_pool(p_game, m);
    select * into p from pools where game = p_game and mult = m and status = 'open'
     order by pool_no desc limit 1 for update;
  end if;
  if p.price_p > 5000 then raise exception 'max stake is £50 per entry'; end if;
  if iw_balance(u.id) < p.price_p then raise exception 'insufficient credit'; end if;

  v_label := p.game||'-P'||lpad(p.pool_no::text,4,'0');
  v_entry := p.sold + 1;
  select prize_p into v_prize from allocation where pool_id=p.id and entry_no=v_entry;

  insert into ledger (user_id, delta_p, reason)
    values (u.id, -p.price_p, 'entry '||v_label||' #'||v_entry||case when m>1 then ' x'||m else '' end);
  update allocation set claimed_by=u.id::text, claimed_at=now() where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  if v_prize > 0 then
    insert into ledger (user_id, delta_p, reason)
      values (u.id, v_prize, 'win '||v_label||' #'||v_entry||case when m>1 then ' x'||m else '' end);
  end if;

  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id;
    perform open_pool(p_game, m);
    v_extra := jsonb_build_object('sold_out', true, 'seed', p.seed);
  else
    v_extra := jsonb_build_object('sold_out', false);
  end if;

  return v_extra || jsonb_build_object('entry_no',v_entry,'prize_p',v_prize,'pool',v_label,
    'sold',v_entry,'cap',p.cap,'seed_hash',p.seed_hash,'balance_p',iw_balance(u.id),'mult',m);
end $$;

grant execute on function open_pool(text,int)  to anon, authenticated, service_role;
grant execute on function pool_state(text,int) to anon, authenticated, service_role;
grant execute on function buy_entry3(text,uuid,int) to anon, authenticated, service_role;
notify pgrst, 'reload schema';
