-- reset.sql — remove bots, reset all prizes, delete all accounts except admin.
-- DESTRUCTIVE, test-mode cleanup. Run once in Supabase.

-- 1) stop the bot auto-player
do $$ begin perform cron.unschedule('iw-bots'); exception when others then null; end $$;

-- 2) delete every account except the admin (cascades ledger + sessions; removes all bots too)
delete from users where lower(email) <> 'ryan@sm-i.co.uk';

-- 3) give the admin a clean £20 wallet
delete from ledger where user_id in (select id from users where lower(email)='ryan@sm-i.co.uk');
insert into ledger (user_id, delta_p, reason)
  select id, 2000, 'welcome play credit' from users where lower(email)='ryan@sm-i.co.uk';

-- 4) reset all game prizes — wipe pools/allocations, open fresh ones
delete from allocation;
delete from pools;
select open_pool(tag) from games;

-- 5) reset the Card — wipe entries/draws, open fresh ones
delete from card_entries;
delete from card_draws;
select card_ensure_open();

notify pgrst, 'reload schema';
