-- competitions.sql — ITV-style competitions: prize + easy multiple-choice question, paid online or free
-- by post (the postcard carries the answer), open for a week, winner drawn from the correct entries by
-- commit-and-reveal. Run once; safe to re-run.

create table if not exists competitions (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,                 -- e.g. C001; quoted on postcards
  title      text not null,                        -- "Win £1,000"
  blurb      text,
  prize_p    int  not null,
  price_p    int  not null,
  question   text not null,
  options    jsonb not null,                       -- ["Jamaica","Kenya","USA"]
  correct    int  not null,                        -- 0-based index
  opens_at   timestamptz not null default now(),
  closes_at  timestamptz not null,
  cap        int,                                  -- optional max entries
  sold       int  not null default 0,
  seed       text not null,
  seed_hash  text not null,
  status     text not null default 'open' check (status in ('open','settled','void')),
  winner_entry int,
  correct_count int,
  settled_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists comp_entries (
  comp_id  uuid not null references competitions(id) on delete cascade,
  entry_no int  not null,
  user_id  uuid not null references users(id),
  answer   int  not null,
  via      text not null default 'online',
  created_at timestamptz not null default now(),
  primary key (comp_id, entry_no)
);
alter table competitions enable row level security; alter table comp_entries enable row level security;
create sequence if not exists comp_code_seq start 1;

create or replace function comp_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c competitions%rowtype; n int; idx int; v_win int; v_uid uuid;
begin
  for c in select * from competitions where status='open' and closes_at <= now() for update loop
    select count(*) into n from comp_entries where comp_id=c.id and answer=c.correct;
    v_win := null;
    if n > 0 then
      idx := ((('x'||substr(md5(c.seed||':'||n::text),1,8))::bit(32)::bigint & 2147483647) % n)::int;
      select entry_no, user_id into v_win, v_uid from comp_entries where comp_id=c.id and answer=c.correct order by entry_no offset idx limit 1;
      insert into ledger (user_id, delta_p, reason) values (v_uid, c.prize_p, 'Competition '||c.code||' win #'||v_win);
    end if;
    update competitions set status='settled', winner_entry=v_win, correct_count=n, settled_at=now() where id=c.id;
  end loop;
end $$;

create or replace function comp_list() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform comp_settle_due();
  return jsonb_build_object('server_now',now(),
    'open',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'title',title,'blurb',blurb,'prize_p',prize_p,'price_p',price_p,'question',question,'options',options,
        'opens_at',opens_at,'closes_at',closes_at,'cap',cap,'sold',sold,'seed_hash',seed_hash) order by closes_at) from competitions where status='open'),'[]'::jsonb),
    'results',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'title',title,'prize_p',prize_p,'question',question,'options',options,'correct',correct,
        'closes_at',closes_at,'sold',sold,'correct_count',correct_count,'winner_entry',winner_entry,'seed',seed,'seed_hash',seed_hash,
        'winner_name',(select split_part(coalesce(u.name,''),' ',1) from comp_entries e join users u on u.id=e.user_id where e.comp_id=competitions.id and e.entry_no=competitions.winner_entry)) order by settled_at desc)
        from (select * from competitions where status='settled' order by settled_at desc limit 12) competitions),'[]'::jsonb));
end $$;

create or replace function comp_add_entry(p_user uuid, p_code text, p_answer int, p_via text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c competitions%rowtype; v_no int;
begin
  select * into c from competitions where code=upper(trim(p_code)) for update;
  if not found then raise exception 'no such competition'; end if;
  if c.status<>'open' or c.closes_at<=now() or c.opens_at>now() then raise exception 'this competition is closed'; end if;
  if p_answer is null or p_answer < 0 or p_answer >= jsonb_array_length(c.options) then raise exception 'pick an answer'; end if;
  if c.cap is not null and c.sold >= c.cap then raise exception 'this competition is full'; end if;
  if p_via='online' and c.price_p > 0 then
    if iw_balance(p_user) < c.price_p then raise exception 'insufficient credit'; end if;
    insert into ledger (user_id, delta_p, reason) values (p_user, -c.price_p, 'Competition '||c.code||' #'||(c.sold+1));
  end if;
  v_no := c.sold + 1;
  insert into comp_entries (comp_id, entry_no, user_id, answer, via) values (c.id, v_no, p_user, p_answer, p_via);
  update competitions set sold=v_no where id=c.id;
  return jsonb_build_object('code',c.code,'entry_no',v_no,'answer',p_answer,'closes_at',c.closes_at,'balance_p',iw_balance(p_user));
end $$;

create or replace function comp_enter(p_token uuid, p_code text, p_answer int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token); perform comp_settle_due();
  return comp_add_entry(u.id, p_code, p_answer, 'online');
end $$;

create or replace function comp_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('code',c.code,'title',c.title,'entry_no',e.entry_no,'answer',e.answer,'via',e.via,'status',c.status,'closes_at',c.closes_at,
    'won',(c.status='settled' and c.winner_entry=e.entry_no)) order by e.created_at desc)
    from comp_entries e join competitions c on c.id=e.comp_id where e.user_id=u.id),'[]'::jsonb);
end $$;

-- admin
create or replace function iw_admin_comp_create(p_token uuid, p_title text, p_blurb text, p_prize_p int, p_price_p int, p_question text, p_options jsonb, p_correct int, p_days int, p_cap int default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_code text; v_seed text; v_id uuid;
begin
  perform iw_admin(p_token);
  if jsonb_array_length(p_options) < 2 or p_correct < 0 or p_correct >= jsonb_array_length(p_options) then raise exception 'need 2+ options and a valid correct index'; end if;
  v_code := 'C'||lpad(nextval('comp_code_seq')::text,3,'0');
  v_seed := v_code||'|'||gen_random_uuid();
  insert into competitions (code,title,blurb,prize_p,price_p,question,options,correct,closes_at,cap,seed,seed_hash)
  values (v_code,p_title,p_blurb,p_prize_p,p_price_p,p_question,p_options,p_correct,now()+(coalesce(p_days,7)||' days')::interval,p_cap,v_seed,encode(digest(v_seed,'sha256'),'hex'))
  returning id into v_id;
  return jsonb_build_object('id',v_id,'code',v_code);
end $$;
create or replace function iw_admin_comp_postal(p_token uuid, p_ref text, p_code text, p_answer int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_uid uuid;
begin
  perform iw_admin(p_token);
  select id into v_uid from users where lower(email)=lower(trim(p_ref)) or upper(coalesce(acct_no,''))=upper(trim(p_ref)) limit 1;
  if v_uid is null then raise exception 'no account matches that account number / email'; end if;
  insert into postal_entries (game, details) values ('comp', upper(trim(p_code))||' answer '||p_answer||' '||trim(p_ref));
  return comp_add_entry(v_uid, p_code, p_answer, 'post');
end $$;
create or replace function iw_admin_comps(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('code',code,'title',title,'prize_p',prize_p,'price_p',price_p,'question',question,'options',options,'correct',correct,
    'closes_at',closes_at,'sold',sold,'status',status,'winner_entry',winner_entry,'correct_count',correct_count,
    'postal',(select count(*) from comp_entries e where e.comp_id=competitions.id and e.via='post')) order by created_at desc) from competitions),'[]'::jsonb);
end $$;
grant execute on function comp_list(), comp_enter(uuid,text,int), comp_mine(uuid), iw_admin_comp_create(uuid,text,text,int,int,text,jsonb,int,int,int), iw_admin_comp_postal(uuid,text,text,int), iw_admin_comps(uuid) to service_role;

-- first competition: closes in 7 days
do $$ begin
  if not exists (select 1 from competitions) then
    insert into competitions (code,title,blurb,prize_p,price_p,question,options,correct,closes_at,seed,seed_hash)
    select 'C001','Win £1,000','One winner takes £1,000 cash. Answer the question, enter online for £2 or free by post, and you’re in the draw.',
           100000,200,'Which country is Usain Bolt from?','["Jamaica","Kenya","USA"]',0,
           (date_trunc('day', now() at time zone 'Europe/London') + interval '7 days 20 hours') at time zone 'Europe/London',
           s, encode(digest(s,'sha256'),'hex') from (select 'C001|'||gen_random_uuid() s) x;
    perform nextval('comp_code_seq');
  end if;
end $$;
notify pgrst, 'reload schema';
