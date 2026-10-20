-- 100 bot users with ~infinite (£1,000,000) play balances. TEST ONLY.
-- Tagged is_bot=true so you can filter/delete:  delete from users where is_bot;
alter table users add column if not exists is_bot boolean default false;

do $$
declare
  i int; v_id uuid;
  firsts text[] := array['Dave','Sarah','Mo','Kelly','Tom','Priya','Gareth','Lisa','Jamal','Ffion',
    'Steve','Aisha','Rhys','Donna','Marek','Jo','Nia','Owen','Beca','Carl','Leah','Sam','Ade','Megan'];
  towns  text[] := array['Cardiff','Leeds','Barry','Swindon','Glasgow','Luton','Wrexham','Hull',
    'Derby','Newport','Bolton','Penarth','Hull','Stoke','Ayr','Ely'];
begin
  for i in 1..100 loop
    if not exists (select 1 from users where lower(email)=lower('bot'||i||'@bots.local')) then
      insert into users (email, pass, name, dob, is_bot)
      values ('bot'||i||'@bots.local',
              crypt('bot-'||i||'-'||gen_random_uuid(), gen_salt('bf')),
              firsts[1+floor(random()*array_length(firsts,1))]||' from '||towns[1+floor(random()*array_length(towns,1))],
              date '1990-01-01', true)
      returning id into v_id;
      insert into ledger (user_id, delta_p, reason) values (v_id, 100000000, 'bot test credit');  -- £1,000,000
    end if;
  end loop;
end $$;

select count(*) as bots, to_char(sum(iw_balance(id))/100.0,'FM999,999,999') as total_credit_gbp
from users where is_bot;
