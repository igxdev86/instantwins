-- buy-balance.sql — "Use my whole balance": tickets priced on a sliding rate (same ladder as the packs), server authoritative.
create or replace function c2_rate_for(p_amount_p int) returns int language sql immutable as $$
  select case when p_amount_p >= 35000 then 70 when p_amount_p >= 18000 then 72 when p_amount_p >= 7500 then 75 when p_amount_p >= 4000 then 80
              when p_amount_p >= 2100 then 84 when p_amount_p >= 900 then 90 when p_amount_p >= 475 then 95 else 100 end $$;

-- shared issue path
create or replace function c2_issue(p_uid uuid, p_n int, p_cost_p int, p_label text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; v_from int; v_to int;
begin
  if p_n < 1 then raise exception 'not enough credit for a ticket'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.closes_at is not null and p.closes_at <= now() then raise exception 'this round has just closed — the next one opens in a moment'; end if;
  if p.sold + p_n > p.cap then raise exception 'only % tickets left in the round', p.cap-p.sold; end if;
  if iw_balance(p_uid) < p_cost_p then raise exception 'insufficient credit'; end if;
  insert into ledger (user_id, delta_p, reason) values (p_uid, -p_cost_p, 'Million Round: '||p_n||' tickets #'||(p.sold+1)||'-#'||(p.sold+p_n)||coalesce(' '||p_label,''));
  v_from := p.sold+1; v_to := p.sold+p_n;
  insert into allocation (pool_id, entry_no, prize_p) select p.id, gs, 0 from generate_series(v_from, v_to) gs on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=p_uid::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no between v_from and v_to;
  update pools set sold=v_to where id=p.id;
  if v_to >= p.cap then perform c2_close_round(p.id); end if;
  return jsonb_build_object('from',v_from,'to',v_to,'n',p_n,'price_p',p_cost_p,'balance_p',iw_balance(p_uid),'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=p_uid::text and not a.revealed));
end $$;

create or replace function c2_buy(p_token uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_price int;
begin
  u := iw_user(p_token); v_price := c2_pack_price(p_n); if v_price is null then raise exception 'pick a pack'; end if;
  return c2_issue(u.id, p_n, v_price, null);
end $$;

create or replace function c2_buy_balance(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_bal int; v_rate int; v_n int;
begin
  u := iw_user(p_token); v_bal := iw_balance(u.id);
  if v_bal < 100 then raise exception 'you need at least £1 of credit'; end if;
  v_rate := c2_rate_for(v_bal); v_n := least(v_bal / v_rate, 5000);
  return c2_issue(u.id, v_n, v_n * v_rate, '(whole balance @ '||v_rate||'p)');
end $$;
grant execute on function c2_buy(uuid,int), c2_buy_balance(uuid) to service_role;
revoke all on function c2_issue(uuid,int,int,text) from public;
notify pgrst, 'reload schema';
