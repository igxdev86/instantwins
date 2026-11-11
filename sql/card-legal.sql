-- card-legal.sql — the Card rebuilt on the Omaze benchmark.
--
--   • Draws: Five-Minute Draw (£1 → £100, 200 numbers), Hourly Grand (£2 → £1,000, 1,000
--     numbers, fixed — no snowball), Free Draw (£0 → £5, every 10 minutes).
--     The 60-second draw is withdrawn.
--   • Every draw is open for SEVEN DAYS before it closes. Any draw in the next 7 days can be
--     entered online, or by postcard naming the draw ("Five-Minute Draw, Tue 3 Nov, 19:05").
--     A postcard naming no draw enters the next draw after processing AND every Five-Minute
--     Draw for the rest of that day — the postal route is never less generous than paying.
--   • One flat price per draw. No stake multipliers. Postal and paid entries take the next
--     number in the same sequence, same draw, same odds.
--   • Every prize is paid: the winner is drawn from the numbers actually entered
--     (md5(seed:entries) mod entries + 1), matching the Fairness page. No "retained" prize.
--   • Draw rows are created on first entry (or on display) with the seed committed and the
--     hash published before any number is sold.
-- Run AFTER card-minute.sql. Safe to re-run.

-- 1. refund + withdraw open draws of the old shape (test data)
insert into ledger (user_id, delta_p, reason)
select u.id, d.price_p * coalesce(ce.mult,1), 'refund: '||d.kind||' draw withdrawn'
  from card_entries ce join card_draws d on d.id=ce.draw_id join users u on u.id::text=ce.punter
 where d.status='open' and d.price_p>0;
delete from card_draws where status='open';
drop table if exists card_rollover;

alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws add  constraint card_draws_kind_check
  check (kind in ('five','grand','free','minute'));           -- 'minute' kept for history rows only
alter table card_draws add column if not exists cap int;
alter table card_draws add column if not exists drawn_no int;
alter table card_entries add column if not exists mult int not null default 1;
alter table card_entries add column if not exists via text not null default 'online';   -- online | post

create or replace function drawlabel(k text) returns text
language sql immutable as $$ select case k when 'grand' then 'Hourly Grand' when 'free' then 'Free Draw'
  when 'minute' then '60-Second Draw' else 'Five-Minute Draw' end $$;

-- fixed economics per kind
create or replace function card_spec(k text, out price_p int, out prize_p int, out cap int, out step_s int)
language sql immutable as $$
  select case k when 'five' then 100 when 'grand' then 200 else 0 end,
         case k when 'five' then 10000 when 'grand' then 100000 else 500 end,
         case k when 'five' then 200 when 'grand' then 1000 else null end,
         case k when 'five' then 300 when 'grand' then 3600 else 600 end $$;

-- is this a valid draw time for the kind, inside the 7-day entry window?
create or replace function card_valid_off(k text, t timestamptz) returns boolean
language sql stable as $$
  select t > now() and t <= now() + interval '7 days'
     and mod(extract(epoch from t)::bigint, (select step_s from card_spec(k))) = 0 $$;

-- get-or-create the draw row for (kind, off_at); seed committed at creation
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

create or replace function card_next_off(k text) returns timestamptz
language sql stable as $$
  select to_timestamp(ceil(extract(epoch from now())/s.step_s)*s.step_s) from card_spec(k) s $$;

create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform card_draw_for('five',  card_next_off('five'));
  perform card_draw_for('grand', card_next_off('grand'));
  perform card_draw_for('free',  card_next_off('free'));
end $$;

-- core insert used by online and postal routes
create or replace function card_add_entry(p_user uuid, k text, t timestamptz, p_via text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_no int;
begin
  if k not in ('five','grand','free') then raise exception 'bad kind'; end if;
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

drop function if exists card_enter3(text,uuid,int);

-- online entry: next draw by default, or a named draw up to 7 days ahead
create or replace function card_enter3(p_kind text, p_token uuid, p_mult int default 1, p_off_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; t timestamptz;
begin
  u := iw_user(p_token);
  perform card_settle_due();
  t := coalesce(p_off_at, card_next_off(p_kind));
  return card_add_entry(u.id, p_kind, t, 'online');
end $$;

-- postal entry (admin keys the postcard in). p_off_at null = next draw + every Five-Minute
-- Draw for the rest of today (London time). Account matched by the email on the card.
create or replace function iw_admin_postal_enter(p_token uuid, p_email text, p_kind text, p_off_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; t timestamptz; day_end timestamptz; n int := 0; r jsonb;
begin
  perform iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_email));
  if v_uid is null then raise exception 'no account for that email'; end if;
  perform card_settle_due();
  insert into postal_entries (game, details) values ('card', p_kind||' '||coalesce(p_off_at::text,'unnamed')||' '||lower(trim(p_email)));
  if p_off_at is not null then
    r := card_add_entry(v_uid, p_kind, p_off_at, 'post');
    return jsonb_build_object('entered',1,'first',r);
  end if;
  -- unnamed: next draw of the kind, then every five-minute draw left today
  t := card_next_off(p_kind);
  r := card_add_entry(v_uid, p_kind, t, 'post'); n := 1;
  day_end := (date_trunc('day', now() at time zone 'Europe/London') + interval '1 day') at time zone 'Europe/London';
  t := card_next_off('five');
  while t < day_end loop
    begin
      if not (p_kind='five' and t = (r->>'off_at')::timestamptz) then
        perform card_add_entry(v_uid, 'five', t, 'post'); n := n + 1;
      end if;
    exception when others then null;   -- full draw: skip it
    end;
    t := t + interval '5 minutes';
  end loop;
  return jsonb_build_object('entered',n,'first',r);
end $$;

-- settle: the winner is always one of the numbers entered
create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_win int; v_uid uuid;
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    v_win := null;
    if d.sold > 0 then
      v_win := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
    end if;
    update card_draws set status='settled', winner_entry=v_win, drawn_no=v_win, settled_at=now() where id=d.id;
    if v_win is not null then
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p, drawlabel(d.kind)||' win '||to_char(d.off_at at time zone 'Europe/London','DD Mon HH24:MI')||' #'||v_win);
      end if;
    end if;
  end loop;
end $$;

create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb; v_ahead jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  -- the next draw of each kind
  select jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,
           'cap',cap,'sold',sold,'seed_hash',seed_hash)) into v_open
    from (select distinct on (kind) * from card_draws where status='open' and off_at > now() order by kind, off_at) o;
  -- future draws that already hold entries (so the board can show them filling)
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'off_at',off_at,'sold',sold,'cap',cap) order by off_at),'[]'::jsonb)
    into v_ahead from card_draws where status='open' and sold>0 and off_at > now();
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'sold',d.sold,'cap',d.cap,
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,
             'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter
                              where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
             'win_mult',1) as r
      from card_draws d where d.status='settled' and d.kind in ('five','grand','free') order by d.off_at desc limit 8) s;
  return jsonb_build_object('open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),
    'window_days',7,'postal_days',3);
end $$;

-- a player's upcoming entries
create or replace function card_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('draw_id',d.id,'kind',d.kind,'off_at',d.off_at,'entry_no',ce.entry_no,'via',ce.via) order by d.off_at, ce.entry_no)
    from card_entries ce join card_draws d on d.id=ce.draw_id
    where ce.punter=u.id::text and d.status='open'),'[]'::jsonb);
end $$;

grant execute on function card_enter3(text,uuid,int,timestamptz) to service_role;
grant execute on function card_mine(uuid) to service_role;
grant execute on function iw_admin_postal_enter(uuid,text,text,timestamptz) to service_role;
select card_ensure_open();
notify pgrst, 'reload schema';
