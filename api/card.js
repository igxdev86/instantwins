// api/card.js — the Card's serving hatch.
// GET  -> board state (settles any past-due draws first, lazily)
// POST -> enter a draw {kind:'five'|'grand', punter:'anon-id'}
// TEST MODE: entries are free until Stripe + accounts are wired in.
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
    const kind = body && body.kind;
    const punter = String((body && body.punter) || '');
    if (kind !== 'five' && kind !== 'grand') return res.status(400).json({ error: 'bad kind' });
    if (!/^[a-z0-9-]{6,40}$/i.test(punter)) return res.status(400).json({ error: 'bad punter' });
    r = await rpc('card_enter', { p_kind: kind, p_punter: punter });
  } else {
    r = await rpc('card_state', {});
  }
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  return res.status(r.ok ? 200 : 500).json(data);
}
