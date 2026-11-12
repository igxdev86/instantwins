-- monthly-limit.sql — DCMS code 1.4: a monthly spend limit across all draws (player-settable, £0 allowed), alongside the daily one.
alter table users add column if not exists monthly_limit_p int;
alter table users add column if not exists pending_mlimit_p int;
alter table users add column if not exists pending_mlimit_at timestamptz;

create or replace function iw_limits(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int; v_mspent int;
begin
  u := iw_user(p_token);
  if u.pending_limit_at is not null and u.pending_limit_at <= now() then
    update users set daily_limit_p = pending_limit_p, pending_limit_p = null, pending_limit_at = null where id = u.id;
    u.daily_limit_p := u.pending_limit_p; u.pending_limit_p := null; u.pending_limit_at := null;
  end if;
  if u.pending_mlimit_at is not null and u.pending_mlimit_at <= now() then
    update users set monthly_limit_p = pending_mlimit_p, pending_mlimit_p = null, pending_mlimit_at = null where id = u.id;
    u.monthly_limit_p := u.pending_mlimit_p; u.pending_mlimit_p := null; u.pending_mlimit_at := null;
  end if;
  select coalesce(-sum(delta_p),0) into v_spent from ledger where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%'
     and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
  select coalesce(-sum(delta_p),0) into v_mspent from ledger where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%'
     and created_at >= date_trunc('month', now() at time zone 'Europe/London') at time zone 'Europe/London';
  return jsonb_build_object('daily_limit_p', u.daily_limit_p, 'pending_limit_p', u.pending_limit_p, 'pending_limit_at', u.pending_limit_at,
    'monthly_limit_p', u.monthly_limit_p, 'pending_mlimit_p', u.pending_mlimit_p, 'pending_mlimit_at', u.pending_mlimit_at,
    'spent_today_p', v_spent, 'spent_month_p', v_mspent, 'excluded_until', u.excluded_until, 'closed', u.closed_at is not null);
end $$;

create or replace function iw_set_monthly_limit(p_token uuid, p_limit_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if p_limit_p is not null and p_limit_p < 0 then raise exception 'limit must be 0 or more'; end if;
  if p_limit_p is null or (u.monthly_limit_p is not null and p_limit_p > u.monthly_limit_p) then
    update users set pending_mlimit_p = p_limit_p, pending_mlimit_at = now() + interval '24 hours' where id = u.id;
  else
    update users set monthly_limit_p = p_limit_p, pending_mlimit_p = null, pending_mlimit_at = null where id = u.id;
  end if;
  return iw_limits(p_token);
end $$;

create or replace function iw_ledger_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int; v_limit int; v_mlimit int;
begin
  if new.delta_p >= 0 or new.reason ilike 'refund%' or new.reason ilike 'admin%' then return new; end if;
  select * into u from users where id = new.user_id;
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if u.excluded_until is not null and u.excluded_until > now() then
    raise exception 'paid entries are paused until %', to_char(u.excluded_until at time zone 'Europe/London','DD Mon HH24:MI');
  end if;
  v_limit := u.daily_limit_p; if u.pending_limit_at is not null and u.pending_limit_at <= now() then v_limit := u.pending_limit_p; end if;
  if v_limit is not null then
    select coalesce(-sum(delta_p),0) into v_spent from ledger where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%'
       and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
    if v_spent - new.delta_p > v_limit then raise exception 'daily spending limit reached (£%)', (v_limit/100.0); end if;
  end if;
  v_mlimit := u.monthly_limit_p; if u.pending_mlimit_at is not null and u.pending_mlimit_at <= now() then v_mlimit := u.pending_mlimit_p; end if;
  if v_mlimit is not null then
    select coalesce(-sum(delta_p),0) into v_spent from ledger where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%'
       and created_at >= date_trunc('month', now() at time zone 'Europe/London') at time zone 'Europe/London';
    if v_spent - new.delta_p > v_mlimit then raise exception 'monthly spending limit reached (£%)', (v_mlimit/100.0); end if;
  end if;
  return new;
end $$;
drop trigger if exists iw_ledger_guard on ledger;
create trigger iw_ledger_guard before insert on ledger for each row execute function iw_ledger_guard();
grant execute on function iw_limits(uuid), iw_set_monthly_limit(uuid,int) to service_role;
notify pgrst, 'reload schema';
