-- card-launch-schedule.sql — lean launch set (worst case ≈ £16k/day). Everything else stays defined but off.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('m5_20', 'F20',  'Five-Minute £20', 100,  2000,  40,  300, 0, null, 19),
 ('h_250', 'H250', 'Hourly £250',     200, 25000, 250, 3600, 0, null, 39)
on conflict (kind) do update set code=excluded.code, label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;
update card_kinds set active = (kind in ('t_1','m5_20','h_250','d_1000','free'));
delete from card_draws where status='open' and sold=0 and kind not in (select kind from card_kinds where active);
select card_ensure_open();
notify pgrst, 'reload schema';
