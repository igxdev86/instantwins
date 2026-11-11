-- stakes.sql — variable stake (up to £50) for instant games & slots.
-- Same committed numbered entry; cost and prize both scale by the chosen
-- multiplier, so the house edge / RTP is identical at every stake.

create or replace function buy_entry3(p_game text, p_token uuid, p_mult int default 1)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; v_entry int; v_prize int; v_cost int;
        v_extra jsonb := '{}'::jsonb; v_label text; m int;
begin
  u := iw_user(p_token);
  m := greatest(coalesce(p_mult,1),1);
  select * into p from pools
   where game = p_game and status = 'open'
   order by pool_no desc limit 1 for update;
  if not found then
    perform open_pool(p_game);
    select * into p from pools where game=p_game and status='open'
     order by pool_no desc limit 1 for update;
  end if;

  v_cost := p.price_p * m;
  if v_cost > 5000 then raise exception 'max stake is £50 per entry'; end if;
  if iw_balance(u.id) < v_cost then raise exception 'insufficient credit'; end if;

  v_label := p.game||'-P'||lpad(p.pool_no::text,4,'0');
  v_entry := p.sold + 1;
  select prize_p into v_prize from allocation where pool_id=p.id and entry_no=v_entry;

  insert into ledger (user_id, delta_p, reason)
    values (u.id, -v_cost, 'entry '||v_label||' #'||v_entry||case when m>1 then ' x'||m else '' end);
  update allocation set claimed_by=u.id::text, claimed_at=now()
   where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  if v_prize > 0 then
    insert into ledger (user_id, delta_p, reason)
      values (u.id, v_prize*m, 'win '||v_label||' #'||v_entry||case when m>1 then ' x'||m else '' end);
  end if;

  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id;
    perform open_pool(p_game);
    v_extra := jsonb_build_object('sold_out', true, 'seed', p.seed);
  else
    v_extra := jsonb_build_object('sold_out', false);
  end if;

  return v_extra || jsonb_build_object('entry_no',v_entry,'prize_p',v_prize*m,'pool',v_label,
    'sold',v_entry,'cap',p.cap,'seed_hash',p.seed_hash,'balance_p',iw_balance(u.id),'mult',m);
end $$;

grant execute on function buy_entry3(text,uuid,int) to anon, authenticated, service_role;
