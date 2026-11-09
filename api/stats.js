// api/stats.js — public live totals (real ledger data) for the home page.
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const r = await fetch(URL + '/rest/v1/rpc/iw_public_stats', { method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY }, body: '{}' });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  return res.status(200).json(data);
}

function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
