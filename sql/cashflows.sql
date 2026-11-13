-- cashflows.sql — card deposits through Cashflows (hosted payment page). Credits the ledger only after the API has
-- fetched the payment from Cashflows and seen status Paid. Switch: site_settings card_on ('true' lets players use it;
-- admins can always test). Keys live in Vercel env, never here.
insert into site_settings (key,value) values ('card_on','false') on conflict (key) do nothing;

create table if not exists card_payments (
  id bigserial primary key, user_id uuid not null references users(id), ref text not null unique,
  amount_p int not null check (amount_p > 0), status text not null default 'started',
  job_ref text, pay_ref text, note text, created_at timestamptz not null default now(), paid_at timestamptz, updated_at timestamptz);
create index if not exists card_payments_job on card_payments(job_ref);
alter table card_payments enable row level security;

create or replace function iw_card_start(p_token uuid, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_ref text; v_on boolean;
begin
  u := iw_user(p_token);
  v_on := coalesce((select value='true' from site_settings where key='card_on'),false);
  if not v_on and not coalesce(u.is_admin,false) then raise exception 'card payments are not open yet'; end if;
  if u.dob is null or u.name is null or u.name='' then raise exception 'finish setting up your account first'; end if;
  if coalesce(u.excluded_until, now()-interval '1s') > now() then raise exception 'you are on a break'; end if;
  if p_amount_p < 500 or p_amount_p > 50000 then raise exception 'amount must be £5 to £500'; end if;
  if (select count(*) from card_payments where user_id=u.id and created_at > now()-interval '10 minutes') >= 6 then raise exception 'too many attempts — wait a few minutes'; end if;
  v_ref := 'CD'||to_char(now(),'YYMMDD')||upper(substr(md5(random()::text||u.id::text),1,6));
  insert into card_payments (user_id, ref, amount_p) values (u.id, v_ref, p_amount_p);
  return jsonb_build_object('ref',v_ref,'email',u.email,'first',split_part(coalesce(u.name,''),' ',1),'last',nullif(substr(coalesce(u.name,''),length(split_part(coalesce(u.name,''),' ',1))+2),''));
end $$;

create or replace function iw_card_link(p_ref text, p_job text, p_pay text) returns void
language sql security definer set search_path = public, extensions as $$
  update card_payments set job_ref=nullif(p_job,''), pay_ref=nullif(p_pay,''), status='pending', updated_at=now() where ref=p_ref and status='started' $$;

create or replace function iw_card_fail(p_ref text, p_note text) returns void
language sql security definer set search_path = public, extensions as $$
  update card_payments set status='failed', note=left(p_note,400), updated_at=now() where ref=p_ref and status in ('started','pending') $$;

create or replace function iw_card_lookup(p_token uuid, p_job text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; c card_payments%rowtype;
begin
  u := iw_user(p_token);
  select * into c from card_payments where job_ref=p_job and user_id=u.id;
  if not found then raise exception 'payment not found'; end if;
  return jsonb_build_object('ref',c.ref,'pay_ref',c.pay_ref,'status',c.status,'amount_p',c.amount_p);
end $$;

-- called by the API after it has fetched the payment from Cashflows. Credits once, whatever the number of calls.
create or replace function iw_card_update(p_job text, p_pay text, p_order text, p_status text, p_amount_p int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c card_payments%rowtype; v_credited boolean := false; v_st text;
begin
  select * into c from card_payments where job_ref=p_job or (p_order is not null and ref=p_order) order by created_at desc limit 1 for update;
  if not found then raise exception 'unknown payment job'; end if;
  v_st := lower(coalesce(p_status,''));
  if v_st = 'paid' then
    if c.status <> 'paid' then
      if p_amount_p is not null and p_amount_p <> c.amount_p then
        update card_payments set status='mismatch', note='cashflows amount '||p_amount_p||' vs '||c.amount_p, updated_at=now() where id=c.id;
        raise exception 'amount mismatch';
      end if;
      insert into ledger (user_id, delta_p, reason) values (c.user_id, c.amount_p, 'Card deposit '||c.ref);
      update card_payments set status='paid', pay_ref=coalesce(nullif(p_pay,''),pay_ref), paid_at=now(), updated_at=now() where id=c.id;
      v_credited := true;
      begin perform iw_mail(c.user_id, 'Deposit received — '||to_char(c.amount_p/100.0,'FM£999,990.00'),
        '<p>Your card payment of <b>'||to_char(c.amount_p/100.0,'FM£999,990.00')||'</b> has been added to your InstantWins credit.</p><p>Reference '||c.ref||'.</p>'); exception when others then null; end;
    end if;
  elsif v_st in ('failed','cancelled','declined','expired') then
    if c.status <> 'paid' then update card_payments set status=v_st, updated_at=now() where id=c.id; end if;
  else
    update card_payments set updated_at=now() where id=c.id;
  end if;
  return jsonb_build_object('credited',v_credited,'status',(select status from card_payments where id=c.id),'balance_p',iw_balance(c.user_id));
end $$;

-- admin: recent card payments + totals
create or replace function iw_admin_card_payments(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return jsonb_build_object('card_on', coalesce((select value='true' from site_settings where key='card_on'),false),
    'paid_today_p', coalesce((select sum(amount_p) from card_payments where status='paid' and paid_at > date_trunc('day',now())),0),
    'paid_30d_p', coalesce((select sum(amount_p) from card_payments where status='paid' and paid_at > now()-interval '30 days'),0),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('ref',c.ref,'amount_p',c.amount_p,'status',c.status,'job_ref',c.job_ref,'created_at',c.created_at,'paid_at',c.paid_at,'note',c.note,'email',u.email,'name',u.name,'acct_no',u.acct_no) order by c.created_at desc)
       from (select * from card_payments order by created_at desc limit 100) c join users u on u.id=c.user_id),'[]'::jsonb));
end $$;

-- my payments now include card deposits
create or replace function iw_my_payments(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('live', iw_payments_live(), 'card', coalesce((select value='true' from site_settings where key='card_on'),false) or coalesce(u.is_admin,false),
    'reference', coalesce(u.acct_no,'IW'||substr(u.id::text,1,8)), 'balance_p', iw_balance(u.id),
    'deposits', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note) order by created_at desc) from (select * from deposits where user_id=u.id order by created_at desc limit 20) d),'[]'::jsonb),
    'cards', coalesce((select jsonb_agg(jsonb_build_object('ref',ref,'amount_p',amount_p,'status',status,'created_at',created_at,'paid_at',paid_at) order by created_at desc) from (select * from card_payments where user_id=u.id and status<>'started' order by created_at desc limit 20) c),'[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'amount_p',amount_p,'status',status,'created_at',created_at,'decided_at',decided_at,'note',note,'last4',right(account_no,4)) order by created_at desc) from (select * from withdrawals where user_id=u.id order by created_at desc limit 20) w),'[]'::jsonb));
end $$;

grant execute on function iw_card_start(uuid,int), iw_card_link(text,text,text), iw_card_fail(text,text), iw_card_lookup(uuid,text), iw_card_update(text,text,text,text,int), iw_admin_card_payments(uuid), iw_my_payments(uuid) to service_role;
notify pgrst, 'reload schema';
