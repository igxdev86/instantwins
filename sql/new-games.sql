-- EIGHT NEW GAMES — run once in the SQL Editor.
-- Adds them to the menu and opens their first sealed pools.
insert into games (tag, name, cap, price_p, tiers) values
 ('RW','Roulette Royale',500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('SG','Scratch Gold',   500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('PT','Pinata Party',   500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('DC','Lucky Dice',     500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('RR','Reel Rush',      500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('MB','Mystery Box',    500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('DT','Dart Dash',      500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]'),
 ('GG','Golden Goal',    500, 200, '[[10000,1],[2000,5],[1000,10],[500,20],[200,50]]')
on conflict (tag) do nothing;

select open_pool(tag) from games
 where tag in ('RW','SG','PT','DC','RR','MB','DT','GG');
