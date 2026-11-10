// api/play.js — authenticated play. {token, game} buys a pool entry;
// {token, kind} enters a Card draw. Wallet is debited/credited server-side.
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
    if (!/^[A-Z0-9]{2,4}$/.test(game)) return res.status(400).json({ error: 'unknown ticket' });
    // only active tickets can be bought
    const cat = await fetch(URL + '/rest/v1/rpc/iw_tickets', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY }, body: '{}' });
    const list = cat.ok ? await cat.json() : [];
    if (!Array.isArray(list) || !list.some(t => t.tag === game)) return res.status(400).json({ error: 'that ticket is not on sale' });
    // one flat price per ticket — no multipliers (legal review, Oct 2026)
    const n = Math.min(50, Math.max(1, parseInt(b.qty, 10) || 1));
    if (n > 1) { fn = 'buy_entries'; args = { p_game: game, p_token: token, p_n: n }; }
    else { fn = 'buy_entry3'; args = { p_game: game, p_token: token, p_mult: 1 }; }
  } else if (b.bundle && /^[a-z0-9_]{2,24}$/.test(String(b.kind||''))) {
    fn = 'card_enter_bundle'; args = { p_token: token, p_kind: b.kind };
  } else if (/^[a-z0-9_]{2,24}$/.test(String(b.kind||''))) {
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
  if (!r.ok) return res.status(400).json({ error: friendly(data && data.message) });
  return res.status(200).json(data);
}

function friendly(m){ m=String(m||''); if(!m||/schema cache|does not exist|relation|column|syntax|permission denied|function .* in the schema/i.test(m)) return 'service temporarily unavailable'; return m; }
