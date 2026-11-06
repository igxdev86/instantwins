-- card-small.sql — Two-Minute "small" draws (£1, £2, £5, £8) + back-office on/off switches
-- for draw kinds and whole cadence groups. Run AFTER postal-roll.sql.
insert into card_kinds (kind,code,label,price_p,prize_p,cap,step_s,offset_s,daily_hour,sort) values
 ('t_1','T1','Two-Minute £1',  10,  100, 20, 120, 0, null, 1),
 ('t_2','T2','Two-Minute £2',  20,  200, 20, 120, 0, null, 2),
 ('t_5','T5','Two-Minute £5',  50,  500, 20, 120, 0, null, 3),
 ('t_8','T8','Two-Minute £8', 100,  800, 16, 120, 0, null, 4)
on conflict (kind) do update set code=excluded.code, label=excluded.label, price_p=excluded.price_p, prize_p=excluded.prize_p,
  cap=excluded.cap, step_s=excluded.step_s, offset_s=excluded.offset_s, daily_hour=excluded.daily_hour, sort=excluded.sort;

-- admin: list every kind with its switch
create or replace function iw_admin_kinds(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'code',code,'label',label,'price_p',price_p,'prize_p',prize_p,
    'cap',cap,'step_s',step_s,'offset_s',offset_s,'daily_hour',daily_hour,'sort',sort,'active',active,
    'open_entries',(select coalesce(sum(sold),0) from card_draws d where d.kind=card_kinds.kind and d.status='open')) order by sort)
    from card_kinds),'[]'::jsonb);
end $$;

-- admin: switch one kind, or every kind in a cadence group (p_kind null + p_step set)
create or replace function iw_admin_kind_active(p_token uuid, p_kind text, p_step int, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform iw_admin(p_token);
  if p_kind is not null then update card_kinds set active=p_active where kind=p_kind;
  elsif p_step is not null then update card_kinds set active=p_active where step_s=p_step;
  else raise exception 'kind or step required'; end if;
  return iw_admin_kinds(p_token);
end $$;
grant execute on function iw_admin_kinds(uuid), iw_admin_kind_active(uuid,text,int,boolean) to service_role;

-- switched-off kinds: no new draws, no new entries. Draws already holding entries still settle and pay.
create or replace function card_ensure_open() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare k text;
begin
  foreach k in array card_kinds() loop perform card_draw_for(k, card_next_off(k)); end loop;
end $$;
select card_ensure_open();
notify pgrst, 'reload schema';
