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
