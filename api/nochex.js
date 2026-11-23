// api/nochex.js — debit-card deposits via the Nochex hosted Payment Page (ssl.nochex.com/docs/Payment-page-int) + APC callback.
// Env (Vercel): NOCHEX_MERCHANT_ID (the Nochex merchant id / account email), optional NOCHEX_TEST=1 (sends test_transaction=100: no money moves).
//   On-page (CopyandPay, ssl.nochex.com/docs/On-page): NOCHEX_ENTITY_ID + NOCHEX_BEARER. When both are set the card form is shown inside our
//   deposit modal and the result is verified server-to-server (GET /v1/checkouts/{id}/payment) — no dependency on the APC. NOCHEX_TEST=1 -> eu-test.oppwa.com.
// Flow: POST {action:'start', token, amount} -> card_payments row (iw_card_start) + the fields for an auto-submitting form to https://secure.nochex.com/
//       POST from Nochex (APC, form-encoded, no token) -> we post the exact body back to Nochex, credit only on "AUTHORISED" (iw_card_update, idempotent)
//       POST {action:'check', token, ref}      -> current status from our table (the APC is the only thing that credits)
//       GET                                   -> {enabled, env}
const PAGE = 'https://secure.nochex.com/';
const VERIFY = 'https://secure.nochex.com/callback/callback.aspx';
const MID = () => (process.env.NOCHEX_MERCHANT_ID || '').trim();
const TEST = () => !!process.env.NOCHEX_TEST;
const OPP = () => (TEST() ? 'https://eu-test.oppwa.com' : 'https://eu-prod.oppwa.com');
const ENT = () => ({ id: (process.env.NOCHEX_ENTITY_ID || '').trim(), bearer: (process.env.NOCHEX_BEARER || '').trim() });
const ONPAGE = () => !!(ENT().id && ENT().bearer);
const OK_RE = /^(000\.000\.|000\.100\.1|000\.[36]|000\.400\.[1][12]0)/;   // ACI "successful" result codes
const PENDING_RE = /^(000\.200)/;

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
  if (req.method === 'GET') { res.setHeader('Cache-Control', 'no-store'); return res.status(200).json({ enabled: enabled || ONPAGE(), env: TEST() ? 'test' : 'live', onpage: ONPAGE(), widget: ONPAGE() ? OPP() + '/v1/paymentWidgets.js' : null }); }
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
  if (!enabled && !ONPAGE()) return res.status(503).json({ error: 'card payments are not set up yet' });

  // ---- on-page: create a checkout, the browser renders the card form from it ----
  if (b.action === 'checkout') {
    if (!ONPAGE()) return res.status(503).json({ error: 'on-page card form not configured' });
    const amt = Math.round(parseFloat(b.amount) * 100);
    if (!(amt >= 500 && amt <= 50000)) return res.status(400).json({ error: 'amount must be £5 to £500' });
    let row; try { row = await rpcJ(e, 'iw_card_start', { p_token: token, p_amount_p: amt }); } catch (err) { return res.status(400).json({ error: err.message }); }
    const p = new URLSearchParams({ entityId: ENT().id, amount: (amt / 100).toFixed(2), currency: 'GBP', paymentType: 'DB', merchantTransactionId: row.ref, 'customer.email': row.email || '' });
    if (row.first) p.set('customer.givenName', row.first); if (row.last) p.set('customer.surname', row.last);
    if (TEST() && process.env.NOCHEX_TESTMODE) p.set('testMode', process.env.NOCHEX_TESTMODE);   // INTERNAL (simulator) or EXTERNAL (acquirer test system)
    const r = await fetch(OPP() + '/v1/checkouts', { method: 'POST', headers: { Authorization: 'Bearer ' + ENT().bearer, 'Content-Type': 'application/x-www-form-urlencoded' }, body: p.toString() });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || !j.id) { await rpc(e, 'iw_card_fail', { p_ref: row.ref, p_note: 'checkout ' + r.status + ' ' + JSON.stringify(j.result || j).slice(0, 300) }); return res.status(502).json({ error: 'card form could not be started' }); }
    await rpc(e, 'iw_card_link', { p_ref: row.ref, p_job: j.id, p_pay: '' });
    return res.status(200).json({ checkoutId: j.id, widget: OPP() + '/v1/paymentWidgets.js?checkoutId=' + encodeURIComponent(j.id), ref: row.ref, test: TEST() });
  }
  // ---- on-page: the shopper is back with ?id=<checkoutId>; ask the gateway what happened and credit if paid ----
  if (b.action === 'result') {
    if (!ONPAGE()) return res.status(503).json({ error: 'not configured' });
    const id = String(b.id || ''); if (!id) return res.status(400).json({ error: 'id?' });
    let pay; try { pay = await rpcJ(e, 'iw_card_lookup', { p_token: token, p_job: id }); } catch (err) { return res.status(400).json({ error: err.message }); }
    if (pay.status === 'paid') return res.status(200).json({ ok: true, status: 'paid', credited: false });
    const r = await fetch(OPP() + '/v1/checkouts/' + encodeURIComponent(id) + '/payment?entityId=' + encodeURIComponent(ENT().id), { headers: { Authorization: 'Bearer ' + ENT().bearer } });
    const j = await r.json().catch(() => ({}));
    const code = String((j.result && j.result.code) || ''); const desc = String((j.result && j.result.description) || '');
    if (OK_RE.test(code)) {
      const amount = j.amount != null ? Math.round(parseFloat(j.amount) * 100) : null;
      try { const out = await rpcJ(e, 'iw_card_update', { p_job: id, p_pay: String(j.id || ''), p_order: pay.ref, p_status: 'Paid', p_amount_p: amount }); return res.status(200).json({ ok: true, status: 'paid', credited: out.credited, balance_p: out.balance_p }); }
      catch (err) { return res.status(502).json({ error: err.message }); }
    }
    if (PENDING_RE.test(code)) return res.status(200).json({ ok: true, status: 'pending', code });
    await rpc(e, 'iw_card_fail', { p_ref: pay.ref, p_note: (code + ' ' + desc).slice(0, 400) });
    return res.status(200).json({ ok: true, status: 'failed', code, reason: desc });
  }

  if (b.action === 'start') {
    if (!enabled) return res.status(503).json({ error: 'hosted page not configured' });
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
