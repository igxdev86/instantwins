// api/c2.js — Million Round: GET -> round state; POST {action:'buy',n} | {action:'reveal'} | {action:'revealall'} | {action:'mine'} | {action:'accept_terms'} | {action:'profile'} with token
import { env, rpc, ip, allow, flushMail, friendly } from './_lib.js';
export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
    const a = b.action;
    if (a === 'buy') { if (!await allow(e, 'buy:' + token, 30, 60)) return res.status(429).json({ error: 'slow down a moment' }); const n = parseInt(b.n, 10); if (![1,5,10,25,50,100].includes(n)) return res.status(400).json({ error: 'pick a pack' }); r = await rpc(e, 'c2_buy', { p_token: token, p_n: n }); }
    else if (a === 'reveal') { if (!await allow(e, 'rev:' + token, 400, 60)) return res.status(429).json({ error: 'slow down a moment' }); r = await rpc(e, 'c2_reveal', { p_token: token }); }
    else if (a === 'revealall') r = await rpc(e, 'c2_reveal_all', { p_token: token });
    else if (a === 'mine') r = await rpc(e, 'c2_mine', { p_token: token });
    else if (a === 'accept_terms') r = await rpc(e, 'iw_accept_terms', { p_token: token });
    else if (a === 'profile') r = await rpc(e, 'iw_set_profile', { p_token: token, p_county: String(b.county || '').slice(0, 40), p_publish: b.publish !== false });
    else return res.status(400).json({ error: 'bad request' });
    if (a === 'buy' || a === 'revealall') { flushMail(e, 5).catch(() => {}); }
  } else {
    if (!await allow(e, 'state:' + ip(req), 120, 60)) return res.status(429).json({ error: 'slow down' });
    r = await rpc(e, 'c2_state', {});
  }
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  return res.status(200).json(data === null ? { ok: true } : data);
}
