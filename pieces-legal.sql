-- pieces-legal.sql — Pick a Piece after the legal review. Run AFTER pieces.sql.
--   • One board a day, closing 20:00 London time (long enough for a postcard to arrive).
--   • Fixed £50 prize, £2 a piece, 48 pieces. No jackpot, no rollover.
--   • The winning piece is chosen from the pieces actually CLAIMED
--     (md5(seed:claimed) mod claimed, indexing claimed pieces in number order),
--     so the prize is paid on every board with at least one claim.

create or replace function piece_next_close() returns timestamptz
language sql stable as $$
  select case when (now() at time zone 'Europe/London') < date_trunc('day', now() at time zone 'Europe/London') + interval '20 hours'
              then (date_trunc('day', now() at time zone 'Europe/London') + interval '20 hours') at time zone 'Europe/London'
              else (date_trunc('day', now() at time zone 'Europe/London') + interval '44 hours') at time zone 'Europe/London' end $$;

create or replace function piece_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_no int; v_seed text;
begin
  if exists (select 1 from piece_boards where status='open') then return; end if;
  select coalesce(max(board_no),0)+1 into v_no from piece_boards;
  v_seed := 'PIECE-'||lpad(v_no::text,4,'0')||'|'||gen_random_uuid();
  insert into piece_boards (board_no, off_at, jackpot_p, seed, seed_hash)
  values (v_no, piece_next_close(), 5000, v_seed, encode(digest(v_seed,'sha256'),'hex'));
end $$;

create or replace function piece_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare b piece_boards%rowtype; v_win int; v_holder text; v_cnt int; v_idx int; v_uid uuid;
begin
  for b in select * from piece_boards where status='open' and off_at <= now() for update loop
    v_win := null; v_holder := null;
    select count(*) into v_cnt from piece_entries where board_id=b.id;
    if v_cnt > 0 then
      v_idx := ((('x'||substr(md5(b.seed||':'||v_cnt::text),1,8))::bit(32)::bigint & 2147483647) % v_cnt)::int;
      select piece_no, punter into v_win, v_holder from piece_entries where board_id=b.id order by piece_no offset v_idx limit 1;
    end if;
    if v_holder is not null then
      begin v_uid := v_holder::uuid; exception when others then v_uid := null; end;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason) values (v_uid, b.jackpot_p, 'Pick a Piece win board '||b.board_no||' #'||v_win);
      end if;
      update piece_boards set status='settled', settled_at=now(), winning_piece=v_win, winner=v_holder, won=true where id=b.id;
    else
      update piece_boards set status='settled', settled_at=now(), winning_piece=null, won=false where id=b.id;   -- nobody claimed a piece
    end if;
  end loop;
  perform piece_ensure_open();
end $$;

-- move the current open (hourly) board to the daily close and fixed prize
update piece_boards set off_at = piece_next_close(), jackpot_p = 5000 where status='open';
notify pgrst, 'reload schema';
