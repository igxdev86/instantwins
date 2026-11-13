-- onboard-prefill.sql — sign-up records the terms version (no second form for new accounts); c2_mine returns name/dob so any later check is prefilled.
create or replace function iw_signup(p_email text, p_pass text, p_name text, p_dob date, p_ref text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid; v_tok uuid; v_ref text;
begin
  if length(trim(p_email)) < 5 or position('@' in p_email)=0 then raise exception 'valid email required'; end if;
  if length(p_pass) < 8 then raise exception 'password must be at least 8 characters'; end if;
  if length(trim(p_name)) < 2 then raise exception 'name required'; end if;
  if p_dob > (current_date - interval '18 years') then raise exception 'you must be 18 or over'; end if;
  if exists (select 1 from users where lower(email)=lower(trim(p_email))) then
    raise exception 'an account with that email already exists';
  end if;
  select code into v_ref from affiliates where lower(code)=lower(trim(coalesce(p_ref,''))) and status='active';
  insert into users (email, pass, name, dob, ref_code, gb_resident, terms_version)
  values (trim(p_email), crypt(p_pass, gen_salt('bf')), trim(p_name), p_dob, v_ref, true, (select value from site_settings where key='terms_version'))
  returning id into v_id;
  insert into ledger (user_id, delta_p, reason) values (v_id, 2000, 'welcome play credit');
  insert into sessions (user_id) values (v_id) returning token into v_tok;
  return jsonb_build_object('token',v_tok,'name',trim(p_name),'email',trim(p_email),'is_admin',false,'balance_p',2000);
end $$;

create or replace function c2_mine(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype;
begin
  u := iw_user(p_token);
  return jsonb_build_object('balance_p',iw_balance(u.id),'name',u.name,'county',u.county,'publish_wins',u.publish_wins,'marketing_ok',coalesce(u.marketing_ok,false),'name',coalesce(u.name,''),'dob',to_char(u.dob,'YYYY-MM-DD'),
    'terms_due',(u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'onboard',(u.dob is null or coalesce(u.name,'')='' or u.terms_version is distinct from (select value from site_settings where key='terms_version')),
    'won_p',(select coalesce(sum(delta_p),0) from ledger where user_id=u.id and delta_p>0 and reason like 'win MIL-%'),
    'opened',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and a.revealed),
    'bank',(select count(*) from allocation a join pools q on q.id=a.pool_id where q.game='MIL' and a.claimed_by=u.id::text and not a.revealed),
    'recent',coalesce((select jsonb_agg(jsonb_build_object('no',a.entry_no,'prize_p',a.prize_p) order by a.claimed_at desc, a.entry_no desc) from (select * from allocation al join pools q on q.id=al.pool_id where q.game='MIL' and al.claimed_by=u.id::text and al.revealed order by al.claimed_at desc, al.entry_no desc limit 40) a),'[]'::jsonb));
end $$;
-- existing accounts that signed up with name + DOB only need the terms tick, not the form again
update users set gb_resident=true where gb_resident is null and dob is not null and coalesce(name,'')<>'';
notify pgrst, 'reload schema';
