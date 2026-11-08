-- labels-nohyphen.sql — drop hyphens from draw labels ("Five-Minute" → "Five Minute")
update card_kinds set label = regexp_replace(label, '-(Second|Minute|Hour)', ' \1', 'g') where label ~ '-(Second|Minute|Hour)';
update games set name = regexp_replace(name, '-(Second|Minute|Hour)', ' \1', 'g') where name ~ '-(Second|Minute|Hour)';
