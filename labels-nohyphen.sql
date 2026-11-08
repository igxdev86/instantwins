-- labels-nohyphen.sql — drop hyphens from draw labels ("Five-Minute" → "Five Minute")
update card_kinds set label = regexp_replace(label, '-(Second|Minute|Hour)', ' \1', 'g') where label ~ '-(Second|Minute|Hour)';
update games set name = regexp_replace(name, '-(Second|Minute|Hour)', ' \1', 'g') where name ~ '-(Second|Minute|Hour)';
-- 30s / 60s rows: "30s Draw £8"
update card_kinds set label = regexp_replace(label, '^30[- ]Second ', '30s Draw ') where label ~ '^30[- ]Second ';
update card_kinds set label = regexp_replace(label, '^60[- ]Second ', '60s Draw ') where label ~ '^60[- ]Second ';
