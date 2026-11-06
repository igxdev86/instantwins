-- card-30s.sql — the small draws run every 30 seconds.
update card_kinds set step_s=30, label=replace(label,'Two-Minute','30-Second') where kind in ('t_1','t_2','t_5','t_8');
delete from card_draws where kind in ('t_1','t_2','t_5','t_8') and status='open' and sold=0;
select card_ensure_open();
notify pgrst, 'reload schema';
