// api/cashflows.js — card deposits via the Cashflows Hosted Payment Page (developer.cashflows.com).
// Env (Vercel): CASHFLOWS_CONFIG_ID, CASHFLOWS_API_KEY, CASHFLOWS_ENV = 'int' (sandbox, default) | 'live'
// Flow: POST {action:'start', token, amount}  -> creates a card_payments row + Cashflows payment job, returns {url} to send the player to.
//       POST (from Cashflows webhook, no token) {notifyType, paymentJobReference, paymentReference} -> we fetch the payment and credit the ledger when Paid.
//       POST {action:'check', token, job}      -> same verification when the player lands back on account.html (instant credit, webhook is the backstop).
//       GET                                   -> {enabled, env}
import { createHash } from 'crypto';

const BASE = () => (process.env.CASHFLOWS_ENV === 'live' ? 'https://gateway.cashflows.com' : 'https://gateway-int.cashflows.com');
const CFG = () => ({ id: process.env.CASHFLOWS_CONFIG_ID || '', key: process.env.CASHFLOWS_API_KEY || '' });
const hash = (key, body) => createHash('sha512').update(key + body, 'utf8').digest('hex');

async function cf(method, path, bodyObj) {
  const { id, key } = CFG(); const body = bodyObj ? JSON.stringify(bodyObj) : '';
  const r = await fetch(BASE() + path, { method, headers: { 'Content-Type': 'application/json', ConfigurationId: id, Hash: hash(key, body) }, body: body || undefined });
  const txt = await r.text(); let j = null; try { j = JSON.parse(txt); } catch { j = { raw: txt }; }
  return { ok: r.ok, status: r.status, j };
}
function env(res) { const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL; if (!KEY || !URL) { res.status(503).json({ error: 'backend not connected' }); return null; } return { KEY, URL }; }
function rpc(e, fn, body) { return fetch(e.URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: e.KEY, Authorization: 'Bearer ' + e.KEY }, body: JSON.stringify(body || {}) }); }
async function rpcJ(e, fn, body) { const r = await rpc(e, fn, body); const j = await r.json(); if (!r.ok) throw new Error((j && (j.message || j.hint)) || 'database error'); return j; }
const siteOf = req => { const h = req.headers['x-forwarded-host'] || req.headers.host || 'instantwins.co.uk'; return 'https://' + h; };

// Verify one payment with Cashflows and credit it. Idempotent (iw_card_paid ignores repeats).
async function settle(e, jobRef, payRef) {
  const r = await cf('GET', `/api/gateway/payment-jobs/${encodeURIComponent(jobRef)}/payments/${encodeURIComponent(payRef)}`);
  if (!r.ok) return { ok: false, error: 'cashflows ' + r.status };
  const d = r.j && (r.j.data || r.j); const status = String(d.status || d.paymentStatus || '');
  const amount = d.amountToCollect != null ? Math.round(parseFloat(d.amountToCollect) * 100) : null;
  const order = (d.order && d.order.orderNumber) || d.orderNumber || null;
  const out = await rpcJ(e, 'iw_card_update', { p_job: jobRef, p_pay: payRef, p_order: order, p_status: status, p_amount_p: amount });
  return { ok: true, status, credited: out && out.credited, balance_p: out && out.balance_p };
}

export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  const enabled = !!(CFG().id && CFG().key);
  if (req.method === 'GET') { res.setHeader('Cache-Control', 'no-store'); return res.status(200).json({ enabled, env: process.env.CASHFLOWS_ENV === 'live' ? 'live' : 'int' }); }
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } } b = b || {};

  // Cashflows webhook (no token; we trust nothing in it — we look the payment up ourselves)
  if (!b.token && b.paymentJobReference) {
    if (!enabled) return res.status(503).json({ error: 'not configured' });
    try { await settle(e, String(b.paymentJobReference), String(b.paymentReference || '')); } catch (err) { console.error('cashflows webhook', err.message); }
    return res.status(200).json({ ok: true });
  }

  const token = String(b.token || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
  if (!enabled) return res.status(503).json({ error: 'card payments are not set up yet' });

  if (b.action === 'start') {
    const amt = Math.round(parseFloat(b.amount) * 100);
    if (!(amt >= 500 && amt <= 50000)) return res.status(400).json({ error: 'amount must be £5 to £500' });
    let row; try { row = await rpcJ(e, 'iw_card_start', { p_token: token, p_amount_p: amt }); } catch (err) { return res.status(400).json({ error: err.message }); }
    const site = siteOf(req);
    const job = { type: 'Payment', amountToCollect: (amt / 100).toFixed(2), currency: 'GBP', locale: 'en_GB',
      paymentMethodsToUse: ['Card'],
      order: { orderNumber: row.ref, billingAddress: { firstName: row.first || '', lastName: row.last || '' }, billingIdentity: { emailAddress: row.email || '' } },
      parameters: { ReturnUrlSuccess: site + '/account.html?pay=ok', ReturnUrlFailed: site + '/account.html?pay=failed', ReturnUrlCancelled: site + '/account.html?pay=cancelled', WebhookUrl: site + '/api/cashflows', Descriptor: 'INSTANTWINS' } };
    const r = await cf('POST', '/api/gateway/payment-jobs', job);
    if (!r.ok) { await rpc(e, 'iw_card_fail', { p_ref: row.ref, p_note: 'cashflows ' + r.status + ' ' + JSON.stringify(r.j).slice(0, 300) }); return res.status(502).json({ error: 'card payment could not be started (' + r.status + ')' }); }
    const url = r.j && r.j.links && r.j.links.action && r.j.links.action.url; const jobRef = r.j && r.j.data && r.j.data.reference; const payRef = r.j && r.j.data && r.j.data.payments && r.j.data.payments[0] && r.j.data.payments[0].reference;
    await rpc(e, 'iw_card_link', { p_ref: row.ref, p_job: jobRef || '', p_pay: payRef || '' });
    if (!url) return res.status(502).json({ error: 'no payment page returned' });
    return res.status(200).json({ url, ref: row.ref });
  }
  if (b.action === 'check') {
    const jobRef = String(b.job || ''); if (!jobRef) return res.status(400).json({ error: 'job?' });
    let pay; try { pay = await rpcJ(e, 'iw_card_lookup', { p_token: token, p_job: jobRef }); } catch (err) { return res.status(400).json({ error: err.message }); }
    try { const out = await settle(e, jobRef, pay.pay_ref || ''); return res.status(200).json(out); } catch (err) { return res.status(502).json({ error: err.message }); }
  }
  return res.status(400).json({ error: 'unknown action' });
}
