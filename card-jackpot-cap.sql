-- =====================================================================
-- CARD GRAND — cap the snowball + must-drop jackpot. Run once.
-- Jackpot grows by £1,000 per miss up to a £2,500 ceiling; at the ceiling
-- the next draw MUST pay (winner drawn from entries sold), clearing it to
-- £1,000. Bounds max liability to £2,500.  Change CEIL (pence) to taste.
-- =====================================================================

-- reset the current runaway jackpot
update card_rollover set amount_p = 100000 where kind='grand';           -- £1,000 base
update card_draws set prize_p = 100000 where kind='grand' and status='open';

-- open draws: grand jackpot = stored pot (>= base)
create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_five timestamptz; v_hour timestamptz; v_free timestamptz; v_seed text; v_pot int;
begin
  v_five := to_timestamp(ceil(extract(epoch from now())/300)*300);
  v_hour := to_timestamp(ceil(extract(epoch from now())/3600)*3600);
  v_free := to_timestamp(ceil(extract(epoch from now())/600)*600);
  if not exists (select 1 from card_draws where kind='five' and off_at=v_five) then
    v_seed := 'FIVE|'||v_five||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('five',v_five,100,10000,10000,200,v_seed,encode(digest(v_seed,'sha256'),'hex')) on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='grand' and off_at=v_hour) then
    select amount_p into v_pot from card_rollover where kind='grand';
    v_pot := greatest(coalesce(v_pot,100000),100000);
    v_seed := 'GRAND|'||v_hour||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('grand',v_hour,200,v_pot,100000,1000,v_seed,encode(digest(v_seed,'sha256'),'hex')) on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='free' and off_at=v_free) then
    v_seed := 'FREE|'||v_free||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('free',v_free,0,500,500,null,v_seed,encode(digest(v_seed,'sha256'),'hex')) on conflict do nothing;
  end if;
end $$;

-- settle: five (retain), free (guaranteed), grand (cap £2,500 + must-drop)
create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_draw int; v_win int; v_uid uuid; CEIL int := 250000;  -- £2,500
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    v_win := null;
    if d.cap is null then
      if d.sold > 0 then
        v_win := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
      end if;
    elsif d.kind='grand' and d.prize_p >= CEIL then
      -- must-drop: jackpot at ceiling, draw a guaranteed winner from entries sold
      if d.sold > 0 then
        v_win := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
      end if;
    else
      v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.cap::text),1,8))::bit(32)::bigint & 2147483647) % d.cap)::int;
      if d.sold > 0 and v_draw <= d.sold then v_win := v_draw; end if;
    end if;

    update card_draws set status='settled', winner_entry=v_win, settled_at=now() where id=d.id;

    if v_win is not null then
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter
       where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p, drawlabel(d.kind)||' win '||to_char(d.off_at,'HH24:MI')||' #'||v_win);
      end if;
      if d.kind='grand' then update card_rollover set amount_p=100000 where kind='grand'; end if;
    else
      if d.kind='grand' then
        update card_rollover set amount_p = least(d.prize_p + 100000, CEIL) where kind='grand';
      end if;
    end if;
  end loop;
end $$;

grant execute on function card_ensure_open() to service_role;
grant execute on function card_settle_due()  to service_role;
select card_settle_due(); select card_ensure_open();
