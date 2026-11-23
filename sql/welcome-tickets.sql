-- welcome-tickets.sql — 10 free Million Round tickets for every new account (set welcome_tickets to 0 to switch off).
-- Issued once per account the moment sign-up completes (name + DOB present). Real tickets in the live sequence, same odds, no cash credit.
insert into site_settings (key, value) values ('welcome_tickets','10') on conflict (key) do update set value=excluded.value;

create or replace function iw_welcome_tickets(p_uid uuid) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; v_n int; v_from int; v_to int;
begin
  v_n := coalesce((select value::int from site_settings where key='welcome_tickets'),0);
  if v_n < 1 then return 0; end if;
  if exists (select 1 from ledger where user_id=p_uid and reason like 'Welcome: %') then return 0; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.sold + v_n > p.cap then return 0; end if;
  v_from := p.sold+1; v_to := p.sold+v_n;
  insert into ledger (user_id, delta_p, reason) values (p_uid, 0, 'Welcome: '||v_n||' free tickets #'||v_from||'-#'||v_to);
  insert into allocation (pool_id, entry_no, prize_p) select p.id, gs, 0 from generate_series(v_from, v_to) gs on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=p_uid::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no between v_from and v_to;
  update pools set sold=v_to where id=p.id;
  if v_to >= p.cap then perform c2_close_round(p.id); end if;
  return v_n;
end $$;

create or replace function trg_welcome_tickets() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'UPDATE' and not (old.dob is null and new.dob is not null) then return new; end if;
  if new.dob is null or coalesce(new.name,'') = '' then return new; end if;
  begin perform iw_welcome_tickets(new.id); exception when others then null; end;
  return new;
end $$;
drop trigger if exists welcome_tickets on users;
create trigger welcome_tickets after insert on users for each row execute function trg_welcome_tickets();
drop trigger if exists welcome_tickets_onboard on users;
create trigger welcome_tickets_onboard after update of dob on users for each row execute function trg_welcome_tickets();

-- welcome email mentions the tickets
create or replace function trg_mail_welcome() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_first text; v_n int;
begin
  if tg_op = 'UPDATE' and not (old.dob is null and new.dob is not null) then return new; end if;
  if new.dob is null or coalesce(new.name,'') = '' then return new; end if;
  v_first := split_part(new.name,' ',1);
  v_n := coalesce((select value::int from site_settings where key='welcome_tickets'),0);
  perform iw_mail(new.id,'Welcome to InstantWins'||case when v_n>0 then ' — your '||v_n||' free tickets are in' else '' end,
    '<p>Hi '||v_first||', your account is open and ready.</p>'
    ||case when v_n>0 then '<p><b>'||v_n||' free Million Round tickets</b> are waiting in your bank &mdash; real tickets in the live round, same odds as a paid one. Feed them through the reader and see what they hold.</p><p><a class="btn" href="https://instantwins.co.uk/game.html?g=quick">Reveal my free tickets</a></p>' else '<p><a class="btn" href="https://instantwins.co.uk/#buy">Buy your first ticket</a></p>' end
    ||'<p>Your account number is <b>'||coalesce(new.acct_no,'')||'</b> &mdash; keep it, you need it on any free postal entry.</p>'
    ||'<p>No purchase necessary: <a href="https://instantwins.co.uk/free.html">enter free by post</a> &mdash; same tickets, same odds. Every ticket in the round also goes into the guaranteed End Prize Draw.</p>');
  return new;
end $$;

notify pgrst, 'reload schema';
