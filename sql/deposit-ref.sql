-- deposit-ref.sql — manual/ANNA deposits get a unique 4-character reference each time (and the £1,000 cap). Replaces deposit-1000.sql.
create or replace function iw_deposit_request(p_token uuid, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_id bigint; v_ref text; v_try int := 0;
begin
  u := iw_user(p_token);
  if u.closed_at is not null then raise exception 'this account is closed'; end if;
  if p_amount_p < 500 or p_amount_p > 100000 then raise exception 'deposit between £5 and £1,000'; end if;
  -- short unique reference: 4 characters from an unambiguous alphabet (no 0/O/1/I), unique among open deposits
  loop
    v_ref := ''; for i in 1..4 loop v_ref := v_ref || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1+floor(random()*32)::int, 1); end loop;
    exit when not exists (select 1 from deposits where reference=v_ref and (status='pending' or created_at > now()-interval '90 days'));
    v_try := v_try+1; if v_try > 50 then raise exception 'could not make a reference, try again'; end if;
  end loop;
  insert into deposits (user_id, amount_p, reference) values (u.id, p_amount_p, v_ref) returning id into v_id;
  return jsonb_build_object('id',v_id,'amount_p',p_amount_p,'reference',v_ref);
end $$;
create index if not exists deposits_ref on deposits(reference);
-- run cashflows.sql first (card_payments table)
-- my payments now include card deposits
create or replace function iw_my_payments(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('live', iw_payments_live(), 'card', coalesce((select value='true' from site_settings where key='card_on'),false) or coalesce(u.is_admin,false),
    'reference', coalesce(u.acct_no,'IW'||substr(u.id::text,1,8)), 'balance_p', iw_balance(u.id),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'reference',reference,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note) order by created_at desc) from (select * from deposits where user_id=u.id order by created_at desc limit 20) d),'[]'::jsonb),
    'cards', coalesce((select jsonb_agg(jsonb_build_object('ref',ref,'amount_p',amount_p,'status',status,'created_at',created_at,'paid_at',paid_at) order by created_at desc) from (select * from card_payments where user_id=u.id and status<>'started' order by created_at desc limit 20) c),'[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note,'last4',right(account_no,4)) order by created_at desc) from (select * from withdrawals where user_id=u.id order by created_at desc limit 20) w),'[]'::jsonb));
end $$;
notify pgrst, 'reload schema';
