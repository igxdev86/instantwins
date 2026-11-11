-- =====================================================================
-- CARD DRAWS v2 — lucky-number model (no refunds, no guaranteed loss)
-- Winning number is drawn from a fixed CAPACITY, not from entries sold:
--   • number sold  -> that entry wins the pot
--   • number unsold-> NO WINNER; pot retained (five) or rolled on (grand)
-- Capacity vs prize sets the house edge, like the slots.
--   Five-Minute : cap 200, £100, RETAIN  (~50% edge at full)
--   Hourly Grand: cap 1000, £1,000 base, SNOWBALL (rolls until won)
--   Free £5     : no cap, guaranteed winner among entrants (acquisition)
-- Run once in the Supabase SQL editor.
-- =====================================================================

alter table card_draws add column if not exists cap int;
alter table card_draws add column if not exists base_prize_p int;

create table if not exists card_rollover(
  kind text primary key,
  amount_p int not null default 0
);
insert into card_rollover(kind,amount_p) values ('grand',0)
  on conflict (kind) do nothing;

alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws add  constraint card_draws_kind_check
  check (kind in ('five','grand','free'));

-- open the next five / hourly / free draws (prizes incl. any rollover)
create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_five timestamptz; v_hour timestamptz; v_free timestamptz; v_seed text; v_roll int;
begin
  v_five := to_timestamp(ceil(extract(epoch from now())/300)*300);
  v_hour := to_timestamp(ceil(extract(epoch from now())/3600)*3600);
  v_free := to_timestamp(ceil(extract(epoch from now())/600)*600);

  if not exists (select 1 from card_draws where kind='five' and off_at=v_five) then
    v_seed := 'FIVE|'||v_five||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('five',v_five,100,10000,10000,200,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;

  if not exists (select 1 from card_draws where kind='grand' and off_at=v_hour) then
    select amount_p into v_roll from card_rollover where kind='grand';
    v_seed := 'GRAND|'||v_hour||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('grand',v_hour,200,100000+coalesce(v_roll,0),100000,1000,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;

  if not exists (select 1 from card_draws where kind='free' and off_at=v_free) then
    v_seed := 'FREE|'||v_free||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('free',v_free,0,500,500,null,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
end $$;

-- settle: lucky-number over capacity; pay only a sold number; roll/retain otherwise
create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_draw int; v_win int; v_uid uuid;
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    v_win := null;
    if d.cap is null then
      -- free: guaranteed winner among entrants
      if d.sold > 0 then
        v_win := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
      end if;
    else
      -- paid: draw across the full capacity
      v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.cap::text),1,8))::bit(32)::bigint & 2147483647) % d.cap)::int;
      if d.sold > 0 and v_draw <= d.sold then
        v_win := v_draw;
      end if;
    end if;

    update card_draws set status='settled', winner_entry=v_win, settled_at=now() where id=d.id;

    if v_win is not null then
      -- pay the pot to the winning entrant
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter
       where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p, drawlabel(d.kind)||' win '||to_char(d.off_at,'HH24:MI')||' #'||v_win);
      end if;
      if d.kind='grand' then update card_rollover set amount_p=0 where kind='grand'; end if;
    else
      -- no winner: grand snowballs (carry the whole pot), five retains (resets to base)
      if d.kind='grand' then update card_rollover set amount_p=d.prize_p where kind='grand'; end if;
    end if;
  end loop;
end $$;

-- tiny label helper
create or replace function drawlabel(k text) returns text
language sql immutable as $$ select case k when 'grand' then 'Hourly Grand' when 'free' then 'Free Draw' else 'Five-Minute Draw' end $$;

-- authenticated entry: free = no cost/one per user; paid = debit + full guard
create or replace function card_enter2(p_kind text, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; d card_draws%rowtype; v_no int;
begin
  u := iw_user(p_token);
  if p_kind not in ('five','grand','free') then raise exception 'bad kind'; end if;
  perform card_settle_due();
  perform card_ensure_open();
  select * into d from card_draws where kind=p_kind and status='open' order by off_at asc limit 1 for update;

  if d.cap is not null and d.sold >= d.cap then raise exception 'this draw is full'; end if;

  if p_kind='free' then
    if exists (select 1 from card_entries where draw_id=d.id and punter=u.id::text) then
      raise exception 'already entered this free draw';
    end if;
  else
    if iw_balance(u.id) < d.price_p then raise exception 'insufficient credit'; end if;
  end if;

  v_no := d.sold + 1;
  if d.price_p > 0 then
    insert into ledger (user_id, delta_p, reason)
    values (u.id, -d.price_p, drawlabel(p_kind)||' '||to_char(d.off_at,'HH24:MI')||' #'||v_no);
  end if;
  insert into card_entries (draw_id, entry_no, punter) values (d.id, v_no, u.id::text);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,'cap',d.cap,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p,'balance_p',iw_balance(u.id));
end $$;

-- state now exposes cap + the live pot
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb;
begin
  perform card_settle_due();
  perform card_ensure_open();
  select jsonb_object_agg(kind, jsonb_build_object(
           'id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,'base_prize_p',base_prize_p,
           'cap',cap,'sold',sold,'seed_hash',seed_hash))
    into v_open from card_draws where status='open';
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb)
    into v_results from (
      select jsonb_build_object('kind',kind,'off_at',off_at,'prize_p',prize_p,'sold',sold,'cap',cap,
             'winner_entry',winner_entry,'seed',seed,'seed_hash',seed_hash,'draw_id',id) as r
      from card_draws where status='settled' order by off_at desc limit 8) s;
  return jsonb_build_object('open',v_open,'results',v_results,'server_now',now());
end $$;

grant execute on function card_ensure_open()        to service_role;
grant execute on function card_settle_due()         to service_role;
grant execute on function card_enter2(text,uuid)     to service_role;
grant execute on function card_state()              to service_role;
grant execute on function drawlabel(text)           to service_role;

select card_ensure_open();
