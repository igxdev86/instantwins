-- ===================== games-rename2.sql =====================
update games set name='Golden Ticket' where tag='PL';
notify pgrst, 'reload schema';

-- ===================== instant-books.sql =====================
-- instant-books.sql — four Instant Win books. Golden (PL) and Platinum (SC) already exist; Mega (SP) exists;
-- Diamond reuses the DD tag with a new table. Run once.
update games set name='Golden Ticket'   where tag='PL';
update games set name='Platinum Ticket' where tag='SC';
update games set name='Mega Ticket'     where tag='SP';
insert into games (tag, name, cap, price_p, tiers) values
 ('DD','Diamond Ticket',1000,1000,'[[250000,1],[50000,1],[20000,5],[5000,10],[2000,20],[1000,40]]')
on conflict (tag) do update set name=excluded.name, cap=excluded.cap, price_p=excluded.price_p, tiers=excluded.tiers;
update pools set status='settled', settled_at=now() where game='DD' and status='open';
select open_pool('DD', 1);
notify pgrst, 'reload schema';

-- ===================== card-verify.sql =====================
-- card-verify.sql — public lookup of one draw by game number, for the "check this draw" page.
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
    'status',d.status,'price_p',d.price_p,'prize_p',d.prize_p,'cap',d.cap,'sold',d.sold,'seed_hash',d.seed_hash,
    'seed',case when d.status='settled' then d.seed end,'winner_entry',d.winner_entry,'settled_at',d.settled_at,
    'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
    'postal_entries',(select count(*) from card_entries ce where ce.draw_id=d.id and ce.via='post'));
end $$;
grant execute on function card_lookup(text) to service_role;
notify pgrst, 'reload schema';

-- ===================== stats-public.sql =====================
-- stats-public.sql — honest, live site totals for the home page strip. Real ledger data only.
create or replace function iw_public_stats() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare day0 timestamptz := date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
        v_entries int; v_winners int; v_paid bigint; v_last jsonb;
begin
  perform card_settle_due();
  select count(*) into v_entries from card_entries ce join card_draws d on d.id=ce.draw_id where ce.created_at >= day0;
  select count(*), coalesce(sum(prize_p),0) into v_winners, v_paid from card_draws where status='settled' and winner_entry is not null and settled_at >= day0;
  select jsonb_build_object('name',split_part(coalesce(u.name,''),' ',1),'prize_p',d.prize_p,'label',drawlabel(d.kind),'at',d.settled_at,'game_no',card_game_no(d.kind,d.off_at))
    into v_last from card_draws d join card_entries ce on ce.draw_id=d.id and ce.entry_no=d.winner_entry join users u on u.id::text=ce.punter
   where d.status='settled' and d.winner_entry is not null order by d.settled_at desc limit 1;
  return jsonb_build_object('entries_today',v_entries,'winners_today',v_winners,'paid_today_p',v_paid,'last',v_last,'server_now',now());
end $$;
grant execute on function iw_public_stats() to service_role;
notify pgrst, 'reload schema';

-- ===================== card-small.sql =====================
-- card-small.sql — 30-Second "small" draws (£1, £2, £5, £8) + back-office on/off switches
-- for draw kinds and whole cadence groups. Run AFTER postal-roll.sql.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('t_1','T1','30-Second £1',  10,  100, 20, 30, 0, null, 1),
 ('t_2','T2','30-Second £2',  20,  200, 20, 30, 0, null, 2),
 ('t_5','T5','30-Second £5',  50,  500, 20, 30, 0, null, 3),
 ('t_8','T8','30-Second £8', 100,  800, 16, 30, 0, null, 4)
on conflict (kind) do update set code=excluded.code, label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;

-- admin: list every kind with its switch
create or replace function iw_admin_kinds(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,
    'cap',cap,'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'sort',sort,'active',active,
    'open_entries',(select coalesce(sum(sold),0) from card_draws d where d.kind=card_kinds.kind and d.status='open')) order by sort)
    from card_kinds),'[]'::jsonb);
end $$;

-- admin: switch one kind, or every kind in a cadence group (p_kind null + p_step set)
create or replace function iw_admin_kind_active(p_token uuid, p_kind text, p_step int, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  if p_kind is not null then update card_kinds set active=p_active where kind=p_kind;
  elsif p_step is not null then update card_kinds set active=p_active where step_s=p_step;
  else raise exception 'kind or step required'; end if;
  return iw_admin_kinds(p_token);
end $$;
grant execute on function iw_admin_kinds(uuid), iw_admin_kind_active(uuid,text,int,boolean) to service_role;

-- switched-off kinds: no new draws, no new entries. Draws already holding entries still settle and pay.
create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  foreach k in array card_kinds() loop perform card_draw_for(k, card_next_off(k)); end loop;
end $$;
select card_ensure_open();
notify pgrst, 'reload schema';

-- ===================== card-30s.sql =====================
-- card-30s.sql — the small draws run every 30 seconds.
update card_kinds set step_s=30, label=replace(label,'Two-Minute','30-Second') where kind in ('t_1','t_2','t_5','t_8');
delete from card_draws where kind in ('t_1','t_2','t_5','t_8') and status='open' and sold=0;
select card_ensure_open();
notify pgrst, 'reload schema';

-- ===================== instant-books-2.sql =====================
-- instant-books-2.sql — four low-price Instant Win tickets. Reuses retired game tags. Run once.
insert into games (tag, name, cap, price_p, tiers) values
 ('LD','Penny Ticket',  200,  10, '[[500,1],[100,2],[50,3],[20,5],[10,10]]'),
 ('CL','Bronze Ticket', 250,  20, '[[1000,1],[200,3],[100,5],[50,8],[20,15]]'),
 ('PR','Silver Ticket', 300,  50, '[[2500,1],[500,3],[200,6],[100,10],[50,25]]'),
 ('PF','Lucky Ticket',  400, 100, '[[5000,1],[1000,3],[500,8],[200,20],[100,30]]')
on conflict (tag) do update set name=excluded.name, cap=excluded.cap, price_p=excluded.price_p, tiers=excluded.tiers;
update pools set status='settled', settled_at=now() where game in ('LD','CL','PR','PF') and status='open';
select open_pool('LD',1); select open_pool('CL',1); select open_pool('PR',1); select open_pool('PF',1);
notify pgrst, 'reload schema';

-- ===================== payments-bank.sql =====================
-- payments-bank.sql — manual bank-transfer deposits and withdrawals (the PRIZERUN model).
--   • Deposit: player states an amount, pays IGX Ltd by bank transfer quoting their account number
--     (IW…) as the reference; admin approves when it lands → ledger credit.
--   • Withdrawal: player gives bank details; the amount is held (ledger debit) at once; admin pays
--     and marks it paid, or declines → hold refunded.
--   • Nothing is offered until site_settings.payments_live = 'true' (admin switch).
-- Run AFTER limits-legal.sql.

create table if not exists site_settings (key text primary key, value text not null, updated_at timestamptz not null default now());
insert into site_settings (key,value) values ('payments_live','false') on conflict (key) do nothing;

create table if not exists deposits (
  id bigserial primary key, user_id uuid not null references users(id), amount_p int not null check (amount_p > 0),
  reference text not null, status text not null default 'pending' check (status in ('pending','approved','declined')),
  note text, created_at timestamptz not null default now(), decided_at timestamptz);
create table if not exists withdrawals (
  id bigserial primary key, user_id uuid not null references users(id), amount_p int not null check (amount_p > 0),
  account_name text not null, sort_code text not null, account_no text not null,
  status text not null default 'pending' check (status in ('pending','paid','declined')),
  note text, created_at timestamptz not null default now(), decided_at timestamptz);
alter table deposits enable row level security; alter table withdrawals enable row level security;

create or replace function iw_payments_live() returns boolean
language sql stable as $$ select coalesce((select value='true' from site_settings where key='payments_live'), false) $$;

-- withdrawals must not be blocked by spending limits / breaks
create or replace function iw_ledger_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int; v_limit int;
begin
  if new.delta_p >= 0 or new.reason ilike 'refund%' or new.reason ilike 'admin%' or new.reason ilike 'withdrawal%' then return new; end if;
  select * into u from users where id = new.user_id;
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if u.excluded_until is not null and u.excluded_until > now() then
    raise exception 'paid entries are paused until %', to_char(u.excluded_until at time zone 'Europe/London','DD Mon HH24:MI');
  end if;
  v_limit := u.daily_limit_p;
  if u.pending_limit_at is not null and u.pending_limit_at <= now() then v_limit := u.pending_limit_p; end if;
  if v_limit is not null then
    select coalesce(-sum(delta_p),0) into v_spent from ledger
     where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%' and reason not ilike 'withdrawal%'
       and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
    if v_spent - new.delta_p > v_limit then raise exception 'daily spending limit reached (£%)', (v_limit/100.0); end if;
  end if;
  return new;
end $$;

create or replace function iw_deposit_request(p_token uuid, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint;
begin
  u := iw_user(p_token);
  if not iw_payments_live() then raise exception 'payments are not open yet'; end if;
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if p_amount_p < 500 or p_amount_p > 50000 then raise exception 'deposit between £5 and £500'; end if;
  insert into deposits (user_id, amount_p, reference) values (u.id, p_amount_p, coalesce(u.acct_no, 'IW'||substr(u.id::text,1,8))) returning id into v_id;
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'reference',coalesce(u.acct_no,'IW'||substr(u.id::text,1,8)));
end $$;

create or replace function iw_withdraw_request(p_token uuid, p_amount_p int, p_name text, p_sort text, p_acct text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint; v_sort text; v_acct text;
begin
  u := iw_user(p_token);
  if not iw_payments_live() then raise exception 'payments are not open yet'; end if;
  v_sort := regexp_replace(coalesce(p_sort,''), '\D', '', 'g'); v_acct := regexp_replace(coalesce(p_acct,''), '\D', '', 'g');
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'account holder name required'; end if;
  if length(v_sort) <> 6 then raise exception 'sort code should be 6 digits'; end if;
  if length(v_acct) <> 8 then raise exception 'account number should be 8 digits'; end if;
  if p_amount_p < 500 then raise exception 'minimum withdrawal £5'; end if;
  if iw_balance(u.id) < p_amount_p then raise exception 'insufficient balance'; end if;
  insert into withdrawals (user_id, amount_p, account_name, sort_code, account_no) values (u.id, p_amount_p, trim(p_name), v_sort, v_acct) returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (u.id, -p_amount_p, 'withdrawal #'||v_id||' requested');
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'balance_p',iw_balance(u.id));
end $$;

create or replace function iw_my_payments(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('live', iw_payments_live(), 'reference', coalesce(u.acct_no,'IW'||substr(u.id::text,1,8)), 'balance_p', iw_balance(u.id),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note) order by created_at desc) from (select * from deposits where user_id=u.id order by created_at desc limit 20) d),'[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note,'last4',right(account_no,4)) order by created_at desc) from (select * from withdrawals where user_id=u.id order by created_at desc limit 20) w),'[]'::jsonb));
end $$;

-- ---------- admin ----------
create or replace function iw_admin_payments(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object('live', iw_payments_live(),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'amount_p',d.amount_p,'reference',d.reference,'status',d.status,'created_at',d.created_at,'email',u.email,'name',u.name,'acct_no',u.acct_no) order by d.created_at desc)
       from deposits d join users u on u.id=d.user_id where d.status='pending' or d.decided_at > now()-interval '2 days'),'[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'amount_p',w.amount_p,'account_name',w.account_name,'sort_code',w.sort_code,'account_no',w.account_no,'status',w.status,'created_at',w.created_at,'email',u.email,'name',u.name,'acct_no',u.acct_no) order by w.created_at desc)
       from withdrawals w join users u on u.id=w.user_id where w.status='pending' or w.decided_at > now()-interval '2 days'),'[]'::jsonb));
end $$;

create or replace function iw_admin_deposit_decide(p_token uuid, p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d deposits%rowtype;
begin
  perform iw_admin(p_token);
  select * into d from deposits where id=p_id for update;
  if not found or d.status<>'pending' then raise exception 'deposit not pending'; end if;
  update deposits set status=case when p_approve then 'approved' else 'declined' end, decided_at=now(), note=p_note where id=p_id;
  if p_approve then insert into ledger (user_id, delta_p, reason) values (d.user_id, d.amount_p, 'deposit #'||d.id||' by bank transfer'); end if;
  return iw_admin_payments(p_token);
end $$;

create or replace function iw_admin_withdraw_decide(p_token uuid, p_id bigint, p_paid boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare w withdrawals%rowtype;
begin
  perform iw_admin(p_token);
  select * into w from withdrawals where id=p_id for update;
  if not found or w.status<>'pending' then raise exception 'withdrawal not pending'; end if;
  update withdrawals set status=case when p_paid then 'paid' else 'declined' end, decided_at=now(), note=p_note where id=p_id;
  if not p_paid then insert into ledger (user_id, delta_p, reason) values (w.user_id, w.amount_p, 'refund: withdrawal #'||w.id||' declined'); end if;
  return iw_admin_payments(p_token);
end $$;

create or replace function iw_admin_setting(p_token uuid, p_key text, p_value text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into site_settings (key,value,updated_at) values (p_key,p_value,now()) on conflict (key) do update set value=excluded.value, updated_at=now();
  return (select jsonb_object_agg(key,value) from site_settings);
end $$;

grant execute on function iw_deposit_request(uuid,int), iw_withdraw_request(uuid,int,text,text,text), iw_my_payments(uuid),
  iw_admin_payments(uuid), iw_admin_deposit_decide(uuid,bigint,boolean,text), iw_admin_withdraw_decide(uuid,bigint,boolean,text), iw_admin_setting(uuid,text,text) to service_role;
notify pgrst, 'reload schema';

-- ===================== launch.sql =====================
-- launch.sql — going live. Run AFTER payments-bank.sql.
--   1. The £20 welcome play-credit stops the moment payments are live (it would be real money).
--   2. Every existing play-money balance is zeroed ONCE when you flip the switch (admin accounts too),
--      so nobody carries test credit into real money. Done by iw_go_live(), called from the admin switch.

create or replace function iw_signup(p_email text, p_pass text, p_name text, p_dob date)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_tok uuid; v_welcome int := case when iw_payments_live() then 0 else 2000 end;
begin
  if length(trim(p_email)) < 5 or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  if length(p_pass) < 8 then raise exception 'password must be at least 8 characters'; end if;
  if length(trim(p_name)) < 2 then raise exception 'name required'; end if;
  if p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over'; end if;
  if exists (select 1 from users where lower(email)=lower(trim(p_email))) then
    raise exception 'an account with that email already exists';
  end if;
  insert into users (email, pass, name, dob)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob)
  returning id into v_id;
  if v_welcome > 0 then insert into ledger (user_id, delta_p, reason) values (v_id, v_welcome, 'welcome play credit'); end if;
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', trim(p_name), 'email', trim(p_email), 'is_admin', false, 'balance_p', v_welcome);
end $$;

-- zero every play-money balance once, then switch payments on
create or replace function iw_go_live(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0;
begin
  perform iw_admin(p_token);
  if iw_payments_live() then return jsonb_build_object('already_live', true); end if;
  for r in select u.id, iw_balance(u.id) bal from users u loop
    if r.bal <> 0 then
      insert into ledger (user_id, delta_p, reason) values (r.id, -r.bal, 'admin: play-money balance cleared at launch'); n := n + 1;
    end if;
  end loop;
  insert into site_settings (key,value,updated_at) values ('payments_live','true',now()) on conflict (key) do update set value='true', updated_at=now();
  insert into site_settings (key,value,updated_at) values ('launched_at',now()::text,now()) on conflict (key) do update set value=now()::text, updated_at=now();
  return jsonb_build_object('live', true, 'balances_cleared', n);
end $$;

-- public: is the site live? (no token needed)
create or replace function iw_site() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('live', iw_payments_live(), 'launched_at', (select value from site_settings where key='launched_at')) $$;

grant execute on function iw_go_live(uuid), iw_site() to service_role;
notify pgrst, 'reload schema';

