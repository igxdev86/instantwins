// api/auth.js — signup / login / me / logout. Zero dependencies.
const RPC = { signup:'iw_signup', login:'iw_login', me:'iw_me', logout:'iw_logout' };
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const fn = RPC[b && b.action];
  if (!fn) return res.status(400).json({ error: 'bad action' });
  let args;
  if (b.action === 'signup') args = { p_email: String(b.email||''), p_pass: String(b.password||''), p_name: String(b.name||''), p_dob: String(b.dob||'') };
  else if (b.action === 'login') args = { p_email: String(b.email||''), p_pass: String(b.password||'') };
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
