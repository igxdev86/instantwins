// api/comp.js — Competitions (prize + qualifying question, week-long window).
// GET  -> open competitions + recent results (settles any past-due ones first)
// POST {action:'enter', token, code, answer} -> paid online entry
// POST {action:'mine', token} -> the signed-in player's entries
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(503).json({ error: 'backend not connected' });
  const H = { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY };
  const rpc = (fn, body) => fetch(URL + '/rest/v1/rpc/' + fn, { method: 'POST', headers: H, body: JSON.stringify(body || {}) });
  let r;
  if (req.method === 'POST') {
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b); } catch { b = {}; } }
    const token = String((b && b.token) || '');
    if (!token) return res.status(400).json({ error: 'sign in first' });
    if (b.action === 'mine') r = await rpc('comp_mine', { p_token: token });
    else if (b.action === 'enter') {
      const code = String(b.code || '').toUpperCase().slice(0, 8);
      const answer = parseInt(b.answer, 10);
      if (!/^C\d{3}$/.test(code) || !(answer >= 0 && answer < 10)) return res.status(400).json({ error: 'bad request' });
      r = await rpc('comp_enter', { p_token: token, p_code: code, p_answer: answer });
    } else return res.status(400).json({ error: 'bad request' });
  } else r = await rpc('comp_list', {});
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  if (!r.ok) return res.status(400).json({ error: (data && data.message) || 'failed' });
  return res.status(200).json(data);
}
