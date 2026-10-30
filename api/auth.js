// api/auth.js — signup / login / me / logout. Zero dependencies.
const RPC = { signup:'iw_signup', login:'iw_login', me:'iw_me', logout:'iw_logout', reset:'iw_reset_password',
              limits:'iw_limits', setlimit:'iw_set_limit', takebreak:'iw_take_break', close:'iw_close_account' };
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const fn = RPC[b && b.action];
  if (!fn) return res.status(400).json({ error: 'bad action' });
  let args;
  if (b.action === 'signup') args = { p_email: String(b.email||''), p_pass: String(b.password||''), p_name: String(b.name||''), p_dob: String(b.dob||''), p_ref: String(b.ref||'') };
  else if (b.action === 'login') args = { p_email: String(b.email||''), p_pass: String(b.password||'') };
  else if (b.action === 'reset') args = { p_email: String(b.email||''), p_dob: String(b.dob||''), p_newpass: String(b.password||'') };
  else if (b.action === 'setlimit') args = { p_token: String(b.token||''), p_limit_p: (b.limit_p===null||b.limit_p==='')?null:Math.max(parseInt(b.limit_p,10)||0,0) };
  else if (b.action === 'takebreak') args = { p_token: String(b.token||''), p_days: parseInt(b.days,10)||1 };
  else args = { p_token: String(b.token||'') };
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data === null ? { ok: true } : data);
}
