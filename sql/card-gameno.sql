-- card-gameno.sql — every draw carries a visible game number: CODE-DDMMYY-HHMM (London time),
-- e.g. F100-311026-1815. Postcards can quote it. Run AFTER card-kinds-4.sql.

alter table card_kinds add column if not exists code text;
update card_kinds set code = c from (values
 ('minute','S10'),('s60_20','S20'),('s60_50','S50'),('s60_100','S100'),
 ('five','F100'),('m5_200','F200'),('m5_500','F500'),('m5_1000','F1K'),
 ('m15_150','Q150'),('silver','Q400'),('m15_1000','Q1K'),('m15_2000','Q2K'),
 ('gold','H750'),('grand','H1K'),('h_2000','H2K'),('h_5000','H5K'),
 ('d_400','D400'),('d_1000','D1K'),('platinum','D1500'),('d_5000','D5K'),
 ('free','FREE')) v(k,c) where kind = v.k;
create unique index if not exists card_kinds_code_idx on card_kinds(code);

create or replace function card_game_no(k text, t timestamptz) returns text
language sql stable as $$
  select (select code from card_kinds where kind=k)||'-'||to_char(t at time zone 'Europe/London','DDMMYY')||'-'||to_char(t at time zone 'Europe/London','HH24MI') $$;

-- parse "F100-311026-1815" (spaces, slashes, colons and case tolerated) -> (kind, off_at)
create or replace function card_parse_game_no(p text, out kind text, out off_at timestamptz)
language plpgsql stable as $$
declare s text; parts text[];
begin
  s := upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]+', '-', 'g'));
  s := trim(both '-' from s);
  parts := string_to_array(s, '-');
  if array_length(parts,1) <> 3 then raise exception 'game number should look like F100-311026-1815'; end if;
  select ck.kind into kind from card_kinds ck where ck.code = parts[1];
  if kind is null then raise exception 'unknown draw code %', parts[1]; end if;
  if parts[2] !~ '^\d{6}$' or parts[3] !~ '^\d{4}$' then raise exception 'game number should look like F100-311026-1815'; end if;
  off_at := to_timestamp(parts[2]||' '||parts[3], 'DDMMYY HH24MI') at time zone 'UTC';   -- naive local
  off_at := (off_at at time zone 'UTC') at time zone 'Europe/London';                    -- reinterpret as London
end $$;

-- admin: key a postcard in by game number
create or replace function iw_admin_postal_enter_no(p_token uuid, p_email text, p_game_no text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare g record; v_uid uuid; r jsonb;
begin
  perform iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_email));
  if v_uid is null then raise exception 'no account for that email'; end if;
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  insert into postal_entries (game, details) values ('card', upper(trim(p_game_no))||' '||lower(trim(p_email)));
  r := card_add_entry(v_uid, g.kind, g.off_at, 'post');
  return jsonb_build_object('entered',1,'first',r,'game_no',card_game_no(g.kind,g.off_at));
end $$;
grant execute on function iw_admin_postal_enter_no(uuid,text,text) to service_role;

-- expose code in state
create or replace function card_state() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_open jsonb; v_results jsonb; v_ahead jsonb; v_kinds jsonb;
begin
  perform card_settle_due(); perform card_ensure_open();
  select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,'cap',cap,
           'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour) order by sort) into v_kinds from card_kinds where active;
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

-- results feed: label + game number for every settled draw
create or replace function iw_results() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_card jsonb; v_pools jsonb;
begin
  select coalesce(jsonb_agg(c order by c->>'off_at' desc),'[]'::jsonb) into v_card from (
    select jsonb_build_object('kind',kind,'label',drawlabel(kind),'game_no',card_game_no(kind,off_at),'off_at',off_at,'prize_p',prize_p,'cap',cap,
      'sold',sold,'winner_entry',winner_entry,'seed',seed,'seed_hash',seed_hash) c
    from card_draws where status='settled' and sold>0 order by off_at desc limit 40) s;
  select coalesce(jsonb_agg(p order by p->>'settled_at' desc),'[]'::jsonb) into v_pools from (
    select jsonb_build_object('game',g.name,'tag',pl.game,'pool_no',pl.pool_no,
      'settled_at',pl.settled_at,'seed',pl.seed,'seed_hash',pl.seed_hash,'cap',pl.cap,
      'winners',(select count(*) from allocation a where a.pool_id=pl.id and a.prize_p>0),
      'top_p',(select max(a.prize_p) from allocation a where a.pool_id=pl.id)) p
    from pools pl join games g on g.tag=pl.game
    where pl.status='settled' order by pl.settled_at desc limit 25) s;
  return jsonb_build_object('card',v_card,'pools',v_pools,'server_now',now());
end $$;
notify pgrst, 'reload schema';
