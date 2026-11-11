-- card-kinds.sql — the Card's draws become a table. Add a tier with one insert.
-- Run AFTER card-tiers.sql. Safe to re-run.
--
-- Every row is a separate draw: own price, own fixed prize, own number sequence, own seed,
-- open 7 days ahead, postcards may name it, winner drawn from the numbers entered.

create table if not exists card_kinds (
  kind       text primary key,
  label      text not null,
  price_p    int  not null,
  prize_p    int  not null,
  cap        int,
  step_s     int  not null,          -- seconds between draws (86400 = daily)
  offset_s   int  not null default 0,
  daily_hour int,                    -- for daily draws: London hour of the draw
  sort       int  not null default 100,
  active     boolean not null default true
);

insert into card_kinds (kind,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 -- 60-second draws
 ('minute',  '60-Second £10',     50,   1000,   50,   60, 0, null, 10),
 ('s60_20',  '60-Second £20',    100,   2000,   40,   60, 0, null, 11),
 ('s60_50',  '60-Second £50',    200,   5000,   50,   60, 0, null, 12),
 ('s60_100', '60-Second £100',   500,  10000,   40,   60, 0, null, 13),
 -- five-minute draws
 ('five',    'Five-Minute £100', 100,  10000,  200,  300, 0, null, 20),
 ('m5_200',  'Five-Minute £200', 200,  20000,  200,  300, 0, null, 21),
 ('m5_500',  'Five-Minute £500', 500,  50000,  200,  300, 0, null, 22),
 -- quarter-hour draws
 ('silver',  '15-Minute £400',   500,  40000,  160,  900, 0, null, 30),
 ('m15_1000','15-Minute £1,000',1000, 100000,  200,  900, 0, null, 31),
 -- hourly draws
 ('gold',    'Hourly £750',     1000,  75000,  150, 3600, 1800, null, 40),
 ('grand',   'Hourly Grand £1,000', 200, 100000, 1000, 3600, 0, null, 41),
 ('h_2000',  'Hourly £2,000',   2000, 200000,  200, 3600, 1800, null, 42),
 -- daily draws (21:00 London)
 ('platinum','Daily £1,500',    2000, 150000,  150, 86400, 0, 21, 50),
 ('d_5000',  'Daily £5,000',    5000, 500000,  200, 86400, 0, 21, 51),
 -- free
 ('free',    'Free Draw £5',       0,    500, null,  600, 0, null, 60)
on conflict (kind) do update set label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;

alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws drop constraint if exists card_draws_kind_fkey;
alter table card_draws add constraint card_draws_kind_fkey foreign key (kind) references card_kinds(kind);

create or replace function drawlabel(k text) returns text
language sql stable as $$ select coalesce((select label from card_kinds where kind=k), k) $$;

drop function if exists card_spec(text);
create or replace function card_spec(k text, out price_p int, out prize_p int, out cap int, out step_s int, out offset_s int, out daily_hour int)
language sql stable as $$ select price_p, prize_p, cap, step_s, offset_s, daily_hour from card_kinds where kind=k $$;

create or replace function card_kinds() returns text[]
language sql stable as $$ select coalesce(array_agg(kind order by sort),'{}') from card_kinds where active $$;

create or replace function card_valid_off(k text, t timestamptz) returns boolean
language plpgsql stable as $$
declare s record;
begin
  select * into s from card_spec(k);
  if s.step_s is null then return false; end if;
  if not (t > now() and t <= now() + interval '7 days') then return false; end if;
  if s.daily_hour is not null then
    return (t at time zone 'Europe/London')::time = make_time(s.daily_hour,0,0);
  end if;
  return mod(extract(epoch from t)::bigint - s.offset_s, s.step_s) = 0;
end $$;

create or replace function card_next_off(k text) returns timestamptz
language plpgsql stable as $$
declare s record; l timestamp; d timestamp;
begin
  select * into s from card_spec(k);
  if s.daily_hour is not null then
    l := now() at time zone 'Europe/London';
    d := date_trunc('day', l) + (s.daily_hour||' hours')::interval;
    if d <= l then d := d + interval '1 day'; end if;
    return d at time zone 'Europe/London';
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

create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb; v_ahead jsonb; v_kinds jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select jsonb_agg(jsonb_build_object('kind',kind,'label',label,'price_p',price_p,'prize_p',prize_p,'cap',cap,
           'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour) order by sort) into v_kinds from card_kinds where active;
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
      from card_draws d where d.status='settled' and d.settled_at > now() - interval '2 days' order by d.off_at desc limit 20) s;
  return jsonb_build_object('kinds',v_kinds,'open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),
    'window_days',7,'postal_days',3);
end $$;

select card_ensure_open();
notify pgrst, 'reload schema';
