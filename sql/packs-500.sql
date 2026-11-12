-- packs-500.sql (v3) — packs up to 1,000 tickets, discounts capped so every pack clears the 51p average payout by a wide margin.
create or replace function c2_pack_price(n int) returns int language sql immutable as $$
  select case n when 1 then 100 when 5 then 475 when 10 then 900 when 25 then 2100 when 50 then 4000 when 100 then 7500 when 250 then 18000 when 500 then 35000 when 1000 then 68000 else null end $$;
notify pgrst, 'reload schema';
