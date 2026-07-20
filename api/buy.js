// api/buy.js — the buy hatch. TEST MODE: no payment, no login yet.
// Takes the next numbered entry in the game's open pool and returns
// its pre-set prize. Settles the pool + reveals the seed on sell-out.
// DO NOT share the site publicly until Stripe + accounts are wired in.
const TAGS = ['PL','RC','DD','CL','SC','PR','PF','BB','PP','HL','CG'];

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST only' });
  }
  let body = req.body;
  if (typeof body === 'string') { try { body = JSON.parse(body); } catch { body = {}; } }
  const game = String((body && body.game) || '').toUpperCase();
  if (!TAGS.includes(game)) {
    return res.status(400).json({ error: 'unknown game' });
  }
  const r = await fetch(process.env.SUPABASE_URL + '/rest/v1/rpc/buy_entry', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: 'Bearer ' + process.env.SUPABASE_SERVICE_ROLE_KEY,
    },
    body: JSON.stringify({ p_game: game }),
  });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  return res.status(r.ok ? 200 : 500).json(data);
}
