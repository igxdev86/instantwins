-- card-minute.sql — the 60-SECOND draw on the Card.
-- 50p entry, £10 prize, winning number drawn from a capacity of 50 (no winner
-- if that number wasn't sold — prize retained). A new draw every minute.
-- Run AFTER card-stakes.sql.

alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws add  constraint card_draws_kind_check
  check (kind in ('minute','five','grand','free'));

create or replace function drawlabel(k text) returns text
language sql immutable as $$ select case k when 'grand' then 'Hourly Grand' when 'free' then 'Free Draw'
  when 'minute' then '60-Second Draw' else 'Five-Minute Draw' end $$;

create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_min timestamptz; v_five timestamptz; v_hour timestamptz; v_free timestamptz; v_seed text; v_roll int;
begin
  v_min  := to_timestamp(ceil(extract(epoch from now())/60)*60);
  v_five := to_timestamp(ceil(extract(epoch from now())/300)*300);
  v_hour := to_timestamp(ceil(extract(epoch from now())/3600)*3600);
  v_free := to_timestamp(ceil(extract(epoch from now())/600)*600);

  if not exists (select 1 from card_draws where kind='minute' and off_at=v_min) then
    v_seed := 'MIN|'||v_min||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('minute',v_min,50,1000,1000,50,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='five' and off_at=v_five) then
    v_seed := 'FIVE|'||v_five||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('five',v_five,100,10000,10000,200,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='grand' and off_at=v_hour) then
    select amount_p into v_roll from card_rollover where kind='grand';
    v_seed := 'GRAND|'||v_hour||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('grand',v_hour,200,100000+coalesce(v_roll,0),100000,1000,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='free' and off_at=v_free) then
    v_seed := 'FREE|'||v_free||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,base_prize_p,cap,seed,seed_hash)
    values ('free',v_free,0,500,500,null,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
end $$;

-- allow 'minute' entries (fixed 50p, no multiplier)
create or replace function card_enter3(p_kind text, p_token uuid, p_mult int default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; d card_draws%rowtype; v_no int; m int; v_cost int;
begin
  u := iw_user(p_token);
  if p_kind not in ('minute','five','grand','free') then raise exception 'bad kind'; end if;
  m := case when p_kind='five' then greatest(coalesce(p_mult,1),1) else 1 end;
  perform card_settle_due(); perform card_ensure_open();
  select * into d from card_draws where kind=p_kind and status='open' order by off_at asc limit 1 for update;
  if d.cap is not null and d.sold >= d.cap then raise exception 'this draw is full'; end if;
  v_cost := d.price_p * m;
  if v_cost > 5000 then raise exception 'max stake is £50 per entry'; end if;
  if p_kind='free' then
    if exists (select 1 from card_entries where draw_id=d.id and punter=u.id::text) then raise exception 'already entered this free draw'; end if;
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

select card_ensure_open();
notify pgrst, 'reload schema';
