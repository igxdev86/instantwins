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
    else if (a === 'profile') r = await rpc(e, 'iw_set_profile', { p_token: token, p_county: String(b.county || '').slice(0, 40), p_publish: b.publish !== false, p_marketing: typeof b.marketing === 'boolean' ? b.marketing : null });
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
  let sent=0; for(const m of rows){ let ok=false, err=null; try{ const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+RK},body:JSON.stringify({from:FROM,to:[m.to],subject:m.subject,html:wrapMail(m.subject,m.html,m.to),reply_to:process.env.MAIL_REPLY_TO||undefined})}); ok=r.ok; if(!ok)err=(await r.text()).slice(0,300); }catch(x){ err=String(x.message||x).slice(0,300); }
    await rpc(e,'iw_outbox_mark',{p_id:m.id,p_ok:ok,p_error:err}); if(ok)sent++; }
  return {sent,queued:rows.length}; }
function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
// Branded email shell: dark, table-based, inline styles, hosted PNG art from instantwins.co.uk/mail/. Injected into every api/*.js flushMail.
function wrapMail(subject, body, to){
  const esc=s=>String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;');
  const F='Helvetica,Arial,sans-serif', SITE='https://instantwins.co.uk';
  const sub=String(subject||''); let kind='info';
  if(/won|winner|end prize/i.test(sub))kind='win'; else if(/welcome/i.test(sub))kind='welcome'; else if(/could not|declined|not matched|limit|changed/i.test(sub))kind='warn'; else if(/deposit|withdrawal|funds|payment/i.test(sub))kind='money'; else if(/code|sign/i.test(sub))kind='code'; else if(/postal|ticket/i.test(sub))kind='ticket'; else if(/reply|support/i.test(sub))kind='mail';
  const K={ win:{bg:'#C6FF3D',bg2:'#8fd81c',ink:'#0B0B10',art:'star',k:'You won'}, welcome:{bg:'#3DF2FF',bg2:'#1aa7c4',ink:'#0B0B10',art:'bolt',k:'Welcome'}, warn:{bg:'#FF3D8A',bg2:'#b4155a',ink:'#ffffff',art:'shield',k:'Heads up'},
            money:{bg:'#FF6A1A',bg2:'#c23a08',ink:'#1A0A00',art:'coins',k:'Your funds'}, code:{bg:'#3DF2FF',bg2:'#1aa7c4',ink:'#0B0B10',art:'shield',k:'Sign in'}, ticket:{bg:'#C6FF3D',bg2:'#8fd81c',ink:'#0B0B10',art:'tickets',k:'Your tickets'}, mail:{bg:'#FF6A1A',bg2:'#c23a08',ink:'#1A0A00',art:'mail',k:'From the team'}, info:{bg:'#FF6A1A',bg2:'#c23a08',ink:'#1A0A00',art:'tickets',k:'InstantWins'} }[kind];
  body=String(body||'')
    .replace(/<p>/g,'<p style="margin:0 0 14px;font:400 16px/1.55 '+F+';color:#d6d8e0">')
    .replace(/<b>/g,'<b style="color:#ffffff;font-weight:700">')
    .replace(/<a class="btn" href="([^"]+)">/g,'<a href="$1" style="display:inline-block;margin:6px 0 10px;padding:14px 26px;border-radius:999px;background:#FF6A1A;color:#1A0A00;font:800 16px '+F+';text-decoration:none">')
    .replace(/<a href="([^"]+)">/g,'<a href="$1" style="color:#3DF2FF;text-decoration:none;font-weight:600">')
    .replace(/<code>/g,'<code style="display:inline-block;padding:14px 22px;border-radius:12px;background:#0B0B10;border:1px solid #2a2a36;color:#C6FF3D;font:800 30px/1 Courier,monospace;letter-spacing:.25em">');
  const headline=esc(sub).replace(/ on InstantWins$/,'');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><style>:root{color-scheme:dark;supported-color-schemes:dark}body{background:#0B0B10!important}</style></head>
<body style="margin:0;padding:0;background:#0B0B10" bgcolor="#0B0B10">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" bgcolor="#0B0B10" style="background:#0B0B10"><tr><td align="center" style="padding:26px 14px 32px">
<table role="presentation" width="560" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;width:100%">
<tr><td style="padding:0 4px 16px"><a href="${SITE}" style="text-decoration:none"><img src="${SITE}/mail/logo.png" width="180" height="42" alt="InstantWins" style="display:block;border:0;width:180px;height:42px"></a></td></tr>
<tr><td bgcolor="${K.bg}" background="${SITE}/mail/${K.art}.png" style="background:${K.bg} url('${SITE}/mail/${K.art}.png') no-repeat right -20px top -10px;background-size:210px auto;border-radius:22px 22px 0 0;padding:30px 28px 26px">
  <div style="font:800 11px ${F};letter-spacing:.18em;text-transform:uppercase;color:${K.ink};opacity:.7;margin:0 0 10px">${K.k}</div>
  <h1 style="margin:0;padding-right:110px;font:900 30px/1.1 ${F};color:${K.ink};letter-spacing:-.02em">${headline}</h1>
</td></tr>
<tr><td bgcolor="#15151D" style="background:#15151D;border:1px solid #262633;border-top:0;border-radius:0 0 22px 22px;padding:26px 28px 20px">
  ${body}
</td></tr>
<tr><td style="padding:22px 6px 0">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr>
    <td width="33%" style="padding:0 4px 0 0"><a href="${SITE}/account.html" style="display:block;background:#15151D;border:1px solid #262633;border-radius:14px;padding:14px 12px;text-decoration:none;font:800 13px ${F};color:#ffffff;text-align:center">My account</a></td>
    <td width="33%" style="padding:0 4px"><a href="${SITE}/game.html?g=quick" style="display:block;background:#15151D;border:1px solid #262633;border-radius:14px;padding:14px 12px;text-decoration:none;font:800 13px ${F};color:#ffffff;text-align:center">Reveal</a></td>
    <td width="33%" style="padding:0 0 0 4px"><a href="${SITE}/free.html" style="display:block;background:#15151D;border:1px solid #262633;border-radius:14px;padding:14px 12px;text-decoration:none;font:800 13px ${F};color:#ffffff;text-align:center">Free entry</a></td>
  </tr></table>
</td></tr>
<tr><td style="padding:22px 8px 0;font:400 12px/1.6 ${F};color:#7c8190">
  <a href="${SITE}/support.html" style="color:#9aa0ad;text-decoration:none">Support</a> &nbsp;&middot;&nbsp; <a href="${SITE}/responsible-play.html" style="color:#9aa0ad;text-decoration:none">Responsible play</a> &nbsp;&middot;&nbsp; <a href="${SITE}/terms.html" style="color:#9aa0ad;text-decoration:none">Terms</a><br><br>
  InstantWins.co.uk is operated by IGX Ltd, company no. 13057559, 20-22 Wenlock Road, London N1 7GU. Prize competitions with a free postal entry route under Schedule 2 of the Gambling Act 2005. 18+, Great Britain only. Prizes are a matter of luck and most tickets win nothing &mdash; please play within your means. GamCare 0808 8020 133.<br><br>
  Sent to ${esc(to)} because you have an InstantWins account.
</td></tr>
</table></td></tr></table></body></html>`;
}
