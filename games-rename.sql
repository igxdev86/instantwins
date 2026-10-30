-- games-rename.sql — ticket books replace the game names in results and ledgers.
update games set name='Gold Ticket'     where tag='PL';
update games set name='Platinum Ticket' where tag='SC';
update games set name='Mega Ticket'     where tag='SP';
notify pgrst, 'reload schema';
