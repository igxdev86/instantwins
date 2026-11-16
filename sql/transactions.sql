-- transactions.sql — player-facing transaction log: every ledger line, categorised, with a running balance and totals.
create index if not exists ledger_user_time on ledger (user_id, created_at desc, id desc);

create or replace function iw_my_ledger(p_token uuid, p_limit int default 50, p_before bigint default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_rows jsonb; v_more boolean;
begin
  u := iw_user(p_token);
  with base as (
    select l.id, l.delta_p, l.reason, l.created_at,
           sum(l.delta_p) over (order by l.created_at, l.id) as bal_after,
           case when l.reason like 'Million Round:%' then 'tickets'
                when l.reason like 'win %' and l.reason like '%END PRIZE DRAW%' then 'enddraw'
                when l.reason like 'win %' then 'win'
                when l.reason like 'deposit #%' or l.reason like 'Card deposit%' then 'deposit'
                when l.reason like 'withdrawal #%' then 'withdrawal'
                when l.reason like 'refund:%' then 'refund'
                else 'adjust' end as kind
      from ledger l where l.user_id=u.id),
  page as (select * from base where (p_before is null or id < p_before) order by created_at desc, id desc limit greatest(1,least(p_limit,200))+1)
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'delta_p',delta_p,'bal_p',bal_after,'kind',kind,'at',created_at,
           'label', case kind when 'tickets' then regexp_replace(reason,'^Million Round: (\d+) tickets.*$','\1 tickets')||coalesce(' '||substring(reason from '#\d+-#\d+'),'')
                              when 'win' then 'Prize on ticket '||coalesce(substring(reason from '#\d+'),'')
                              when 'enddraw' then 'End Prize Draw win'
                              when 'deposit' then case when reason like 'Card deposit%' then 'Card deposit' else 'Bank deposit' end
                              when 'withdrawal' then 'Withdrawal to bank'
                              when 'refund' then 'Withdrawal declined — returned'
                              else case when reason like 'admin:%' then 'Adjustment' else reason end end,
           'ref', coalesce(substring(reason from 'CD[0-9A-Z]{10,}'), substring(reason from '#\d+'))
         ) order by created_at desc, id desc), '[]'::jsonb), count(*) > least(p_limit,200)
    into v_rows, v_more from page;
  if v_more then v_rows := v_rows - (jsonb_array_length(v_rows)-1); end if;
  return jsonb_build_object('rows', v_rows, 'more', v_more,
    'totals', (select jsonb_build_object(
        'spent_p', coalesce(-sum(delta_p) filter (where reason like 'Million Round:%'),0),
        'spent_month_p', coalesce(-sum(delta_p) filter (where reason like 'Million Round:%' and created_at >= date_trunc('month', now())),0),
        'won_p', coalesce(sum(delta_p) filter (where reason like 'win %'),0),
        'deposited_p', coalesce(sum(delta_p) filter (where reason like 'deposit #%' or reason like 'Card deposit%'),0),
        'withdrawn_p', coalesce(-sum(delta_p) filter (where reason like 'withdrawal #%'),0) - coalesce(sum(delta_p) filter (where reason like 'refund:%'),0),
        'tickets', coalesce(sum((regexp_match(reason,'^Million Round: (\d+) tickets'))[1]::int) filter (where reason like 'Million Round:%'),0))
      from ledger where user_id=u.id),
    'balance_p', iw_balance(u.id));
end $$;
grant execute on function iw_my_ledger(uuid,int,bigint) to service_role;
notify pgrst, 'reload schema';
