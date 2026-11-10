-- draw-packs.sql — Draw Packs: pennies-a-draw rollover draws sold as a pack of 20 consecutive draws (one number in each).
-- 30 s packs = 10 minutes of play; 60 s packs = 20 minutes. Rollover on, so payout = prize ÷ (cap × price) = 50% of takings.
-- Run AFTER rollover.sql. Adds to whatever schedule is on; switch rows in admin-draws as usual.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort,active,bundle_n,bundle_price_p,rollover) values
 ('pk_20', 'P20', '30s Pack Draw 20p',  2,   20, 20, 30, 0, null, 0, true, 20,   40, true),   -- 20 draws for 40p
 ('pk_50', 'P50', '30s Pack Draw 50p',  5,   50, 20, 30, 0, null, 1, true, 20,  100, true),   -- 20 draws for £1
 ('pk_100','P100','60s Pack Draw £1',  10,  100, 20, 60, 0, null, 10, true, 20,  200, true),  -- 20 draws for £2
 ('pk_500','P500','60s Pack Draw £5',  50,  500, 20, 60, 0, null, 11, true, 20, 1000, true)   -- 20 draws for £10
on conflict (kind) do update set code=excluded.code,label=excluded.label,price_p=excluded.price_p,prize_p=excluded.prize_p,cap=excluded.cap,step_s=excluded.step_s,
  offset_s=excluded.offset_s,sort=excluded.sort,active=excluded.active,bundle_n=excluded.bundle_n,bundle_price_p=excluded.bundle_price_p,rollover=excluded.rollover;
select card_ensure_open();
notify pgrst, 'reload schema';
