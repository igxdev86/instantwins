-- =====================================================================
-- CARD FREE DRAWS — blend a 100% free £5 draw (site credit or cash)
-- into the Card, every 10 minutes. Run once in the Supabase SQL editor.
-- Winner is drawn by the same sealed-seed method; settlement already
-- credits the winner's wallet, so £5 lands as site credit (payable as
-- cash on withdrawal). Free entry: no debit, one entry per user/draw.
-- =====================================================================

-- allow the new kind
alter table card_draws drop constraint if exists card_draws_kind_check;
alter table card_draws add  constraint card_draws_kind_check
  check (kind in ('five','grand','free'));

-- open the next five / hourly / FREE draws
create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_five timestamptz; v_hour timestamptz; v_free timestamptz; v_seed text;
begin
  v_five := to_timestamp(ceil(extract(epoch from now())/300)*300);
  v_hour := to_timestamp(ceil(extract(epoch from now())/3600)*3600);
  v_free := to_timestamp(ceil(extract(epoch from now())/600)*600);   -- every 10 min
  if not exists (select 1 from card_draws where kind='five' and off_at=v_five) then
    v_seed := 'FIVE|'||v_five||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,seed,seed_hash)
    values ('five',v_five,100,10000,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='grand' and off_at=v_hour) then
    v_seed := 'GRAND|'||v_hour||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,seed,seed_hash)
    values ('grand',v_hour,200,100000,v_seed,encode(digest(v_seed,'sha256'),'hex'))
    on conflict do nothing;
  end if;
  if not exists (select 1 from card_draws where kind='free' and off_at=v_free) then
    v_seed := 'FREE|'||v_free||'|'||gen_random_uuid();
    insert into card_draws (kind,off_at,price_p,prize_p,seed,seed_hash)
    values ('free',v_free,0,500,v_seed,encode(digest(v_seed,'sha256'),'hex'))  -- £5
    on conflict do nothing;
  end if;
end $$;

-- authenticated entry: free draws cost nothing, one per user per draw
create or replace function card_enter2(p_kind text, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; d card_draws%rowtype; v_no int;
begin
  u := iw_user(p_token);
  if p_kind not in ('five','grand','free') then raise exception 'bad kind'; end if;
  perform card_settle_due();
  perform card_ensure_open();
  select * into d from card_draws
   where kind=p_kind and status='open' order by off_at asc limit 1 for update;

  if p_kind='free' then
    if exists (select 1 from card_entries where draw_id=d.id and punter=u.id::text) then
      raise exception 'already entered this free draw';
    end if;
  else
    if iw_balance(u.id) < d.price_p then raise exception 'insufficient credit'; end if;
  end if;

  v_no := d.sold + 1;
  if d.price_p > 0 then
    insert into ledger (user_id, delta_p, reason)
    values (u.id, -d.price_p, p_kind||' draw '||to_char(d.off_at,'HH24:MI')||' #'||v_no);
  end if;
  insert into card_entries (draw_id, entry_no, punter) values (d.id, v_no, u.id::text);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p,'balance_p',iw_balance(u.id));
end $$;

grant execute on function card_ensure_open()        to service_role;
grant execute on function card_enter2(text,uuid)     to service_role;

-- open the first free draw now
select card_ensure_open();
