-- rollover.sql — rollover draws. For a kind with rollover=true the winning number is drawn from ALL numbers (1..cap),
-- not just the sold ones. Sold number → that player wins prize + any rollover. Unsold number → nobody wins this draw and
-- the whole pot (prize + rollover) is carried into the next draw of the same kind. A draw with no entries is void:
-- nothing taken, nothing owed, nothing carried. Payout stays prize ÷ (cap × price) of takings at any fill.
alter table card_kinds add column if not exists rollover boolean not null default false;
alter table card_draws add column if not exists rollover_p int not null default 0;
alter table card_draws add column if not exists drawn_range int;       -- numbers the draw was made from (cap or sold)

-- next slot strictly after a given time (same arithmetic as card_next_off)
create or replace function card_next_off_after(k text, t timestamptz) returns timestamptz
language plpgsql stable set search_path = public, extensions as $$
declare s record; l timestamp; d timestamp;
begin
  select * into s from card_spec(k);
  if s.daily_hour is not null then
    l := t at time zone 'Europe/London';
    d := date_trunc('day', l) + (s.daily_hour||' hours')::interval;
    if d <= l then d := d + interval '1 day'; end if;
    return d at time zone 'Europe/London';
  end if;
  return to_timestamp((floor((extract(epoch from t) - s.offset_s)/s.step_s) + 1)*s.step_s + s.offset_s);
end $$;


create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; k card_kinds%rowtype; v_range int; v_drawn int; v_win int; v_uid uuid; v_pot int; nxt card_draws%rowtype;
begin
  for d in select * from card_draws where status='open' and off_at <= now() order by off_at for update loop
    select * into k from card_kinds where kind=d.kind;
    v_win := null; v_drawn := null; v_pot := d.prize_p + d.rollover_p;
    if d.sold > 0 then
      v_range := case when coalesce(k.rollover,false) and d.cap is not null then d.cap else d.sold end;
      v_drawn := 1 + ((('x'||substr(md5(d.seed||':'||v_range::text),1,8))::bit(32)::bigint & 2147483647) % v_range)::int;
      if v_drawn <= d.sold then v_win := v_drawn; end if;
    else
      v_range := 0;
    end if;
    update card_draws set status='settled', winner_entry=v_win, drawn_no=v_drawn, drawn_range=v_range, settled_at=now() where id=d.id;
    if v_win is not null then
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, v_pot, drawlabel(d.kind)||' win '||to_char(d.off_at at time zone 'Europe/London','DD Mon HH24:MI')||' #'||v_win||case when d.rollover_p>0 then ' (incl. rollover)' else '' end);
      end if;
    elsif d.sold > 0 and coalesce(k.rollover,false) then
      -- unsold number drawn: carry the pot to the next draw of this kind (create it if needed)
      nxt := card_draw_for(d.kind, card_next_off_after(d.kind, d.off_at));
      update card_draws set rollover_p = rollover_p + v_pot where id = nxt.id;
    end if;
  end loop;
end $$;

-- state: expose rollover + pot on kinds, open draws, ahead and results
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_kinds jsonb; v_open jsonb; v_ahead jsonb; v_results jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,'cap',cap,
           'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'bundle_n',bundle_n,'bundle_price_p',bundle_price_p,'rollover',rollover) order by sort),'[]'::jsonb) into v_kinds from card_kinds where active;
  select coalesce(jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'sold',sold,'cap',cap,'prize_p',prize_p,'rollover_p',rollover_p,'price_p',price_p,'seed_hash',seed_hash,'game_no',card_game_no(kind,off_at))),'{}'::jsonb)
    into v_open from (select distinct on (kind) * from card_draws where status='open' and off_at > now() order by kind, off_at) o;
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'off_at',off_at,'sold',sold,'cap',cap,'prize_p',prize_p,'rollover_p',rollover_p,'game_no',card_game_no(kind,off_at)) order by off_at),'[]'::jsonb)
    into v_ahead from card_draws where status='open' and (sold>0 or rollover_p>0) and off_at > now();
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'rollover_p',d.rollover_p,'sold',d.sold,'cap',d.cap,'drawn_range',d.drawn_range,
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,'game_no',card_game_no(d.kind,d.off_at),
             'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter
                              where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
             'win_mult',1) as r
      from card_draws d where d.status='settled' and d.sold>0 and d.settled_at > now() - interval '2 days' order by d.off_at desc limit 20) s;
  return jsonb_build_object('kinds',v_kinds,'open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),'window_days',7,'postal_days',3);
end $$;

create or replace function card_lookup(p_game_no text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g record; d card_draws%rowtype;
begin
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  select * into d from card_draws where kind=g.kind and off_at=g.off_at;
  if not found then
    return jsonb_build_object('found',false,'kind',g.kind,'label',drawlabel(g.kind),'off_at',g.off_at,'game_no',card_game_no(g.kind,g.off_at),
      'status',case when g.off_at<=now() then 'no entries' else 'open' end);
  end if;
  return jsonb_build_object('found',true,'kind',d.kind,'label',drawlabel(d.kind),'off_at',d.off_at,'game_no',card_game_no(d.kind,d.off_at),
    'status',d.status,'price_p',d.price_p,'prize_p',d.prize_p,'rollover_p',d.rollover_p,'cap',d.cap,'sold',d.sold,'drawn_range',d.drawn_range,'drawn_no',d.drawn_no,
    'rollover',(select rollover from card_kinds where kind=d.kind),'seed_hash',d.seed_hash,
    'seed',case when d.status='settled' then d.seed end,'winner_entry',d.winner_entry,'settled_at',d.settled_at,
    'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
    'postal_entries',(select count(*) from card_entries ce where ce.draw_id=d.id and ce.via='post'));
end $$;

create or replace function iw_admin_kinds(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,
    'cap',cap,'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'sort',sort,'active',active,'rollover',rollover,
    'open_entries',(select coalesce(sum(sold),0) from card_draws d where d.kind=card_kinds.kind and d.status='open'),
    'rollover_open_p',(select coalesce(sum(rollover_p),0) from card_draws d where d.kind=card_kinds.kind and d.status='open')) order by sort)
    from card_kinds),'[]'::jsonb);
end $$;

-- admin switch per row
create or replace function iw_admin_kind_rollover(p_token uuid, p_kind text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin perform iw_admin(p_token); update card_kinds set rollover=p_on where kind=p_kind; return jsonb_build_object('kind',p_kind,'rollover',p_on); end $$;
grant execute on function iw_admin_kind_rollover(uuid,text,boolean) to service_role;

-- the full schedule back on, as rollover draws (every row with a cap); free draws stay "winner from entries"
update card_kinds set rollover = (price_p > 0 and cap is not null);
notify pgrst, 'reload schema';
-- draw-packs.sql — Draw Packs: pennies-a-draw rollover draws sold as a pack of 20 consecutive draws (one number in each).
-- 30 s packs = 10 minutes of play; 60 s packs = 20 minutes. Rollover on, so payout = prize ÷ (cap × price) = 50% of takings.
-- Run AFTER rollover.sql. Adds to whatever schedule is on; switch rows in admin-draws as usual.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort,active,bundle_n,bundle_price_p,rollover) values
 ('pk_20', 'P20', '30s Pack Draw 20p',  2,   20, 20, 30, 0, null, 0, true, 20,   40, true),   -- 20 draws for 40p
 ('pk_50', 'P50', '30s Pack Draw 50p',  5,   50, 20, 30, 0, null, 1, true, 20,  100, true),   -- 20 draws for £1
 ('pk_100','P100','60s Pack Draw £1',  10,  100, 20, 60, 0, null, 10, true, 20,  200, true),  -- 20 draws for £2
 ('pk_500','P500','60s Pack Draw £5',  50,  500, 20, 60, 0, null, 11, true, 20, 1000, true)   -- 20 draws for £10
on conflict (kind) do update set code=excluded.code,label=excluded.label,price_p=excluded.price_p,prize_p=excluded.prize_p,cap=excluded.cap,step_s=excluded.step_s,
  offset_s=excluded.offset_s,sort=excluded.sort,active=excluded.active,bundle_n=excluded.bundle_n,bundle_price_p=excluded.bundle_price_p,rollover=excluded.rollover;
select card_ensure_open();
notify pgrst, 'reload schema';
-- items.sql — Instant Win rounds with a physical prize (bag, phone, console…) as the top line of the prize table.
-- The item's ticket pays its cash alternative at once; the winner can swap for the item within 7 days (admin queue).
-- Run AFTER tickets.sql and rollover.sql. Safe to re-run.

alter table games add column if not exists item_name     text;      -- "Louis Vuitton Neverfull MM"
alter table games add column if not exists item_rrp_p    int;
alter table games add column if not exists item_cashalt_p int;      -- credited on the spot; swap for item within 7 days
alter table games add column if not exists item_tickets  int not null default 1;
alter table games add column if not exists slug          text unique;   -- /win-<slug>
alter table games add column if not exists category      text;      -- bag, phone, console, cash, watch, trainers, headphones, laptop, tablet, tv, perfume, voucher, holiday
alter table games add column if not exists blurb         text;
alter table games add column if not exists about         text;      -- html
alter table games add column if not exists faq           jsonb;     -- [["q","a"],...]
alter table games add column if not exists question      text;      -- optional qualifying question (unused for instant wins)
alter table allocation add column if not exists item boolean not null default false;

create table if not exists item_claims (
  id bigserial primary key, user_id uuid not null references users(id), pool_id uuid not null, entry_no int not null,
  game text not null, item_name text not null, cashalt_p int not null,
  status text not null default 'cash' check (status in ('cash','item_requested','shipped','cancelled')),
  address text, note text, created_at timestamptz not null default now(), decided_at timestamptz);
alter table item_claims enable row level security;

-- open_pool: same allocation, then mark the item tickets (the rows carrying the cash-alternative amount)
create or replace function open_pool(p_game text, p_mult int default 1) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare g games%rowtype; v_no int; v_seed text; v_id uuid; t jsonb; prizes int[] := '{}'; i int; m int;
begin
  select * into g from games where tag = p_game;
  if not found then raise exception 'unknown game %', p_game; end if;
  m := greatest(coalesce(p_mult,1),1);
  select coalesce(max(pool_no),0)+1 into v_no from pools where game = p_game;
  v_seed := p_game || '-P' || lpad(v_no::text,4,'0') || '-S' || m || '|' || gen_random_uuid();
  insert into pools (game, pool_no, cap, price_p, seed, seed_hash, mult) values (p_game, v_no, g.cap, g.price_p * m, v_seed, encode(digest(v_seed,'sha256'),'hex'), m) returning id into v_id;
  for t in select * from jsonb_array_elements(g.tiers) loop
    for i in 1..(t->>1)::int loop prizes := prizes || ((t->>0)::int * m); end loop;
  end loop;
  if g.item_name is not null then
    for i in 1..greatest(g.item_tickets,1) loop prizes := prizes || g.item_cashalt_p; end loop;
  end if;
  while coalesce(array_length(prizes,1),0) < g.cap loop prizes := prizes || 0; end loop;
  insert into allocation (pool_id, entry_no, prize_p)
  select v_id, row_number() over (order by md5(v_seed || ':' || idx)), prizes[idx] from generate_subscripts(prizes,1) idx;
  if g.item_name is not null then
    update allocation set item = true where pool_id = v_id and entry_no in
      (select entry_no from allocation where pool_id = v_id and prize_p = g.item_cashalt_p order by entry_no limit greatest(g.item_tickets,1));
  end if;
  return v_id;
end $$;

-- buy one ticket; item tickets create a claim and report the item
create or replace function buy_entry3(p_game text, p_token uuid, p_mult int default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; g games%rowtype; v_entry int; v_prize int; v_item boolean; v_extra jsonb := '{}'::jsonb; v_label text; m int; v_claim bigint;
begin
  u := iw_user(p_token);
  select * into g from games where tag=p_game and active; if not found then raise exception 'that ticket is not running'; end if;
  m := 1;
  select * into p from pools where game = p_game and mult = m and status = 'open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool(p_game, m); select * into p from pools where game = p_game and mult = m and status = 'open' order by pool_no desc limit 1 for update; end if;
  if iw_balance(u.id) < p.price_p then raise exception 'insufficient credit'; end if;
  v_label := p.game||'-P'||lpad(p.pool_no::text,4,'0');
  v_entry := p.sold + 1;
  select prize_p, item into v_prize, v_item from allocation where pool_id=p.id and entry_no=v_entry;
  insert into ledger (user_id, delta_p, reason) values (u.id, -p.price_p, 'entry '||v_label||' #'||v_entry);
  update allocation set claimed_by=u.id::text, claimed_at=now() where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  if v_prize > 0 then
    insert into ledger (user_id, delta_p, reason) values (u.id, v_prize, 'win '||v_label||' #'||v_entry||case when v_item then ' — '||g.item_name||' (cash alternative)' else '' end);
  end if;
  if v_item then
    insert into item_claims (user_id, pool_id, entry_no, game, item_name, cashalt_p) values (u.id, p.id, v_entry, p_game, g.item_name, v_prize) returning id into v_claim;
    v_extra := jsonb_build_object('item', g.item_name, 'item_rrp_p', g.item_rrp_p, 'claim_id', v_claim);
  end if;
  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id; perform open_pool(p_game, m);
    v_extra := v_extra || jsonb_build_object('sold_out', true, 'seed', p.seed);
  else v_extra := v_extra || jsonb_build_object('sold_out', false); end if;
  return v_extra || jsonb_build_object('entry_no',v_entry,'prize_p',v_prize,'pool',v_label,'sold',v_entry,'cap',p.cap,'seed_hash',p.seed_hash,'balance_p',iw_balance(u.id),'mult',m);
end $$;

-- buy several tickets in one go (1..50)
create or replace function buy_entries(p_game text, p_token uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare i int; r jsonb; outp jsonb := '[]'::jsonb; n int;
begin
  n := least(greatest(coalesce(p_n,1),1),50);
  for i in 1..n loop r := buy_entry3(p_game, p_token, 1); outp := outp || jsonb_build_array(r); end loop;
  return jsonb_build_object('tickets', outp, 'n', n, 'won_p', (select coalesce(sum((x->>'prize_p')::int),0) from jsonb_array_elements(outp) x),
    'items', (select coalesce(jsonb_agg(x->'item'),'[]'::jsonb) from jsonb_array_elements(outp) x where x ? 'item'),
    'balance_p', (outp->(n-1)->>'balance_p')::int, 'sold', (outp->(n-1)->>'sold')::int, 'cap', (outp->(n-1)->>'cap')::int);
end $$;

-- swap cash alternative for the item (within 7 days)
create or replace function iw_item_swap(p_token uuid, p_claim bigint, p_address text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; c item_claims%rowtype;
begin
  u := iw_user(p_token);
  select * into c from item_claims where id=p_claim and user_id=u.id for update;
  if not found then raise exception 'claim not found'; end if;
  if c.status <> 'cash' then raise exception 'already decided'; end if;
  if c.created_at < now() - interval '7 days' then raise exception 'the 7-day swap window has passed'; end if;
  if length(trim(coalesce(p_address,''))) < 10 then raise exception 'delivery address required'; end if;
  if iw_balance(u.id) < c.cashalt_p then raise exception 'the cash alternative has already been spent or withdrawn'; end if;
  insert into ledger (user_id, delta_p, reason) values (u.id, -c.cashalt_p, 'item swap: '||c.item_name||' (claim #'||c.id||')');
  update item_claims set status='item_requested', address=trim(p_address), decided_at=now() where id=c.id;
  return jsonb_build_object('id',c.id,'status','item_requested','balance_p',iw_balance(u.id));
end $$;
create or replace function iw_my_claims(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'item_name',item_name,'cashalt_p',cashalt_p,'status',status,'created_at',created_at,'decided_at',decided_at,
    'swap_until',created_at+interval '7 days','address',address) order by created_at desc) from item_claims where user_id=u.id),'[]'::jsonb);
end $$;

-- ledger guard: item swaps are not spending
create or replace function iw_ledger_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int; v_limit int;
begin
  if new.delta_p >= 0 or new.reason ilike 'refund%' or new.reason ilike 'admin%' or new.reason ilike 'withdrawal%' or new.reason ilike 'item swap%' then return new; end if;
  select * into u from users where id = new.user_id;
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if u.excluded_until is not null and u.excluded_until > now() then
    raise exception 'paid entries are paused until %', to_char(u.excluded_until at time zone 'Europe/London','DD Mon HH24:MI');
  end if;
  v_limit := u.daily_limit_p;
  if u.pending_limit_at is not null and u.pending_limit_at <= now() then v_limit := u.pending_limit_p; end if;
  if v_limit is not null then
    select coalesce(-sum(delta_p),0) into v_spent from ledger
     where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%' and reason not ilike 'withdrawal%' and reason not ilike 'item swap%'
       and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
    if v_spent - new.delta_p > v_limit then raise exception 'daily spending limit reached (£%)', (v_limit/100.0); end if;
  end if;
  return new;
end $$;

-- public catalogue: item fields + "item still in the round"
create or replace function iw_tickets() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('tag',g.tag,'name',g.name,'tier',g.tier,'code',g.code,'price_p',g.price_p,'cap',g.cap,'tiers',g.tiers,'sort',g.sort,
           'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,
           'prize_total_p',(select coalesce(sum((x->>0)::int*(x->>1)::int),0) from jsonb_array_elements(g.tiers) x)+coalesce(g.item_cashalt_p*g.item_tickets,0),
           'prize_left_p',p.left_p,
           'item_name',g.item_name,'item_rrp_p',g.item_rrp_p,'item_cashalt_p',g.item_cashalt_p,'item_left',p.item_left,'slug',g.slug,'category',g.category,'blurb',g.blurb) order by g.sort),'[]'::jsonb)
  from games g left join lateral (select po.sold, po.pool_no, po.seed_hash,
           (select coalesce(sum(prize_p),0) from allocation a where a.pool_id=po.id and a.claimed_by is null) as left_p,
           (select count(*) from allocation a where a.pool_id=po.id and a.claimed_by is null and a.item) as item_left
         from pools po where po.game=g.tag and po.mult=1 and po.status='open' order by po.pool_no desc limit 1) p on true
  where g.active $$;

-- one prize page
create or replace function iw_prize(p_slug text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g games%rowtype; p pools%rowtype;
begin
  select * into g from games where slug=p_slug and active; if not found then return jsonb_build_object('found',false); end if;
  select * into p from pools where game=g.tag and mult=1 and status='open' order by pool_no desc limit 1;
  return jsonb_build_object('found',true,'tag',g.tag,'name',g.name,'code',g.code,'price_p',g.price_p,'cap',g.cap,'tiers',g.tiers,'item_name',g.item_name,'item_rrp_p',g.item_rrp_p,'item_cashalt_p',g.item_cashalt_p,
    'item_tickets',g.item_tickets,'slug',g.slug,'category',g.category,'blurb',g.blurb,'about',g.about,'faq',g.faq,
    'sold',coalesce(p.sold,0),'round',p.pool_no,'seed_hash',p.seed_hash,
    'item_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.item),
    'tiers_left',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',prize_p,'left',cnt,'item',item) order by prize_p desc),'[]'::jsonb) from (select prize_p, item, count(*) cnt from allocation where pool_id=p.id and claimed_by is null and prize_p>0 group by prize_p, item) s),
    'winners',(select coalesce(jsonb_agg(jsonb_build_object('entry_no',a.entry_no,'prize_p',a.prize_p,'item',a.item,'name',split_part(coalesce(u.name,''),' ',1),'at',a.claimed_at) order by a.claimed_at desc),'[]'::jsonb)
               from (select * from allocation where pool_id=p.id and claimed_by is not null and prize_p>0 order by claimed_at desc limit 10) a left join users u on u.id::text=a.claimed_by));
end $$;

-- admin
create or replace function iw_admin_item_create(p_token uuid, p_tag text, p_name text, p_slug text, p_category text, p_item_name text, p_rrp_p int, p_cashalt_p int, p_price_p int, p_cap int, p_tiers jsonb, p_blurb text, p_about text, p_faq jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  if exists (select 1 from jsonb_array_elements(p_tiers) x where (x->>0)::int = p_cashalt_p) then raise exception 'cash tiers must not equal the cash alternative'; end if;
  insert into games (tag,name,cap,price_p,tiers,tier,code,sort,active,item_name,item_rrp_p,item_cashalt_p,item_tickets,slug,category,blurb,about,faq)
  values (upper(p_tag),p_name,p_cap,p_price_p,p_tiers,'Prize',upper(p_tag),5,true,p_item_name,p_rrp_p,p_cashalt_p,1,lower(p_slug),p_category,p_blurb,p_about,p_faq)
  on conflict (tag) do update set name=excluded.name,cap=excluded.cap,price_p=excluded.price_p,tiers=excluded.tiers,tier='Prize',active=true,item_name=excluded.item_name,item_rrp_p=excluded.item_rrp_p,
    item_cashalt_p=excluded.item_cashalt_p,slug=excluded.slug,category=excluded.category,blurb=excluded.blurb,about=excluded.about,faq=excluded.faq;
  if not exists (select 1 from pools where game=upper(p_tag) and mult=1 and status='open') then perform open_pool(upper(p_tag),1); end if;
  return jsonb_build_object('tag',upper(p_tag),'slug',lower(p_slug));
end $$;
create or replace function iw_admin_item_claims(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'item_name',c.item_name,'cashalt_p',c.cashalt_p,'status',c.status,'address',c.address,'created_at',c.created_at,'decided_at',c.decided_at,
    'email',u.email,'name',u.name,'acct_no',u.acct_no,'game',c.game,'entry_no',c.entry_no) order by c.created_at desc) from item_claims c join users u on u.id=c.user_id),'[]'::jsonb);
end $$;
create or replace function iw_admin_item_claim_set(p_token uuid, p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c item_claims%rowtype;
begin
  perform iw_admin(p_token);
  select * into c from item_claims where id=p_id for update; if not found then raise exception 'claim not found'; end if;
  if p_status='cancelled' and c.status='item_requested' then insert into ledger (user_id, delta_p, reason) values (c.user_id, c.cashalt_p, 'refund: item swap cancelled (claim #'||c.id||')'); end if;
  update item_claims set status=p_status, note=p_note, decided_at=now() where id=p_id;
  return iw_admin_item_claims(p_token);
end $$;
grant execute on function buy_entries(text,uuid,int), iw_item_swap(uuid,bigint,text), iw_my_claims(uuid), iw_prize(text), iw_tickets(),
  iw_admin_item_create(uuid,text,text,text,text,text,int,int,int,int,jsonb,text,text,jsonb), iw_admin_item_claims(uuid), iw_admin_item_claim_set(uuid,bigint,text,text) to service_role;

-- three launch items (mirrors the example pages). Cash tiers never equal the cash alternative.
insert into games (tag,name,cap,price_p,tiers,tier,code,sort,active,item_name,item_rrp_p,item_cashalt_p,item_tickets,slug,category,blurb,about,faq) values
 ('LVN','Louis Vuitton Neverfull MM',2000,199,'[[10000,1],[2500,4],[1000,10],[500,25]]','Prize','LVN',1,true,'Louis Vuitton Neverfull MM',165000,125000,1,'louis-vuitton-neverfull','bag',
  'Monogram canvas, the classic MM size, brand new and boxed with receipt. Or take £1,250 cash.',
  '<p>The Neverfull MM is the one everybody recognises: the open-top tote in Monogram canvas with cowhide trim. This one is brand new, bought at retail by IGX Ltd, and comes with the dust bag, box and our purchase receipt.</p><p>One ticket in this round is the bag. The moment it is bought, its owner sees it and £1,250 is credited at once; they have seven days to swap that for the bag itself, delivered insured and signed for.</p>',
  '[["Is the bag genuine?","Yes. Bought at retail or from an authenticated reseller; the winner sees the receipt."],["What if I would rather have cash?","£1,250 is credited the moment you win. Do nothing and it is yours to withdraw."],["How do I enter for free?","Postcard naming this round — Louis Vuitton Neverfull MM £1.99 — with your name and account number. Same ticket sequence, same odds."]]'),
 ('IP17','iPhone 17 Pro 256GB',1500,149,'[[5000,1],[2000,4],[500,25]]','Prize','IP17',2,true,'iPhone 17 Pro 256GB',109900,85000,1,'iphone-17-pro','phone',
  'Sealed, unlocked, any colour, 256GB. Or take £850 cash.',
  '<p>A sealed iPhone 17 Pro, 256GB, unlocked to any network, in the colour you choose when you win. Delivered insured and signed-for within 7 days, or keep the £850 credited the moment your ticket reveals it.</p>',
  '[["Is it unlocked?","Yes, factory unlocked, sealed, full Apple warranty from the date you receive it."],["Can I choose the colour?","Yes, any colour in stock when you win."],["How do I enter for free?","Postcard naming this round — iPhone 17 Pro 256GB £1.49 — with your name and account number."]]'),
 ('PS5P','PlayStation 5 Pro',1500,99,'[[5000,1],[1000,4],[200,25]]','Prize','PS5P',3,true,'PlayStation 5 Pro',69900,55000,1,'ps5-pro','console',
  'Brand new, boxed, with a second controller. Or take £550 cash.',
  '<p>The PS5 Pro, boxed and sealed, plus a second DualSense controller. Delivered within 7 days of your win, or keep the £550 credited on the spot.</p>',
  '[["Disc or digital?","Disc edition."],["Does it come with games?","No, console and two controllers."],["How do I enter for free?","Postcard naming this round — PlayStation 5 Pro 99p — with your name and account number."]]')
on conflict (tag) do nothing;
do $$ declare g record; begin
  for g in select tag from games where item_name is not null and active loop
    if not exists (select 1 from pools where game=g.tag and mult=1 and status='open') then perform open_pool(g.tag,1); end if;
  end loop;
end $$;
notify pgrst, 'reload schema';
