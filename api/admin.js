// api/admin.js — admin console. Server verifies is_admin on every call.
const MAP = { stats:'iw_admin_stats', users:'iw_admin_users', threads:'iw_admin_threads',
              thread:'iw_admin_thread', reply:'iw_admin_reply', announce:'iw_admin_announce',
              aff_list:'iw_admin_aff_list', aff_create:'iw_admin_aff_create', aff_update:'iw_admin_aff_update',
              setbal:'iw_admin_my_balance', postal:'iw_admin_postal_enter', postal_no:'iw_admin_postal_enter_no', kinds:'iw_admin_kinds', kindset:'iw_admin_kind_active',
              payments:'iw_admin_payments', depdecide:'iw_admin_deposit_decide', wddecide:'iw_admin_withdraw_decide', setting:'iw_admin_setting', golive:'iw_go_live', tickets:'iw_admin_tickets', ticketset:'iw_admin_ticket_active',
              comps:'iw_admin_comps', compcreate:'iw_admin_comp_create', comppostal:'iw_admin_comp_postal', postal_ticket:'iw_admin_postal_ticket', kindroll:'iw_admin_kind_rollover', itemcreate:'iw_admin_item_create', itemclaims:'iw_admin_item_claims', itemclaimset:'iw_admin_item_claim_set', postal_mil:'iw_admin_postal_mil', postal_reject:'iw_admin_postal_reject', postal_log:'iw_admin_postal_log', milstats:'iw_admin_mil_stats', milset:'iw_admin_mil_set', milclose:'iw_admin_mil_close' };
import { flushMail } from './_lib.js';
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
  if (['depdecide','wddecide','postal_mil','announce'].includes(b.action)) flushMail({ KEY, URL }, 10).catch(() => {});
  return res.status(200).json(data);
}

function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
