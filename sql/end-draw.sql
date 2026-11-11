-- end-draw.sql — Closing date + End Prize Draw for the Million Round.
-- Every round has a closing date. At the earlier of sell-out and the closing date the round closes:
--   • one End Prize (default £10,000) is drawn from ALL tickets issued in the round (paid and postal alike), commit-and-reveal from the round seed;
--   • any unopened ticket is opened and its prize credited;
--   • the seed is published; the next round opens with its own closing date.
-- Prizes on tickets never sold in a closed round are not awarded (the terms say so).

alter table pools add column if not exists closes_at timestamptz;
alter table pools add column if not exists end_prize_p int not null default 0;
alter table pools add column if not exists end_winner_entry int;
alter table pools add column if not exists end_drawn_at timestamptz;
alter table pools add column if not exists end_winner_user uuid;
insert into site_settings (key,value) values ('mil_round_days','60') on conflict (key) do nothing;
insert into site_settings (key,value) values ('mil_end_prize_p','1000000') on conflict (key) do nothing;

-- give the current open round a date + end prize if it has none
update pools set closes_at = date_trunc('day', now() + make_interval(days => (select value::int from site_settings where key='mil_round_days'))) + interval '20 hours',
                 end_prize_p = (select value::int from site_settings where key='mil_end_prize_p')
 where game='MIL' and status='open' and closes_at is null;

-- new rounds get a date + end prize automatically
create or replace function trg_pool_defaults() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.game='MIL' then
    if new.closes_at is null then new.closes_at := date_trunc('day', now() + make_interval(days => coalesce((select value::int from site_settings where key='mil_round_days'),60))) + interval '20 hours'; end if;
    if new.end_prize_p = 0 then new.end_prize_p := coalesce((select value::int from site_settings where key='mil_end_prize_p'),1000000); end if;
  end if;
  return new;
end $$;
drop trigger if exists pool_defaults on pools;
create trigger pool_defaults before insert on pools for each row execute function trg_pool_defaults();

-- the draw itself: number = 1 + (first 8 hex of md5(seed||':end') as int) mod tickets issued
create or replace function c2_end_number(p_seed text, p_sold int) returns int
language sql immutable as $$ select 1 + ((('x'||substr(md5(p_seed||':end'),1,8))::bit(32)::bigint & 2147483647) % greatest(p_sold,1))::int $$;

-- close a round: end draw + open unopened + next round
create or replace function c2_close_round(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; n int := 0; won bigint := 0; r record; v_no int; v_uid uuid; v_label text;
begin
  select * into p from pools where id=p_id for update;
  if not found then return jsonb_build_object('error','no round'); end if;
  v_label := 'MIL-P'||lpad(p.pool_no::text,4,'0');
  if p.status='open' then update pools set status='settled', settled_at=now() where id=p.id; end if;
  -- open every unopened ticket
  for r in update allocation a set revealed=true where a.pool_id=p.id and a.claimed_by is not null and not a.revealed returning a.claimed_by, a.entry_no, a.prize_p loop
    n := n + 1;
    if r.prize_p > 0 then insert into ledger (user_id, delta_p, reason) values (r.claimed_by::uuid, r.prize_p, 'win '||v_label||' #'||r.entry_no||' (round closed)'); won := won + r.prize_p; end if;
  end loop;
  -- end prize draw
  if p.end_prize_p > 0 and p.end_drawn_at is null and p.sold > 0 then
    v_no := c2_end_number(p.seed, p.sold);
    select claimed_by::uuid into v_uid from allocation where pool_id=p.id and entry_no=v_no;
    update pools set end_winner_entry=v_no, end_winner_user=v_uid, end_drawn_at=now() where id=p.id;
    if v_uid is not null then
      insert into ledger (user_id, delta_p, reason) values (v_uid, p.end_prize_p, 'win '||v_label||' END PRIZE DRAW #'||v_no);
      perform iw_mail(v_uid,'You won the End Prize Draw — £'||to_char(p.end_prize_p/100.0,'FM999,999,990'),'<p>Your ticket <b>#'||to_char(v_no,'FM9,999,999')||'</b> was drawn for the <b>£'||to_char(p.end_prize_p/100.0,'FM999,999,990')||' End Prize</b> when round '||p.pool_no||' closed. It is in your balance now &mdash; withdraw it any time from <a href="https://instantwins.co.uk/account.html">your account</a>. The draw number is verifiable from the published seed on the <a href="https://instantwins.co.uk/winners.html">winners page</a>.</p>');
    end if;
  end if;
  if not exists (select 1 from pools where game='MIL' and status='open') then perform open_pool_big('MIL'); end if;
  return jsonb_build_object('round',p.pool_no,'opened',n,'credited_p',won,'end_entry',v_no,'end_prize_p',p.end_prize_p);
end $$;

-- settle: rounds past their closing date, sold-out rounds, and anything settled earlier that still has loose ends
create or replace function c2_settle() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p record; out jsonb := '[]'::jsonb;
begin
  for p in select id from pools where game='MIL' and (
      (status='open' and closes_at is not null and closes_at <= now())
      or (status='settled' and (end_drawn_at is null and end_prize_p > 0 and sold > 0))
      or (status='settled' and exists (select 1 from allocation a where a.pool_id=pools.id and a.claimed_by is not null and not a.revealed)))
    order by pool_no loop
    out := out || c2_close_round(p.id);
  end loop;
  if not exists (select 1 from pools where game='MIL' and status='open') then perform open_pool_big('MIL'); end if;
  return jsonb_build_object('closed',out);
end $$;

-- c2_buy: closing date respected; sell-out closes the round properly (end draw included). Limits/breaks are enforced by the ledger guard trigger.
create or replace function c2_buy(p_token uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; v_price int; v_from int; v_to int;
begin
  u := iw_user(p_token); v_price := c2_pack_price(p_n); if v_price is null then raise exception 'pick a pack'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.closes_at is not null and p.closes_at <= now() then raise exception 'this round has just closed — the next one opens in a moment'; end if;
  if p.sold + p_n > p.cap then raise exception 'only % tickets left in the round', p.cap-p.sold; end if;
  if iw_balance(u.id) < v_price then raise exception 'insufficient credit'; end if;
  insert into ledger (user_id, delta_p, reason) values (u.id, -v_price, 'Million Round: '||p_n||' tickets #'||(p.sold+1)||'-#'||(p.sold+p_n));
  v_from := p.sold+1; v_to := p.sold+p_n;
  insert into allocation (pool_id, entry_no, prize_p) select p.id, gs, 0 from generate_series(v_from, v_to) gs on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=u.id::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no between v_from and v_to;
  update pools set sold=v_to where id=p.id;
  if v_to >= p.cap then perform c2_close_round(p.id); end if;
  return jsonb_build_object('from',v_from,'to',v_to,'n',p_n,'price_p',v_price,'balance_p',iw_balance(u.id),'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed));
end $$;

-- round state: closing date + end prize for the site
create or replace function c2_state() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('cap',p.cap,'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'price_p',p.price_p,
    'closes_at',p.closes_at,'end_prize_p',p.end_prize_p,'closed',(p.closes_at is not null and p.closes_at <= now()),
    'prizes_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'prize_left_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'top_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p=10000000),
    'left',(select coalesce(jsonb_object_agg(x.prize_p::text, x.n),'{}'::jsonb) from (select prize_p, count(*) n from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0 group by prize_p) x),
    'tiers',(select g.tiers from games g where g.tag='MIL'),
    'won_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>0),
    'postal',(select count(*) from postal_log l where l.status='accepted' and l.pool='MIL-P'||lpad(p.pool_no::text,4,'0')),
    'last_end',(select jsonb_build_object('round',q.pool_no,'entry',q.end_winner_entry,'prize_p',q.end_prize_p,'at',q.end_drawn_at,'name',split_part(coalesce(u.name,''),' ',1),'county',u.county) from pools q left join users u on u.id=q.end_winner_user where q.game='MIL' and q.end_drawn_at is not null order by q.pool_no desc limit 1),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',split_part(coalesce(u.name,''),' ',1)) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1),
    'recent',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',r.prize_p,'name',r.name,'at',r.at)),'[]'::jsonb) from (select a.prize_p, split_part(coalesce(u.name,'A player'),' ',1) as name, a.claimed_at as at from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=500 order by a.claimed_at desc limit 8) r))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;

-- results feed: end draw per closed round
create or replace function c2_results() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'rounds',coalesce((select jsonb_agg(jsonb_build_object('round',p.pool_no,'cap',p.cap,'sold',p.sold,'seed',p.seed,'seed_hash',p.seed_hash,'opened_at',p.opened_at,'settled_at',p.settled_at,
        'end_prize_p',p.end_prize_p,'end_entry',p.end_winner_entry,'end_name',split_part(coalesce(u.name,''),' ',1),'end_county',case when u.publish_wins then u.county end,
        'paid_p',(select coalesce(sum(a.prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null)) order by p.pool_no desc)
      from pools p left join users u on u.id=p.end_winner_user where p.game='MIL' and p.status='settled'),'[]'::jsonb),
    'winners',coalesce((select jsonb_agg(w) from (
        select jsonb_build_object('name',split_part(u.name,' ',1),'county',u.county,'prize_p',a.prize_p,'at',a.claimed_at,'round',p.pool_no,'no',a.entry_no) w
        from allocation a join pools p on p.id=a.pool_id join users u on u.id::text=a.claimed_by
        where p.game='MIL' and a.revealed and a.prize_p>=10000 and u.publish_wins
        order by a.claimed_at desc limit 100) x),'[]'::jsonb),
    'totals',jsonb_build_object('paid_p',(select coalesce(sum(delta_p),0) from ledger where reason like 'win MIL-%'),'winners',(select count(*) from ledger where reason like 'win MIL-%'))) $$;

-- admin: set the closing date / end prize of the open round, or close it now
create or replace function iw_admin_mil_set(p_token uuid, p_closes_at timestamptz, p_end_prize_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  update pools set closes_at=coalesce(p_closes_at,closes_at), end_prize_p=coalesce(p_end_prize_p,end_prize_p) where game='MIL' and status='open';
  if p_end_prize_p is not null then update site_settings set value=p_end_prize_p::text, updated_at=now() where key='mil_end_prize_p'; end if;
  return jsonb_build_object('ok',true);
end $$;
create or replace function iw_admin_mil_close(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  perform iw_admin(p_token);
  select id into v_id from pools where game='MIL' and status='open' order by pool_no desc limit 1;
  if v_id is null then return jsonb_build_object('error','no open round'); end if;
  return c2_close_round(v_id);
end $$;

grant execute on function c2_end_number(text,int), c2_close_round(uuid), c2_settle(), c2_buy(uuid,int), c2_state(), c2_results(), iw_admin_mil_set(uuid,timestamptz,int), iw_admin_mil_close(uuid) to service_role;
notify pgrst, 'reload schema';
