// api/c2.js — Million Round: GET -> round state; POST {action:'buy',n} | {action:'reveal'} | {action:'revealall'} | {action:'mine'} | {action:'accept_terms'} | {action:'profile'} with token
// qualifying questions — generated fresh each time, answer carried as an HMAC so nothing is stored and nothing is guessable
import { createHmac } from 'crypto';
const R=n=>Math.floor(Math.random()*n), pick=a=>a[R(a.length)], shuffle=a=>{for(let i=a.length-1;i>0;i--){const j=R(i+1);[a[i],a[j]]=[a[j],a[i]];}return a;};
function distract(ans, span){ const set=new Set([ans]); let g=0; while(set.size<3&&g++<50){ const d=ans+(R(2)?1:-1)*(1+R(span)); if(d>=0&&d!==ans)set.add(d); } while(set.size<3)set.add(ans+set.size*3); return shuffle([...set]).map(String); }
const WORDS=['TICKET','REVEAL','WINNER','JACKPOT','MILLION','PRIZE','ORANGE','PURPLE','BANANA','LONDON','CARDIFF','SUMMER','WINTER','ROCKET','PLANET','GUITAR','SILVER','GOLDEN','BRIDGE','CASTLE'];
const GEN=[
  ()=>{ const a=11+R(40), b=11+R(40); return {q:`What is ${a} + ${b}?`, a:a+b, span:4}; },
  ()=>{ const a=30+R(60), b=5+R(25); return {q:`What is ${a} − ${b}?`, a:a-b, span:4}; },
  ()=>{ const a=3+R(10), b=3+R(10); return {q:`What is ${a} × ${b}?`, a:a*b, span:6}; },
  ()=>{ const b=2+R(10), r=2+R(10); return {q:`What is ${b*r} ÷ ${b}?`, a:r, span:3}; },
  ()=>{ const s=1+R(9), d=2+R(7); const seq=[s,s+d,s+2*d,s+3*d]; return {q:`Which number comes next: ${seq.join(', ')}, …?`, a:s+4*d, span:d}; },
  ()=>{ const s=1+R(4), m=2+R(2); const seq=[s,s*m,s*m*m,s*m*m*m]; return {q:`Which number comes next: ${seq.join(', ')}, …?`, a:s*m*m*m*m, span:6}; },
  ()=>{ const h=1+R(5), half=R(2); const mins=h*60+(half?30:0); return {q:`How many minutes are in ${h}${half?' and a half':''} hour${h>1||half?'s':''}?`, opts:shuffle([mins,mins+30,mins-30].map(String)), a:mins}; },
  ()=>{ const pc=pick([10,20,25,50]), n=pick([40,60,80,120,200,300]); const v=pc*n/100; return {q:`What is ${pc}% of ${n}?`, opts:shuffle([v,v+5,v-5>0?v-5:v+10].map(String)), a:v}; },
  ()=>{ const w=pick(WORDS); return {q:`How many letters are in the word ${w}?`, a:w.length, span:2}; },
  ()=>{ const u=[...new Set([10+R(80),10+R(80),10+R(80)])]; while(u.length<3)u.push(u[u.length-1]+7); const big=Math.max(...u); return {q:`Which of these is the largest number?`, opts:shuffle(u.map(String)), a:big}; },
  ()=>{ const a=2+R(9); return {q:`What is ${a} squared?`, a:a*a, span:5}; },
  ()=>{ const d=pick([['Monday',3,'Thursday'],['Tuesday',4,'Saturday'],['Friday',3,'Monday'],['Wednesday',5,'Monday'],['Sunday',2,'Tuesday'],['Thursday',4,'Monday']]); return {q:`If today is ${d[0]}, what day is it in ${d[1]} days?`, opts:shuffle([d[2],...shuffle(['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'].filter(x=>x!==d[2])).slice(0,2)]), a:d[2]}; },
  ()=>{ const a=10+R(30), b=10+R(30), c=5+R(20); return {q:`What is ${a} + ${b} − ${c}?`, a:a+b-c, span:4}; },
];
function makeQ(e){ const g=pick(GEN)(); const a=String(g.a); const opts=g.opts||distract(g.a,g.span||4); const exp=Date.now()+15*60*1000; const sig=sign(e,g.q,a,exp); return {q:g.q,opts,exp,sig}; }
function sign(e,q,a,exp){ return createHmac('sha256', e.KEY).update(q+'|'+a+'|'+exp).digest('hex'); }
export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
    const a = b.action;
    if (a === 'buy') { if (!await allow(e, 'buy:' + token, 30, 60)) return res.status(429).json({ error: 'slow down a moment' }); const n = parseInt(b.n, 10); if (![1,5,10,25,50,100,250,500,1000].includes(n)) return res.status(400).json({ error: 'choose how many tickets' }); r = await rpc(e, 'c2_buy', { p_token: token, p_n: n }); }
    else if (a === 'buybal') { if (!await allow(e, 'buy:' + token, 30, 60)) return res.status(429).json({ error: 'slow down a moment' }); r = await rpc(e, 'c2_buy_balance', { p_token: token }); }
    else if (a === 'reveal') { if (!await allow(e, 'rev:' + token, 400, 60)) return res.status(429).json({ error: 'slow down a moment' }); r = await rpc(e, 'c2_reveal', { p_token: token }); }
    else if (a === 'revealall') r = await rpc(e, 'c2_reveal_all', { p_token: token });
    else if (a === 'mine') r = await rpc(e, 'c2_mine', { p_token: token });
    else if (a === 'answer') { if (!await allow(e, 'ans:' + token, 8, 60)) return res.status(429).json({ error: 'too many tries — wait a minute' }); const q=String(b.q||'').slice(0,200), ans=String(b.answer||'').slice(0,100), exp=+b.exp||0; if(!q||!b.sig||exp<Date.now()) return res.status(400).json({ error: 'question expired — try again' }); const ok = sign(e,q,ans,exp)===String(b.sig); r = await rpc(e, 'c2_answer', { p_token: token, p_q: q, p_answer: ans, p_correct: ok }); }
    else if (a === 'accept_terms') r = await rpc(e, 'iw_accept_terms', { p_token: token });
    else if (a === 'profile') r = await rpc(e, 'iw_set_profile', { p_token: token, p_county: String(b.county || '').slice(0, 40), p_publish: b.publish !== false });
    else return res.status(400).json({ error: 'bad request' });
    if (a === 'buy' || a === 'buybal' || a === 'revealall') { flushMail(e, 5).catch(() => {}); }
  } else if (req.query && req.query.q !== undefined) {
    res.setHeader('Cache-Control','no-store'); return res.status(200).json(makeQ(e));
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
