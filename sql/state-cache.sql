-- state-cache.sql — the public round state is computed at most once every 10 seconds and served from a cache row,
-- instead of five scans over 1.4m prize rows on every page load.
create table if not exists state_cache (k text primary key, data jsonb, at timestamptz not null default now());
alter table state_cache enable row level security;

create or replace function c2_state_cached(p_max_age_s int default 10) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v jsonb; v_at timestamptz;
begin
  select data, at into v, v_at from state_cache where k='mil';
  if v is not null and v_at > now() - make_interval(secs => p_max_age_s) then return v; end if;
  v := c2_state();
  insert into state_cache (k, data, at) values ('mil', v, now()) on conflict (k) do update set data=excluded.data, at=now();
  return v;
end $$;
-- buys and reveals invalidate it so the numbers move straight away for the person who just acted
create or replace function trg_state_bust() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin update state_cache set at = now() - interval '1 hour' where k='mil'; return null; end $$;
drop trigger if exists state_bust_alloc on allocation;
create trigger state_bust_alloc after update of claimed_by, revealed on allocation for each statement execute function trg_state_bust();
drop trigger if exists state_bust_pools on pools;
create trigger state_bust_pools after update on pools for each statement execute function trg_state_bust();
grant execute on function c2_state_cached(int) to service_role;
notify pgrst, 'reload schema';
