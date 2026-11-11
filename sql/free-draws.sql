-- free-draws.sql — a selection of free draws (no entry fee, one entry per account per draw, free by post too).
-- Worst case paid out if every draw has an entry ≈ £1,600/day (£1×288 + £5×144 + £20×24 + £100).
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort,active) values
 ('free_1',  'FR1',  'Free Draw £1',    0,   100, null,   300, 150, null, 59, true),   -- every 5 min at :30 past the slot
 ('free',    'FREE', 'Free Draw £5',    0,   500, null,   600,   0, null, 60, true),   -- every 10 min
 ('free_20', 'FR20', 'Free Draw £20',   0,  2000, null,  3600,2700, null, 61, true),   -- hourly at :45
 ('free_100','FR100','Free Draw £100',  0, 10000, null, 86400,   0,   20, 62, true)    -- daily 20:00
on conflict (kind) do update set code=excluded.code, label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort, active=excluded.active;

-- one entry per account applies to every free draw, not just 'free'
create or replace function card_add_entry(p_user uuid, k text, t timestamptz, p_via text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_no int;
begin
  if not (k = any(card_kinds())) then raise exception 'bad kind'; end if;
  if not card_valid_off(k, t) then raise exception 'that draw is not open for entry'; end if;
  d := card_draw_for(k, t);
  select * into d from card_draws where id=d.id for update;
  if d.status <> 'open' then raise exception 'draw closed'; end if;
  if d.cap is not null and d.sold >= d.cap then raise exception 'this draw is full'; end if;
  if d.price_p = 0 and exists (select 1 from card_entries where draw_id=d.id and punter=p_user::text) then
    raise exception 'already entered this free draw'; end if;
  if p_via='online' and d.price_p > 0 then
    if iw_balance(p_user) < d.price_p then raise exception 'insufficient credit'; end if;
    insert into ledger (user_id, delta_p, reason)
    values (p_user, -d.price_p, drawlabel(k)||' '||to_char(d.off_at at time zone 'Europe/London','DD Mon HH24:MI')||' #'||(d.sold+1));
  end if;
  v_no := d.sold + 1;
  insert into card_entries (draw_id, entry_no, punter, mult, via) values (d.id, v_no, p_user::text, 1, p_via);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'kind',k,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p,'balance_p',iw_balance(p_user));
end $$;
notify pgrst, 'reload schema';
