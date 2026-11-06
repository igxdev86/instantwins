-- card-verify.sql — public lookup of one draw by game number, for the "check this draw" page.
create or replace function card_lookup(p_game_no text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g record; d card_draws%rowtype;
begin
  select * into g from card_parse_game_no(p_game_no);
  perform card_settle_due();
  select * into d from card_draws where kind=g.kind and off_at=g.off_at;
  if not found then
    return jsonb_build_object('found',false,'kind',g.kind,'label',drawlabel(g.kind),'off_at',g.off_at,'game_no',card_game_no(g.kind,g.off_at),
      'status',case when g.off_at<=now() then 'no entries' else 'open' end);
  end if;
  return jsonb_build_object('found',true,'kind',d.kind,'label',drawlabel(d.kind),'off_at',d.off_at,'game_no',card_game_no(d.kind,d.off_at),
    'status',d.status,'price_p',d.price_p,'prize_p',d.prize_p,'cap',d.cap,'sold',d.sold,'seed_hash',d.seed_hash,
    'seed',case when d.status='settled' then d.seed end,'winner_entry',d.winner_entry,'settled_at',d.settled_at,
    'winner_name',(select split_part(coalesce(u.name,''),' ',1) from card_entries ce join users u on u.id::text=ce.punter where ce.draw_id=d.id and ce.entry_no=d.winner_entry),
    'postal_entries',(select count(*) from card_entries ce where ce.draw_id=d.id and ce.via='post'));
end $$;
grant execute on function card_lookup(text) to service_role;
notify pgrst, 'reload schema';
