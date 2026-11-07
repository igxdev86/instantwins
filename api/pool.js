// api/pool.js — the read-only serving hatch.
// Asks Supabase for the current pool's counter for one game.
// Zero dependencies. Keys come from the Supabase<->Vercel integration.

export default async function handler(req, res) {
  const game = String(req.query.game || '').toUpperCase();
  if (!/^[A-Z0-9]{2,4}$/.test(game)) {
    return res.status(400).json({ error: 'unknown game' });
  }
  const mult = 1; // flat price — stake multipliers withdrawn
  const r = await fetch(process.env.SUPABASE_URL + '/rest/v1/rpc/pool_state', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: 'Bearer ' + process.env.SUPABASE_SERVICE_ROLE_KEY,
    },
    body: JSON.stringify({ p_game: game, p_mult: mult }),
  });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  return res.status(r.ok ? 200 : 500).json(data);
}
