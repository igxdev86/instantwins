// api/inbound.js — Resend Receiving webhook. Any email sent to @instantwins.co.uk lands in the admin support inbox.
// Env: RESEND_API_KEY (to fetch the full email), RESEND_WEBHOOK_SECRET (whsec_…, optional but recommended — Svix signature check).
import { createHmac, timingSafeEqual } from 'crypto';
export const config = { api: { bodyParser: false } };

function raw(req){ return new Promise((res,rej)=>{ let d=''; req.setEncoding('utf8'); req.on('data',c=>d+=c); req.on('end',()=>res(d)); req.on('error',rej); }); }
function verify(req, body){ const sec=process.env.RESEND_WEBHOOK_SECRET; if(!sec) return true;
  const id=req.headers['svix-id'], ts=req.headers['svix-timestamp'], sig=req.headers['svix-signature']; if(!id||!ts||!sig) return false;
  if(Math.abs(Date.now()/1000 - Number(ts)) > 300) return false;
  const key=Buffer.from(String(sec).replace(/^whsec_/,''),'base64'); const want=createHmac('sha256',key).update(`${id}.${ts}.${body}`).digest('base64');
  return String(sig).split(' ').some(p=>{ const v=p.split(',')[1]||''; try{ return v.length===want.length && timingSafeEqual(Buffer.from(v),Buffer.from(want)); }catch{ return false; } }); }
function env(res){ const KEY=process.env.SUPABASE_SERVICE_ROLE_KEY, URL=process.env.SUPABASE_URL; if(!KEY||!URL){ res.status(503).json({error:'backend not connected'}); return null; } return {KEY,URL}; }
function rpc(e, fn, body){ return fetch(e.URL+'/rest/v1/rpc/'+fn,{method:'POST',headers:{'Content-Type':'application/json',apikey:e.KEY,Authorization:'Bearer '+e.KEY},body:JSON.stringify(body||{})}); }
// Keep only what the person typed: drop quoted replies and signatures.
function clean(text, html){ let t=text||''; if(!t&&html){ t=String(html).replace(/<style[\s\S]*?<\/style>/gi,'').replace(/<br\s*\/?>/gi,'\n').replace(/<\/(p|div|tr|li|h\d)>/gi,'\n').replace(/<[^>]+>/g,'').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&#39;|&apos;/g,"'").replace(/&quot;/g,'"'); }
  const lines=t.replace(/\r/g,'').split('\n'); const out=[];
  for(const l of lines){ if(/^\s*>/.test(l)) break; if(/^On .+wrote:\s*$/.test(l.trim())) break; if(/^-{2,}\s*Original Message/i.test(l.trim())) break; if(/^From: .+$/.test(l.trim())&&out.length) break; if(/^-- $/.test(l)) break; out.push(l); }
  return out.join('\n').replace(/\n{3,}/g,'\n\n').trim(); }
function parseFrom(h){ const m=/^(.*?)\s*<([^>]+)>\s*$/.exec(String(h||'').trim()); return m?{name:m[1].replace(/^"|"$/g,'').trim(),email:m[2].trim()}:{name:'',email:String(h||'').trim()}; }

export default async function handler(req, res){
  if(req.method!=='POST') return res.status(405).json({error:'POST only'});
  const body=await raw(req); if(!verify(req, body)) return res.status(401).json({error:'bad signature'});
  let ev={}; try{ ev=JSON.parse(body); }catch{ return res.status(400).json({error:'bad json'}); }
  if(ev.type!=='email.received') return res.status(200).json({ok:true,ignored:ev.type});
  const e=env(res); if(!e) return;
  const RK=process.env.RESEND_API_KEY; if(!RK) return res.status(503).json({error:'no key'});
  const id=ev.data&&ev.data.email_id; if(!id) return res.status(400).json({error:'no id'});
  const r=await fetch('https://api.resend.com/emails/receiving/'+encodeURIComponent(id),{headers:{Authorization:'Bearer '+RK}});
  if(!r.ok) return res.status(502).json({error:'fetch '+r.status});
  const m=await r.json();
  const from=parseFrom((m.headers&&m.headers.from)||m.from);
  if(/mailer-daemon|postmaster|no-?reply|noreply|notifications?@/i.test(from.email)) return res.status(200).json({ok:true,ignored:'automated'});
  const auto=(m.headers&&(m.headers['auto-submitted']||m.headers['x-autoreply']||m.headers['x-auto-response-suppress']))||''; if(auto&&!/^no$/i.test(auto)) return res.status(200).json({ok:true,ignored:'auto-reply'});
  const text=clean(m.text, m.html);
  const out=await rpc(e,'iw_inbound_mail',{p_from:from.email,p_name:from.name,p_subject:String(m.subject||'').slice(0,200),p_body:text,p_msg_id:m.message_id||null,p_resend_id:id});
  const j=await out.json().catch(()=>({}));
  if(!out.ok) return res.status(500).json({error:(j&&j.message)||'db'});
  // tell the admin
  const notify=process.env.MAIL_ADMIN_TO; if(notify){ try{ await fetch('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+RK},body:JSON.stringify({from:process.env.MAIL_FROM||'InstantWins <hello@instantwins.co.uk>',to:[notify],subject:'Support: '+(from.name||from.email)+' — '+(m.subject||'(no subject)'),text:text+'\n\n— open in admin: https://instantwins.co.uk/admin.html#support'})}); }catch{} }
  return res.status(200).json({ok:true,id:j.id});
}
