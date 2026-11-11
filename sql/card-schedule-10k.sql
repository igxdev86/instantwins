-- card-schedule-10k.sql — lean schedule for early traffic (~10k visits/month). Run AFTER free-draws.sql.
-- Live: one fast paid draw (Five Minute £20), free £5 hourly, free £100 daily. Everything else off.
-- Worst case (every draw of the day paid) ≈ £5,760 + £120 + £100 = £5,980; realistic far lower.
update card_kinds set step_s=3600, offset_s=0, label='Free Draw £5' where kind='free';   -- hourly, on the hour
update card_kinds set active = (kind in ('m5_20','free','free_100'));
delete from card_draws where status='open' and sold=0 and kind not in (select kind from card_kinds where active);
select card_ensure_open();
select kind, label, price_p, prize_p, cap, step_s from card_kinds where active order by sort;
select sum(prize_p * case when daily_hour is not null then 1 else 86400/step_s end)/100.0 as worst_case_gbp_per_day from card_kinds where active;
notify pgrst, 'reload schema';
