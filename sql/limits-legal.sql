-- limits-legal.sql — responsible-play controls (DCMS Code 1.3–1.8). Run after accounts-schema.sql.
--   • Daily spending limit (including £0): a lower limit applies at once, a higher one after 24 hours.
--   • Take a break (24h / 7d / 30d / 180d): blocks paid entries; cannot be lifted early.
--   • Close account: permanent block on paid entries.
--   • Enforced by a trigger on the ledger, so every paid route (Card, tickets, pieces) is covered.
--   • Free entries are never blocked.

alter table users add column if not exists daily_limit_p   int;
alter table users add column if not exists pending_limit_p int;
alter table users add column if not exists pending_limit_at timestamptz;
alter table users add column if not exists excluded_until  timestamptz;
alter table users add column if not exists closed_at       timestamptz;

create or replace function iw_limits(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int;
begin
  u := iw_user(p_token);
  if u.pending_limit_at is not null and u.pending_limit_at <= now() then
    update users set daily_limit_p = pending_limit_p, pending_limit_p = null, pending_limit_at = null where id = u.id;
    u.daily_limit_p := u.pending_limit_p; u.pending_limit_p := null; u.pending_limit_at := null;
  end if;
  select coalesce(-sum(delta_p),0) into v_spent from ledger
   where user_id = u.id and delta_p < 0 and reason not ilike 'refund%'
     and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
  return jsonb_build_object('daily_limit_p', u.daily_limit_p, 'pending_limit_p', u.pending_limit_p, 'pending_limit_at', u.pending_limit_at,
    'spent_today_p', v_spent, 'excluded_until', u.excluded_until, 'closed_at', u.closed_at);
end $$;

create or replace function iw_set_limit(p_token uuid, p_limit_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if p_limit_p is not null and p_limit_p < 0 then raise exception 'limit must be 0 or more'; end if;
  if p_limit_p is null or (u.daily_limit_p is not null and p_limit_p > u.daily_limit_p) then
    -- raising or removing a limit: 24-hour cooling-off
    update users set pending_limit_p = p_limit_p, pending_limit_at = now() + interval '24 hours' where id = u.id;
  else
    update users set daily_limit_p = p_limit_p, pending_limit_p = null, pending_limit_at = null where id = u.id;
  end if;
  return iw_limits(p_token);
end $$;

create or replace function iw_take_break(p_token uuid, p_days int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if p_days not in (1,7,30,180) then raise exception 'break must be 1, 7, 30 or 180 days'; end if;
  update users set excluded_until = greatest(coalesce(excluded_until, now()), now() + (p_days||' days')::interval) where id = u.id;
  return iw_limits(p_token);
end $$;

create or replace function iw_close_account(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  update users set closed_at = now() where id = u.id;
  delete from sessions where user_id = u.id;
  return jsonb_build_object('closed', true);
end $$;

-- enforcement: every paid debit passes through here
create or replace function iw_ledger_guard() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_spent int; v_limit int;
begin
  if new.delta_p >= 0 or new.reason ilike 'refund%' or new.reason ilike 'admin%' then return new; end if;
  select * into u from users where id = new.user_id;
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if u.excluded_until is not null and u.excluded_until > now() then
    raise exception 'paid entries are paused until %', to_char(u.excluded_until at time zone 'Europe/London','DD Mon HH24:MI');
  end if;
  v_limit := u.daily_limit_p;
  if u.pending_limit_at is not null and u.pending_limit_at <= now() then v_limit := u.pending_limit_p; end if;
  if v_limit is not null then
    select coalesce(-sum(delta_p),0) into v_spent from ledger
     where user_id = u.id and delta_p < 0 and reason not ilike 'refund%' and reason not ilike 'admin%'
       and created_at >= date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
    if v_spent - new.delta_p > v_limit then raise exception 'daily spending limit reached (£%)', (v_limit/100.0); end if;
  end if;
  return new;
end $$;
drop trigger if exists iw_ledger_guard on ledger;
create trigger iw_ledger_guard before insert on ledger for each row execute function iw_ledger_guard();

grant execute on function iw_limits(uuid), iw_set_limit(uuid,int), iw_take_break(uuid,int), iw_close_account(uuid) to service_role;
notify pgrst, 'reload schema';
