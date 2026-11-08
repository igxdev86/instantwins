-- postal-tickets.sql — key a postcard into an Instant Win round. Takes the next ticket in the open
-- round of the named ticket (same sequence as paid), no charge, any prize credited at once.
create or replace function iw_admin_postal_ticket(p_token uuid, p_ref text, p_tag text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid; g games%rowtype; p pools%rowtype; v_entry int; v_prize int; v_label text; v_extra jsonb;
begin
  perform iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  select * into g from games where tag=p_tag and active;
  if not found then raise exception 'that ticket is not running'; end if;
  select * into p from pools where game=p_tag and mult=1 and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool(p_tag,1); select * into p from pools where game=p_tag and mult=1 and status='open' order by pool_no desc limit 1 for update; end if;
  v_label := p.game||'-P'||lpad(p.pool_no::text,4,'0');
  v_entry := p.sold + 1;
  select prize_p into v_prize from allocation where pool_id=p.id and entry_no=v_entry;
  update allocation set claimed_by=v_uid::text, claimed_at=now() where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  insert into postal_entries (game, details) values ('ticket', p_tag||' '||v_label||' #'||v_entry||' '||trim(p_ref));
  if v_prize > 0 then insert into ledger (user_id, delta_p, reason) values (v_uid, v_prize, 'win '||v_label||' #'||v_entry||' (post)'); end if;
  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id; perform open_pool(p_tag,1);
    v_extra := jsonb_build_object('sold_out', true);
  else v_extra := jsonb_build_object('sold_out', false); end if;
  return v_extra || jsonb_build_object('ticket',g.name||' '||case when g.price_p<100 then g.price_p||'p' else '£'||(g.price_p/100) end,'entry_no',v_entry,'prize_p',v_prize,'pool',v_label,'sold',v_entry,'cap',p.cap);
end $$;
grant execute on function iw_admin_postal_ticket(uuid,text,text) to service_role;
notify pgrst, 'reload schema';
