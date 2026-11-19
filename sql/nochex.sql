-- nochex.sql — look up one of your own card payments by reference (used when you land back from the Nochex page)
create or replace function iw_card_lookup_ref(p_token uuid, p_ref text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; c card_payments%rowtype;
begin
  u := iw_user(p_token);
  select * into c from card_payments where ref=p_ref and user_id=u.id;
  if not found then raise exception 'unknown payment'; end if;
  return jsonb_build_object('ref',c.ref,'status',c.status,'amount_p',c.amount_p,'balance_p',iw_balance(u.id));
end $$;
grant execute on function iw_card_lookup_ref(uuid,text) to service_role;
-- deposit email: say "card payment" without naming the old processor in notes
create or replace function iw_card_update(p_job text, p_pay text, p_order text, p_status text, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c card_payments%rowtype; v_credited boolean := false; v_st text;
begin
  select * into c from card_payments where (p_job <> '' and job_ref=p_job) or (p_order is not null and ref=p_order) order by created_at desc limit 1 for update;
  if not found then raise exception 'unknown payment job'; end if;
  v_st := lower(coalesce(p_status,''));
  if v_st = 'paid' then
    if c.status <> 'paid' then
      if p_amount_p is not null and p_amount_p <> c.amount_p then
        update card_payments set status='mismatch', note='processor amount '||p_amount_p||' vs '||c.amount_p, updated_at=now() where id=c.id;
        raise exception 'amount mismatch';
      end if;
      insert into ledger (user_id, delta_p, reason) values (c.user_id, c.amount_p, 'Card deposit '||c.ref);
      update card_payments set status='paid', job_ref=coalesce(nullif(p_job,''),job_ref), pay_ref=coalesce(nullif(p_pay,''),pay_ref), paid_at=now(), updated_at=now() where id=c.id;
      v_credited := true;
      begin perform iw_mail(c.user_id, 'Deposit received — '||to_char(c.amount_p/100.0,'FM£999,990.00'),
        '<p>Your card payment of <b>'||to_char(c.amount_p/100.0,'FM£999,990.00')||'</b> has been added to your InstantWins funds.</p><p>Reference '||c.ref||'.</p>'); exception when others then null; end;
    end if;
  elsif v_st in ('failed','cancelled','declined','expired') then
    if c.status <> 'paid' then update card_payments set status=v_st, updated_at=now() where id=c.id; end if;
  else
    update card_payments set updated_at=now() where id=c.id;
  end if;
  return jsonb_build_object('credited',v_credited,'status',(select status from card_payments where id=c.id),'balance_p',iw_balance(c.user_id));
end $$;
notify pgrst, 'reload schema';
