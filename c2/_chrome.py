BOLT='<svg viewBox="0 0 24 24" fill="none" stroke="#1A0A00" stroke-width="2.6" stroke-linejoin="round" stroke-linecap="round"><path d="M13 2L4 14h7l-1 8 9-12h-7z"/></svg>'
def top(active=''):
    return f'''<div class="concept">Concept 2 &middot; prototype &middot; prototype credit, no real money</div>
<header class="top"><div class="wrap"><a class="brand" href="index.html"><i>{BOLT}</i>INSTANTWINS</a>
<div class="bank"><span>Tickets <b id="bankN">0</b></span><span style="color:var(--soft)">&middot;</span><span id="balN">£50</span><a href="index.html#buy">Buy</a></div></div></header>'''
def bar(active=''):
    def a(h,k,ic,l): return f'<a href="{h}" class="{"on" if active==k else ""}"><svg viewBox="0 0 24 24">{ic}</svg>{l}</a>'
    return '<nav class="mbar">'+a('index.html','home','<path d="M3 11l9-8 9 8v10H3z"/>','Home')+a('index.html#buy','buy','<rect x="3" y="7" width="18" height="10" rx="3"/><path d="M3 12h18"/>','Buy')+a('index.html#games','games','<rect x="2" y="7" width="20" height="12" rx="4"/><path d="M7 11v4M5 13h4M15 12h.01M18 14h.01"/>','Games')+a('prizes.html','prizes','<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2-5.5-2.9L6.5 20l1-6.2L3 9.6l6.2-.9z"/>','Prizes')+a('index.html#free','free','<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>','Free')+'</nav>'
FOOT='''<footer class="wrap">InstantWins Concept 2 is a design prototype. In the live product every ticket&rsquo;s prize is allocated on the server before any game runs; games are reveals only. Free entry by post on every round. 18+, Great Britain. IGX Ltd.</footer>'''
