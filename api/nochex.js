// api/nochex.js — debit-card deposits via the Nochex hosted Payment Page (ssl.nochex.com/docs/Payment-page-int) + APC callback.
// Env (Vercel): NOCHEX_MERCHANT_ID (the Nochex merchant id / account email), optional NOCHEX_TEST=1 (sends test_transaction=100: no money moves).
// Flow: POST {action:'start', token, amount} -> card_payments row (iw_card_start) + the fields for an auto-submitting form to https://secure.nochex.com/
//       POST from Nochex (APC, form-encoded, no token) -> we post the exact body back to Nochex, credit only on "AUTHORISED" (iw_card_update, idempotent)
//       POST {action:'check', token, ref}      -> current status from our table (the APC is the only thing that credits)
//       GET                                   -> {enabled, env}
const PAGE = 'https://secure.nochex.com/';
const VERIFY = 'https://secure.nochex.com/callback/callback.aspx';
const MID = () => (process.env.NOCHEX_MERCHANT_ID || '').trim();
const TEST = () => !!process.env.NOCHEX_TEST;

function env(res) { const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL; if (!KEY || !URL) { res.status(503).json({ error: 'backend not connected' }); return null; } return { KEY, URL }; }
function rpc(e, fn, body) { return fetch(e.URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: e.KEY, Authorization: 'Bearer ' + e.KEY }, body: JSON.stringify(body || {}) }); }
async function rpcJ(e, fn, body) { const r = await rpc(e, fn, body); const j = await r.json(); if (!r.ok) throw new Error((j && (j.message || j.hint)) || 'database error'); return j; }
const siteOf = req => { const h = req.headers['x-forwarded-host'] || req.headers.host || 'instantwins.co.uk'; return 'https://' + h; };

// Body parsing is off so the APC post-back to Nochex is the exact bytes they sent us.
export const config = { api: { bodyParser: false } };
function readRaw(req) { return new Promise((ok, no) => { let d = ''; req.setEncoding('utf8'); req.on('data', c => { d += c; }); req.on('end', () => ok(d)); req.on('error', no); }); }

export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  const enabled = !!MID();
  if (req.method === 'GET') { res.setHeader('Cache-Control', 'no-store'); return res.status(200).json({ enabled, env: TEST() ? 'test' : 'live' }); }
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const ct = String(req.headers['content-type'] || ''); const raw = await readRaw(req);

  // ---- APC callback from Nochex (form-encoded; never trusted until Nochex confirms it) ----
  if (!ct.includes('application/json')) {
    if (!enabled) return res.status(503).send('not configured');
    const f = Object.fromEntries(new URLSearchParams(raw));
    let verdict = '';
    try { const v = await fetch(VERIFY, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: raw }); verdict = (await v.text()).trim(); } catch (err) { console.error('nochex verify', err.message); }
    if (!/AUTHORISED/i.test(verdict)) { console.error('nochex APC not authorised', verdict, f.order_id); return res.status(200).send('DECLINED'); }
    if (String(f.merchant_id || f.to_email || '').toLowerCase() !== MID().toLowerCase()) { console.error('nochex APC wrong merchant', f.merchant_id); return res.status(200).send('WRONG MERCHANT'); }
    const isTest = String(f.transaction_status || '') === '100';
    if (isTest && !TEST()) { console.error('nochex test APC on live site', f.order_id); return res.status(200).send('TEST IGNORED'); }
    const amount = f.amount != null ? Math.round(parseFloat(f.amount) * 100) : null;
    try { await rpcJ(e, 'iw_card_update', { p_job: String(f.transaction_id || ''), p_pay: String(f.transaction_id || ''), p_order: String(f.order_id || ''), p_status: 'Paid', p_amount_p: amount }); }
    catch (err) { console.error('nochex APC apply', err.message, f.order_id); }
    return res.status(200).send('OK');
  }

  let b = {}; try { b = JSON.parse(raw || '{}'); } catch { b = {}; } b = b || {};
  const token = String(b.token || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
  if (!enabled) return res.status(503).json({ error: 'card payments are not set up yet' });

  if (b.action === 'start') {
    const amt = Math.round(parseFloat(b.amount) * 100);
    if (!(amt >= 500 && amt <= 50000)) return res.status(400).json({ error: 'amount must be £5 to £500' });
    let row; try { row = await rpcJ(e, 'iw_card_start', { p_token: token, p_amount_p: amt }); } catch (err) { return res.status(400).json({ error: err.message }); }
    const site = siteOf(req);
    const f = { merchant_id: MID(), amount: (amt / 100).toFixed(2), order_id: row.ref, description: 'InstantWins funds ' + row.ref,
      success_url: site + '/account.html?pay=ok&ref=' + encodeURIComponent(row.ref), cancel_url: site + '/account.html?pay=cancelled', callback_url: site + '/api/nochex',
      email_address: row.email || '', billing_fullname: [row.first, row.last].filter(Boolean).join(' '), optional_1: row.ref };
    if (TEST()) { f.test_transaction = '100'; f.test_success_url = f.success_url; }
    return res.status(200).json({ url: PAGE, fields: f, ref: row.ref });
  }
  if (b.action === 'check') {
    const ref = String(b.ref || ''); if (!ref) return res.status(400).json({ error: 'ref?' });
    let pay; try { pay = await rpcJ(e, 'iw_card_lookup_ref', { p_token: token, p_ref: ref }); } catch (err) { return res.status(400).json({ error: err.message }); }
    return res.status(200).json({ ok: true, status: pay.status, credited: pay.status === 'paid', balance_p: pay.balance_p });
  }
  return res.status(400).json({ error: 'unknown action' });
}
