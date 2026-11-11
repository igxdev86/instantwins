-- card-drawn.sql — always record and expose the DRAWN number on the Card,
-- even when it wasn't sold (so the client can animate every close).
-- Also backfills drawn_no for already-settled draws from their seeds.

alter table card_draws add column if not exists drawn_no int;

create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_draw int; v_win int; v_uid uuid; CEIL int := 250000;  -- £2,500
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    v_win := null; v_draw := null;
    if d.cap is null then
      if d.sold > 0 then
        v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
        v_win := v_draw;
      end if;
    elsif d.kind='grand' and d.prize_p >= CEIL then
      if d.sold > 0 then
        v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint & 2147483647) % d.sold)::int;
        v_win := v_draw;
      end if;
    else
      v_draw := 1 + ((('x'||substr(md5(d.seed||':'||d.cap::text),1,8))::bit(32)::bigint & 2147483647) % d.cap)::int;
      if d.sold > 0 and v_draw <= d.sold then v_win := v_draw; end if;
    end if;

    update card_draws set status='settled', winner_entry=v_win, drawn_no=v_draw, settled_at=now() where id=d.id;

    if v_win is not null then
      select u.id into v_uid from card_entries ce join users u on u.id::text=ce.punter
       where ce.draw_id=d.id and ce.entry_no=v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p, drawlabel(d.kind)||' win '||to_char(d.off_at,'HH24:MI')||' #'||v_win);
      end if;
      if d.kind='grand' then update card_rollover set amount_p=100000 where kind='grand'; end if;
    else
      if d.kind='grand' then
        update card_rollover set amount_p = least(amount_p + d.base_prize_p, CEIL) where kind='grand';
      end if;
    end if;
  end loop;
end $$;

-- backfill drawn_no on settled draws (capacity draws only; pre-cap draws fall back to winner_entry)
update card_draws set drawn_no = case
  when cap is not null then 1 + ((('x'||substr(md5(seed||':'||cap::text),1,8))::bit(32)::bigint & 2147483647) % cap)::int
  else winner_entry end
where status='settled' and drawn_no is null;

create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb;
begin
  perform card_settle_due();
  perform card_ensure_open();
  select jsonb_object_agg(kind, jsonb_build_object(
           'id',id,'off_at',off_at,'price_p',price_p,'prize_p',prize_p,'base_prize_p',base_prize_p,
           'cap',cap,'sold',sold,'seed_hash',seed_hash))
    into v_open from card_draws where status='open';
  select coalesce(jsonb_agg(r order by r->>'off_at' desc),'[]'::jsonb)
    into v_results from (
      select jsonb_build_object('kind',kind,'off_at',off_at,'prize_p',prize_p,'sold',sold,'cap',cap,
             'winner_entry',winner_entry,'drawn_no',drawn_no,'seed',seed,'seed_hash',seed_hash,'draw_id',id) as r
      from card_draws where status='settled' order by off_at desc limit 8) s;
  return jsonb_build_object('open',v_open,'results',v_results,'server_now',now());
end $$;

notify pgrst, 'reload schema';
