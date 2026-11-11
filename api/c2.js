// api/c2.js — Concept 2: GET -> round state; POST {action:'buy',n} | {action:'reveal'} | {action:'mine'} with token
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const H = { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY };
  const rpc = (fn, body) => fetch(URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: H, body: JSON.stringify(body || {}) });
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || ''); if (!token) return res.status(401).json({ error: 'sign in first' });
    if (b.action === 'buy') { const n = parseInt(b.n, 10); if (![1,5,10,25,50,100].includes(n)) return res.status(400).json({ error: 'pick a pack' }); r = await rpc('c2_buy', { p_token: token, p_n: n }); }
    else if (b.action === 'reveal') r = await rpc('c2_reveal', { p_token: token });
    else if (b.action === 'revealall') r = await rpc('c2_reveal_all', { p_token: token });
    else if (b.action === 'mine') r = await rpc('c2_mine', { p_token: token });
    else return res.status(400).json({ error: 'bad request' });
  } else r = await rpc('c2_state', {});
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  return res.status(200).json(data);
}
function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
