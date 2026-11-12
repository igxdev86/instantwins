// api/auth.js — signup / login / me / logout. Rate-limited per IP on the credential actions.
const RPC = { signup:'iw_signup', login:'iw_login', me:'iw_me', logout:'iw_logout', reset:'iw_reset_password',
              limits:'iw_limits', setlimit:'iw_set_limit', setmlimit:'iw_set_monthly_limit', takebreak:'iw_take_break', close:'iw_close_account' };
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const fn = RPC[b && b.action];
  if (!fn) return res.status(400).json({ error: 'bad action' });
  const e = { KEY, URL };
  if (['login','signup','reset'].includes(b.action) && !await allow(e, 'auth:' + ip(req), 20, 600)) return res.status(429).json({ error: 'too many attempts — try again in a few minutes' });
  let args;
  if (b.action === 'signup') args = { p_email: String(b.email||''), p_pass: String(b.password||''), p_name: String(b.name||''), p_dob: String(b.dob||''), p_ref: String(b.ref||'') };
  else if (b.action === 'login') args = { p_email: String(b.email||''), p_pass: String(b.password||'') };
  else if (b.action === 'reset') args = { p_email: String(b.email||''), p_dob: String(b.dob||''), p_newpass: String(b.password||'') };
  else if (b.action === 'setmlimit') args = { p_token: String(b.token||''), p_limit_p: (b.limit_p===null||b.limit_p==='')?null:Math.max(parseInt(b.limit_p,10)||0,0) };
  else if (b.action === 'setlimit') args = { p_token: String(b.token||''), p_limit_p: (b.limit_p===null||b.limit_p==='')?null:Math.max(parseInt(b.limit_p,10)||0,0) };
  else if (b.action === 'takebreak') args = { p_token: String(b.token||''), p_days: parseInt(b.days,10)||1 };
  else args = { p_token: String(b.token||'') };
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  if (b.action === 'signup' || b.action === 'setlimit' || b.action === 'setmlimit') flushMail(e, 3).catch(() => {});
  return res.status(200).json(data === null ? { ok: true } : data);
}

// ---- shared helpers (inlined; no cross-file imports in api/) ----
function env(res){ const KEY=process.env.SUPABASE_SERVICE_ROLE_KEY, URL=process.env.SUPABASE_URL; if(!KEY||!URL){ res.status(503).json({error:'backend not connected'}); return null; } return {KEY,URL}; }
function rpc(e, fn, body){ return fetch(e.URL+'/rest/v1/rpc/'+fn,{method:'POST',headers:{'Content-Type':'application/json',apikey:e.KEY,Authorization:'Bearer '+e.KEY},body:JSON.stringify(body||{})}); }
function ip(req){ return String(req.headers['x-forwarded-for']||req.socket?.remoteAddress||'').split(',')[0].trim()||'0.0.0.0'; }
// returns true when allowed; fails open if the limiter itself errors
async function allow(e, key, limit, windowS){ try{ const r=await rpc(e,'iw_rate',{p_key:key,p_limit:limit,p_window_s:windowS}); if(!r.ok)return true; return (await r.json())!==false; }catch{ return true; } }
// send up to n queued emails through Resend; no-op without RESEND_API_KEY
async function flushMail(e, n){ const RK=process.env.RESEND_API_KEY, FROM=process.env.MAIL_FROM||'InstantWins <no-reply@instantwins.co.uk>'; if(!RK)return {skipped:true};
  let rows=[]; try{ const r=await rpc(e,'iw_outbox_take',{p_n:n||10}); if(!r.ok)return {error:'take'}; rows=await r.json(); }catch{ return {error:'take'}; }
  let sent=0; for(const m of rows){ let ok=false, err=null; try{ const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+RK},body:JSON.stringify({from:FROM,to:[m.to],subject:m.subject,html:m.html})}); ok=r.ok; if(!ok)err=(await r.text()).slice(0,300); }catch(x){ err=String(x.message||x).slice(0,300); }
    await rpc(e,'iw_outbox_mark',{p_id:m.id,p_ok:ok,p_error:err}); if(ok)sent++; }
  return {sent,queued:rows.length}; }
function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
