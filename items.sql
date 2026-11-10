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
