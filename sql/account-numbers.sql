-- account-numbers.sql — give every user a public account number (IW + 7 digits),
-- auto-assign on signup, and make ryan@sm-i.co.uk an admin.
-- Safe to re-run.

-- 1. Column + sequence (starts at 1000001 -> IW1000001)
alter table users add column if not exists acct_no text unique;
create sequence if not exists iw_acct_seq start 1000001;

-- 2. Backfill existing users that don't have one yet (oldest first)
with ord as (
  select id, row_number() over (order by created_at, id) rn
    from users where acct_no is null
)
update users u
   set acct_no = 'IW' || nextval('iw_acct_seq')::text
  from ord o
 where u.id = o.id;

-- 3. New rows get one automatically
alter table users alter column acct_no set default ('IW' || nextval('iw_acct_seq')::text);

-- 4. Make Ryan an admin (shows the Admin console link on the account page)
update users set is_admin = true where lower(email) = 'ryan@sm-i.co.uk';
