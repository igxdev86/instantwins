// api/affiliate.js — affiliate self-serve stats by code (read-only).
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const code = String((b && b.code) || '').trim();
  if (!/^[a-z0-9_-]{2,40}$/i.test(code)) return res.status(400).json({ error: 'bad code' });
  const r = await fetch(URL + '/rest/v1/rpc/iw_aff_stats', {
    method: 'POST', headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify({ p_code: code }) });
  const d = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (d && d.message) || 'not found' });
  return res.status(200).json(d);
}
