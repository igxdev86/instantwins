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
notify pgrst, 'reload schema';
