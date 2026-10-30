// api/card.js — the Card's serving hatch.
// GET  -> board state (settles any past-due draws first, lazily)
// POST {action:'mine', token} -> the signed-in player's upcoming entries
// Entries are placed through /api/play.
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const H = { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY };
  const rpc = (fn, body) => fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST', headers: H, body: JSON.stringify(body || {}) });
  let r;
  if (req.method === 'POST') {
    let body = req.body;
    if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = {}; } }
    const token = String((body && body.token) || '');
    if (!token || (body && body.action) !== 'mine') return res.status(400).json({ error: 'bad request' });
    r = await rpc('card_mine', { p_token: token });
  } else {
    r = await rpc('card_state', {});
  }
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
