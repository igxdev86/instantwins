-- card-schedule-28k.sql — the live draw schedule. Worst case (every draw of the day paid) ≈ £28.3k.
-- Prize scales with the gap between draws: fast draws stay cheap, big prizes where draws are few.
-- Run AFTER free-draws.sql. Every other row stays defined but switched off (admin can flick on later).
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('t_1',    'T1',   '30s Draw £1',      10,    100,  20,    30, 0, null,  1),
 ('s60_5',  'M5',   '60s Draw £5',      50,    500,  20,    60, 0, null, 10),
 ('m5_20',  'F20',  'Five Minute £20', 100,   2000,  40,   300, 0, null, 19),
 ('m15_40', 'Q40',  '15 Minute £40',   100,   4000,  80,   900, 0, null, 29),
 ('h_250',  'H250', 'Hourly £250',     200,  25000, 250,  3600, 0, null, 39),
 ('d_1000', 'D1K',  'Daily £1,000',    500, 100000, 400, 86400, 0,   21, 49)
on conflict (kind) do update set code=excluded.code, label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;
update card_kinds set active = (kind in ('t_1','s60_5','m5_20','m15_40','h_250','d_1000','free_1','free','free_20','free_100'));
-- drop empty open draws for rows now off; make sure the live rows have their week of draws
delete from card_draws where status='open' and sold=0 and kind not in (select kind from card_kinds where active);
select card_ensure_open();
-- check: worst case per day
select sum(prize_p * case when daily_hour is not null then 1 else 86400/step_s end)/100.0 as worst_case_gbp_per_day from card_kinds where active;
notify pgrst, 'reload schema';
