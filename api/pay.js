// api/pay.js — bank-transfer deposits and withdrawals (manual approval in admin).
// Bank details come from Vercel env vars, never from the repo:
//   IGX_BANK_NAME, IGX_ACCOUNT_NAME, IGX_SORT_CODE, IGX_ACCOUNT_NO
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
  const bank = { bank: process.env.IGX_BANK_NAME || '', name: process.env.IGX_ACCOUNT_NAME || 'IGX Ltd',
                 sort: process.env.IGX_SORT_CODE || '', acct: process.env.IGX_ACCOUNT_NO || '' };
  let fn, args;
  if (b.action === 'mine')          { fn = 'iw_my_payments';     args = { p_token: token }; }
  else if (b.action === 'deposit')  { fn = 'iw_deposit_request'; args = { p_token: token, p_amount_p: Math.round(parseFloat(b.amount) * 100) || 0 }; }
  else if (b.action === 'withdraw') { fn = 'iw_withdraw_request'; args = { p_token: token, p_amount_p: Math.round(parseFloat(b.amount) * 100) || 0,
                                       p_name: String(b.name || ''), p_sort: String(b.sort || ''), p_acct: String(b.acct || '') }; }
  else return res.status(400).json({ error: 'bad action' });
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, { method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY }, body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  if (b.action === 'mine' || b.action === 'deposit') data.bank = bank;
  return res.status(200).json(data);
}
