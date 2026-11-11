-- postal-roll.sql — a postcard naming a full or already-closed draw rolls to the next draw of the
-- same kind with room, exactly as an online entry does. Run AFTER postal-acct.sql.
create or replace function card_next_with_room(k text, t timestamptz) returns timestamptz
language plpgsql stable as $$
declare s record; cur timestamptz; d card_draws%rowtype; i int := 0;
begin
  select * into s from card_spec(k);
  cur := t;
  loop
    if cur <= now() then cur := card_next_off(k); end if;      -- already closed: start from the next scheduled draw
    exit when cur > now() + interval '7 days' or i > 2000;
    select * into d from card_draws where kind=k and off_at=cur;
    if not found or (d.status='open' and (d.cap is null or d.sold < d.cap)) then return cur; end if;
    -- step to the following slot
    if s.daily_hour is not null then cur := cur + interval '1 day';
    else cur := cur + (s.step_s||' seconds')::interval; end if;
    i := i + 1;
  end loop;
  return null;
end $$;

create or replace function iw_admin_postal_enter_no(p_token uuid, p_email text, p_game_no text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare g record; v_uid uuid; r jsonb; t timestamptz; moved boolean := false;
begin
  perform iw_admin(p_token);
  v_uid := iw_postal_user(p_email);
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  t := card_next_with_room(g.kind, g.off_at);
  if t is null then raise exception 'no % draw with room in the next 7 days', drawlabel(g.kind); end if;
  moved := (t <> g.off_at);
  insert into postal_entries (game, details) values ('card', upper(trim(p_game_no))||' '||trim(p_email)||case when moved then ' -> '||card_game_no(g.kind,t) else '' end);
  r := card_add_entry(v_uid, g.kind, t, 'post');
  return jsonb_build_object('entered',1,'first',r,'game_no',card_game_no(g.kind,t),'moved',moved,'named',upper(trim(p_game_no)));
end $$;
notify pgrst, 'reload schema';
