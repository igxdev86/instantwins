// api/admin.js — admin console. Server verifies is_admin on every call.
const MAP = { stats:'iw_admin_stats', users:'iw_admin_users', threads:'iw_admin_threads',
              thread:'iw_admin_thread', reply:'iw_admin_reply', announce:'iw_admin_announce',
              aff_list:'iw_admin_aff_list', aff_create:'iw_admin_aff_create', aff_update:'iw_admin_aff_update' };
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const token = String((b && b.token) || '');
  const fn = MAP[b && b.action];
  if (!token || !fn) return res.status(400).json({ error: 'bad request' });
  const args = { p_token: token };
  if (b.action === 'thread') args.p_user = String(b.user_id||'');
  if (b.action === 'reply') { args.p_user = String(b.user_id||''); args.p_body = String(b.body||''); }
  if (b.action === 'announce') { args.p_title = String(b.title||''); args.p_body = String(b.body||''); }
  if (b.action === 'aff_create') { args.p_name=String(b.name||''); args.p_email=String(b.email||''); args.p_code=String(b.code||''); args.p_model=String(b.model||'revshare'); args.p_rate=parseInt(b.rate,10)||0; }
  if (b.action === 'aff_update') { args.p_code=String(b.code||''); args.p_model=String(b.model||''); args.p_rate=(b.rate===''||b.rate==null)?null:parseInt(b.rate,10); args.p_status=String(b.status||''); }
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
