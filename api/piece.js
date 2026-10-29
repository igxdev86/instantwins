// api/piece.js — Pick a Piece. {action:'state', token?} reads the open board
// (settles any due board first); {action:'pick', token, piece} buys a piece.
// Wallet is debited/credited server-side. Zero dependencies.
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  b = b || {};
  const token = b.token ? String(b.token) : null;
  let fn, args;
  if (b.action === 'pick') {
    if (!token) return res.status(401).json({ error: 'sign in to play' });
    fn = 'piece_pick'; args = { p_token: token, p_piece: parseInt(b.piece, 10) || 0 };
  } else {
    fn = 'piece_state'; args = { p_token: token };
  }
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
