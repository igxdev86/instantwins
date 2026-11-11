-- games-switch.sql — admin switch: show the themed games or Quick Reveal only (default: reveal only).
insert into site_settings (key,value) values ('games_enabled','false') on conflict (key) do nothing;
create or replace function iw_site() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('live', iw_payments_live(), 'launched_at', (select value from site_settings where key='launched_at'),
    'games', coalesce((select value='true' from site_settings where key='games_enabled'), false)) $$;
create or replace function iw_admin_games(p_token uuid, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into site_settings (key,value,updated_at) values ('games_enabled', case when p_on then 'true' else 'false' end, now())
    on conflict (key) do update set value=excluded.value, updated_at=now();
  return jsonb_build_object('games',p_on);
end $$;
grant execute on function iw_site(), iw_admin_games(uuid,boolean) to service_role;
notify pgrst, 'reload schema';
