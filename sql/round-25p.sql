-- round-25p.sql — 25p tickets. 8,000,000 tickets · £1,185,000 in prizes · 1,410,425 winning tickets (1 in 5.7) · closes 31 Jan 2027 8pm UK.
-- Flatter discount ladder (max 24% off). Re-opens the round with a fresh seed; wipes tickets, money and logs like reset-fresh.
begin;
update games set cap=8000000, price_p=25,
  tiers='[[2000000,5],[500000,20],[200000,50],[100000,50],[50000,100],[10000,400],[5000,800],[2000,2000],[1000,5000],[500,12000],[200,40000],[100,100000],[50,250000],[25,1000000]]',
  blurb='One round for the whole site: 8,000,000 tickets at 25p, £1,185,000 in prizes across 1,410,425 winning tickets, every prize on a ticket before the round opens.'
 where tag='MIL';
update site_settings set value='77', updated_at=now() where key='mil_round_days';
update site_settings set value='1000000', updated_at=now() where key='mil_end_prize_p';
delete from allocation a using pools p where p.id=a.pool_id and p.game='MIL';
delete from postal_log; delete from pools where game='MIL';
delete from ledger; delete from deposits; delete from withdrawals; delete from outbox; delete from rate_limits;
do $$ begin
  if to_regclass('public.card_payments') is not null then delete from card_payments; end if;
  if to_regclass('public.skill_answers') is not null then delete from skill_answers; end if;
end $$;
insert into ledger (user_id, delta_p, reason) select id, 500000, 'admin: fresh play credit' from users where is_admin;
commit;

-- pack prices (pence) and the whole-balance rate (pence per ticket)
create or replace function c2_pack_price(n int) returns int language sql immutable as $$
  select case n when 1 then 25 when 5 then 125 when 10 then 240 when 25 then 575 when 50 then 1100 when 100 then 2100 when 250 then 5250 when 500 then 10000 when 1000 then 19000 else null end $$;
create or replace function c2_rate_for(p_amount_p int) returns int language sql immutable as $$
  select case when p_amount_p >= 19000 then 19 when p_amount_p >= 10000 then 20 when p_amount_p >= 2100 then 21 when p_amount_p >= 1100 then 22
              when p_amount_p >= 575 then 23 when p_amount_p >= 240 then 24 else 25 end $$;
-- whole balance: up to 20,000 tickets in one go
create or replace function c2_buy_balance(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_bal int; v_rate int; v_n int;
begin
  u := iw_user(p_token);
  v_bal := iw_balance(u.id);
  if v_bal < 25 then raise exception 'not enough funds for a ticket'; end if;
  v_rate := c2_rate_for(v_bal); v_n := least(v_bal / v_rate, 20000);
  return c2_issue(u.id, v_n, v_n * v_rate, '(whole balance @ '||v_rate||'p)');
end $$;

select open_pool_big('MIL');
update pools set closes_at = '2027-01-31 20:00:00 Europe/London'::timestamptz where game='MIL' and status='open';
notify pgrst, 'reload schema';
select pool_no, sold, cap, price_p, closes_at at time zone 'Europe/London' as closes_uk, end_prize_p, (select count(*) from allocation a where a.pool_id=p.id) as winners from pools p where game='MIL' and status='open';
