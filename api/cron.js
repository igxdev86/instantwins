// api/cron.js — settlement + email outbox. Called by Vercel Cron (Authorization: Bearer CRON_SECRET) and opportunistically by other routes.
import { env, rpc, flushMail } from './_lib.js';
export default async function handler(req, res) {
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.authorization !== 'Bearer ' + secret) return res.status(401).json({ error: 'no' });
  const e = env(res); if (!e) return;
  let settle = null; try { const r = await rpc(e, 'c2_settle', {}); settle = r.ok ? await r.json() : { error: (await r.json()).message }; } catch (x) { settle = { error: String(x.message || x) }; }
  const mail = await flushMail(e, 50);
  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json({ settle, mail, at: new Date().toISOString() });
}
