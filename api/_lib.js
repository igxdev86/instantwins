// api/_lib.js — shared helpers: Supabase RPC, rate limiting, outbox flush (Resend).
export function env(res){ const KEY=process.env.SUPABASE_SERVICE_ROLE_KEY, URL=process.env.SUPABASE_URL; if(!KEY||!URL){ res.status(503).json({error:'backend not connected'}); return null; } return {KEY,URL}; }
export function rpc(e, fn, body){ return fetch(e.URL+'/rest/v1/rpc/'+fn,{method:'POST',headers:{'Content-Type':'application/json',apikey:e.KEY,Authorization:'Bearer '+e.KEY},body:JSON.stringify(body||{})}); }
export function ip(req){ return String(req.headers['x-forwarded-for']||req.socket?.remoteAddress||'').split(',')[0].trim()||'0.0.0.0'; }
// returns true when allowed; fails open if the limiter itself errors
export async function allow(e, key, limit, windowS){ try{ const r=await rpc(e,'iw_rate',{p_key:key,p_limit:limit,p_window_s:windowS}); if(!r.ok)return true; return (await r.json())!==false; }catch{ return true; } }
// send up to n queued emails through Resend; no-op without RESEND_API_KEY
export async function flushMail(e, n){ const RK=process.env.RESEND_API_KEY, FROM=process.env.MAIL_FROM||'InstantWins <no-reply@instantwins.co.uk>'; if(!RK)return {skipped:true};
  let rows=[]; try{ const r=await rpc(e,'iw_outbox_take',{p_n:n||10}); if(!r.ok)return {error:'take'}; rows=await r.json(); }catch{ return {error:'take'}; }
  let sent=0; for(const m of rows){ let ok=false, err=null; try{ const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+RK},body:JSON.stringify({from:FROM,to:[m.to],subject:m.subject,html:m.html})}); ok=r.ok; if(!ok)err=(await r.text()).slice(0,300); }catch(x){ err=String(x.message||x).slice(0,300); }
    await rpc(e,'iw_outbox_mark',{p_id:m.id,p_ok:ok,p_error:err}); if(ok)sent++; }
  return {sent,queued:rows.length}; }
export function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
