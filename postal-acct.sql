-- postal-acct.sql — postcards are matched by account number (IW…) or, failing that, email.
create or replace function iw_postal_user(p_ref text) returns uuid
language sql stable as $$
  select id from users
   where upper(replace(trim(p_ref),' ','')) = upper(coalesce(acct_no,''))
      or lower(trim(p_ref)) = lower(email)
   limit 1 $$;

create or replace function iw_admin_postal_enter_no(p_token uuid, p_email text, p_game_no text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare g record; v_uid uuid; r jsonb;
begin
  perform iw_admin(p_token);
  v_uid := iw_postal_user(p_email);
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  insert into postal_entries (game, details) values ('card', upper(trim(p_game_no))||' '||trim(p_email));
  r := card_add_entry(v_uid, g.kind, g.off_at, 'post');
  return jsonb_build_object('entered',1,'first',r,'game_no',card_game_no(g.kind,g.off_at));
end $$;

create or replace function iw_admin_postal_enter(p_token uuid, p_email text, p_kind text, p_off_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; t timestamptz; day_end timestamptz; n int := 0; r jsonb;
begin
  perform iw_admin(p_token);
  v_uid := iw_postal_user(p_email);
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  perform card_settle_due();
  insert into postal_entries (game, details) values ('card', p_kind||' '||coalesce(p_off_at::text,'unnamed')||' '||trim(p_email));
  if p_off_at is not null then
    r := card_add_entry(v_uid, p_kind, p_off_at, 'post');
    return jsonb_build_object('entered',1,'first',r);
  end if;
  t := card_next_off(p_kind);
  r := card_add_entry(v_uid, p_kind, t, 'post'); n := 1;
  day_end := (date_trunc('day', now() at time zone 'Europe/London') + interval '1 day') at time zone 'Europe/London';
  t := card_next_off('five');
  while t < day_end loop
    begin
      if not (p_kind='five' and t = (r->>'off_at')::timestamptz) then
        perform card_add_entry(v_uid, 'five', t, 'post'); n := n + 1;
      end if;
    exception when others then null;
    end;
    t := t + interval '5 minutes';
  end loop;
  return jsonb_build_object('entered',n,'first',r);
end $$;
notify pgrst, 'reload schema';
