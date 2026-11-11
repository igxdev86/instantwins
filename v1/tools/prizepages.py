import re,json,html,sys,os
OUT=os.path.dirname(os.path.abspath(__file__))+'/../'
# usage: python3 tools/prizepages.py  — regenerates the example prize pages from the PAGES dict below
base=open(OUT+'competitions.html').read()
head=base[:base.index('<div class="wrap"><div class="herowrap">')]
tail=base[base.index('<nav class="mtab"'):]
# strip the competitions runtime script from tail (keep site-mode/checkin/catalog scripts)
tail=re.sub(r'<script>\n\(function\(\)\{\n  const gbp=.*?\n\}\)\(\);\n</script>','',tail,flags=re.S)
head=head.replace('<a class="on" href="competitions.html">','<a class="" href="competitions.html">')
CSS='''<style>

.c-opts{display:grid;gap:8px}

.c-opt{display:flex;align-items:center;gap:12px;width:100%;text-align:left;border:1px solid rgba(255,255,255,.14);background:linear-gradient(180deg,#152A52,#0E1D3C);color:#fff;border-radius:9px;padding:11px 12px;font-family:'Barlow',sans-serif;font-weight:700;font-size:1rem;cursor:pointer}

.c-opt i{font-style:normal;width:30px;height:30px;border-radius:50%;flex:0 0 30px;display:inline-flex;align-items:center;justify-content:center;font-family:'Barlow Condensed',sans-serif;font-weight:900;background:#0A1528;border:1px solid rgba(255,255,255,.18)}

.c-opt.sel{border-color:var(--tc);background:linear-gradient(180deg,color-mix(in srgb,var(--tc) 35%,#152A52),color-mix(in srgb,var(--tc) 18%,#0E1D3C));box-shadow:0 0 0 2px color-mix(in srgb,var(--tc) 45%,transparent)}

.c-opt.sel i{background:var(--tc);color:#07122A;border-color:#fff}

.c-btn{flex:1 1 200px;display:inline-flex;align-items:center;justify-content:center;gap:8px;border:0;border-radius:10px;padding:13px 16px;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:1.15rem;letter-spacing:.06em;text-transform:uppercase;cursor:pointer;color:#07122A;text-decoration:none;
  background:linear-gradient(180deg,#FFF1B8,var(--tc) 45%,color-mix(in srgb,var(--tc) 65%,#000));box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 6px 16px rgba(0,0,0,.4)}

.c-btn:disabled{opacity:.55;cursor:not-allowed}

.c-free{flex:1 1 160px;display:inline-flex;align-items:center;justify-content:center;border:1px solid var(--line);border-radius:10px;padding:12px 14px;color:#fff;text-decoration:none;font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:1rem;letter-spacing:.06em;text-transform:uppercase;background:#0A1730}
.pp{display:grid;gap:14px}
.pp-hero{display:grid;grid-template-columns:1fr;gap:14px}
@media(min-width:760px){.pp-hero{grid-template-columns:1.1fr 1fr}}
.pp-gal{position:relative;border-radius:14px;overflow:hidden;border:1px solid var(--line);background:radial-gradient(120% 90% at 20% 0%,color-mix(in srgb,var(--tc) 30%,transparent),transparent 60%),linear-gradient(180deg,#0E1B38,#070F22);aspect-ratio:4/3;display:flex;align-items:center;justify-content:center}
.pp-gal svg{width:62%;height:62%;filter:drop-shadow(0 18px 24px rgba(0,0,0,.5))}
.pp-gal .tag{position:absolute;left:12px;top:12px;padding:5px 10px;border-radius:999px;background:var(--tc);color:#07122A;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:.72rem;letter-spacing:.12em;text-transform:uppercase}
.pp-gal .rrp{position:absolute;right:12px;bottom:12px;padding:6px 10px;border-radius:9px;background:rgba(5,12,28,.75);border:1px solid rgba(255,255,255,.12);font-family:'IBM Plex Mono',monospace;font-size:.74rem;color:#C9D6EE}
.pp-thumbs{display:flex;gap:8px;margin-top:8px}.pp-thumbs span{flex:1;aspect-ratio:1;border-radius:9px;border:1px solid var(--line);background:#0A1528;opacity:.6}
.pp-buy{border:1px solid var(--line);border-top:3px solid var(--tc);border-radius:14px;padding:18px;background:linear-gradient(180deg,#0E1B38,#0A1528)}
.pp-k{font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:.72rem;letter-spacing:.14em;text-transform:uppercase;color:var(--soft)}
.pp-h1{font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:2.1rem;line-height:1;margin:4px 0 2px;background:linear-gradient(180deg,#fff,var(--tc) 60%,color-mix(in srgb,var(--tc) 60%,#000));-webkit-background-clip:text;background-clip:text;color:transparent}
.pp-sub{color:var(--soft);font-size:.92rem;margin:0 0 12px}
.pp-facts{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:12px 0}
.pp-facts div{background:#07122A;border:1px solid var(--line);border-radius:9px;padding:9px 8px;text-align:center}
.pp-facts b{display:block;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:1.25rem;color:#fff}.pp-facts i{font-style:normal;font-family:'IBM Plex Mono',monospace;font-size:.62rem;color:var(--soft);letter-spacing:.06em;text-transform:uppercase}
.bar{height:10px;border-radius:999px;background:#07122A;border:1px solid var(--line);overflow:hidden}.bar i{display:block;height:100%;background:linear-gradient(90deg,color-mix(in srgb,var(--tc) 70%,#fff),var(--tc));width:var(--w)}
.bar-k{display:flex;justify-content:space-between;font-family:'IBM Plex Mono',monospace;font-size:.72rem;color:var(--soft);margin:6px 0 12px}
.qty{display:flex;gap:8px;margin:10px 0}.qty button{flex:1;border:1px solid var(--line);background:#07122A;color:#fff;border-radius:9px;padding:10px 0;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:1rem;cursor:pointer}.qty button.sel{border-color:var(--tc);background:color-mix(in srgb,var(--tc) 25%,#07122A);box-shadow:0 0 0 2px color-mix(in srgb,var(--tc) 40%,transparent)}
.pp-q{margin:12px 0;padding:12px;border-radius:10px;background:rgba(5,12,28,.55);border:1px solid rgba(255,255,255,.08)}
.pp-q h3{margin:0 0 8px;font-family:'Barlow Condensed',sans-serif;font-weight:800;font-size:1.1rem;color:#fff}
.pp-q .c-opts{display:grid;gap:6px}.pp-q .c-opt{padding:9px 10px;font-size:.92rem}.pp-q .c-opt i{width:26px;height:26px;flex-basis:26px}
.pp-cta{display:flex;gap:8px;flex-wrap:wrap}.pp-cta .c-btn{font-size:1.1rem}
.pp-iw{margin-top:12px;border:1px dashed color-mix(in srgb,var(--tc) 60%,#0A1528);border-radius:10px;padding:10px 12px;font-size:.86rem;color:#C9D6EE}
.pp-iw b{color:#fff}
.pp-sec{border:1px solid var(--line);border-radius:14px;padding:18px;background:linear-gradient(180deg,#0B1733,#0A1528)}
.pp-sec h2{margin:0 0 10px;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:1.4rem;color:#fff}
.pp-sec p,.pp-sec li{color:#C9D6EE;line-height:1.55;font-size:.95rem}.pp-sec ul{padding-left:18px;margin:0}
.faq details{border-top:1px solid var(--line);padding:10px 0}.faq summary{cursor:pointer;font-weight:700;color:#fff}.faq p{margin:8px 0 0}
.more{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}@media(min-width:760px){.more{grid-template-columns:repeat(4,1fr)}}
.more a{display:block;border:1px solid var(--line);border-top:2px solid var(--tc);border-radius:12px;padding:12px;background:#0A1528;text-decoration:none;color:#fff}
.more a b{display:block;font-family:'Barlow Condensed',sans-serif;font-weight:900;font-size:1.1rem}.more a span{font-family:'IBM Plex Mono',monospace;font-size:.7rem;color:var(--soft)}
.ex{margin:0 0 12px;padding:8px 12px;border:1px solid var(--gold);border-radius:8px;color:var(--gold);font-size:.78rem;font-weight:700}
</style>'''
ART={
 'watch':'<svg viewBox="0 0 200 160" fill="none"><rect x="78" y="6" width="44" height="40" rx="8" fill="#2A3A5C"/><rect x="78" y="114" width="44" height="40" rx="8" fill="#2A3A5C"/><circle cx="100" cy="80" r="42" fill="#0A1528" stroke="#F0C98A" stroke-width="6"/><path d="M100 80V54M100 80l18 12" stroke="#fff" stroke-width="4" stroke-linecap="round"/></svg>',
 'trainers':'<svg viewBox="0 0 200 160" fill="none"><path d="M20 110c20-6 40-30 60-50 14 14 36 22 60 26 26 4 40 10 40 24v10H20z" fill="#EDF2FA"/><path d="M20 120h160v12H20z" fill="#5FB4FF"/><path d="M60 80l26 22" stroke="#0A1528" stroke-width="4"/></svg>',
 'headphones':'<svg viewBox="0 0 200 160" fill="none"><path d="M40 100V80a60 60 0 0 1 120 0v20" stroke="#9DB4DB" stroke-width="8" stroke-linecap="round"/><rect x="28" y="96" width="32" height="48" rx="10" fill="#2A3A5C" stroke="#9DB4DB" stroke-width="3"/><rect x="140" y="96" width="32" height="48" rx="10" fill="#2A3A5C" stroke="#9DB4DB" stroke-width="3"/></svg>',
 'laptop':'<svg viewBox="0 0 200 160" fill="none"><rect x="40" y="30" width="120" height="78" rx="6" fill="#2A3A5C" stroke="#9DB4DB" stroke-width="3"/><rect x="48" y="38" width="104" height="62" rx="3" fill="#0A1E44"/><path d="M20 112h160l-8 14H28z" fill="#9DB4DB"/></svg>',
 'tablet':'<svg viewBox="0 0 200 160" fill="none"><rect x="40" y="14" width="120" height="132" rx="12" fill="#2A3A5C" stroke="#9DB4DB" stroke-width="3"/><rect x="50" y="24" width="100" height="112" rx="6" fill="#0A1E44"/></svg>',
 'tv':'<svg viewBox="0 0 200 160" fill="none"><rect x="14" y="24" width="172" height="100" rx="6" fill="#0A1528" stroke="#9DB4DB" stroke-width="4"/><rect x="22" y="32" width="156" height="84" fill="#0A1E44"/><rect x="80" y="128" width="40" height="8" rx="4" fill="#9DB4DB"/></svg>',
 'perfume':'<svg viewBox="0 0 200 160" fill="none"><rect x="86" y="14" width="28" height="22" rx="4" fill="#F0C98A"/><rect x="60" y="40" width="80" height="106" rx="14" fill="#B07CFF" opacity=".9"/><rect x="72" y="60" width="56" height="60" rx="6" fill="#fff" opacity=".2"/></svg>',
 'voucher':'<svg viewBox="0 0 200 160" fill="none"><rect x="20" y="40" width="160" height="80" rx="10" fill="#FF5FA2"/><path d="M20 80h160" stroke="#fff" stroke-dasharray="8 6" stroke-width="3"/><circle cx="20" cy="80" r="10" fill="#070F22"/><circle cx="180" cy="80" r="10" fill="#070F22"/></svg>',
 'holiday':'<svg viewBox="0 0 200 160" fill="none"><circle cx="150" cy="44" r="22" fill="#FFC53D"/><path d="M0 130c40-30 80-30 120 0s60 20 80 0v30H0z" fill="#36E0FF"/><path d="M60 128V60M60 60c-20-4-34 6-40 18 12-6 26-6 40 0M60 60c20-4 34 6 40 18-12-6-26-6-40 0" stroke="#19E6A0" stroke-width="6" stroke-linecap="round"/></svg>',
 'bag':'<svg viewBox="0 0 200 160" fill="none"><defs><linearGradient id="g1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F0C98A"/><stop offset="1" stop-color="#8A5A2B"/></linearGradient></defs><path d="M60 50c0-26 80-26 80 0" stroke="#C9975C" stroke-width="7" stroke-linecap="round"/><path d="M30 60h140l-12 80H42z" fill="url(#g1)"/><path d="M30 60h140" stroke="#5A3A12" stroke-width="3"/><rect x="88" y="96" width="24" height="16" rx="3" fill="#5A3A12"/></svg>',
 'phone':'<svg viewBox="0 0 200 160" fill="none"><defs><linearGradient id="g2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3B4A6B"/><stop offset="1" stop-color="#0B1326"/></linearGradient></defs><rect x="62" y="8" width="76" height="144" rx="14" fill="url(#g2)" stroke="#9DB4DB" stroke-width="3"/><rect x="70" y="18" width="60" height="124" rx="8" fill="#0A1E44"/><circle cx="84" cy="30" r="6" fill="#1D2E52" stroke="#5FB4FF"/><circle cx="100" cy="30" r="6" fill="#1D2E52" stroke="#5FB4FF"/></svg>',
 'console':'<svg viewBox="0 0 200 160" fill="none"><rect x="36" y="40" width="128" height="80" rx="10" fill="#EDF2FA"/><rect x="48" y="52" width="104" height="56" rx="6" fill="#0A1528"/><circle cx="100" cy="80" r="6" fill="#5FB4FF"/><rect x="60" y="122" width="80" height="10" rx="5" fill="#9DB4DB"/></svg>',
 'cash':'<svg viewBox="0 0 200 160" fill="none"><rect x="30" y="40" width="140" height="80" rx="8" fill="#19E6A0"/><rect x="42" y="52" width="116" height="56" rx="6" fill="none" stroke="#07261C" stroke-width="3"/><circle cx="100" cy="80" r="18" fill="#07261C"/><text x="100" y="87" text-anchor="middle" font-family="Barlow Condensed,Arial Black" font-weight="900" font-size="20" fill="#19E6A0">£</text></svg>',
}
def page(d):
    sold_pc=int(d['sold']/d['max']*100)
    opts=''.join(f'<button class="c-opt"><i>{"ABC"[i]}</i>{html.escape(o)}</button>' for i,o in enumerate(d['options']))
    faq_schema=json.dumps({"@context":"https://schema.org","@type":"FAQPage","mainEntity":[{"@type":"Question","name":q,"acceptedAnswer":{"@type":"Answer","text":re.sub('<[^>]+>','',a)}} for q,a in d['faq']]})
    body=f'''<div class="wrap" style="--tc:{d['col']}">
<p class="ex">Example product page — not on sale. Images are placeholders; live pages use our own photographs of the actual item.</p>
<div class="pp">
 <div class="pp-hero">
  <div><div class="pp-gal"><span class="tag">{d['tag']}</span>{ART[d['art']]}<span class="rrp">RRP {d['rrp']}</span></div><div class="pp-thumbs"><span></span><span></span><span></span><span></span></div></div>
  <div class="pp-buy">
   <div class="pp-k">Prize competition · {d['code']}</div>
   <h1 class="pp-h1">WIN {d['name_caps']}</h1>
   <p class="pp-sub">{d['sub']}</p>
   <div class="pp-facts"><div><b>{d['price']}</b><i>per ticket</i></div><div><b>{d['max']:,}</b><i>max tickets</i></div><div><b>{d['closes']}</b><i>draw</i></div></div>
   <div class="bar"><i style="--w:{sold_pc}%"></i></div><div class="bar-k"><span>{d['sold']:,} sold</span><span>{d['max']-d['sold']:,} left</span></div>
   <div class="pp-k">How many tickets?</div>
   <div class="qty"><button>1</button><button class="sel">5</button><button>10</button><button>25</button><button>50</button></div>
   <div class="pp-q"><h3>{d['question']}</h3><div class="c-opts">{opts}</div></div>
   <div class="pp-cta"><button class="c-btn">Enter · 5 tickets {d['price5']} &rarr;</button><a class="c-free" href="free-entry.html#competitions">Free entry by post</a></div>
   <div class="pp-iw"><b>Instant wins inside:</b> {d['iw']}</div>
   <div class="pp-k" style="margin-top:12px">Cash alternative <b style="color:#fff">{d['cashalt']}</b> · winner's choice</div>
  </div>
 </div>
 <div class="pp-sec"><h2>About the prize</h2>{d['about']}</div>
 <div class="pp-sec"><h2>How to win {d['name']}</h2><ol style="padding-left:18px;margin:0"><li>Pick how many tickets you want ({d['price']} each, up to 50 per order).</li><li>Answer the qualifying question — only correct entries go into the draw.</li><li>When all {d['max']:,} tickets are gone or the clock runs out on {d['closes_long']}, one winner is drawn at random from the correct entries using our <a href="fairness.html" style="color:var(--buy-ink)">published-seed method</a>.</li><li>Winner chooses the item (delivered insured, signed for, within 7 days) or the cash alternative of {d['cashalt']}.</li></ol><p style="margin-top:10px"><b>Your odds:</b> 1 in {d['max']:,} per ticket if every ticket sells; better if it doesn't, because the draw goes ahead on the closing date regardless — we never extend or roll a prize competition.</p></div>
 <div class="pp-sec"><h2>Free entry — no purchase necessary</h2><p>Every competition on InstantWins can be entered free by post. Send a postcard with the competition code <b>{d['code']}</b>, your answer, your full name and your InstantWins account number to the address on the <a href="free-entry.html" style="color:var(--buy-ink)">free entry page</a>. Postal entries take the next ticket number in exactly the same sequence as paid tickets and have the same chance of winning, including the instant-win tickets.</p></div>
 <div class="pp-sec faq"><h2>Questions people ask</h2>{''.join(f"<details><summary>{html.escape(q)}</summary><p>{a}</p></details>" for q,a in d['faq'])}</div>
 <div class="pp-sec"><h2>More to win</h2><div class="more">{d['more']}</div></div>
</div>
</div>
'''
    meta=f'<title>{html.escape(d["title"])}</title>\n<meta name="description" content="{html.escape(d["desc"])}">\n<meta name="robots" content="noindex">\n<script type="application/ld+json">{faq_schema}</script>\n'
    h=re.sub(r'<title>.*?</title>\n<link rel="canonical"[^>]*>\n<meta name="description" content="[^"]*">',lambda m:meta.rstrip('\n'),head,count=1,flags=re.S)
    h=h.replace('</head>',CSS+'</head>',1)
    return h+body+tail
MORE='''<a href="win-louis-vuitton-neverfull.html" style="--tc:#F0C98A"><b>Louis Vuitton Neverfull MM</b><span>£1.99 · 2,000 tickets</span></a><a href="win-iphone-17-pro.html" style="--tc:#5FB4FF"><b>iPhone 17 Pro 256GB</b><span>£1.49 · 1,500 tickets</span></a><a href="win-ps5-pro.html" style="--tc:#EDF2FA"><b>PlayStation 5 Pro</b><span>99p · 1,500 tickets</span></a><a href="competitions.html" style="--tc:#19E6A0"><b>£500 cash</b><span>49p · 2,000 tickets</span></a>'''
PAGES={
'win-louis-vuitton-neverfull.html':dict(col='#F0C98A',tag='Designer bag',art='bag',code='C004',name='a Louis Vuitton Neverfull MM',name_caps='A LOUIS VUITTON NEVERFULL MM',rrp='£1,650',sub='Monogram canvas, the classic MM size, brand new and boxed with receipt. Or take £1,250 cash.',price='£1.99',price5='£9.95',max=2000,sold=1184,closes='Sun 20:00',closes_long='Sunday at 20:00',question='Which city is Louis Vuitton from?',options=['Paris','Milan','London'],iw='40 of the 2,000 tickets win on the spot — 1 × £100, 4 × £25, 10 × £10, 25 × £5. You see it the moment your ticket is issued.',cashalt='£1,250',
 title='Win a Louis Vuitton Neverfull MM — £1.99 a ticket, free entry by post | InstantWins',desc='Win a brand-new Louis Vuitton Neverfull MM (RRP £1,650) for £1.99 a ticket or free by post. 2,000 tickets, 40 instant cash wins inside, draw Sunday 20:00. Cash alternative £1,250.',
 about='<p>The Neverfull MM is the one everybody recognises: the open-top tote in Monogram canvas with cowhide trim, the bag that goes to work, on the plane and out at the weekend. This one is brand new, bought at retail by IGX Ltd, and comes with the dust bag, box and our purchase receipt so you know exactly what you are getting.</p><p>Buying one outright is £1,650. Here a ticket is £1.99, with 40 instant cash prizes inside the run, and every entrant can also enter free by post. One winner takes the bag or £1,250 in cash within 5 working days of the draw.</p>',
 faq=[('Is the bag genuine?','Yes. We buy every designer prize at retail or from an authenticated reseller and show the receipt to the winner. We never use grey-market stock.'),('Can I take cash instead?','Yes — £1,250 by bank transfer, your choice at the time of the draw.'),('What if not all tickets sell?','The draw still happens on the closing date with whoever is in. We never extend a prize competition.'),('How do I enter for free?','Postcard with the code C004, your answer, name and account number to our PO Box. Same ticket sequence, same odds, including the instant wins.'),('How is the winner chosen?','At random from all correct entries using a seed we published before the competition opened — anyone can check it on our Fairness page.')],
 more=MORE),
'win-iphone-17-pro.html':dict(col='#5FB4FF',tag='Phone',art='phone',code='C005',name='an iPhone 17 Pro',name_caps='AN IPHONE 17 PRO 256GB',rrp='£1,099',sub='Sealed, unlocked, any colour you like, 256GB. Or take £850 cash.',price='£1.49',price5='£7.45',max=1500,sold=421,closes='Fri 20:00',closes_long='Friday at 20:00',question='Which company makes the iPhone?',options=['Apple','Samsung','Sony'],iw='30 of the 1,500 tickets win on the spot — 1 × £50, 4 × £20, 25 × £5.',cashalt='£850',
 title='Win an iPhone 17 Pro 256GB — £1.49 a ticket, free entry by post | InstantWins',desc='Win a sealed, unlocked iPhone 17 Pro 256GB (RRP £1,099) for £1.49 a ticket or free by post. 1,500 tickets, 30 instant cash wins, draw Friday 20:00. Cash alternative £850.',
 about='<p>A sealed iPhone 17 Pro, 256GB, unlocked to any network, in the colour you choose when you win. Delivered insured and signed-for within 7 days, or take £850 cash instead.</p><p>1,500 tickets at £1.49. Thirty tickets in the run carry an instant cash prize, revealed the moment the ticket is issued — so you can win before the draw even happens.</p>',
 faq=[('Is it unlocked?','Yes, factory unlocked, sealed, with full Apple warranty from the date you receive it.'),('Can I choose the colour?','Yes, any colour in stock when you win.'),('Can I take cash instead?','£850 by bank transfer, your choice.'),('How do I enter for free?','Postcard with the code C005, your answer, name and account number to our PO Box. Same tickets, same odds.'),('When is the draw?','Friday at 20:00, or sooner if all 1,500 tickets go. Never later.')],
 more=MORE),
'win-ps5-pro.html':dict(col='#EDF2FA',tag='Console',art='console',code='C006',name='a PlayStation 5 Pro',name_caps='A PLAYSTATION 5 PRO',rrp='£699',sub='Brand new, boxed, with a second controller. Or take £550 cash.',price='99p',price5='£4.95',max=1500,sold=903,closes='Sat 20:00',closes_long='Saturday at 20:00',question='What colour is the PlayStation logo on the console?',options=['Blue','Red','Green'],iw='30 of the 1,500 tickets win on the spot — 1 × £50, 4 × £10, 25 × £2.',cashalt='£550',
 title='Win a PS5 Pro — 99p a ticket, free entry by post | InstantWins',desc='Win a brand-new PlayStation 5 Pro with a second controller (RRP £699) for 99p a ticket or free by post. 1,500 tickets, 30 instant wins, draw Saturday 20:00. Cash alternative £550.',
 about='<p>The PS5 Pro, boxed and sealed, plus a second DualSense controller so you are not sharing. Delivered within 7 days of the draw, or £550 cash if you would rather.</p><p>Tickets are 99p and 30 of the 1,500 win instantly. Enter online or free by post — same odds either way.</p>',
 faq=[('Does it come with games?','No, console and two controllers. Winner can take £550 cash instead.'),('Disc or digital?','Disc edition.'),('How do I enter for free?','Postcard with the code C006, your answer, name and account number to our PO Box.'),('How is the winner picked?','At random from all correct entries by our published-seed method; check any draw on the Fairness page.')],
 more=MORE),
}
for f,d in PAGES.items(): open(OUT+f,'w').write(page(d))
print('ok')
