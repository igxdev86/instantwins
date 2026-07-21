-- =====================================================================
-- INSTANTWINS — ACCOUNTS LAYER  (run once, after the main schema)
-- Users + sessions + wallet ledger + gated play + support + admin.
-- Everything stays behind service-role RPCs; no table is exposed.
-- Wallet is a pure ledger (sum of deltas), racing1-style: no stored
-- balance column, so it can never drift.
-- TEST MODE: signup grants £20 play credit. Stripe replaces that later.
-- =====================================================================

create table if not exists users (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  pass       text not null,               -- bcrypt via pgcrypto
  name       text not null,
  dob        date not null,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now(),
  constraint adults_only check (dob <= (current_date - interval '18 years'))
);
create unique index if not exists users_email_uq on users (lower(email));

create table if not exists sessions (
  token      uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references users(id) on delete cascade,
  delta_p    int not null,                -- pence; + credit, - debit
  reason     text not null,
  created_at timestamptz not null default now()
);

create table if not exists messages (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references users(id) on delete cascade,
  sender     text not null check (sender in ('user','admin')),
  body       text not null,
  created_at timestamptz not null default now()
);

create table if not exists announcements (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now()
);

alter table users         enable row level security;
alter table sessions      enable row level security;
alter table ledger        enable row level security;
alter table messages      enable row level security;
alter table announcements enable row level security;

-- ---------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------
create or replace function iw_user(p_token uuid) returns users
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  select us.* into u from sessions s join users us on us.id=s.user_id
   where s.token = p_token;
  if not found then raise exception 'not signed in'; end if;
  return u;
end $$;

create or replace function iw_balance(p_user uuid) returns int
language sql security definer set search_path = public, extensions as $$
  select coalesce(sum(delta_p),0)::int from ledger where user_id = p_user;
$$;

-- ---------------------------------------------------------------
-- auth
-- ---------------------------------------------------------------
create or replace function iw_signup(p_email text, p_pass text, p_name text, p_dob date)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_tok uuid;
begin
  if length(trim(p_email)) < 5 or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  if length(p_pass) < 8 then raise exception 'password must be at least 8 characters'; end if;
  if length(trim(p_name)) < 2 then raise exception 'name required'; end if;
  if p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over'; end if;
  if exists (select 1 from users where lower(email)=lower(trim(p_email))) then
    raise exception 'an account with that email already exists';
  end if;
  insert into users (email, pass, name, dob)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob)
  returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (v_id, 2000, 'welcome play credit');
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', trim(p_name), 'email', trim(p_email),
                            'is_admin', false, 'balance_p', 2000);
end $$;

create or replace function iw_login(p_email text, p_pass text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_tok uuid;
begin
  select * into u from users where lower(email)=lower(trim(p_email));
  if not found or u.pass <> crypt(p_pass, u.pass) then
    raise exception 'wrong email or password';
  end if;
  insert into sessions (user_id) values (u.id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', u.name, 'email', u.email,
                            'is_admin', u.is_admin, 'balance_p', iw_balance(u.id));
end $$;

create or replace function iw_logout(p_token uuid) returns void
language sql security definer set search_path = public, extensions as $$
  delete from sessions where token = p_token;
$$;

create or replace function iw_me(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_entries jsonb;
begin
  u := iw_user(p_token);
  select coalesce(jsonb_agg(e order by e->>'at' desc),'[]'::jsonb) into v_entries from (
    select jsonb_build_object('at',a.claimed_at,'what',g.name,'ref',p.game||'-P'||lpad(p.pool_no::text,4,'0')
             ,'entry',a.entry_no,'prize_p',a.prize_p) as e
      from allocation a join pools p on p.id=a.pool_id join games g on g.tag=p.game
     where a.claimed_by = u.id::text
     union all
    select jsonb_build_object('at',ce.created_at,'what',case when d.kind='grand' then 'Hourly Grand' else 'Five-Minute Draw' end
             ,'ref',to_char(d.off_at at time zone 'utc','HH24:MI'),'entry',ce.entry_no
             ,'prize_p',case when d.status='settled' and d.winner_entry=ce.entry_no then d.prize_p
                             when d.status='settled' then 0 else null end) as e
      from card_entries ce join card_draws d on d.id=ce.draw_id
     where ce.punter = u.id::text
     order by 1 desc limit 20
  ) s;
  return jsonb_build_object('name',u.name,'email',u.email,'is_admin',u.is_admin,
                            'balance_p', iw_balance(u.id), 'entries', v_entries);
end $$;

-- ---------------------------------------------------------------
-- gated play: pools
-- ---------------------------------------------------------------
create or replace function buy_entry2(p_game text, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; p pools%rowtype; v_entry int; v_prize int;
        v_extra jsonb := '{}'::jsonb; v_label text;
begin
  u := iw_user(p_token);
  select * into p from pools
   where game = p_game and status = 'open'
   order by pool_no desc limit 1 for update;
  if not found then
    perform open_pool(p_game);
    select * into p from pools where game=p_game and status='open'
     order by pool_no desc limit 1 for update;
  end if;
  if iw_balance(u.id) < p.price_p then raise exception 'insufficient credit'; end if;

  v_label := p.game||'-P'||lpad(p.pool_no::text,4,'0');
  v_entry := p.sold + 1;
  select prize_p into v_prize from allocation where pool_id=p.id and entry_no=v_entry;

  insert into ledger (user_id, delta_p, reason) values (u.id, -p.price_p, 'entry '||v_label||' #'||v_entry);
  update allocation set claimed_by=u.id::text, claimed_at=now()
   where pool_id=p.id and entry_no=v_entry;
  update pools set sold=v_entry where id=p.id;
  if v_prize > 0 then
    insert into ledger (user_id, delta_p, reason) values (u.id, v_prize, 'win '||v_label||' #'||v_entry);
  end if;

  if v_entry >= p.cap then
    update pools set status='settled', settled_at=now() where id=p.id;
    perform open_pool(p_game);
    v_extra := jsonb_build_object('sold_out', true, 'seed', p.seed);
  else
    v_extra := jsonb_build_object('sold_out', false);
  end if;

  return v_extra || jsonb_build_object('entry_no',v_entry,'prize_p',v_prize,'pool',v_label,
    'sold',v_entry,'cap',p.cap,'seed_hash',p.seed_hash,'balance_p',iw_balance(u.id));
end $$;

-- ---------------------------------------------------------------
-- gated play: the Card (and settlement now pays winners' ledgers)
-- ---------------------------------------------------------------
create or replace function card_enter2(p_kind text, p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; d card_draws%rowtype; v_no int;
begin
  u := iw_user(p_token);
  if p_kind not in ('five','grand') then raise exception 'bad kind'; end if;
  perform card_settle_due();
  perform card_ensure_open();
  select * into d from card_draws
   where kind=p_kind and status='open' order by off_at asc limit 1 for update;
  if iw_balance(u.id) < d.price_p then raise exception 'insufficient credit'; end if;
  v_no := d.sold + 1;
  insert into ledger (user_id, delta_p, reason)
  values (u.id, -d.price_p, p_kind||' draw '||to_char(d.off_at,'HH24:MI')||' #'||v_no);
  insert into card_entries (draw_id, entry_no, punter) values (d.id, v_no, u.id::text);
  update card_draws set sold=v_no where id=d.id;
  return jsonb_build_object('draw_id',d.id,'off_at',d.off_at,'entry_no',v_no,'sold',v_no,
    'seed_hash',d.seed_hash,'prize_p',d.prize_p,'balance_p',iw_balance(u.id));
end $$;

create or replace function card_settle_due() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare d card_draws%rowtype; v_win int; v_uid uuid;
begin
  for d in select * from card_draws where status='open' and off_at <= now() for update loop
    if d.sold > 0 then
      v_win := 1 + ((('x'||substr(md5(d.seed||':'||d.sold::text),1,8))::bit(32)::bigint
                     & 2147483647) % d.sold)::int;
    else
      v_win := null;
    end if;
    update card_draws set status='settled', winner_entry=v_win, settled_at=now() where id=d.id;
    if v_win is not null then
      select u.id into v_uid
        from card_entries ce join users u on u.id::text = ce.punter
       where ce.draw_id = d.id and ce.entry_no = v_win;
      if v_uid is not null then
        insert into ledger (user_id, delta_p, reason)
        values (v_uid, d.prize_p, d.kind||' draw win '||to_char(d.off_at,'HH24:MI')||' #'||v_win);
      end if;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------
-- support centre
-- ---------------------------------------------------------------
create or replace function iw_msg_send(p_token uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if length(trim(p_body)) < 1 then raise exception 'empty message'; end if;
  insert into messages (user_id, sender, body) values (u.id, 'user', left(trim(p_body),2000));
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_msg_list(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_msgs jsonb; v_ann jsonb;
begin
  u := iw_user(p_token);
  select coalesce(jsonb_agg(jsonb_build_object('sender',sender,'body',body,'at',created_at)
                            order by created_at),'[]'::jsonb)
    into v_msgs from messages where user_id=u.id;
  select coalesce(jsonb_agg(jsonb_build_object('title',title,'body',body,'at',created_at)
                            order by created_at desc),'[]'::jsonb)
    into v_ann from announcements;
  return jsonb_build_object('messages',v_msgs,'announcements',v_ann);
end $$;

-- ---------------------------------------------------------------
-- admin (token must belong to an is_admin user)
-- ---------------------------------------------------------------
create or replace function iw_admin(p_token uuid) returns users
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  if not u.is_admin then raise exception 'admin only'; end if;
  return u;
end $$;

create or replace function iw_admin_stats(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v jsonb;
begin
  perform iw_admin(p_token);
  select jsonb_build_object(
    'users',(select count(*) from users),
    'entries_sold',(select count(*) from allocation where claimed_by is not null),
    'card_entries',(select count(*) from card_entries),
    'prizes_paid_p',(select coalesce(sum(delta_p),0) from ledger where delta_p>0 and reason like 'win %' or delta_p>0 and reason like '%draw win%'),
    'per_game',(select coalesce(jsonb_agg(jsonb_build_object('game',g.name,'sold',
                 (select count(*) from allocation a join pools p on p.id=a.pool_id
                   where p.game=g.tag and a.claimed_by is not null and a.claimed_by<>'web'))
                 order by g.name),'[]'::jsonb) from games g),
    'recent_wins',(select coalesce(jsonb_agg(jsonb_build_object('who',u.name,'amount_p',l.delta_p,
                    'reason',l.reason,'at',l.created_at) order by l.created_at desc),'[]'::jsonb)
                   from (select * from ledger where delta_p>0 and reason not like 'welcome%'
                          order by created_at desc limit 12) l join users u on u.id=l.user_id))
  into v;
  return v;
end $$;

create or replace function iw_admin_users(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'email',u.email,
            'joined',u.created_at,'balance_p',iw_balance(u.id)) order by u.created_at desc),'[]'::jsonb)
          from users u);
end $$;

create or replace function iw_admin_threads(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return (select coalesce(jsonb_agg(t order by t->>'last_at' desc),'[]'::jsonb) from (
    select jsonb_build_object('user_id',m.user_id,'name',u.name,'email',u.email,
             'last_at',max(m.created_at),'count',count(*)) as t
      from messages m join users u on u.id=m.user_id
     group by m.user_id,u.name,u.email) s);
end $$;

create or replace function iw_admin_thread(p_token uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return (select coalesce(jsonb_agg(jsonb_build_object('sender',sender,'body',body,'at',created_at)
            order by created_at),'[]'::jsonb) from messages where user_id=p_user);
end $$;

create or replace function iw_admin_reply(p_token uuid, p_user uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into messages (user_id, sender, body) values (p_user, 'admin', left(trim(p_body),2000));
  return jsonb_build_object('ok',true);
end $$;

create or replace function iw_admin_announce(p_token uuid, p_title text, p_body text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  insert into announcements (title, body) values (left(trim(p_title),140), left(trim(p_body),2000));
  return jsonb_build_object('ok',true);
end $$;

-- lock the levers to the server only
do $$
declare f text;
begin
  foreach f in array array[
    'iw_user(uuid)','iw_balance(uuid)','iw_signup(text,text,text,date)','iw_login(text,text)',
    'iw_logout(uuid)','iw_me(uuid)','buy_entry2(text,uuid)','card_enter2(text,uuid)',
    'iw_msg_send(uuid,text)','iw_msg_list(uuid)','iw_admin(uuid)','iw_admin_stats(uuid)',
    'iw_admin_users(uuid)','iw_admin_threads(uuid)','iw_admin_thread(uuid,uuid)',
    'iw_admin_reply(uuid,uuid,text)','iw_admin_announce(uuid,text,text)']
  loop
    execute 'revoke all on function '||f||' from public';
    execute 'grant execute on function '||f||' to service_role';
  end loop;
end $$;

-- AFTER YOU SIGN UP on the site, make yourself admin (edit the email):
-- update users set is_admin = true where lower(email) = 'you@example.com';
