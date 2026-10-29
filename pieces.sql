-- pieces.sql — Pick a Piece, live engine (lucky-piece snowball).
-- Hourly boards of 48 pieces at £2. One winning piece per board is committed
-- (seed hashed up front, revealed at close). Holder of the winning piece takes
-- the jackpot; if that piece was unsold there is no winner and the jackpot rolls
-- over (+£100 per roll, seeded at £100). Must-drop at £1,000: at the cap, if the
-- committed piece is unsold, the winner is drawn from the pieces that WERE sold.
-- Settlement is lazy (runs on every read/pick) — no cron required.

create table if not exists piece_boards (
  id            uuid primary key default gen_random_uuid(),
  board_no      int  not null unique,
  off_at        timestamptz not null,
  pieces        int  not null default 48,
  price_p       int  not null default 200,
  jackpot_p     int  not null,
  seed          text not null,            -- secret until settled
  seed_hash     text not null,            -- published while open
  winning_piece int,
  winner        text,                     -- users.id::text
  won           boolean,
  status        text not null default 'open',   -- open | settled
  settled_at    timestamptz,
  created_at    timestamptz not null default now()
);
create table if not exists piece_entries (
  board_id   uuid not null references piece_boards(id) on delete cascade,
  piece_no   int  not null,
  punter     text not null,               -- users.id::text
  created_at timestamptz not null default now(),
  primary key (board_id, piece_no)
);
alter table piece_boards  enable row level security;
alter table piece_entries enable row level security;

-- deterministic winning piece from the committed seed
create or replace function piece_win_no(p_seed text, p_pieces int) returns int
language sql immutable as $$
  select 1 + ((('x'||substr(md5(p_seed||':win'),1,8))::bit(32)::bigint & 2147483647) % p_pieces)::int;
$$;

create or replace function piece_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_no int; v_seed text; v_jack int; last_b piece_boards%rowtype;
begin
  if exists (select 1 from piece_boards where status='open') then return; end if;
  select * into last_b from piece_boards where status='settled' order by board_no desc limit 1;
  if found and last_b.won = false then v_jack := least(last_b.jackpot_p + 10000, 100000);
  else v_jack := 10000; end if;
  select coalesce(max(board_no),0)+1 into v_no from piece_boards;
  v_seed := 'PIECE-'||lpad(v_no::text,4,'0')||'|'||gen_random_uuid();
  insert into piece_boards (board_no, off_at, jackpot_p, seed, seed_hash)
  values (v_no, date_trunc('hour', now()) + interval '1 hour', v_jack, v_seed,
          encode(digest(v_seed,'sha256'),'hex'));
end $$;

create or replace function piece_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare b piece_boards%rowtype; v_win int; v_holder text; v_cnt int; v_idx int; v_uid uuid;
begin
  for b in select * from piece_boards where status='open' and off_at <= now() for update loop
    v_win := piece_win_no(b.seed, b.pieces);
    select punter into v_holder from piece_entries where board_id=b.id and piece_no=v_win;
    -- must-drop at the cap: committed piece unsold -> draw from sold pieces
    if v_holder is null and b.jackpot_p >= 100000 then
      select count(*) into v_cnt from piece_entries where board_id=b.id;
      if v_cnt > 0 then
        v_idx := ((('x'||substr(md5(b.seed||':drop'),1,8))::bit(32)::bigint & 2147483647) % v_cnt)::int;
        select piece_no, punter into v_win, v_holder
          from piece_entries where board_id=b.id order by piece_no offset v_idx limit 1;
      end if;
    end if;
    if v_holder is not null then
      begin v_uid := v_holder::uuid; exception when others then v_uid := null; end;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, b.jackpot_p, 'piece win board '||b.board_no||' #'||v_win);
      end if;
      update piece_boards set status='settled', settled_at=now(), winning_piece=v_win, winner=v_holder, won=true where id=b.id;
    else
      update piece_boards set status='settled', settled_at=now(), winning_piece=v_win, won=false where id=b.id;
    end if;
  end loop;
  perform piece_ensure_open();
end $$;

create or replace function piece_state(p_token uuid default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare b piece_boards%rowtype; v_uid uuid; v_taken int[]; v_mine int[]; v_last jsonb;
begin
  perform piece_settle_due();
  perform piece_ensure_open();
  select * into b from piece_boards where status='open' order by board_no desc limit 1;
  if p_token is not null then
    select user_id into v_uid from sessions where token = p_token;
  end if;
  select coalesce(array_agg(piece_no order by piece_no),'{}') into v_taken from piece_entries where board_id=b.id;
  if v_uid is not null then
    select coalesce(array_agg(piece_no order by piece_no),'{}') into v_mine
      from piece_entries where board_id=b.id and punter=v_uid::text;
  else v_mine := '{}'; end if;
  select jsonb_build_object('board_no',l.board_no,'winning_piece',l.winning_piece,'won',l.won,
           'jackpot_p',l.jackpot_p,'seed',l.seed,
           'winner_name',(select u.name from users u where u.id::text = l.winner),
           'mine',(v_uid is not null and l.winner = v_uid::text))
    into v_last from piece_boards l where l.status='settled' order by l.board_no desc limit 1;
  return jsonb_build_object(
    'board','PIECE-'||lpad(b.board_no::text,4,'0'),'board_no',b.board_no,'off_at',b.off_at,
    'pieces',b.pieces,'price_p',b.price_p,'jackpot_p',b.jackpot_p,'cap_p',100000,'seed_hash',b.seed_hash,
    'taken',to_jsonb(v_taken),'mine',to_jsonb(v_mine),'last',v_last,'server_now',now(),
    'balance_p',case when v_uid is null then null else iw_balance(v_uid) end);
end $$;

create or replace function piece_pick(p_token uuid, p_piece int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; b piece_boards%rowtype;
begin
  u := iw_user(p_token);
  perform piece_settle_due();
  perform piece_ensure_open();
  select * into b from piece_boards where status='open' order by board_no desc limit 1 for update;
  if p_piece < 1 or p_piece > b.pieces then raise exception 'pick a piece between 1 and %', b.pieces; end if;
  if exists (select 1 from piece_entries where board_id=b.id and piece_no=p_piece) then
    raise exception 'that piece has already been taken';
  end if;
  if iw_balance(u.id) < b.price_p then raise exception 'insufficient credit'; end if;
  insert into ledger (user_id, delta_p, reason) values (u.id, -b.price_p, 'piece board '||b.board_no||' #'||p_piece);
  insert into piece_entries (board_id, piece_no, punter) values (b.id, p_piece, u.id::text);
  return piece_state(p_token);
end $$;

grant execute on function piece_state(uuid)        to service_role;
grant execute on function piece_pick(uuid,int)     to service_role;
grant execute on function piece_settle_due()       to service_role;
grant execute on function piece_ensure_open()      to service_role;

select piece_ensure_open();
notify pgrst, 'reload schema';
