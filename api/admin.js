// api/admin.js — admin console. Server verifies is_admin on every call.
const MAP = { stats:'iw_admin_stats', users:'iw_admin_users', threads:'iw_admin_threads',
              thread:'iw_admin_thread', reply:'iw_admin_reply', announce:'iw_admin_announce',
              aff_list:'iw_admin_aff_list', aff_create:'iw_admin_aff_create', aff_update:'iw_admin_aff_update',
              setbal:'iw_admin_my_balance', postal:'iw_admin_postal_enter', postal_no:'iw_admin_postal_enter_no', kinds:'iw_admin_kinds', kindset:'iw_admin_kind_active',
              payments:'iw_admin_payments', cardpay:'iw_admin_card_payments', inboxcount:'iw_admin_inbox_count', mailone:'iw_admin_mail_one', mailall:'iw_admin_mail_all', mailcounts:'iw_admin_mail_counts', depdecide:'iw_admin_deposit_decide', wddecide:'iw_admin_withdraw_decide', setting:'iw_admin_setting', golive:'iw_go_live', tickets:'iw_admin_tickets', ticketset:'iw_admin_ticket_active',
              comps:'iw_admin_comps', compcreate:'iw_admin_comp_create', comppostal:'iw_admin_comp_postal', postal_ticket:'iw_admin_postal_ticket', kindroll:'iw_admin_kind_rollover', itemcreate:'iw_admin_item_create', itemclaims:'iw_admin_item_claims', itemclaimset:'iw_admin_item_claim_set', postal_mil:'iw_admin_postal_mil', postal_reject:'iw_admin_postal_reject', postal_log:'iw_admin_postal_log', milstats:'iw_admin_mil_stats', milset:'iw_admin_mil_set', milclose:'iw_admin_mil_close', games:'iw_admin_games', skillq:'iw_admin_skillq', credit:'iw_admin_credit' };
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const token = String((b && b.token) || '');
  const fn = MAP[b && b.action];
  if (!token || !fn) return res.status(400).json({ error: 'bad request' });
  const args = { p_token: token };
  if (b.action === 'mailone') { args.p_to=String(b.to||''); args.p_subject=String(b.subject||''); args.p_body=String(b.body||''); }
  if (b.action === 'mailall') { args.p_subject=String(b.subject||''); args.p_body=String(b.body||''); args.p_audience=['all','buyers','test'].includes(b.audience)?b.audience:'all'; }
  if (b.action === 'thread') args.p_key = String(b.key||b.user_id||'');
  if (b.action === 'reply') { args.p_key = String(b.key||b.user_id||''); args.p_body = String(b.body||''); }
  if (b.action === 'announce') { args.p_title = String(b.title||''); args.p_body = String(b.body||''); }
  if (b.action === 'aff_create') { args.p_name=String(b.name||''); args.p_email=String(b.email||''); args.p_code=String(b.code||''); args.p_model='cpa' /* rev-share withdrawn */; args.p_rate=parseInt(b.rate,10)||0; }
  if (b.action === 'aff_update') { args.p_code=String(b.code||''); args.p_model=String(b.model||''); args.p_rate=(b.rate===''||b.rate==null)?null:parseInt(b.rate,10); args.p_status=String(b.status||''); }
  if (b.action === 'ticketset') { args.p_tag=b.tag?String(b.tag):null; args.p_tier=b.tier?String(b.tier):null; args.p_active=!!b.active; }
  if (b.action === 'depdecide') { args.p_id=parseInt(b.id,10); args.p_approve=!!b.approve; args.p_note=b.note?String(b.note):null; }
  if (b.action === 'wddecide') { args.p_id=parseInt(b.id,10); args.p_paid=!!b.paid; args.p_note=b.note?String(b.note):null; }
  if (b.action === 'setting') { args.p_key=String(b.key||''); args.p_value=String(b.value||''); }
  if (b.action === 'itemcreate') { ['tag','name','slug','category','item_name','blurb','about'].forEach(k=>args['p_'+k]=String(b[k]||'')); args.p_rrp_p=parseInt(b.rrp_p,10)||0; args.p_cashalt_p=parseInt(b.cashalt_p,10)||0; args.p_price_p=parseInt(b.price_p,10)||0; args.p_cap=parseInt(b.cap,10)||0; args.p_tiers=Array.isArray(b.tiers)?b.tiers:[]; args.p_faq=Array.isArray(b.faq)?b.faq:[]; }
  if (b.action === 'itemclaimset') { args.p_id=parseInt(b.id,10)||0; args.p_status=String(b.status||''); args.p_note=b.note?String(b.note):null; }
  if (b.action === 'kindroll') { args.p_kind=String(b.kind||''); args.p_on=!!b.on; }
  if (b.action === 'kindset') { args.p_kind=b.kind?String(b.kind):null; args.p_step=b.step!=null?parseInt(b.step,10):null; args.p_active=!!b.active; }
  if (b.action === 'postal_no') { args.p_email=String(b.email||''); args.p_game_no=String(b.game_no||''); }
  if (b.action === 'postal') { args.p_email=String(b.email||''); args.p_kind=String(b.kind||'five'); args.p_off_at=b.off_at?new Date(b.off_at).toISOString():null; }
  if (b.action === 'compcreate') { args.p_title=String(b.title||''); args.p_blurb=b.blurb?String(b.blurb):null; args.p_prize_p=parseInt(b.prize_p,10)||0; args.p_price_p=parseInt(b.price_p,10)||0; args.p_question=String(b.question||''); args.p_options=Array.isArray(b.options)?b.options.map(String).slice(0,6):[]; args.p_correct=parseInt(b.correct,10)||0; args.p_days=parseInt(b.days,10)||7; args.p_cap=b.cap?parseInt(b.cap,10):null; }
  if (b.action === 'postal_ticket') { args.p_ref=String(b.ref||''); args.p_tag=String(b.tag||'').toUpperCase().slice(0,4); }
  if (b.action === 'comppostal') { args.p_ref=String(b.ref||''); args.p_code=String(b.code||''); args.p_answer=parseInt(b.answer,10)||0; }
  if (b.action === 'postal_mil') { args.p_ref=String(b.ref||'').slice(0,120); args.p_note=b.note?String(b.note).slice(0,200):null; }
  if (b.action === 'credit') { args.p_ref=String(b.ref||'').slice(0,120); args.p_amount_p=parseInt(b.amount_p,10)||0; args.p_note=b.note?String(b.note).slice(0,120):null; }
  if (b.action === 'games') { args.p_on = b.on === true; } else if (b.action === 'skillq') { args.p_mode = ['off','round','each'].includes(b.mode)?b.mode:(b.on===true?'round':'off'); }
  if (b.action === 'milset') { args.p_closes_at=b.closes_at?String(b.closes_at):null; args.p_end_prize_p=(b.end_prize_p===null||b.end_prize_p===undefined||b.end_prize_p==='')?null:Math.max(0,parseInt(b.end_prize_p,10)||0); }
  if (b.action === 'postal_reject') { args.p_ref=String(b.ref||'').slice(0,120); args.p_reason=String(b.reason||'other').slice(0,60); args.p_note=b.note?String(b.note).slice(0,200):null; }
  if (b.action === 'setbal') { args.p_target_p = parseInt(b.amount_p,10)||0; }
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  if (['depdecide','wddecide','postal_mil','announce','reply','mailone'].includes(b.action)) flushMail({ KEY, URL }, 10).catch(() => {}); if (b.action === 'mailall') flushMail({ KEY, URL }, 50).catch(() => {});
  return res.status(200).json(data);
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
