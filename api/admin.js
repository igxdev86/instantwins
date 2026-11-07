// api/admin.js — admin console. Server verifies is_admin on every call.
const MAP = { stats:'iw_admin_stats', users:'iw_admin_users', threads:'iw_admin_threads',
              thread:'iw_admin_thread', reply:'iw_admin_reply', announce:'iw_admin_announce',
              aff_list:'iw_admin_aff_list', aff_create:'iw_admin_aff_create', aff_update:'iw_admin_aff_update',
              setbal:'iw_admin_my_balance', postal:'iw_admin_postal_enter', postal_no:'iw_admin_postal_enter_no', kinds:'iw_admin_kinds', kindset:'iw_admin_kind_active',
              payments:'iw_admin_payments', depdecide:'iw_admin_deposit_decide', wddecide:'iw_admin_withdraw_decide', setting:'iw_admin_setting', golive:'iw_go_live', tickets:'iw_admin_tickets', ticketset:'iw_admin_ticket_active' };
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
  if (b.action === 'kindset') { args.p_kind=b.kind?String(b.kind):null; args.p_step=b.step!=null?parseInt(b.step,10):null; args.p_active=!!b.active; }
  if (b.action === 'postal_no') { args.p_email=String(b.email||''); args.p_game_no=String(b.game_no||''); }
  if (b.action === 'postal') { args.p_email=String(b.email||''); args.p_kind=String(b.kind||'five'); args.p_off_at=b.off_at?new Date(b.off_at).toISOString():null; }
  if (b.action === 'setbal') { args.p_target_p = parseInt(b.amount_p,10)||0; }
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
