-- packs-1000.sql — 1,000-ticket pack (£680) + whole-balance rate at £680+.
create or replace function c2_pack_price(n int) returns int language sql immutable as $$
  select case n when 1 then 100 when 5 then 475 when 10 then 900 when 25 then 2100 when 50 then 4000 when 100 then 7500 when 250 then 18000 when 500 then 35000 when 1000 then 68000 else null end $$;
create or replace function c2_rate_for(p_amount_p int) returns int language sql immutable as $$
  select case when p_amount_p >= 68000 then 68 when p_amount_p >= 35000 then 70 when p_amount_p >= 18000 then 72 when p_amount_p >= 7500 then 75 when p_amount_p >= 4000 then 80
              when p_amount_p >= 2100 then 84 when p_amount_p >= 900 then 90 when p_amount_p >= 475 then 95 else 100 end $$;
notify pgrst, 'reload schema';
