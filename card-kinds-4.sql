-- card-kinds-4.sql — four prize levels in every cadence group. Run AFTER card-kinds.sql.
insert into card_kinds (kind,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('m5_1000', 'Five-Minute £1,000', 1000, 100000, 200,  300,    0, null, 23),
 ('m15_150', '15-Minute £150',      200,  15000, 150,  900,    0, null, 29),
 ('m15_2000','15-Minute £2,000',   2000, 200000, 200,  900,    0, null, 32),
 ('h_5000',  'Hourly £5,000',      5000, 500000, 200, 3600, 1800, null, 43),
 ('d_400',   'Daily £400',          500,  40000, 160, 86400,   0,   21, 48),
 ('d_1000',  'Daily £1,000',       1000, 100000, 200, 86400,   0,   21, 49)
on conflict (kind) do update set label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;
select card_ensure_open();
notify pgrst, 'reload schema';
