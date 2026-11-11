-- stats-public.sql — honest, live site totals for the home page strip. Real ledger data only.
create or replace function iw_public_stats() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare day0 timestamptz := date_trunc('day', now() at time zone 'Europe/London') at time zone 'Europe/London';
        v_entries int; v_winners int; v_paid bigint; v_last jsonb;
begin
  perform card_settle_due();
  select count(*) into v_entries from card_entries ce join card_draws d on d.id=ce.draw_id where ce.created_at >= day0;
  select count(*), coalesce(sum(prize_p),0) into v_winners, v_paid from card_draws where status='settled' and winner_entry is not null and settled_at >= day0;
  select jsonb_build_object('name',split_part(coalesce(u.name,''),' ',1),'prize_p',d.prize_p,'label',drawlabel(d.kind),'at',d.settled_at,'game_no',card_game_no(d.kind,d.off_at))
    into v_last from card_draws d join card_entries ce on ce.draw_id=d.id and ce.entry_no=d.winner_entry join users u on u.id::text=ce.punter
   where d.status='settled' and d.winner_entry is not null order by d.settled_at desc limit 1;
  return jsonb_build_object('entries_today',v_entries,'winners_today',v_winners,'paid_today_p',v_paid,'last',v_last,'server_now',now());
end $$;
grant execute on function iw_public_stats() to service_role;
notify pgrst, 'reload schema';
