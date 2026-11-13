-- postal-reject-mail.sql — when a postcard is rejected and we can tell whose it is, email them why and how to fix it.
create or replace function trg_mail_postal_reject() returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare v_why text; v_fix text;
begin
  if new.status <> 'rejected' or new.user_id is null then return new; end if;
  v_why := coalesce(nullif(trim(new.reason),''),'it did not meet the free-entry rules');
  v_fix := case
    when new.reason ilike '%envelope%' then 'Send it as an unenclosed postcard &mdash; no envelope.'
    when new.reason ilike '%photocop%' or new.reason ilike '%printed%' then 'Write the card by hand &mdash; printed or photocopied cards are not accepted.'
    when new.reason ilike '%illegible%' then 'Write clearly in capitals so we can read every detail.'
    when new.reason ilike '%million round%' then 'Write &ldquo;Million Round&rdquo; on the card so we know what it is for.'
    when new.reason ilike '%18%' or new.reason ilike '%GB%' then 'Entry is open to residents of Great Britain aged 18 or over only.'
    else 'Check every detail against the free-entry page and send another card.' end;
  perform iw_mail(new.user_id,'We could not accept your postcard',
    '<p>A postcard arrived for the Million Round in your name, but we could not accept it: <b>'||v_why||'</b>.</p>'
    ||case when coalesce(new.note,'')<>'' then '<p>'||replace(replace(new.note,'&','&amp;'),'<','&lt;')||'</p>' else '' end
    ||'<p>'||v_fix||' There is no limit on cards, so you can send another any time.</p>'
    ||'<p><a class="btn" href="https://instantwins.co.uk/free.html">What to write</a></p>'
    ||'<p>If you think we have got this wrong, reply to this email and we will look again.</p>');
  return new;
end $$;
drop trigger if exists mail_postal_reject on postal_log;
create trigger mail_postal_reject after insert on postal_log for each row execute function trg_mail_postal_reject();
notify pgrst, 'reload schema';
