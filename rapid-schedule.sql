-- rapid-schedule.sql — "Rapid" tiles: seven fast draws on two shared clocks (every 30 s and every 60 s), tiny prizes.
-- NOT applied until you choose it. Worst case if every draw of the day paid ≈ £139,700; realistic cost = prize × draws actually entered.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('t_50p','T50','30s Draw 50p',  5,   50, 20, 30, 0, null, 0),
 ('t_1',  'T1', '30s Draw £1',  10,  100, 20, 30, 0, null, 1),
 ('t_2',  'T2', '30s Draw £2',  20,  200, 20, 30, 0, null, 2),
 ('t_5',  'T5', '30s Draw £5',  50,  500, 20, 30, 0, null, 3),
 ('minute','S10','60s Draw £10', 50, 1000, 50, 60, 0, null, 10),
 ('s60_20','S20','60s Draw £20',100, 2000, 40, 60, 0, null, 11),
 ('s60_50','S50','60s Draw £50',200, 5000, 50, 60, 0, null, 12)
on conflict (kind) do update set code=excluded.code,label=excluded.label,price_p=excluded.price_p,prize_p=excluded.prize_p,cap=excluded.cap,step_s=excluded.step_s,offset_s=excluded.offset_s,sort=excluded.sort;
update card_kinds set active = (kind in ('t_50p','t_1','t_2','t_5','minute','s60_20','s60_50','free','free_100'));
delete from card_draws where status='open' and sold=0 and kind not in (select kind from card_kinds where active);
select card_ensure_open();
select sum(prize_p * case when daily_hour is not null then 1 else 86400/step_s end)/100.0 as worst_case_gbp_per_day from card_kinds where active;
