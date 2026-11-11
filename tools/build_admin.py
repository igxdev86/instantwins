import re,glob
HEAD=open('terms.html').read()
HEADER=HEAD[:HEAD.find('<main class="wrap">')]
def head(title,desc):
    h=HEADER.replace('<title>Terms — InstantWins.co.uk</title>','<title>'+title+' — InstantWins.co.uk</title><meta name="description" content="'+desc+'"><link rel="canonical" href="https://instantwins.co.uk/'+PAGE+'">')
    h=h.replace('<span id="balN">£50</span>','<span id="balN">—</span>').replace('<a href="index.html#buy">Buy</a>','<a id="hdrAct" href="index.html#buy">Buy</a>')
    return h
FOOT=open('footer.part.html').read()
MBAR=re.search(r'<nav class="mbar">.*?</nav>',open('index.html').read(),re.S).group(0).replace('class="on"','class=""')

# ---------- ADMIN ----------
PAGE='admin.html'
TABS=[('overview','Overview','admin.html'),('revenue','Revenue','admin-revenue.html'),('users','Users','admin-users.html'),('payments','Payments','admin-payments.html'),('postal','Postal','admin-postal.html'),('support','Support','admin-support.html'),('affiliates','Affiliates','admin-affiliates.html'),('announce','Broadcast','admin-announce.html')]
PRE="""const $=id=>document.getElementById(id);
function sess(){try{return JSON.parse(localStorage.getItem('iw_session'))}catch(e){return null}}
async function api(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const d=await r.json();if(!r.ok||d.error)throw new Error(d.error||'failed');return d;}
const fmtp=p=>'£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:2});
function esc(x){const d=document.createElement('div');d.textContent=x;return d.innerHTML;}
const s=sess(); if(!s){location.href='signin.html';}
let _g=null; function guard(){ if(_g)return _g; _g=(async()=>{ try{ const me=await api('/api/auth',{action:'me',token:s.token});
  if(!me.is_admin){$('gate').textContent='This account is not an admin.';return false;} $('console').style.display='';return true; }catch(e){$('gate').textContent=e.message;return false;} })(); return _g; }
function showTab(){ const h=(location.hash||'#overview').slice(1); document.querySelectorAll('.ap').forEach(p=>p.style.display=p.id==='ap-'+h?'':'none'); document.querySelectorAll('.atabs a').forEach(a=>a.classList.toggle('on',a.getAttribute('href')==='#'+h)); window.scrollTo(0,0); }
window.addEventListener('hashchange',showTab);
"""
panels=[];js=[]
for key,label,src in TABS:
    s=open('v1/'+src).read(); i=s.find('<div id="all" style="display:none">'); j=s.find('</div></div><nav class="mtab"')
    body=s[i:j].strip()
    assert body.endswith('</div>'), src
    body='<div class="ap" id="ap-'+key+'">'+body[len('<div id="all" style="display:none">'):]
    body=re.sub(r'href="admin-([a-z]+)\.html"',r'href="#\1"',body).replace('href="admin.html"','href="#overview"')
    body=body.replace('<p class="lead">Live highlights. Tap any tile for the full breakdown.</p>','<div class="panel"><h2>Million Round</h2><div id="milBox"><p class="lead">Loading…</p></div></div><p class="lead">Live highlights. Tap any tile for the full breakdown.</p>')
    body=re.sub(r'<style>.*?</style>','',body,flags=re.S)
    body=body.replace('background:#050B1A;color:var(--ink);font-family:inherit','')
    body=body.replace("<span class=\"m\" style=\"color:var(--soft);font-size:.75rem\">Loading\\u2026</span>","<span class=\"m\">Loading…</span>")
    sc=re.findall(r'<script>(.*?)</script>',s,re.S)[2]; k=sc.find('async function guard'); k=sc.find('\n}\n',k)+3; code=sc[k:]
    if key=='draws':
        body=body.replace('id="kErr"','id="kErr2"'); code=code.replace("$('kErr')","$('kErr2')").replace("document.querySelectorAll('.sw')","document.querySelectorAll('#kindsBox .sw')")
    if key=='postal':
        body=re.sub(r'<div class="panel"><h2>Key in a postcard</h2>.*','',body,flags=re.S)+'</div>'; code=''
        body=body.replace('<div class="panel"><h2>Competition postcard</h2><p class="lead">Cards with a competition code and answer are keyed in on the <a href="#competitions" style="color:var(--cyan)">Competitions admin</a> page.</p></div>','<div class="panel"><h2>Competition postcard</h2><p class="lead">Cards with a competition code and answer are keyed in on the <a href="#competitions" style="color:var(--cyan)">Competitions admin</a> page.</p></div></details>')
        body=body.replace('<div class="ap" id="ap-postal">',open('tools/postal_panel.html').read())
        code+=open('tools/postal_panel.js').read()
    if key=='users':
        body=body.replace('<div class="panel"><h2>Users</h2>','''<div class="panel"><h2>Credit a player</h2><p class="lead">Play credit for testing, or a refund once live. Negative amounts debit.</p>
    <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end"><div style="flex:2;min-width:160px"><label>Account no. / email</label><input id="crRef" placeholder="IW1234 or name@…" autocomplete="off" style="margin:0"></div><div style="flex:1;min-width:90px"><label>Amount £</label><input id="crAmt" type="number" step="0.01" value="100" style="margin:0"></div></div>
    <label>Note</label><input id="crNote" placeholder="testing" style="margin:0">
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:10px"><button class="btn lime" id="crGo" style="margin:0">Credit</button><button class="btn ghost" id="cr100" style="margin:0">+£100 to me</button></div><div class="err" id="crErr"></div></div>
  <div class="panel"><h2>Users</h2><p class="lead">Tap a user to fill the credit box.</p>''')
        code+='''
$('crGo').onclick=async()=>{ $('crErr').className='err'; $('crErr').textContent=''; try{ const d=await api('/api/admin',{action:'credit',token:s.token,ref:$('crRef').value.trim(),amount_p:Math.round(parseFloat($('crAmt').value||'0')*100),note:$('crNote').value.trim()}); $('crErr').className='err ok'; $('crErr').textContent=d.name+' now has '+fmtp(d.balance_p); loadUsers(); }catch(e){ $('crErr').textContent=e.message; } };
$('cr100').onclick=async()=>{ $('crErr').className='err'; $('crErr').textContent=''; try{ const me=await api('/api/auth',{action:'me',token:s.token}); const d=await api('/api/admin',{action:'credit',token:s.token,ref:me.email||me.acct_no||'',amount_p:10000,note:'testing'}); $('crErr').className='err ok'; $('crErr').textContent='You now have '+fmtp(d.balance_p); loadUsers(); }catch(e){ $('crErr').textContent=e.message; } };
document.getElementById('users').addEventListener('click',e=>{ const row=e.target.closest('.row'); if(!row)return; const m=row.textContent.match(/[\w.+-]+@[\w.-]+/); if(m){ $('crRef').value=m[0]; $('crRef').scrollIntoView({behavior:'smooth',block:'center'}); } });'''
    if key=='overview':
        body=re.sub(r'<a class="tile" href="#(prizes|competitions|draws)">.*?</a>\s*','',body,flags=re.S)
        code+="""
async function mil(){ try{ const st=await (await fetch('/api/c2',{cache:'no-store'})).json(); const d=await api('/api/admin',{action:'milstats',token:s.token}); const site=await (await fetch('/api/site',{cache:'no-store'})).json();
  $('milBox').innerHTML='<div class="row"><span>Tickets sold</span><span class="mono">'+(st.sold||0).toLocaleString()+' / '+(st.cap||0).toLocaleString()+'</span></div>'
   +'<div class="row"><span>Prizes still in the round</span><span class="mono">'+Number(st.prizes_left||0).toLocaleString()+'</span></div>'
   +'<div class="row"><span>Bought but not yet opened</span><span class="mono">'+(d.unrevealed||0).toLocaleString()+'</span></div>'
   +'<div class="row"><span>Taken in (Million Round)</span><span class="mono">'+fmtp(d.stakes_p||0)+'</span></div>'
   +'<div class="row"><span>Paid out (Million Round)</span><span class="mono" style="color:var(--pink)">−'+fmtp(d.paid_p||0)+'</span></div>'
   +'<div class="row"><span>Postal entries</span><span class="mono">'+(d.postal||0)+'</span></div>'
   +'<div class="row"><span>End Prize Draw</span><span class="mono" style="color:var(--pink)">'+fmtp(st.end_prize_p||0)+'</span></div>'
   +'<div class="row"><span>Round closes</span><span class="mono">'+(st.closes_at?new Date(st.closes_at).toLocaleString('en-GB',{day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'not set')+'</span></div>'
   +(d.last_end||st.last_end?'<div class="row"><span>Last End Prize</span><span class="mono win">round '+(st.last_end||{}).round+' · #'+Number((st.last_end||{}).entry||0).toLocaleString()+' · '+esc((st.last_end||{}).name||'')+'</span></div>':'')
   +'<div style="display:flex;gap:8px;flex-wrap:wrap;margin:10px 0"><input id="milDate" type="datetime-local" style="margin:0;flex:1;min-width:170px" value="'+(st.closes_at?new Date(new Date(st.closes_at).getTime()-new Date().getTimezoneOffset()*60000).toISOString().slice(0,16):'')+'"><input id="milEnd" type="number" step="1" min="0" placeholder="End prize £" style="margin:0;width:120px" value="'+Math.round((st.end_prize_p||0)/100)+'"><button class="btn ghost" id="milSet" style="margin:0">Save</button><button class="btn ghost" id="milClose" style="margin:0;border-color:var(--pink);color:var(--pink)">Close round now</button></div><div class="err" id="milErr"></div>'
   +'<div class="row"><span>Themed games <small class="m">(off = Quick Reveal only)</small></span><button class="sw'+(site.games?' on':'')+'" id="gamesSw" aria-label="toggle games"></button></div>'
   +'<div class="row"><b>Biggest wins</b><span></span></div>'+((d.top||[]).map(w=>'<div class="row"><span class="m">'+esc(w.who)+' · #'+w.no.toLocaleString()+'</span><span class="mono" style="color:var(--lime)">+'+fmtp(w.prize_p)+'</span></div>').join('')||'<div class="row"><span class="m">None yet</span></div>');
 $('gamesSw').onclick=async()=>{ const on=!$('gamesSw').classList.contains('on'); try{ await api('/api/admin',{action:'games',token:s.token,on}); $('gamesSw').classList.toggle('on',on); }catch(e){ $('milErr').className='err'; $('milErr').textContent=e.message; } };
 $('milSet').onclick=async()=>{ $('milErr').className='err'; $('milErr').textContent=''; try{ await api('/api/admin',{action:'milset',token:s.token,closes_at:$('milDate').value?new Date($('milDate').value).toISOString():null,end_prize_p:Math.round(parseFloat($('milEnd').value||'0')*100)}); $('milErr').className='err ok'; $('milErr').textContent='Saved.'; mil(); }catch(e){ $('milErr').textContent=e.message; } };
 $('milClose').onclick=async()=>{ if(!confirm('Close the open round NOW? This runs the End Prize Draw, opens every unopened ticket and starts the next round. It cannot be undone.'))return; try{ const r=await api('/api/admin',{action:'milclose',token:s.token}); $('milErr').className='err ok'; $('milErr').textContent='Closed. End Prize to ticket #'+(r.end_entry||'—')+'.'; mil(); }catch(e){ $('milErr').className='err'; $('milErr').textContent=e.message; } };
 }catch(e){ $('milBox').innerHTML='<p class="lead">'+esc(e.message)+'</p>'; } }
(async()=>{ if(await guard()){ mil(); setInterval(mil,30000);} })();"""
    panels.append(body); js.append('(function(){\n'+code+'\n})();')
tabs='<nav class="atabs">'+''.join('<a href="#'+k+'">'+l+'</a>' for k,l,_ in TABS)+'</nav>'
html=head('Admin','InstantWins admin console').replace('<meta name="description" content="InstantWins admin console">','<meta name="description" content="InstantWins admin console"><meta name="robots" content="noindex">')+'<main class="wrap"><div class="legal"><h1 style="margin-bottom:10px">Admin</h1><div class="err" id="gate"></div><div id="console" style="display:none">'+tabs+'\n'+'\n'.join(panels)+'\n</div></div></main>'+FOOT+MBAR+'\n<script src="c2.js"></script><script>\n'+PRE+'\n'.join(js)+'\nshowTab();\n</script></body></html>'
open('admin.html','w').write(html)

# ---------- AFFILIATE ----------
PAGE='affiliate.html'
aff=head('Affiliate programme','Earn a fixed fee for every new player you send to InstantWins.co.uk. CPA only, paid monthly.')+'''<main class="wrap"><div class="legal">
  <h1>Affiliate programme</h1>
  <p class="lead">Promote InstantWins and earn a <b>fixed fee (CPA)</b> for each new player you refer who places a paid entry. We do not pay revenue share: partners are never paid out of players&rsquo; losses. Enter your code to see your link and stats.</p>
  <div class="panel"><h2>Your dashboard</h2><label>Affiliate code</label><input id="code" placeholder="your code"><button class="btn" id="go" style="margin-top:10px">View stats</button><div class="err" id="err"></div>
    <div id="out" style="display:none"><div class="linkbox"><span id="lk"></span><button class="pill" id="copy" style="cursor:pointer">Copy</button></div><p class="lead" id="outName" style="margin-top:10px"></p><div class="kv" id="grid"></div></div></div>
  <div class="panel"><h2>How it pays</h2><p class="lead"><b>CPA only:</b> <b>&pound;10</b> per referred player who makes a first deposit and places a paid entry, paid monthly by bank transfer. No revenue share, ever.</p>
    <p class="lead">Partners must follow the CAP Code and must not target under-18s or self-excluded people, or email gambling-derived lists without separate consent. InstantWins may be listed on pages that also carry licensed betting or casino products provided it is presented as what it is &mdash; a free-entry prize competition site, not a bookmaker, casino or licensed gambling product &mdash; is never shown under a &ldquo;casino&rdquo;, &ldquo;betting&rdquo; or &ldquo;gambling&rdquo; heading, carries the words &ldquo;free entry by post&rdquo; wherever a price is shown, and uses creatives we have approved or plain text.</p>
    <p class="lead"><b>To apply:</b> create a player account, then email <a href="mailto:partners@instantwins.co.uk">partners@instantwins.co.uk</a> with your site and the code you would like. Approval is normally same day. We give 30 days&rsquo; notice of any change to these terms and either side may end the partnership at any time.</p></div>
</div></main>'''+FOOT+MBAR+'''
<script src="c2.js"></script><script>
(function(){const $=id=>document.getElementById(id); const money=p=>'£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:2}); const esc=x=>{const d=document.createElement('div');d.textContent=x;return d.innerHTML;};
function show(a){ const link=(location.origin.indexOf('http')===0?location.origin:'https://instantwins.co.uk')+'/?ref='+a.code; $('out').style.display=''; $('outName').textContent=a.name+' · '+money(a.rate)+' CPA · '+a.status; $('lk').textContent=link; $('lk').dataset.l=link;
  $('grid').innerHTML='<div><b>'+a.signups+'</b><i>Sign-ups</i></div><div><b>'+a.players+'</b><i>Players</i></div><div><b>'+money(a.revenue_p)+'</b><i>Revenue generated</i></div><div><b style="color:var(--lime)">'+money(a.commission_p)+'</b><i>Commission owed</i></div>'; }
function look(){ const c=($('code').value||'').trim(); if(!c)return; $('err').textContent='';
  fetch('/api/affiliate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:c})}).then(r=>r.json().then(d=>{if(!r.ok||d.error)throw new Error(d.error||'not found');return d;})).then(show).catch(e=>{$('err').textContent=e.message;$('out').style.display='none';}); }
$('go').onclick=look; $('code').addEventListener('keydown',e=>{if(e.key==='Enter')look();});
$('copy').onclick=()=>{const l=$('lk').dataset.l||'';navigator.clipboard&&navigator.clipboard.writeText(l);$('copy').textContent='Copied';setTimeout(()=>{$('copy').textContent='Copy';},1200);};
const pre=new URLSearchParams(location.search).get('code'); if(pre){$('code').value=pre;look();}
})();</script></body></html>'''
open('affiliate.html','w').write(aff)

# ---------- SUPPORT ----------
PAGE='support.html'
sup=head('Support','Message the InstantWins team and read announcements.')+'''<main class="wrap"><div class="legal">
  <h1>Support</h1>
  <p class="lead">Message us directly &mdash; replies land right here and by email. Announcements from the team appear below. You can also email <a href="mailto:support@instantwins.co.uk">support@instantwins.co.uk</a>.</p>
  <div class="panel"><h2>Announcements</h2><div id="ann"><span class="m">Loading…</span></div></div>
  <div class="panel"><h2>Your conversation</h2>
    <div id="thread" class="thread"></div>
    <label>Message</label><textarea id="body" rows="4" placeholder="How can we help?"></textarea>
    <button class="btn" id="send" style="margin-top:10px">Send</button>
    <div class="err" id="err"></div>
  </div>
  <div class="panel"><h2>Common questions</h2>
    <p class="lead"><b>Where is my prize?</b> Cash prizes are credited to your balance the moment a ticket is opened. Withdraw any time from your <a href="account.html">account</a>.</p>
    <p class="lead"><b>How do I enter for free?</b> By post &mdash; see <a href="free.html">free entry</a>. Same tickets, same odds.</p>
    <p class="lead"><b>Is it fair?</b> Every prize is fixed before the round opens and the seed hash is published. See <a href="fair.html">fairness</a>.</p>
    <p class="lead"><b>Complaints</b> go through our <a href="complaints.html">complaints procedure</a>.</p></div>
</div></main>'''+FOOT+MBAR+'''
<script src="c2.js"></script><script>
(function(){const $=id=>document.getElementById(id); const esc=x=>{const d=document.createElement('div');d.textContent=x;return d.innerHTML;};
async function api(path,body){const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});const d=await r.json();if(!r.ok||d.error)throw new Error(d.error||'failed');return d;}
let s=null; try{s=JSON.parse(localStorage.getItem('iw_session'));}catch(e){}
if(!s){ $('thread').innerHTML='<p class="lead" style="margin:0">Sign in to message us.</p>'; $('send').textContent='Sign in'; $('send').onclick=()=>location.href='signin.html'; $('ann').innerHTML='<span class="m">Sign in to see announcements.</span>'; return; }
async function load(){ try{ const d=await api('/api/support',{action:'list',token:s.token});
  $('ann').innerHTML=(d.announcements||[]).length?d.announcements.map(a=>'<div class="row" style="display:block"><b>'+esc(a.title)+'</b> <span class="m">'+new Date(a.at).toLocaleDateString()+'</span><br><span class="m">'+esc(a.body)+'</span></div>').join(''):'<span class="m">No announcements yet.</span>';
  $('thread').innerHTML=(d.messages||[]).map(m=>'<div class="msg '+m.sender+'">'+esc(m.body)+'<div class="t">'+(m.sender==='admin'?'InstantWins team · ':'You · ')+new Date(m.at).toLocaleString()+'</div></div>').join('')||'<span class="m">Start the conversation below.</span>';
 }catch(e){$('err').textContent=e.message;} }
$('send').onclick=async()=>{ const b=$('body').value.trim(); if(!b)return; $('send').disabled=true; try{await api('/api/support',{action:'send',token:s.token,body:b});$('body').value='';await load();}catch(e){$('err').textContent=e.message;} $('send').disabled=false; };
load(); setInterval(load,15000);
})();</script></body></html>'''
open('support.html','w').write(sup)
print('built')
