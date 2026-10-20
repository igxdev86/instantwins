// api/results.js — public winners feed (read-only).
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const r = await fetch(URL + '/rest/v1/rpc/iw_results', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: '{}' });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  return res.status(r.ok ? 200 : 500).json(data);
}
