-- password-reset.sql — identity-verified password reset (email + date of birth).
-- No email infrastructure is wired yet, so the user proves ownership with the
-- date of birth on file instead of a reset link. On success a fresh session is
-- issued, mirroring iw_login, so the user lands logged in.

create or replace function iw_reset_password(p_email text, p_dob date, p_newpass text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u users%rowtype; v_tok uuid;
begin
  if length(p_newpass) < 8 then
    raise exception 'new password must be at least 8 characters';
  end if;
  select * into u from users where lower(email)=lower(trim(p_email)) and dob = p_dob;
  if not found then
    raise exception 'no account matches that email and date of birth';
  end if;
  update users set pass = crypt(p_newpass, gen_salt('bf')) where id = u.id;
  -- invalidate any old sessions, then start a fresh one
  delete from sessions where user_id = u.id;
  insert into sessions (user_id) values (u.id) returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'name', u.name, 'email', u.email,
                            'is_admin', u.is_admin, 'balance_p', iw_balance(u.id));
end $$;

grant execute on function iw_reset_password(text,date,text) to anon, authenticated, service_role;
