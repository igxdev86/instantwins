-- skill-question.sql — optional qualifying question before the first purchase in a round (admin switch, off by default).
insert into site_settings (key,value) values ('skill_q','false') on conflict (key) do nothing;
create table if not exists skill_answers (user_id uuid not null, pool_no int not null, q text not null, answer text not null, correct boolean not null, created_at timestamptz not null default now(), primary key (user_id, pool_no));
create or replace function iw_site() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('live', iw_payments_live(), 'launched_at', (select value from site_settings where key='launched_at'),
    'games', coalesce((select value='true' from site_settings where key='games_enabled'), false),
    'skill_q', coalesce((select value='true' from site_settings where key='skill_q'), false)) $$;
create or replace function c2_answer(p_token uuid, p_q text, p_answer text, p_correct boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_round int;
begin
  u := iw_user(p_token);
  select pool_no into v_round from pools where game='MIL' and status='open' order by pool_no desc limit 1;
  insert into skill_answers (user_id, pool_no, q, answer, correct) values (u.id, coalesce(v_round,0), left(p_q,200), left(p_answer,100), p_correct)
    on conflict (user_id, pool_no) do update set q=excluded.q, answer=excluded.answer, correct=excluded.correct, created_at=now();
  return jsonb_build_object('ok',p_correct,'round',v_round);
end $$;
-- buying requires a correct answer for the open round while the switch is on
create or replace function c2_issue(p_uid uuid, p_n int, p_cost_p int, p_label text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare p pools%rowtype; v_from int; v_to int;
begin
  if p_n < 1 then raise exception 'not enough credit for a ticket'; end if;
  select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update;
  if not found then perform open_pool_big('MIL'); select * into p from pools where game='MIL' and status='open' order by pool_no desc limit 1 for update; end if;
  if coalesce((select value='true' from site_settings where key='skill_q'),false) and not exists (select 1 from skill_answers a where a.user_id=p_uid and a.pool_no=p.pool_no and a.correct) then
    raise exception 'answer the question first'; end if;
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
create or replace function iw_admin_skillq(p_token uuid, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into site_settings (key,value,updated_at) values ('skill_q', case when p_on then 'true' else 'false' end, now()) on conflict (key) do update set value=excluded.value, updated_at=now();
  return jsonb_build_object('skill_q',p_on);
end $$;
grant execute on function c2_answer(uuid,text,text,boolean), iw_site(), iw_admin_skillq(uuid,boolean) to service_role;
notify pgrst, 'reload schema';
