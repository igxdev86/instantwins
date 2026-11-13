-- close-31jan.sql — the open Million Round closes Sunday 31 January 2027 at 8pm UK; later rounds default to ~11 weeks.
update pools set closes_at = '2027-01-31 20:00:00 Europe/London'::timestamptz where game='MIL' and status='open';
insert into site_settings (key,value,updated_at) values ('mil_round_days','77',now()) on conflict (key) do update set value=excluded.value, updated_at=now();
select pool_no, closes_at at time zone 'Europe/London' as closes_uk, end_prize_p from pools where game='MIL' and status='open';
