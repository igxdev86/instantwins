// Branded email shell. Table layout + inline styles so it renders in Gmail/Outlook/Apple Mail. Injected into every api/*.js flushMail.
function wrapMail(subject, body, to){
  const esc=s=>String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;');
  // body comes from SQL as simple <p>/<b>/<a> html; style those inline
  body=String(body||'')
    .replace(/<p>/g,'<p style="margin:0 0 14px;font:400 16px/1.55 Helvetica,Arial,sans-serif;color:#d6d8e0">')
    .replace(/<b>/g,'<b style="color:#ffffff;font-weight:700">')
    .replace(/<a class="btn" href="([^"]+)">/g,'<a href="$1" style="display:inline-block;margin:6px 0 10px;padding:14px 26px;border-radius:999px;background:#FF6A1A;color:#1A0A00;font:800 16px Helvetica,Arial,sans-serif;text-decoration:none">')
    .replace(/<a href="([^"]+)">/g,'<a href="$1" style="color:#3DF2FF;text-decoration:none;font-weight:600">')
    .replace(/<code>/g,'<code style="display:inline-block;padding:14px 22px;border-radius:12px;background:#0B0B10;border:1px solid #2a2a36;color:#C6FF3D;font:800 30px/1 Courier,monospace;letter-spacing:.25em">');
  const headline=esc(subject).replace(/ on InstantWins$/,'');
  return `<!doctype html><html><body style="margin:0;padding:0;background:#0B0B10">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#0B0B10"><tr><td align="center" style="padding:28px 14px">
<table role="presentation" width="560" cellspacing="0" cellpadding="0" style="max-width:560px;width:100%">
<tr><td style="padding:0 6px 18px"><a href="https://instantwins.co.uk" style="text-decoration:none"><span style="display:inline-block;width:30px;height:30px;line-height:30px;border-radius:9px;background:#FF6A1A;color:#1A0A00;text-align:center;font:900 18px Helvetica,Arial,sans-serif;vertical-align:middle">&#9889;</span><span style="display:inline-block;margin-left:10px;vertical-align:middle;font:900 18px Helvetica,Arial,sans-serif;letter-spacing:.02em;color:#ffffff">INSTANT<span style="color:#C6FF3D">WINS</span></span></a></td></tr>
<tr><td style="background:#15151D;border:1px solid #262633;border-radius:20px;padding:30px 28px 24px">
  <h1 style="margin:0 0 18px;font:900 26px/1.15 Helvetica,Arial,sans-serif;color:#ffffff;letter-spacing:-.01em">${headline}</h1>
  ${body}
</td></tr>
<tr><td style="padding:22px 8px 0;font:400 12px/1.6 Helvetica,Arial,sans-serif;color:#7c8190">
  <a href="https://instantwins.co.uk/account.html" style="color:#9aa0ad;text-decoration:none">My account</a> &nbsp;&middot;&nbsp; <a href="https://instantwins.co.uk/support.html" style="color:#9aa0ad;text-decoration:none">Support</a> &nbsp;&middot;&nbsp; <a href="https://instantwins.co.uk/free.html" style="color:#9aa0ad;text-decoration:none">Free entry by post</a> &nbsp;&middot;&nbsp; <a href="https://instantwins.co.uk/responsible-play.html" style="color:#9aa0ad;text-decoration:none">Responsible play</a><br><br>
  InstantWins.co.uk is operated by IGX Ltd, company no. 13057559, 20-22 Wenlock Road, London N1 7GU. Prize competitions with a free postal entry route under Schedule 2 of the Gambling Act 2005. 18+, Great Britain only. Prizes are a matter of luck and most tickets win nothing &mdash; please play within your means. GamCare 0808 8020 133.<br><br>
  This email was sent to ${esc(to)} because you have an InstantWins account.
</td></tr>
</table></td></tr></table></body></html>`;
}
