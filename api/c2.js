// api/c2.js — Million Round: GET -> round state; POST {action:'buy',n} | {action:'reveal'} | {action:'revealall'} | {action:'mine'} | {action:'accept_terms'} | {action:'profile'} with token
export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
    const a = b.action;
    if (a === 'buy') { if (!await allow(e, 'buy:' + token, 30, 60)) return res.status(429).json({ error: 'slow down a moment' }); const n = parseInt(b.n, 10); if (![1,5,10,25,50,100,250,500].includes(n)) return res.status(400).json({ error: 'pick a pack' }); r = await rpc(e, 'c2_buy', { p_token: token, p_n: n }); }
    else if (a === 'buybal') { if (!await allow(e, 'buy:' + token, 30, 60)) return res.status(429).json({ error: 'slow down a moment' }); r = await rpc(e, 'c2_buy_balance', { p_token: token }); }
    else if (a === 'reveal') { if (!await allow(e, 'rev:' + token, 400, 60)) return res.status(429).json({ error: 'slow down a moment' }); r = await rpc(e, 'c2_reveal', { p_token: token }); }
    else if (a === 'revealall') r = await rpc(e, 'c2_reveal_all', { p_token: token });
    else if (a === 'mine') r = await rpc(e, 'c2_mine', { p_token: token });
    else if (a === 'accept_terms') r = await rpc(e, 'iw_accept_terms', { p_token: token });
    else if (a === 'profile') r = await rpc(e, 'iw_set_profile', { p_token: token, p_county: String(b.county || '').slice(0, 40), p_publish: b.publish !== false });
    else return res.status(400).json({ error: 'bad request' });
    if (a === 'buy' || a === 'buybal' || a === 'revealall') { flushMail(e, 5).catch(() => {}); }
  } else {
    if (!await allow(e, 'state:' + ip(req), 120, 60)) return res.status(429).json({ error: 'slow down' });
    r = await rpc(e, 'c2_state', {});
  }
  const data = await r.json();
  if (req.method !== 'POST' && data && data.closed) { try { await rpc(e, 'c2_settle', {}); const r2 = await rpc(e, 'c2_state', {}); if (r2.ok) { const d2 = await r2.json(); res.setHeader('Cache-Control', 'no-store'); return res.status(200).json(d2); } } catch {} }
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
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
