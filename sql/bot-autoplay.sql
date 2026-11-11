-- =====================================================================
-- BOT AUTO-PLAYER — makes the 100 bots play on a schedule (TEST ONLY).
-- Runs server-side via pg_cron every minute; each tick fires N plays
-- across games, the Spins mega-pool, and the Card. Winners settle and
-- surface on the boards. Tune liveliness with the number in iw_bot_tick.
-- Stop any time:  select cron.unschedule('iw-bots');
-- =====================================================================

create or replace function iw_bot_play_game(uid uuid, p_tag text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; v_entry int; v_prize int;
begin
  select * into p from pools where game=p_tag and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool(p_tag);
    select * into p from pools where game=p_tag and status='open' order by pool_no desc limit 1 for update; end if;
  if iw_balance(uid) < p.price_p then return; end if;
  v_entry := p.sold + 1;
  select prize_p into v_prize from allocation where pool_id=p.id and entry_no=v_entry;
  insert into ledger(user_id,delta_p,reason) values (uid,-p.price_p,'bot '||p.game||' #'||v_entry);
  update allocation set claimed_by=uid::text, claimed_at=now() where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  if coalesce(v_prize,0)>0 then
    insert into ledger(user_id,delta_p,reason) values (uid,v_prize,'bot win '||p.game||' #'||v_entry);
  end if;
  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id;
    perform open_pool(p.game);
  end if;
end $$;

create or replace function iw_bot_play_card(uid uuid, p_kind text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_no int;
begin
  select * into d from card_draws where kind=p_kind and status='open' order by off_at asc limit 1 for update;
  if not found then return; end if;
  if d.cap is not null and d.sold >= d.cap then return; end if;
  if p_kind='free' then
    if exists (select 1 from card_entries where draw_id=d.id and punter=uid::text) then return; end if;
  else
    if iw_balance(uid) < d.price_p then return; end if;
  end if;
  v_no := d.sold + 1;
  if d.price_p > 0 then
    insert into ledger(user_id,delta_p,reason) values (uid,-d.price_p,'bot '||p_kind||' #'||v_no);
  end if;
  insert into card_entries(draw_id,entry_no,punter) values (d.id,v_no,uid::text);
  update card_draws set sold=v_no where id=d.id;
end $$;

create or replace function iw_bot_tick(p_n int default 80) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k int; uid uuid; r float; v_tag text; v_kind text;
begin
  perform card_settle_due();
  perform card_ensure_open();
  for k in 1..p_n loop
    select id into uid from users where is_bot order by random() limit 1;
    if uid is null then return; end if;
    r := random();
    if r < 0.55 then
      select tag into v_tag from games where tag <> 'SP' order by random() limit 1;
      if v_tag is not null then perform iw_bot_play_game(uid, v_tag); end if;
    elsif r < 0.80 then
      perform iw_bot_play_game(uid, 'SP');
    else
      v_kind := (array['five','five','free','grand'])[1+floor(random()*4)];
      perform iw_bot_play_card(uid, v_kind);
    end if;
  end loop;
  perform card_settle_due();
end $$;

grant execute on function iw_bot_tick(int) to service_role;

-- schedule it: 80 plays/min (~1.3/sec). Change 80 to taste, or unschedule to stop.
create extension if not exists pg_cron;
do $$ begin perform cron.unschedule('iw-bots'); exception when others then null; end $$;
select cron.schedule('iw-bots', '* * * * *', 'select iw_bot_tick(80);');

-- kick one tick now so you see activity immediately
select iw_bot_tick(80);
