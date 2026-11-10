// api/prize.js — GET ?s=slug -> one prize round; POST {action:'claims'|'swap', token, claim_id, address}
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const H = { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY };
  const rpc = (fn, body) => fetch(URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: H, body: JSON.stringify(body || {}) });
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
    if (b.action === 'claims') r = await rpc('iw_my_claims', { p_token: token });
    else if (b.action === 'swap') r = await rpc('iw_item_swap', { p_token: token, p_claim: parseInt(b.claim_id, 10) || 0, p_address: String(b.address || '').slice(0, 400) });
    else return res.status(400).json({ error: 'bad request' });
  } else {
    const slug = String((req.query && req.query.s) || '').toLowerCase();
    if (!/^[a-z0-9-]{2,60}$/.test(slug)) return res.status(400).json({ error: 'bad slug' });
    r = await rpc('iw_prize', { p_slug: slug });
  }
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  return res.status(200).json(data);
}
function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
