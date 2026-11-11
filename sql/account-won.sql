-- account-won.sql — account page: lifetime won + opened counts (needs launch-ops.sql first for county/terms columns).
create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;
grant execute on function c2_mine(uuid) to service_role;
notify pgrst, 'reload schema';
