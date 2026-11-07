// api/site.js — public: is the site live (real money) or in play-money test mode?
export default async function handler(req, res) {
  const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY, URL = process.env.SUPABASE_URL;
  if (!KEY || !URL) return res.status(200).json({ live: false });
  const r = await fetch(URL + '/rest/v1/rpc/iw_site', { method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: KEY, Authorization: 'Bearer ' + KEY }, body: '{}' });
  const data = await r.json();
  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json(r.ok ? data : { live: false });
}
