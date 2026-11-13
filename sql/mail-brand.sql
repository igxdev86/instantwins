-- mail-brand.sql — friendlier copy for every automatic email. Layout/branding is applied by the sender (api), so bodies stay
-- simple: <p>, <b>, <a>, and <a class="btn"> for a button. Replaces the trigger bodies from launch-ops.sql / login-code.sql.

-- welcome: on sign-up when the account is complete, or when an onboarding modal completes it
create or replace function trg_mail_welcome() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_first text; v_credit int;
begin
  if tg_op = 'UPDATE' and not (old.dob is null and new.dob is not null) then return new; end if;
  if new.dob is null or coalesce(new.name,'') = '' then return new; end if;
  v_first := split_part(new.name,' ',1);
  v_credit := case when iw_payments_live() then 0 else coalesce(iw_balance(new.id),0) end;
  perform iw_mail(new.id,'Welcome to InstantWins',
    '<p>Hi '||v_first||', your account is open and ready.</p>'
    ||'<p>Your account number is <b>'||coalesce(new.acct_no,'')||'</b> &mdash; keep it, you need it on any free postal entry.</p>'
    ||case when v_credit > 0 then '<p>We have put <b>£'||to_char(v_credit/100.0,'FM999,990')||' of play credit</b> in your account while we are in test mode, so you can try the Reveal game straight away.</p>' else '' end
    ||'<p><a class="btn" href="https://instantwins.co.uk/#buy">Buy your first ticket</a></p>'
    ||'<p>No purchase necessary: <a href="https://instantwins.co.uk/free.html">enter free by post</a> &mdash; same tickets, same odds. Every ticket in the round also goes into the guaranteed End Prize Draw.</p>'
    ||'<p>Questions? Just reply to this email.</p>');
  return new;
end $$;
drop trigger if exists mail_welcome on users; drop trigger if exists mail_welcome_onboard on users;
create trigger mail_welcome after insert on users for each row execute function trg_mail_welcome();
create trigger mail_welcome_onboard after update of dob on users for each row execute function trg_mail_welcome();

-- wins of £50+
create or replace function trg_mail_win() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_amt text;
begin
  if new.delta_p >= 5000 and new.reason like 'win MIL-%' then
    v_amt := '£'||to_char(new.delta_p/100.0,'FM999,999,990');
    perform iw_mail(new.user_id,'You won '||v_amt||' on InstantWins',
      '<p>One of your tickets in the Million Round carried <b>'||v_amt||'</b>.</p>'
      ||'<p>It is in your balance now. Withdraw it to your bank any time, or keep playing &mdash; your call.</p>'
      ||'<p><a class="btn" href="https://instantwins.co.uk/account.html#money">Withdraw to my bank</a></p>'
      ||case when new.delta_p >= 100000 then '<p>For prizes of £1,000 or more we will check your identity before paying out &mdash; we will email you if we need anything.</p>' else '' end
      ||'<p>Prizes of £100 or more appear on the winners page as your first name and county. You can switch that off in your account.</p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_win on ledger;
create trigger mail_win after insert on ledger for each row execute function trg_mail_win();

-- bank deposits / withdrawals decided
create or replace function trg_mail_pay() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_amt text;
begin
  v_amt := '£'||to_char(new.amount_p/100.0,'FM999,990.00');
  if tg_table_name='deposits' and new.status<>old.status then
    perform iw_mail(new.user_id, case when new.status='approved' then 'Deposit received — '||v_amt else 'We could not match your deposit' end,
      case when new.status='approved' then '<p><b>'||v_amt||'</b> has landed and is in your balance now (reference <b>'||new.reference||'</b>).</p><p><a class="btn" href="https://instantwins.co.uk/#buy">Buy tickets</a></p>'
           else '<p>We could not find a transfer of <b>'||v_amt||'</b> with reference <b>'||new.reference||'</b>.</p><p>If you sent it, reply to this email with the date and the name on the account it came from and we will track it down. If you did not send it, nothing has been taken and there is nothing to do.</p>' end);
  elsif tg_table_name='withdrawals' and new.status<>old.status then
    perform iw_mail(new.user_id, case when new.status='paid' then 'Withdrawal sent — '||v_amt else 'Withdrawal declined' end,
      case when new.status='paid' then '<p><b>'||v_amt||'</b> is on its way to the account ending <b>'||right(new.account_no,4)||'</b>. It normally arrives within two hours, and always within five working days.</p>'
           else '<p>Your withdrawal of <b>'||v_amt||'</b> was declined'||coalesce(' &mdash; '||new.note,'')||'. The money is back in your balance.</p><p>Reply to this email if you think that is wrong and we will sort it.</p>' end);
  end if;
  return new;
end $$;
drop trigger if exists mail_dep on deposits; drop trigger if exists mail_wd on withdrawals;
create trigger mail_dep after update on deposits for each row execute function trg_mail_pay();
create trigger mail_wd after update on withdrawals for each row execute function trg_mail_pay();

-- postal ticket keyed in
create or replace function trg_mail_postal() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.status='accepted' and new.user_id is not null then
    perform iw_mail(new.user_id,'Your free postal ticket is in',
      '<p>Your postcard arrived. Million Round ticket <b>#'||to_char(new.entry_no,'FM9,999,999')||'</b> is in your bank, with exactly the same chance as a paid one.</p>'
      ||'<p><a class="btn" href="https://instantwins.co.uk/game.html?g=quick">Reveal it</a></p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_postal on postal_log;
create trigger mail_postal after insert on postal_log for each row execute function trg_mail_postal();

-- limit changes
create or replace function trg_mail_limits() returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.daily_limit_p is distinct from old.daily_limit_p or new.pending_limit_p is distinct from old.pending_limit_p then
    perform iw_mail(new.id,'Your spending limit has changed',
      '<p>Your daily limit on paid tickets is now <b>'||case when new.daily_limit_p is null then 'not set' else '£'||to_char(new.daily_limit_p/100.0,'FM999,990') end||'</b>'
      ||case when new.pending_limit_p is not null then ', changing to <b>£'||to_char(new.pending_limit_p/100.0,'FM999,990')||'</b> after the 24-hour cooling-off period' else '' end||'.</p>'
      ||'<p>Lowering a limit always takes effect straight away. If you did not ask for this change, reply to this email.</p>'
      ||'<p><a href="https://instantwins.co.uk/account.html#limits">Review my limits</a></p>');
  end if;
  return new;
end $$;
drop trigger if exists mail_limits on users;
create trigger mail_limits after update of daily_limit_p, pending_limit_p on users for each row execute function trg_mail_limits();

notify pgrst, 'reload schema';
