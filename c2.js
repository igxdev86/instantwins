/* InstantWins (Concept 2) shared client: session, ticket bank, round state */
const C2=(()=>{
  const TABLE=[[2000000,5],[500000,20],[200000,50],[100000,50],[50000,100],[10000,400],[5000,800],[2000,2000],[1000,5000],[500,12000],[200,40000],[100,100000],[50,250000],[25,1000000]];
  const CAP=8000000; const FACE=25;
  const PACKS=[[1,25],[5,125],[10,240],[25,575],[50,1100],[100,2100],[250,5250],[500,10000],[1000,19000]];
  const gbp=p=>p===0?'£0':p<100?p+'p':'£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:p%100?2:0,maximumFractionDigits:2});
  let S=null; try{S=JSON.parse(localStorage.getItem('iw_session'));}catch(e){} const TOKEN=S&&S.token;
  const post=(body)=>fetch('/api/c2',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.assign({token:TOKEN},body))}).then(async r=>{const d=await r.json(); if(!r.ok||d.error)throw new Error(String(d.error||'failed').replace(/insufficient credit/i,'not enough funds').replace(/not enough credit/i,'not enough funds')); return d;});
  const state=()=>fetch('/api/c2',{cache:'no-store'}).then(r=>r.json());
  const mine=()=>TOKEN?post({action:'mine'}):Promise.resolve(null);
  const buy=n=>post({action:'buy',n});
  const buyBalance=()=>post({action:'buybal'});
  const rateFor=a=>a>=19000?19:a>=10000?20:a>=2100?21:a>=1100?22:a>=575?23:a>=240?24:25;
  const balQuote=bal=>{ const r=rateFor(bal), n=Math.min(20000,Math.floor(bal/r)); return n<1?null:{n,rate:r,cost:n*r,save:n*FACE-n*r}; };
  const cachedBal=()=>{ try{ const h=JSON.parse(localStorage.getItem('iw_c2hdr')); return h&&h.balance_p!=null?h.balance_p:null; }catch(e){ return null; } };
  const reveal=()=>post({action:'reveal'});
  const revealAll=()=>post({action:'revealall'});
  function header(m){ const box=document.getElementById('bankBox'); if(!box)return;
    document.body.classList.toggle('signed',!!TOKEN);
    if(!TOKEN){ box.innerHTML='<a class="cta" href="signin.html">Sign in</a>'; return; }
    if(!m){ try{m=JSON.parse(localStorage.getItem('iw_c2hdr'));}catch(e){} } else { try{localStorage.setItem('iw_c2hdr',JSON.stringify({bank:m.bank,balance_p:m.balance_p}));}catch(e){} }
    const bank=m&&m.bank!=null?m.bank:'–', bal=m&&m.balance_p!=null?(window.innerWidth<=430&&m.balance_p>=10000?'£'+Math.floor(m.balance_p/100).toLocaleString():gbp(m.balance_p)):'–';
    box.innerHTML='<a class="bk" href="account.html" title="My tickets"><svg viewBox="0 0 24 24"><path d="M3 9a2 2 0 0 0 2-2V5h14v2a2 2 0 0 0 0 4v2a2 2 0 0 0 0 4v2H5v-2a2 2 0 0 0-2-2z"/><path d="M12 5v14" stroke-dasharray="2 2"/></svg><b id="bankN">'+bank+'</b><small>tickets</small></a><a class="bal" id="balN" href="account.html">'+bal+'</a><a class="me" href="account.html" title="My account" aria-label="My account"><svg viewBox="0 0 24 24" fill="none" stroke="#1A0A00" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8.5" r="3.6"/><path d="M4.5 20c.8-3.6 3.9-5.5 7.5-5.5s6.7 1.9 7.5 5.5"/></svg></a>'; }
  const acceptTerms=()=>post({action:'accept_terms'});
  const profile=(county,publish,marketing)=>post({action:'profile',county,publish,marketing});
  function onboardModal(){ if(document.getElementById('iwOnb'))return; const d=document.createElement('div'); d.id='iwOnb'; d.className='ldm'; d.style.zIndex=72;
    d.innerHTML='<div class="modal onb"><div class="done-k">Almost there</div><h2>Set up your account</h2><p>We need this once. You must be 18 or over and live in Great Britain to play.</p>'
      +'<label>Your name</label><input id="onName" autocomplete="name" placeholder="First and last name">'
      +'<label>Date of birth</label><div class="dob"><input id="onD" inputmode="numeric" pattern="[0-9]*" maxlength="2" placeholder="DD" autocomplete="bday-day"><input id="onM" inputmode="numeric" pattern="[0-9]*" maxlength="2" placeholder="MM" autocomplete="bday-month"><input id="onY" inputmode="numeric" pattern="[0-9]*" maxlength="4" placeholder="YYYY" autocomplete="bday-year"></div>'
      +'<label>Daily spending limit <small class="m">(optional, change any time)</small></label><select id="onLim"><option value="">No limit</option><option value="500">£5 a day</option><option value="1000">£10 a day</option><option value="2000">£20 a day</option><option value="5000">£50 a day</option><option value="0">£0 — free entries only</option></select>'
      +'<label class="chk"><input type="checkbox" id="onGb"><span>I am 18 or over and live in Great Britain</span></label>'
      +'<label class="chk"><input type="checkbox" id="onTerms"><span>I accept the <a href="terms.html" target="_blank">terms &amp; conditions</a> and <a href="privacy.html" target="_blank">privacy policy</a></span></label>'
      +'<button class="btn lime" id="onGo" style="width:100%;margin-top:14px">Start playing</button><div class="err" id="onErr"></div><p class="m" style="margin:12px 0 0">Prizes are a matter of luck and most tickets win nothing. <a href="responsible-play.html" target="_blank">Responsible play</a></p></div>';
    document.body.appendChild(d); const $=id=>document.getElementById(id);
    [['onD','onM'],['onM','onY']].forEach(([a,b])=>$(a).addEventListener('input',()=>{ if($(a).value.replace(/\D/g,'').length>=2)$(b).focus(); }));
    $('onGo').onclick=async()=>{ $('onErr').textContent=''; const dd=$('onD').value.replace(/\D/g,''), mm=$('onM').value.replace(/\D/g,''), yy=$('onY').value.replace(/\D/g,'');
      if(!$('onGb').checked){ $('onErr').textContent='Please confirm you are 18+ and live in Great Britain.'; return; } if(!$('onTerms').checked){ $('onErr').textContent='Please accept the terms to continue.'; return; }
      if(yy.length!==4||!dd||!mm){ $('onErr').textContent='Enter your full date of birth.'; return; }
      const b=$('onGo'); b.disabled=true; try{ const r=await post2('/api/auth',{action:'onboard',name:$('onName').value,dob:yy+'-'+mm.padStart(2,'0')+'-'+dd.padStart(2,'0'),gb:true,limit_p:$('onLim').value}); try{ const s=JSON.parse(localStorage.getItem('iw_session')); s.name=r.name; localStorage.setItem('iw_session',JSON.stringify(s)); }catch(e){} d.remove(); document.dispatchEvent(new CustomEvent('iw:onboarded')); if(/onboard=1/.test(location.search)){ location.href='index.html#buy'; } }catch(e){ $('onErr').textContent=e.message; b.disabled=false; } }; }
  function post2(path,body){ return fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.assign({token:TOKEN},body))}).then(async r=>{ const d=await r.json(); if(!r.ok||d.error)throw new Error(d.error||'failed'); return d; }); }
  function termsModal(){ if(document.getElementById('iwTerms'))return; const d=document.createElement('div'); d.id='iwTerms'; d.className='ldm'; d.style.zIndex=70;
    d.innerHTML='<div class="modal"><h2>Updated terms</h2><p>Our <a href="terms.html" target="_blank">terms &amp; conditions</a> have changed. Please read them and accept to carry on playing.</p><div class="mrow"><button class="btn lime" id="iwTermsOk">I accept</button><a class="btn ghost" href="account.html#close">Close my account</a></div></div>';
    document.body.appendChild(d); document.getElementById('iwTermsOk').onclick=async()=>{ try{ await acceptTerms(); d.remove(); checkin(); }catch(e){} }; }
  // £50+/day check-in (responsible play) — once per day per device, after a spend
  function checkin(){ if(!TOKEN)return; const KEY='iw_checkin_day', today=new Date().toLocaleDateString('en-GB'); try{ if(localStorage.getItem(KEY)===today)return; }catch(e){}
    fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'limits',token:TOKEN})}).then(r=>r.json()).then(l=>{ if(!l||!(l.spent_today_p>=5000)||document.getElementById('iwChk')||document.getElementById('iwTerms'))return;
      const d=document.createElement('div'); d.id='iwChk'; d.className='ldm'; d.style.zIndex=70;
      d.innerHTML='<div class="modal"><h2>Quick check-in</h2><p>You have spent <b>'+gbp(l.spent_today_p)+'</b> on tickets today'+(l.daily_limit_p!=null?' against a limit of '+gbp(l.daily_limit_p):' and have no daily limit set')+'. Prizes are a matter of luck and most tickets win nothing. Happy to carry on?</p><div class="mrow"><button class="btn lime" id="iwChkGo">Carry on</button><a class="btn ghost" href="account.html#limits">Set a limit / take a break</a></div><p class="m" style="margin:12px 0 0">Support: GamCare 0808 8020 133 · <a href="responsible-play.html">Responsible play</a></p></div>';
      document.body.appendChild(d); document.getElementById('iwChkGo').onclick=()=>{ try{localStorage.setItem(KEY,today);}catch(e){} d.remove(); }; }).catch(()=>{}); }
  // in-page buy sheet: pick a pack, buy, stay where you are. onDone(d) gets the buy result.
  function skillGate(then){ (window.__site||Promise.resolve({})).then(site=>{ if(!site||!site.skill_q){ then(); return; } state().then(st=>{ const key='iw_q_'+(st&&st.round), each=site.skill_q==='each'; try{ if(!each&&localStorage.getItem(key)==='ok'){ then(); return; } }catch(e){}
      fetch('/api/c2?q=1',{cache:'no-store'}).then(r=>r.json()).then(Q=>{ if(document.getElementById('iwQ'))return; const d=document.createElement('div'); d.id='iwQ'; d.className='ldm'; d.style.zIndex=67;
        d.innerHTML='<div class="modal"><div class="done-k">Qualifying question</div><h2>'+Q.q+'</h2><p>'+(site.skill_q==='each'?'Answer correctly to buy tickets.':'Answer correctly to enter this round. One answer covers every ticket you buy in it.')+'</p><div class="qopts">'+Q.opts.map(o=>'<button type="button" class="btn ghost" data-a="'+o+'">'+o+'</button>').join('')+'</div><div class="err" id="iwQErr"></div><p class="m" style="margin:12px 0 0">Or <a href="free.html">enter free by post</a> &mdash; no question needed.</p></div>';
        document.body.appendChild(d); d.querySelectorAll('[data-a]').forEach(b=>b.onclick=async()=>{ try{ const r=await post({action:'answer',q:Q.q,sig:Q.sig,exp:Q.exp,answer:b.dataset.a}); if(r.ok){ try{ if(!each)localStorage.setItem(key,'ok'); }catch(e){} d.remove(); then(); } else { document.getElementById('iwQErr').textContent='Not right — try another.'; } }catch(e){ document.getElementById('iwQErr').textContent=e.message; } }); }).catch(()=>then()); }).catch(()=>then()); }); }
  function buySheet(onDone){ if(!TOKEN){ location.href='signin.html'; return; } if(document.getElementById('iwBuy'))return; if(window.__needOnboard){ onboardModal(); document.addEventListener('iw:onboarded',()=>{ window.__needOnboard=false; buySheet(onDone); },{once:true}); return; } skillGate(()=>buySheet2(onDone)); }
  function buySheet2(onDone){ if(document.getElementById('iwBuy'))return; let sel=1;
    const d=document.createElement('div'); d.id='iwBuy'; d.className='ldm'; d.style.zIndex=66;
    d.innerHTML='<div class="modal buy"><button type="button" class="x" id="iwBuyX" aria-label="close">&times;</button><div class="done-k">Buy tickets</div><h2>How many tickets?</h2><div class="packs mini" id="iwPacks"></div><div class="buyrow"><div><b id="iwSelT"></b><span id="iwSelP"></span><small id="iwSelE"></small></div><button class="btn lime" id="iwBuyGo">Buy</button></div><div class="err" id="iwBuyErr"></div><p class="m" style="margin:12px 0 10px">Balance <b id="iwBuyBal">–</b> · <a href="account.html#money">add funds</a></p><a class="freebtn" href="free.html"><b>No purchase necessary</b><span>Enter free by post &mdash; same tickets, same odds, same End Prize Draw &rarr;</span></a></div>';
    document.body.appendChild(d);
    const $=id=>document.getElementById(id);
    function paint(){ const bal=cachedBal(), q=bal!=null?balQuote(bal):null;
      $('iwPacks').innerHTML=PACKS.map(([n,p],i)=>{const full=n*FACE, sv=full-p; return '<div class="pack'+(i===sel?' sel':'')+'" data-i="'+i+'">'+(sv?'<span class="save">SAVE '+gbp(sv)+'</span>':'')+'<div class="t">'+n+'<small>ticket'+(n>1?'s':'')+'</small></div><div class="p">'+gbp(p)+'</div></div>';}).join('')
        +(q?'<div class="pack all'+(sel==='bal'?' sel':'')+'" data-i="bal">'+(q.save?'<span class="save">SAVE '+gbp(q.save)+'</span>':'')+'<div class="t">'+q.n.toLocaleString()+'<small>tickets</small></div><div class="p">'+gbp(q.cost)+'</div><div class="each">whole balance · '+q.rate+'p each</div></div>':'');
      if(sel==='bal'&&q){ $('iwSelT').textContent=q.n.toLocaleString()+' tickets'; $('iwSelP').textContent=gbp(q.cost); $('iwSelE').textContent=q.rate+'p each · uses your whole balance'; $('iwBuyGo').textContent='Buy for '+gbp(q.cost); }
      else { if(sel==='bal')sel=1; const [n,p]=PACKS[sel]; $('iwSelT').textContent=n+' ticket'+(n>1?'s':''); $('iwSelP').textContent=gbp(p); $('iwSelE').textContent=gbp(Math.round(p/n))+' each'; $('iwBuyGo').textContent='Buy for '+gbp(p); }
      d.querySelectorAll('.pack').forEach(el=>el.onclick=()=>{sel=el.dataset.i==='bal'?'bal':+el.dataset.i;paint();}); }
    paint(); try{ const h=JSON.parse(localStorage.getItem('iw_c2hdr')); if(h&&h.balance_p!=null)$('iwBuyBal').textContent=gbp(h.balance_p); }catch(e){}
    const close=()=>d.remove(); $('iwBuyX').onclick=close; d.addEventListener('click',e=>{ if(e.target===d)close(); });
    $('iwBuyGo').onclick=async()=>{ const b=$('iwBuyGo'); b.disabled=true; b.textContent='Buying…'; $('iwBuyErr').textContent='';
      try{ const r=sel==='bal'?await buyBalance():await buy(PACKS[sel][0]); if(typeof SND!=='undefined')SND.buy(); header({bank:r.bank,balance_p:r.balance_p}); close(); checkin(); if(onDone)onDone(r); }
      catch(e){ $('iwBuyErr').textContent=e.message; b.disabled=false; b.textContent='Buy'; paint(); } }; }
  return {TABLE,CAP,PACKS,gbp,TOKEN,state,mine,buy,buyBalance,balQuote,cachedBal,reveal,revealAll,header,acceptTerms,profile,termsModal,onboardModal,checkin,buySheet};
})();
function __sync(){ if(!C2.TOKEN)return; C2.mine().then(m=>{ window.__needOnboard=!!(m&&m.onboard); C2.header(m); if(m&&m.onboard)C2.onboardModal(); else if(m&&m.terms_due)C2.termsModal(); document.dispatchEvent(new CustomEvent('iw:sync',{detail:m})); }).catch(()=>{}); }
document.addEventListener('DOMContentLoaded',()=>{ C2.header(); __sync(); });
document.addEventListener('click',e=>{ const a=e.target.closest('a[href$="#buy"]'); if(!a||document.body.dataset.g)return; if(!C2.TOKEN){ e.preventDefault(); location.href='signin.html'; return; } e.preventDefault(); C2.buySheet(r=>{ if(!/game\.html/.test(location.pathname)){ location.href='game.html?g=quick'; } }); });
window.addEventListener('pageshow',e=>{ if(e.persisted)__sync(); });
document.addEventListener('visibilitychange',()=>{ if(!document.hidden)__sync(); });
window.addEventListener('focus',__sync);
setInterval(()=>{ if(!document.hidden)__sync(); },30000);

window.__site=fetch('/api/site',{cache:'no-store'}).then(r=>r.json()).then(d=>{ d=d||{}; if(d.live)document.querySelectorAll('.testmode').forEach(e=>e.remove()); document.documentElement.classList.toggle('games-on',!!d.games); return d; }).catch(()=>({}));
