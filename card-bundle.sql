-- card-bundle.sql — "Play the next N draws for £X" bundle on a draw row (one number in each of the next N draws,
-- charged once at the bundle price). Free postal route is unchanged: one card = one entry in a named draw.
alter table card_kinds add column if not exists bundle_n int;
alter table card_kinds add column if not exists bundle_price_p int;
update card_kinds set bundle_n=15, bundle_price_p=1000 where kind='m5_20';   -- 15 × £1 draws for £10

create or replace function card_enter_bundle(p_token uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; k card_kinds%rowtype; t timestamptz; n int := 0; tries int := 0; r jsonb; outp jsonb := '[]'::jsonb; d card_draws%rowtype;
begin
  u := iw_user(p_token); perform card_settle_due();
  select * into k from card_kinds where kind=p_kind and active;
  if not found or k.bundle_n is null or k.bundle_price_p is null then raise exception 'no bundle on this draw'; end if;
  if iw_balance(u.id) < k.bundle_price_p then raise exception 'insufficient credit'; end if;
  insert into ledger (user_id, delta_p, reason) values (u.id, -k.bundle_price_p, k.label||' bundle: next '||k.bundle_n||' draws');
  t := card_next_off(p_kind);
  while n < k.bundle_n and tries < k.bundle_n * 4 loop
    tries := tries + 1;
    d := card_draw_for(p_kind, t);
    if d.status='open' and (d.cap is null or d.sold < d.cap) then
      r := card_add_entry(u.id, p_kind, t, 'bundle'); outp := outp || jsonb_build_array(r); n := n + 1;
    end if;
    t := t + (k.step_s||' seconds')::interval;
  end loop;
  if n = 0 then raise exception 'no open draws to enter'; end if;
  if n < k.bundle_n then  -- partial fill (draws full): refund the unused share
    insert into ledger (user_id, delta_p, reason) values (u.id, (k.bundle_price_p * (k.bundle_n - n)) / k.bundle_n, 'refund: bundle short by '||(k.bundle_n-n)||' draws');
  end if;
  return jsonb_build_object('kind',p_kind,'entered',n,'first_off',outp->0->>'off_at','last_off',outp->(n-1)->>'off_at','entries',outp,'balance_p',iw_balance(u.id));
end $$;
grant execute on function card_enter_bundle(uuid,text) to service_role;

-- expose the bundle in the public kinds list (same shape as before + two fields)
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb; v_ahead jsonb; v_kinds jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,'cap',cap,
           'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'bundle_n',bundle_n,'bundle_price_p',bundle_price_p) order by sort) into v_kinds from card_kinds where active;
  select jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,
           'cap',cap,'sold',sold,'seed_hash',seed_hash,'game_no',card_game_no(kind,off_at))) into v_open
    from (select distinct on (kind) * from card_draws where status='open' and off_at > now() order by kind, off_at) o;
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'off_at',off_at,'sold',sold,'cap',cap) order by off_at),'[]'::jsonb)
    into v_ahead from card_draws where status='open' and sold>0 and off_at > now();
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'sold',d.sold,'cap',d.cap,'game_no',card_game_no(d.kind,d.off_at),
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,
             'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter
                              where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
             'win_mult',1) as r
      from card_draws d where d.status='settled' and d.settled_at > now() - interval '2 days' order by d.off_at desc limit 20) s;
  return jsonb_build_object('kinds',v_kinds,'open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),
    'window_days',7,'postal_days',3);
end $$;
notify pgrst, 'reload schema';
