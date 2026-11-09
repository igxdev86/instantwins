-- review-fixes.sql — changes from the 9 Nov pre-partnership compliance review (B2, C6, C7). Safe to re-run.

-- B2: a postcard naming no draw = ONE entry in the next open Five Minute draw (same as one paid entry)
create or replace function iw_admin_postal_enter(p_token uuid, p_email text, p_kind text default 'm5_20', p_off_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; t timestamptz; k text; r jsonb;
begin
  perform iw_admin(p_token);
  v_uid := iw_postal_user(p_email);
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  k := coalesce(nullif(p_kind,''), 'm5_20');
  if not (k = any(card_kinds())) then k := (select kind from card_kinds where active and price_p > 0 order by step_s, sort limit 1); end if;
  perform card_settle_due();
  t := card_next_with_room(k, coalesce(p_off_at, card_next_off(k)));
  if t is null then raise exception 'no % draw with room in the next 7 days', drawlabel(k); end if;
  insert into postal_entries (game, details) values ('card', 'unnamed -> '||card_game_no(k,t)||' '||trim(p_email));
  r := card_add_entry(v_uid, k, t, 'post');
  return jsonb_build_object('entered',1,'first',r,'game_no',card_game_no(k,t));
end $$;

-- C6: no withdrawal minimum — a balance can be withdrawn in full at any time
create or replace function iw_withdraw_request(p_token uuid, p_amount_p int, p_name text, p_sort text, p_acct text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint; v_sort text; v_acct text;
begin
  u := iw_user(p_token);
  if not iw_payments_live() then raise exception 'payments are not open yet'; end if;
  v_sort := regexp_replace(coalesce(p_sort,''), '\D', '', 'g'); v_acct := regexp_replace(coalesce(p_acct,''), '\D', '', 'g');
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'account holder name required'; end if;
  if length(v_sort) <> 6 then raise exception 'sort code should be 6 digits'; end if;
  if length(v_acct) <> 8 then raise exception 'account number should be 8 digits'; end if;
  if p_amount_p < 1 then raise exception 'enter an amount'; end if;
  if iw_balance(u.id) < p_amount_p then raise exception 'insufficient balance'; end if;
  insert into withdrawals (user_id, amount_p, account_name, sort_code, account_no) values (u.id, p_amount_p, trim(p_name), v_sort, v_acct) returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (u.id, -p_amount_p, 'withdrawal #'||v_id||' requested');
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'balance_p',iw_balance(u.id));
end $$;

-- C7: going live also purges test-mode results so no test winners stay public
create or replace function iw_go_live(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0;
begin
  perform iw_admin(p_token);
  if iw_payments_live() then return jsonb_build_object('already_live', true); end if;
  for r in select u.id, iw_balance(u.id) bal from users u loop
    if r.bal <> 0 then insert into ledger (user_id, delta_p, reason) values (r.id, -r.bal, 'admin: play-money balance cleared at launch'); n := n + 1; end if;
  end loop;
  -- test history out: settled draws and their entries, finished instant-win rounds, settled competitions
  delete from card_entries where draw_id in (select id from card_draws where status <> 'open');
  delete from card_draws where status <> 'open';
  delete from card_entries;  update card_draws set sold = 0;                      -- open test entries too; draws stay scheduled
  delete from allocation where pool_id in (select id from pools where status <> 'open');
  delete from pools where status <> 'open';
  update allocation set claimed_by = null, claimed_at = null where pool_id in (select id from pools where status = 'open');
  update pools set sold = 0 where status = 'open';
  delete from comp_entries; update competitions set sold = 0; delete from competitions where status <> 'open';
  delete from postal_entries;
  insert into site_settings (key,value,updated_at) values ('payments_live','true',now()) on conflict (key) do update set value='true', updated_at=now();
  insert into site_settings (key,value,updated_at) values ('launched_at',now()::text,now()) on conflict (key) do update set value=now()::text, updated_at=now();
  return jsonb_build_object('live', true, 'balances_cleared', n);
end $$;
notify pgrst, 'reload schema';
