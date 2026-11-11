-- packs-500.sql — packs up to 500 tickets.
create or replace function c2_pack_price(n int) returns int language sql immutable as $$
  select case n when 1 then 100 when 5 then 450 when 10 then 800 when 25 then 1800 when 50 then 3200 when 100 then 6000 when 250 then 14500 when 500 then 28000 else null end $$;
notify pgrst, 'reload schema';
