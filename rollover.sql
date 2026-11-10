-- rollover.sql — rollover draws. For a kind with rollover=true the winning number is drawn from ALL numbers (1..cap),
-- not just the sold ones. Sold number → that player wins prize + any rollover. Unsold number → nobody wins this draw and
-- the whole pot (prize + rollover) is carried into the next draw of the same kind. A draw with no entries is void:
-- nothing taken, nothing owed, nothing carried. Payout stays prize ÷ (cap × price) of takings at any fill.
alter table card_kinds add column if not exists rollover boolean not null default false;
alter table card_draws add column if not exists rollover_p int not null default 0;
alter table card_draws add column if not exists drawn_range int;       -- numbers the draw was made from (cap or sold)

-- next slot strictly after a given time (same arithmetic as card_next_off)
create or replace function card_next_off_after(k text, t timestamptz) returns timestamptz
language plpgsql stable set search_path = public, extensions as $$
declare s record; l timestamp; d timestamp;
begin
  select * into s from card_spec(k);
  if s.daily_hour is not null then
    l := t at time zone 'Europe/London';
    d := date_trunc('day', l) + (s.daily_hour||' hours')::interval;
    if d <= l then d := d + interval '1 day'; end if;
    return d at time zone 'Europe/London';
  end if;
  return to_timestamp((floor((extract(epoch from t) - s.offset_s)/s.step_s) + 1)*s.step_s + s.offset_s);
end $$;


create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; k card_kinds%rowtype; v_range int; v_drawn int; v_win int; v_uid uuid; v_pot int; nxt card_draws%rowtype;
begin
  for d in select * from card_draws where status='open' and off_at <= now() order by off_at for update loop
    select * into k from card_kinds where kind=d.kind;
    v_win := null; v_drawn := null; v_pot := d.prize_p + d.rollover_p;
    if d.sold > 0 then
      v_range := case when coalesce(k.rollover,false) and d.cap is not null then d.cap else d.sold end;
      v_drawn := 1 + ((('x'||substr(md5(d.seed||':'||v_range::text),1,8))::bit(32)::bigint & 2147483647) % v_range)::int;
      if v_drawn <= d.sold then v_win := v_drawn; end if;
    else
      v_range := 0;
    end if;
    update card_draws set status='settled', winner_entry=v_win, drawn_no=v_drawn, drawn_range=v_range, settled_at=now() where id=d.id;
    if v_win is not null then
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, v_pot, drawlabel(d.kind)||' win '||to_char(d.off_at at time zone 'Europe/London','DD Mon HH24:MI')||' #'||v_win||case when d.rollover_p>0 then ' (incl. rollover)' else '' end);
      end if;
    elsif d.sold > 0 and coalesce(k.rollover,false) then
      -- unsold number drawn: carry the pot to the next draw of this kind (create it if needed)
      nxt := card_draw_for(d.kind, card_next_off_after(d.kind, d.off_at));
      update card_draws set rollover_p = rollover_p + v_pot where id = nxt.id;
    end if;
  end loop;
end $$;

-- state: expose rollover + pot on kinds, open draws, ahead and results
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_kinds jsonb; v_open jsonb; v_ahead jsonb; v_results jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,'cap',cap,
           'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'bundle_n',bundle_n,'bundle_price_p',bundle_price_p,'rollover',rollover) order by sort),'[]'::jsonb) into v_kinds from card_kinds where active;
  select coalesce(jsonb_object_agg(kind, jsonb_build_object('id',id,'off_at',off_at,'sold',sold,'cap',cap,'prize_p',prize_p,'rollover_p',rollover_p,'price_p',price_p,'seed_hash',seed_hash,'game_no',card_game_no(kind,off_at))),'{}'::jsonb)
    into v_open from (select distinct on (kind) * from card_draws where status='open' and off_at > now() order by kind, off_at) o;
  select coalesce(jsonb_agg(jsonb_build_object('kind',kind,'off_at',off_at,'sold',sold,'cap',cap,'prize_p',prize_p,'rollover_p',rollover_p,'game_no',card_game_no(kind,off_at)) order by off_at),'[]'::jsonb)
    into v_ahead from card_draws where status='open' and (sold>0 or rollover_p>0) and off_at > now();
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb) into v_results from (
      select jsonb_build_object('kind',d.kind,'off_at',d.off_at,'prize_p',d.prize_p,'rollover_p',d.rollover_p,'sold',d.sold,'cap',d.cap,'drawn_range',d.drawn_range,
             'winner_entry',d.winner_entry,'drawn_no',d.drawn_no,'seed',d.seed,'seed_hash',d.seed_hash,'draw_id',d.id,'game_no',card_game_no(d.kind,d.off_at),
             'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter
                              where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
             'win_mult',1) as r
      from card_draws d where d.status='settled' and d.sold>0 and d.settled_at > now() - interval '2 days' order by d.off_at desc limit 20) s;
  return jsonb_build_object('kinds',v_kinds,'open',v_open,'ahead',v_ahead,'results',v_results,'server_now',now(),'window_days',7,'postal_days',3);
end $$;

create or replace function card_lookup(p_game_no text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g record; d card_draws%rowtype;
begin
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  select * into d from card_draws where kind=g.kind and off_at=g.off_at;
  if not found then
    return jsonb_build_object('found',false,'kind',g.kind,'label',drawlabel(g.kind),'off_at',g.off_at,'game_no',card_game_no(g.kind,g.off_at),
      'status',case when g.off_at<=now() then 'no entries' else 'open' end);
  end if;
  return jsonb_build_object('found',true,'kind',d.kind,'label',drawlabel(d.kind),'off_at',d.off_at,'game_no',card_game_no(d.kind,d.off_at),
    'status',d.status,'price_p',d.price_p,'prize_p',d.prize_p,'rollover_p',d.rollover_p,'cap',d.cap,'sold',d.sold,'drawn_range',d.drawn_range,'drawn_no',d.drawn_no,
    'rollover',(select rollover from card_kinds where kind=d.kind),'seed_hash',d.seed_hash,
    'seed',case when d.status='settled' then d.seed end,'winner_entry',d.winner_entry,'settled_at',d.settled_at,
    'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
    'postal_entries',(select count(*) from card_entries ce where ce.draw_id=d.id and ce.via='post'));
end $$;

create or replace function iw_admin_kinds(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,
    'cap',cap,'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'sort',sort,'active',active,'rollover',rollover,
    'open_entries',(select coalesce(sum(sold),0) from card_draws d where d.kind=card_kinds.kind and d.status='open'),
    'rollover_open_p',(select coalesce(sum(rollover_p),0) from card_draws d where d.kind=card_kinds.kind and d.status='open')) order by sort)
    from card_kinds),'[]'::jsonb);
end $$;

-- admin switch per row
create or replace function iw_admin_kind_rollover(p_token uuid, p_kind text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin perform iw_admin(p_token); update card_kinds set rollover=p_on where kind=p_kind; return jsonb_build_object('kind',p_kind,'rollover',p_on); end $$;
grant execute on function iw_admin_kind_rollover(uuid,text,boolean) to service_role;

-- the full schedule back on, as rollover draws (every row with a cap); free draws stay "winner from entries"
update card_kinds set rollover = (price_p > 0 and cap is not null);
notify pgrst, 'reload schema';
