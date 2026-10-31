// api/play.js — authenticated play. {token, game} buys a pool entry;
// {token, kind} enters a Card draw. Wallet is debited/credited server-side.
const TAGS = ['PL','RC','DD','CL','SC','PR','PF','BB','PP','HL','CG','RW','SG','PT','DC','RR','MB','DT','GG','SP'];
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
  const token = String((b && b.token) || '');
  if (!token) return res.status(401).json({ error: 'sign in to play' });
  let fn, args;
  if (b.game) {
    const game = String(b.game).toUpperCase();
    if (!TAGS.includes(game)) return res.status(400).json({ error: 'unknown game' });
    // one flat price per ticket — no multipliers (legal review, Oct 2026)
    fn = 'buy_entry3'; args = { p_game: game, p_token: token, p_mult: 1 };
  } else if (['minute','five','silver','gold','grand','platinum','free'].includes(b.kind)) {
    // optional off_at = a named draw up to 7 days ahead (ISO timestamp)
    fn = 'card_enter3'; args = { p_kind: b.kind, p_token: token };
    if (b.off_at) { const t = new Date(b.off_at); if (isNaN(t)) return res.status(400).json({ error: 'bad draw time' }); args.p_off_at = t.toISOString(); }
  } else return res.status(400).json({ error: 'bad request' });
  const r = await fetch(URL + '/rest/v1/rpc/' + fn, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY },
    body: JSON.stringify(args) });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
