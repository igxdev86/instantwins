-- card-stakes.sql — stake selection on the Card's FIVE-MINUTE draw.
-- An entry at multiplier m costs £1×m (cap £50 → m ≤ 50) and, if its number is
-- drawn, pays £100×m. The Grand (shared rolling jackpot) and Free draw stay at ×1.
-- Run AFTER card-drawn.sql.

alter table card_entries add column if not exists mult int not null default 1;

create or replace function card_enter3(p_kind text, p_token uuid, p_mult int default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; d card_draws%rowtype; v_no int; m int; v_cost int;
begin
  u := iw_user(p_token);
  if p_kind not in ('five','grand','free') then raise exception 'bad kind'; end if;
  m := case when p_kind='five' then greatest(coalesce(p_mult,1),1) else 1 end;
  perform card_settle_due();
  perform card_ensure_open();
  select * into d from card_draws where kind=p_kind and status='open' order by off_at asc limit 1 for update;
  if d.cap is not null and d.sold >= d.cap then raise exception 'this draw is full'; end if;
  v_cost := d.price_p * m;
  if v_cost > 5000 then raise exception 'max stake is £50 per entry'; end if;
  if p_kind='free' then
    if exists (select 1 from card_entries where draw_id=d.id and punter=u.id::text) then
      raise exception 'already entered this free draw'; end if;
  else
    if iw_balance(u.id) < v_cost then raise exception 'insufficient credit'; end if;
  end if;
  v_no := d.sold + 1;
  if v_cost > 0 then
    insert into ledger (user_id, delta_p, reason)
    values (u.id, -v_cost, p_kind||' draw '||to_char(d.off_at,'HH24:MI')||' #'||v_no||case when m>1 then ' x'||m else '' end);
  end if;
  insert into card_entries (draw_id, entry_no, punter, mult) values (d.id, v_no, u.id::text, m);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,'mult',m,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p*m,'balance_p',iw_balance(u.id));
end $$;

-- settle: pay prize × the winning entry's multiplier
create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_draw int; v_win int; v_uid uuid; v_m int; CEIL int := 250000;
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    v_win := null; v_draw := null;
    if d.cap is null then
      if d.sold > 0 then
        v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int; v_win := v_draw; end if;
    elsif d.kind='grand' and d.prize_p >= CEIL then
      if d.sold > 0 then
        v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int; v_win := v_draw; end if;
    else
      v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.cap::text),1,8))::bit(32)::bigint & 2147483647) % d.cap)::int;
      if d.sold > 0 and v_draw <= d.sold then v_win := v_draw; end if;
    end if;
    update card_draws set status='settled', winner_entry=v_win, drawn_no=v_draw, settled_at=now() where id=d.id;
    if v_win is not null then
      select u.id, coalesce(ce.mult,1) into v_uid, v_m from card_entries ce join users u on u.id::text=ce.punter
       where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p*v_m, drawlabel(d.kind)||' win '||to_char(d.off_at,'HH24:MI')||' #'||v_win||case when v_m>1 then ' x'||v_m else '' end);
      end if;
      if d.kind='grand' then update card_rollover set amount_p=100000 where kind='grand'; end if;
    else
      if d.kind='grand' then update card_rollover set amount_p = least(amount_p + d.base_prize_p, CEIL) where kind='grand'; end if;
    end if;
  end loop;
end $$;

-- results: include the winning entry's multiplier so the client shows the right £
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,
           'base_prize_p',base_prize_p,'cap',cap,'sold',sold,'seed_hash',seed_hash)) into v_open from card_draws where status='open';
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'sold',d.sold,'cap',d.cap,
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,
             'win_mult',coalesce((select ce.mult from card_entries ce where ce.draw_id=d.id and ce.entry_no=d.winner_entry),1)) as r
      from card_draws d where d.status='settled' order by d.off_at desc limit 8) s;
  return jsonb_build_object('open',v_open,'results',v_results,'server_now',now());
end $$;

grant execute on function card_enter3(text,uuid,int) to service_role;
notify pgrst, 'reload schema';
