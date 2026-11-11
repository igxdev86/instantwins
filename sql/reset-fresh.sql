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
