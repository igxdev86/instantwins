// api/results.js — public winners feed + published seeds of closed Million Rounds (read-only).
import { env, rpc } from './_lib.js';
export default async function handler(req, res) {
  const e = env(res); if (!e) return;
  const r = await rpc(e, 'c2_results', {});
  const d = await r.json();
  res.setHeader('Cache-Control', 's-maxage=30, stale-while-revalidate=120');
  if (!r.ok) return res.status(400).json({ error: 'service temporarily unavailable' });
  return res.status(200).json(d);
}
