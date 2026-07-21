// api/pool.js — the read-only serving hatch.
// Asks Supabase for the current pool's counter for one game.
// Zero dependencies. Keys come from the Supabase<->Vercel integration.
const TAGS = ['PL','RC','DD','CL','SC','PR','PF','BB','PP','HL','CG','RW','SG','PT','DC','RR','MB','DT','GG','SP'];

export default async function handler(req, res) {
  const game = String(req.query.game || '').toUpperCase();
  if (!TAGS.includes(game)) {
    return res.status(400).json({ error: 'unknown game' });
  }
  const r = await fetch(process.env.SUPABASE_URL + '/rest/v1/rpc/pool_state', {
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
