-- run-me-2.sql — everything outstanding since c2.sql, in order, then the fresh reset. Safe to re-run.

-- ======== c2-finish.sql ========
-- c2-finish.sql (v2) — "Finish now": reveal every unopened Million Round ticket in one call. No temp table.
create or replace function c2_reveal_all(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_rows jsonb; v_won bigint; v_n int;
begin
  u := iw_user(p_token);
  with upd as (
    update allocation al set revealed=true
    from pools q where q.id=al.pool_id and q.game='MIL' and al.claimed_by=u.id::text and not al.revealed
    returning al.entry_no, al.prize_p, q.game, q.pool_no),
  led as (
    insert into ledger (user_id, delta_p, reason)
    select u.id, prize_p, 'win '||game||'-P'||lpad(pool_no::text,4,'0')||' #'||entry_no from upd where prize_p > 0
    returning 1)
  select count(*), coalesce(sum(prize_p),0), coalesce(jsonb_agg(jsonb_build_object('no',entry_no,'prize_p',prize_p) order by entry_no),'[]'::jsonb)
    into v_n, v_won, v_rows from upd;
  if v_n = 0 then return jsonb_build_object('empty',true,'bank',0,'n',0,'won_p',0,'tickets','[]'::jsonb,'balance_p',iw_balance(u.id)); end if;
  return jsonb_build_object('n',v_n,'won_p',v_won,'tickets',v_rows,'bank',0,'balance_p',iw_balance(u.id));
end $$;
grant execute on function c2_reveal_all(uuid) to service_role;



-- ======== postal-mil.sql ========
-- postal-mil.sql — Million Round postal entries: log every card (accepted or rejected), ticket goes into the entrant's bank unopened.
create table if not exists postal_log (
  id bigserial primary key, created_at timestamptz not null default now(),
  ref text not null, user_id uuid, entry_no int, pool text, status text not null check (status in ('accepted','rejected')),
  reason text, note text, keyed_by uuid);
create index if not exists postal_log_created on postal_log (created_at desc);

create or replace function iw_admin_postal_mil(p_token uuid, p_ref text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin users%rowtype; v_uid uuid; v_name text; p pools%rowtype; v_entry int; v_label text;
begin
  v_admin := iw_admin(p_token);
  select id, name into v_uid, v_name from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  if v_uid is null then raise exception 'no account matches that account number / email — reject the card as "no account"'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.sold >= p.cap then raise exception 'round is full'; end if;
  v_entry := p.sold + 1; v_label := 'MIL-P'||lpad(p.pool_no::text,4,'0');
  insert into allocation (pool_id, entry_no, prize_p) values (p.id, v_entry, 0) on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=v_uid::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  insert into ledger (user_id, delta_p, reason) values (v_uid, 0, 'postal entry '||v_label||' #'||v_entry);
  insert into postal_log (ref, user_id, entry_no, pool, status, note, keyed_by) values (trim(p_ref), v_uid, v_entry, v_label, 'accepted', p_note, v_admin.id);
  if v_entry >= p.cap then update pools set status='settled', settled_at=now() where id=p.id; perform open_pool_big('MIL'); end if;
  return jsonb_build_object('entry_no',v_entry,'pool',v_label,'name',v_name,
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=v_uid::text and not a.revealed));
end $$;

create or replace function iw_admin_postal_reject(p_token uuid, p_ref text, p_reason text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin users%rowtype; v_uid uuid;
begin
  v_admin := iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  insert into postal_log (ref, user_id, status, reason, note, keyed_by) values (trim(coalesce(p_ref,'')), v_uid, 'rejected', p_reason, p_note, v_admin.id);
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_postal_log(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object(
    'today_accepted',(select count(*) from postal_log where status='accepted' and created_at::date=current_date),
    'today_rejected',(select count(*) from postal_log where status='rejected' and created_at::date=current_date),
    'total_accepted',(select count(*) from postal_log where status='accepted'),
    'rows',coalesce((select jsonb_agg(jsonb_build_object('at',l.created_at,'ref',l.ref,'name',u.name,'entry_no',l.entry_no,'pool',l.pool,'status',l.status,'reason',l.reason,'note',l.note,
        'revealed',(select a.revealed from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.entry_no=l.entry_no and l.pool='MIL-P'||lpad(q.pool_no::text,4,'0') limit 1)) order by l.created_at desc)
      from (select * from postal_log order by created_at desc limit 150) l left join users u on u.id=l.user_id),'[]'::jsonb));
end $$;

-- round state: publish the postal count on the fairness page
create or replace function c2_state() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('cap',p.cap,'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'price_p',p.price_p,
    'prizes_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'prize_left_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'top_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p=10000000),
    'left',(select coalesce(jsonb_object_agg(x.prize_p::text, x.n),'{}'::jsonb) from (select prize_p, count(*) n from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0 group by prize_p) x),
    'tiers',(select g.tiers from games g where g.tag='MIL'),
    'won_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>0),
    'postal',(select count(*) from postal_log l where l.status='accepted' and l.pool='MIL-P'||lpad(p.pool_no::text,4,'0')),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',split_part(coalesce(u.name,''),' ',1)) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1),
    'recent',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',r.prize_p,'name',r.name,'at',r.at)),'[]'::jsonb) from (select a.prize_p, split_part(coalesce(u.name,'A player'),' ',1) as name, a.claimed_at as at from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=500 order by a.claimed_at desc limit 8) r))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;
create index if not exists allocation_open_prizes on allocation (pool_id, prize_p) where claimed_by is null and prize_p > 0;
grant execute on function iw_admin_postal_mil(uuid,text,text), iw_admin_postal_reject(uuid,text,text,text), iw_admin_postal_log(uuid), c2_state() to service_role;



-- ======== launch-ops.sql ========
-- launch-ops.sql — pre-launch operations for the new site:
--   round-close settlement · email outbox (Resend) · rate limiting · terms re-accept · winners feed · county/publish opt-out
-- Safe to re-run.

-- ---------- users: terms version, county, publish opt-out ----------
alter table users add column if not exists terms_version text;
alter table users add column if not exists county text;
alter table users add column if not exists publish_wins boolean not null default true;
insert into site_settings (key,value) values ('terms_version','2026-11-11') on conflict (key) do nothing;

create or replace function iw_accept_terms(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  update users set terms_version=(select value from site_settings where key='terms_version') where id=u.id;
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_set_profile(p_token uuid, p_county text, p_publish boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  update users set county=nullif(trim(coalesce(p_county,'')),''), publish_wins=coalesce(p_publish,true) where id=u.id;
  return jsonb_build_object('ok',true);
end $$;

-- ---------- email outbox ----------
create table if not exists outbox (
  id bigserial primary key, created_at timestamptz not null default now(),
  user_id uuid, to_email text not null, subject text not null, html text not null,
  sent_at timestamptz, error text, tries int not null default 0);
create index if not exists outbox_pending on outbox (created_at) where sent_at is null;

create or replace function iw_mail(p_user uuid, p_subject text, p_html text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_email text;
begin
  select email into v_email from users where id=p_user;
  if v_email is null then return; end if;
  insert into outbox (user_id, to_email, subject, html) values (p_user, v_email, p_subject,
    '<div style="font-family:Inter,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#0B0B10"><div style="font-weight:900;font-size:20px;letter-spacing:-.02em;margin-bottom:14px">INSTANT<span style="color:#7bb100">WINS</span></div>'
    ||p_html||'<p style="font-size:12px;color:#777;margin-top:28px">InstantWins.co.uk is operated by IGX Ltd, company no. 13057559, 20-22 Wenlock Road, London N1 7GU. Free entry by post on every round. 18+, Great Britain. Prizes are a matter of luck and most tickets win nothing &mdash; please play within your means. <a href="https://instantwins.co.uk/responsible-play.html">Responsible play</a></p></div>');
end $$;

-- welcome
create or replace function trg_mail_welcome() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_mail(new.id,'Welcome to InstantWins','<p>Hi '||split_part(new.name,' ',1)||', your account is open. Your account number is <b>'||coalesce(new.acct_no,'')||'</b> &mdash; you need it on any free postal entry.</p><p><a href="https://instantwins.co.uk/free.html">How to enter free by post</a> &middot; <a href="https://instantwins.co.uk/account.html">Your account</a></p>');
  return new;
end $$;
drop trigger if exists mail_welcome on users;
create trigger mail_welcome after insert on users for each row execute function trg_mail_welcome();

-- wins of £50+ (ledger reason 'win MIL-...')
create or replace function trg_mail_win() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.delta_p >= 5000 and new.reason like 'win MIL-%' then
    perform iw_mail(new.user_id,'You won £'||to_char(new.delta_p/100.0,'FM999,999,990.00')||' on InstantWins','<p>A ticket you opened in the Million Round carried <b>£'||to_char(new.delta_p/100.0,'FM999,999,990.00')||'</b>. It is in your balance now and can be withdrawn any time from <a href="https://instantwins.co.uk/account.html">your account</a>.</p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_win on ledger;
create trigger mail_win after insert on ledger for each row execute function trg_mail_win();

-- deposits / withdrawals decided
create or replace function trg_mail_pay() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_table_name='deposits' and new.status<>old.status then
    perform iw_mail(new.user_id, case when new.status='approved' then 'Deposit received' else 'Deposit not matched' end,
      case when new.status='approved' then '<p>£'||to_char(new.amount_p/100.0,'FM999,990.00')||' has been added to your balance (reference '||new.reference||').</p>'
           else '<p>We could not match a transfer for £'||to_char(new.amount_p/100.0,'FM999,990.00')||' with reference '||new.reference||'. If you sent it, reply to this email with the date and the account it came from.</p>' end);
  elsif tg_table_name='withdrawals' and new.status<>old.status then
    perform iw_mail(new.user_id, case when new.status='paid' then 'Withdrawal sent' else 'Withdrawal declined' end,
      case when new.status='paid' then '<p>£'||to_char(new.amount_p/100.0,'FM999,990.00')||' has been sent to the account ending '||right(new.account_no,4)||'. It normally arrives within two hours.</p>'
           else '<p>Your withdrawal of £'||to_char(new.amount_p/100.0,'FM999,990.00')||' was declined'||coalesce(' ('||new.note||')','')||' and the money is back in your balance. Reply to this email if you think that is wrong.</p>' end);
  end if;
  return new;
end $$;
drop trigger if exists mail_dep on deposits; drop trigger if exists mail_wd on withdrawals;
create trigger mail_dep after update on deposits for each row execute function trg_mail_pay();
create trigger mail_wd after update on withdrawals for each row execute function trg_mail_pay();

-- postal ticket keyed
create or replace function trg_mail_postal() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status='accepted' and new.user_id is not null then
    perform iw_mail(new.user_id,'Your free postal ticket is in','<p>Your postcard arrived. Million Round ticket <b>#'||to_char(new.entry_no,'FM9,999,999')||'</b> is in your bank &mdash; open it in any game at <a href="https://instantwins.co.uk/">instantwins.co.uk</a>.</p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_postal on postal_log;
create trigger mail_postal after insert on postal_log for each row execute function trg_mail_postal();

-- limit / break changes (if the limit functions exist, they write ledger-less rows; mail from a users trigger instead)
create or replace function trg_mail_limits() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.daily_limit_p is distinct from old.daily_limit_p or new.pending_limit_p is distinct from old.pending_limit_p then
    perform iw_mail(new.id,'Your spending limit','<p>Your daily limit on paid tickets is now '||case when new.daily_limit_p is null then 'not set' else '£'||to_char(new.daily_limit_p/100.0,'FM999,990') end||case when new.pending_limit_p is not null then ', changing to £'||to_char(new.pending_limit_p/100.0,'FM999,990')||' after the 24-hour cooling-off period' else '' end||'. If you did not ask for this, reply to this email.</p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_limits on users;
create trigger mail_limits after update of daily_limit_p, pending_limit_p on users for each row execute function trg_mail_limits();

-- outbox fetch / mark (called by the API with the service key)
create or replace function iw_outbox_take(p_n int default 20) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'to',to_email,'subject',subject,'html',html)) from (
    select * from outbox where sent_at is null and tries < 5 order by created_at limit greatest(1,least(p_n,50))) o),'[]'::jsonb);
end $$;
create or replace function iw_outbox_mark(p_id bigint, p_ok boolean, p_error text default null) returns void
language sql security definer set search_path = public, extensions as $$
  update outbox set sent_at=case when p_ok then now() else null end, error=p_error, tries=tries+1 where id=p_id $$;

-- ---------- rate limiting ----------
create table if not exists rate_limits (key text primary key, window_start timestamptz not null, n int not null);
create or replace function iw_rate(p_key text, p_limit int, p_window_s int) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare r rate_limits%rowtype;
begin
  insert into rate_limits (key, window_start, n) values (p_key, now(), 1)
    on conflict (key) do update set n = case when rate_limits.window_start < now() - make_interval(secs=>p_window_s) then 1 else rate_limits.n + 1 end,
                                   window_start = case when rate_limits.window_start < now() - make_interval(secs=>p_window_s) then now() else rate_limits.window_start end
    returning * into r;
  if random() < 0.01 then delete from rate_limits where window_start < now() - interval '1 day'; end if;
  return r.n <= p_limit;
end $$;

-- ---------- round-close settlement ----------
-- When a Million Round sells out it is marked 'settled'. Any ticket still unopened is opened here, prizes credited, and the seed is published.
create or replace function c2_settle() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p record; n int := 0; won bigint := 0; r record;
begin
  for p in select * from pools where game='MIL' and status='settled' and exists (select 1 from allocation a where a.pool_id=pools.id and a.claimed_by is not null and not a.revealed) loop
    for r in update allocation a set revealed=true where a.pool_id=p.id and a.claimed_by is not null and not a.revealed returning a.claimed_by, a.entry_no, a.prize_p loop
      n := n + 1;
      if r.prize_p > 0 then
        insert into ledger (user_id, delta_p, reason) values (r.claimed_by::uuid, r.prize_p, 'win MIL-P'||lpad(p.pool_no::text,4,'0')||' #'||r.entry_no||' (round closed)');
        won := won + r.prize_p;
      end if;
    end loop;
  end loop;
  -- make sure an open round always exists
  if not exists (select 1 from pools where game='MIL' and status='open') then perform open_pool_big('MIL'); end if;
  return jsonb_build_object('opened',n,'credited_p',won);
end $$;

-- published seeds of closed rounds + winners feed for the new site
create or replace function c2_results() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'rounds',coalesce((select jsonb_agg(jsonb_build_object('round',p.pool_no,'cap',p.cap,'seed',p.seed,'seed_hash',p.seed_hash,'opened_at',p.opened_at,'settled_at',p.settled_at,
        'paid_p',(select coalesce(sum(a.prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null)) order by p.pool_no desc)
      from pools p where p.game='MIL' and p.status='settled'),'[]'::jsonb),
    'winners',coalesce((select jsonb_agg(w) from (
        select jsonb_build_object('name',split_part(u.name,' ',1),'county',u.county,'prize_p',a.prize_p,'at',a.claimed_at,'round',p.pool_no,'no',a.entry_no) w
        from allocation a join pools p on p.id=a.pool_id join users u on u.id::text=a.claimed_by
        where p.game='MIL' and a.revealed and a.prize_p>=10000 and u.publish_wins
        order by a.claimed_at desc limit 100) x),'[]'::jsonb),
    'totals',jsonb_build_object('paid_p',(select coalesce(sum(delta_p),0) from ledger where reason like 'win MIL-%'),'winners',(select count(*) from ledger where reason like 'win MIL-%'))) $$;

-- c2_mine: tell the client when the terms need re-accepting
create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;

grant execute on function iw_accept_terms(uuid), iw_set_profile(uuid,text,boolean), iw_outbox_take(int), iw_outbox_mark(bigint,boolean,text), iw_rate(text,int,int), c2_settle(), c2_results(), c2_mine(uuid) to service_role;



-- ======== end-draw.sql ========
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



-- ======== games-switch.sql ========
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



-- ======== account-won.sql ========
-- account-won.sql — account page: lifetime won + opened counts (needs launch-ops.sql first for county/terms columns).
create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;
grant execute on function c2_mine(uuid) to service_role;



-- ======== reset-fresh.sql ========
-- reset-fresh.sql — wipe all play on the Million Round and start clean. Accounts stay; every balance goes to 0; admin accounts get £5,000 play credit.
begin;
-- tickets: drop bought blanks, un-claim the pre-printed winners
delete from allocation a using pools p where p.id=a.pool_id and p.game='MIL' and a.prize_p=0;
update allocation a set claimed_by=null, claimed_at=null, bought_at=null, revealed=true from pools p where p.id=a.pool_id and p.game='MIL';
-- round: back to zero sold, no end draw yet, open
update pools set sold=0, status='open', settled_at=null, end_winner_entry=null, end_winner_user=null, end_drawn_at=null where game='MIL';
-- keep only the newest MIL round open (if several exist)
update pools set status='settled', settled_at=now() where game='MIL' and pool_no < (select max(pool_no) from pools where game='MIL');
-- money and logs
delete from ledger;
delete from deposits; delete from withdrawals;
delete from postal_log; delete from outbox; delete from rate_limits;
-- fresh play credit for admin accounts
insert into ledger (user_id, delta_p, reason) select id, 500000, 'admin: fresh play credit' from users where is_admin;
commit;
select u.email, iw_balance(u.id) as balance_p from users u where u.is_admin;


notify pgrst, 'reload schema';
