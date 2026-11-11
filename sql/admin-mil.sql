-- admin-mil.sql — Million Round admin: postal keying + stats.
create or replace function iw_admin_postal_mil(p_token uuid, p_ref text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; p pools%rowtype; v_entry int; v_prize int; v_label text;
begin
  perform iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.sold >= p.cap then raise exception 'round is full'; end if;
  v_entry := p.sold + 1; v_label := 'MIL-P'||lpad(p.pool_no::text,4,'0');
  insert into allocation (pool_id, entry_no, prize_p) values (p.id, v_entry, 0) on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=v_uid::text, claimed_at=now(), bought_at=now(), revealed=true where pool_id=p.id and entry_no=v_entry returning prize_p into v_prize;
  update pools set sold=v_entry where id=p.id;
  insert into ledger (user_id, delta_p, reason) values (v_uid, 0, 'postal entry '||v_label||' #'||v_entry);
  if v_prize > 0 then insert into ledger (user_id, delta_p, reason) values (v_uid, v_prize, 'win '||v_label||' #'||v_entry||' (postal)'); end if;
  if v_entry >= p.cap then update pools set status='settled', settled_at=now() where id=p.id; perform open_pool_big('MIL'); end if;
  return jsonb_build_object('entry_no',v_entry,'prize_p',coalesce(v_prize,0),'pool',v_label);
end $$;

create or replace function iw_admin_mil_stats(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object(
    'unrevealed',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by is not null and not a.revealed),
    'stakes_p',(select coalesce(sum(-delta_p),0) from ledger where delta_p<0 and reason like 'Million Round:%'),
    'paid_p',(select coalesce(sum(delta_p),0) from ledger where delta_p>0 and reason like 'win MIL-%'),
    'postal',(select count(*) from ledger where reason like 'postal entry MIL-%'),
    'top',coalesce((select jsonb_agg(jsonb_build_object('who',x.who,'no',x.no,'prize_p',x.prize_p)) from (
        select u.name as who, a.entry_no as no, a.prize_p from allocation a join pools q on q.id=a.pool_id join users u on u.id::text=a.claimed_by
        where q.game='MIL' and a.revealed and a.prize_p>0 order by a.prize_p desc, a.claimed_at desc limit 10) x),'[]'::jsonb));
end $$;
grant execute on function iw_admin_postal_mil(uuid,text), iw_admin_mil_stats(uuid) to service_role;
notify pgrst, 'reload schema';
