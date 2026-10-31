-- card-tiers.sql — more draws on the Card, each a separate draw with its own fixed price,
-- fixed prize, own number sequence and own seed. Same rules as card-legal.sql: open 7 days
-- ahead, postcards name the draw, winner drawn from the numbers entered, every prize paid.
-- Run AFTER card-legal.sql. Safe to re-run.
--
--   kind      entry   prize   numbers  when
--   minute    50p     £10     50       every minute
--   five      £1      £100    200      every 5 minutes
--   silver    £5      £400    160      every 15 minutes
--   gold      £10     £750    150      hourly at :30
--   grand     £2      £1,000  1,000    hourly on the hour
--   platinum  £20     £1,500  150      daily 21:00 London
--   free      £0      £5      —        every 10 minutes

alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws add  constraint card_draws_kind_check
  check (kind in ('minute','five','silver','gold','grand','platinum','free'));

create or replace function drawlabel(k text) returns text
language sql immutable as $$ select case k
  when 'minute' then '60-Second Draw' when 'five' then 'Five-Minute Draw' when 'silver' then 'Silver Draw'
  when 'gold' then 'Gold Draw' when 'grand' then 'Hourly Grand' when 'platinum' then 'Platinum Draw'
  when 'free' then 'Free Draw' else k end $$;

drop function if exists card_spec(text);   -- OUT-parameter shape changed

-- price/prize/cap/step; offset_s shifts the grid (gold runs at :30); daily kinds use step 86400 + London 21:00
create or replace function card_spec(k text, out price_p int, out prize_p int, out cap int, out step_s int, out offset_s int)
language sql immutable as $$
  select case k when 'minute' then 50 when 'five' then 100 when 'silver' then 500 when 'gold' then 1000 when 'grand' then 200 when 'platinum' then 2000 else 0 end,
         case k when 'minute' then 1000 when 'five' then 10000 when 'silver' then 40000 when 'gold' then 75000 when 'grand' then 100000 when 'platinum' then 150000 else 500 end,
         case k when 'minute' then 50 when 'five' then 200 when 'silver' then 160 when 'gold' then 150 when 'grand' then 1000 when 'platinum' then 150 else null end,
         case k when 'minute' then 60 when 'five' then 300 when 'silver' then 900 when 'gold' then 3600 when 'grand' then 3600 when 'platinum' then 86400 else 600 end,
         case k when 'gold' then 1800 else 0 end $$;

create or replace function card_kinds() returns text[]
language sql immutable as $$ select array['minute','five','silver','gold','grand','platinum','free'] $$;

create or replace function card_valid_off(k text, t timestamptz) returns boolean
language plpgsql stable as $$
declare s record;
begin
  select * into s from card_spec(k);
  if not (t > now() and t <= now() + interval '7 days') then return false; end if;
  if k = 'platinum' then
    return (t at time zone 'Europe/London')::time = time '21:00';
  end if;
  return mod(extract(epoch from t)::bigint - s.offset_s, s.step_s) = 0;
end $$;

create or replace function card_next_off(k text) returns timestamptz
language plpgsql stable as $$
declare s record; l timestamp;
begin
  select * into s from card_spec(k);
  if k = 'platinum' then
    l := now() at time zone 'Europe/London';
    if l < date_trunc('day', l) + interval '21 hours' then return (date_trunc('day', l) + interval '21 hours') at time zone 'Europe/London';
    else return (date_trunc('day', l) + interval '45 hours') at time zone 'Europe/London'; end if;
  end if;
  return to_timestamp(ceil((extract(epoch from now()) - s.offset_s)/s.step_s)*s.step_s + s.offset_s);
end $$;

create or replace function card_draw_for(k text, t timestamptz) returns card_draws
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; s record; v_seed text;
begin
  select * into d from card_draws where kind=k and off_at=t;
  if found then return d; end if;
  select * into s from card_spec(k);
  v_seed := upper(k)||'|'||t||'|'||gen_random_uuid();
  insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
  values (k,t,s.price_p,s.prize_p,s.prize_p,s.cap,v_seed,encode(digest(v_seed,'sha256'),'hex'))
  on conflict (kind,off_at) do nothing;
  select * into d from card_draws where kind=k and off_at=t;
  return d;
end $$;

create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  foreach k in array card_kinds() loop perform card_draw_for(k, card_next_off(k)); end loop;
end $$;

create or replace function card_add_entry(p_user uuid, k text, t timestamptz, p_via text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_no int;
begin
  if not (k = any(card_kinds())) then raise exception 'bad kind'; end if;
  if not card_valid_off(k, t) then raise exception 'that draw is not open for entry'; end if;
  d := card_draw_for(k, t);
  select * into d from card_draws where id=d.id for update;
  if d.status <> 'open' then raise exception 'draw closed'; end if;
  if d.cap is not null and d.sold >= d.cap then raise exception 'this draw is full'; end if;
  if k='free' and exists (select 1 from card_entries where draw_id=d.id and punter=p_user::text) then
    raise exception 'already entered this free draw'; end if;
  if p_via='online' and d.price_p > 0 then
    if iw_balance(p_user) < d.price_p then raise exception 'insufficient credit'; end if;
    insert into ledger (user_id, delta_p, reason)
    values (p_user, -d.price_p, drawlabel(k)||' '||to_char(d.off_at at time zone 'Europe/London','DD Mon HH24:MI')||' #'||(d.sold+1));
  end if;
  v_no := d.sold + 1;
  insert into card_entries (draw_id, entry_no, punter, mult, via) values (d.id, v_no, p_user::text, 1, p_via);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'kind',k,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p,'balance_p',iw_balance(p_user));
end $$;

create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb; v_ahead jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,
           'cap',cap,'sold',sold,'seed_hash',seed_hash)) into v_open
    from (select distinct on (kind) * from card_draws where status='open' and off_at > now() order by kind, off_at) o;
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'off_at',off_at,'sold',sold,'cap',cap) order by off_at),'[]'::jsonb)
    into v_ahead from card_draws where status='open' and sold>0 and off_at > now();
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'sold',d.sold,'cap',d.cap,
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,
             'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter
                              where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
             'win_mult',1) as r
      from card_draws d where d.status='settled' and d.settled_at > now() - interval '2 days' order by d.off_at desc limit 12) s;
  return jsonb_build_object('open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),
    'window_days',7,'postal_days',3);
end $$;

select card_ensure_open();
notify pgrst, 'reload schema';
