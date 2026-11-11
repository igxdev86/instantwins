-- postal-mil.sql — Million Round postal entries: log every card (accepted or rejected), ticket goes into the entrant's bank unopened.
create table if not exists postal_log (
  id bigserial primary key, created_at timestamptz not null default now(),
  ref text not null, user_id uuid, entry_no int, pool text, status text not null check (status in ('accepted','rejected')),
  reason text, note text, keyed_by uuid);
create index if not exists postal_log_created on postal_log (created_at desc);

create or replace function iw_admin_postal_mil(p_token uuid, p_ref text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin users%rowtype; v_uid uuid; v_name text; p pools%rowtype; v_entry int; v_label text;
begin
  v_admin := iw_admin(p_token);
  select id, name into v_uid, v_name from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  if v_uid is null then raise exception 'no account matches that account number / email — reject the card as "no account"'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if p.sold >= p.cap then raise exception 'round is full'; end if;
  v_entry := p.sold + 1; v_label := 'MIL-P'||lpad(p.pool_no::text,4,'0');
  insert into allocation (pool_id, entry_no, prize_p) values (p.id, v_entry, 0) on conflict (pool_id, entry_no) do nothing;
  update allocation set claimed_by=v_uid::text, claimed_at=now(), bought_at=now(), revealed=false where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  insert into ledger (user_id, delta_p, reason) values (v_uid, 0, 'postal entry '||v_label||' #'||v_entry);
  insert into postal_log (ref, user_id, entry_no, pool, status, note, keyed_by) values (trim(p_ref), v_uid, v_entry, v_label, 'accepted', p_note, v_admin.id);
  if v_entry >= p.cap then update pools set status='settled', settled_at=now() where id=p.id; perform open_pool_big('MIL'); end if;
  return jsonb_build_object('entry_no',v_entry,'pool',v_label,'name',v_name,
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=v_uid::text and not a.revealed));
end $$;

create or replace function iw_admin_postal_reject(p_token uuid, p_ref text, p_reason text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin users%rowtype; v_uid uuid;
begin
  v_admin := iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  insert into postal_log (ref, user_id, status, reason, note, keyed_by) values (trim(coalesce(p_ref,'')), v_uid, 'rejected', p_reason, p_note, v_admin.id);
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_postal_log(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object(
    'today_accepted',(select count(*) from postal_log where status='accepted' and created_at::date=current_date),
    'today_rejected',(select count(*) from postal_log where status='rejected' and created_at::date=current_date),
    'total_accepted',(select count(*) from postal_log where status='accepted'),
    'rows',coalesce((select jsonb_agg(jsonb_build_object('at',l.created_at,'ref',l.ref,'name',u.name,'entry_no',l.entry_no,'pool',l.pool,'status',l.status,'reason',l.reason,'note',l.note,
        'revealed',(select a.revealed from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.entry_no=l.entry_no and l.pool='MIL-P'||lpad(q.pool_no::text,4,'0') limit 1)) order by l.created_at desc)
      from (select * from postal_log order by created_at desc limit 150) l left join users u on u.id=l.user_id),'[]'::jsonb));
end $$;

-- round state: publish the postal count on the fairness page
create or replace function c2_state() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('cap',p.cap,'sold',p.sold,'round',p.pool_no,'seed_hash',p.seed_hash,'price_p',p.price_p,
    'prizes_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'prize_left_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0),
    'top_left',(select count(*) from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p=10000000),
    'left',(select coalesce(jsonb_object_agg(x.prize_p::text, x.n),'{}'::jsonb) from (select prize_p, count(*) n from allocation a where a.pool_id=p.id and a.claimed_by is null and a.prize_p>0 group by prize_p) x),
    'tiers',(select g.tiers from games g where g.tag='MIL'),
    'won_p',(select coalesce(sum(prize_p),0) from allocation a where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>0),
    'postal',(select count(*) from postal_log l where l.status='accepted' and l.pool='MIL-P'||lpad(p.pool_no::text,4,'0')),
    'last',(select jsonb_build_object('prize_p',a.prize_p,'at',a.claimed_at,'name',split_part(coalesce(u.name,''),' ',1)) from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=1000 order by a.claimed_at desc limit 1),
    'recent',(select coalesce(jsonb_agg(jsonb_build_object('prize_p',r.prize_p,'name',r.name,'at',r.at)),'[]'::jsonb) from (select a.prize_p, split_part(coalesce(u.name,'A player'),' ',1) as name, a.claimed_at as at from allocation a left join users u on u.id::text=a.claimed_by where a.pool_id=p.id and a.claimed_by is not null and a.revealed and a.prize_p>=500 order by a.claimed_at desc limit 8) r))
  from pools p where p.game='MIL' and p.status='open' order by p.pool_no desc limit 1 $$;
create index if not exists allocation_open_prizes on allocation (pool_id, prize_p) where claimed_by is null and prize_p > 0;
grant execute on function iw_admin_postal_mil(uuid,text,text), iw_admin_postal_reject(uuid,text,text,text), iw_admin_postal_log(uuid), c2_state() to service_role;
notify pgrst, 'reload schema';
