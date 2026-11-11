/* InstantWins (Concept 2) shared client: session, ticket bank, round state */
const C2=(()=>{
  const TABLE=[[10000000,1],[2500000,2],[500000,5],[100000,20],[25000,100],[5000,1000],[1000,10000],[500,50000],[200,100000],[100,200000]];
  const CAP=2000000;
  const PACKS=[[1,100],[5,450],[10,800],[25,1800],[50,3200],[100,6000]];
  const gbp=p=>p===0?'£0':p<100?p+'p':'£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:p%100?2:0,maximumFractionDigits:2});
  let S=null; try{S=JSON.parse(localStorage.getItem('iw_session'));}catch(e){} const TOKEN=S&&S.token;
  const post=(body)=>fetch('/api/c2',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.assign({token:TOKEN},body))}).then(async r=>{const d=await r.json(); if(!r.ok||d.error)throw new Error(d.error||'failed'); return d;});
  const state=()=>fetch('/api/c2',{cache:'no-store'}).then(r=>r.json());
  const mine=()=>TOKEN?post({action:'mine'}):Promise.resolve(null);
  const buy=n=>post({action:'buy',n});
  const reveal=()=>post({action:'reveal'});
  const revealAll=()=>post({action:'revealall'});
  function header(m){ const box=document.getElementById('bankBox'); if(!box)return;
    document.body.classList.toggle('signed',!!TOKEN);
    if(!TOKEN){ box.innerHTML='<a class="cta" href="signin.html">Sign in</a>'; return; }
    if(!m){ try{m=JSON.parse(localStorage.getItem('iw_c2hdr'));}catch(e){} } else { try{localStorage.setItem('iw_c2hdr',JSON.stringify({bank:m.bank,balance_p:m.balance_p}));}catch(e){} }
    const bank=m&&m.bank!=null?m.bank:'–', bal=m&&m.balance_p!=null?gbp(m.balance_p):'–';
    box.innerHTML='<a class="bk" href="account.html" title="My tickets"><svg viewBox="0 0 24 24"><path d="M3 9a2 2 0 0 0 2-2V5h14v2a2 2 0 0 0 0 4v2a2 2 0 0 0 0 4v2H5v-2a2 2 0 0 0-2-2z"/><path d="M12 5v14" stroke-dasharray="2 2"/></svg><b id="bankN">'+bank+'</b><small>tickets</small></a><a class="bal" id="balN" href="account.html">'+bal+'</a><a class="cta" href="index.html#buy">Buy</a>'; }
  const acceptTerms=()=>post({action:'accept_terms'});
  const profile=(county,publish)=>post({action:'profile',county,publish});
  function termsModal(){ if(document.getElementById('iwTerms'))return; const d=document.createElement('div'); d.id='iwTerms'; d.className='ldm'; d.style.zIndex=70;
    d.innerHTML='<div class="modal"><h2>Updated terms</h2><p>Our <a href="terms.html" target="_blank">terms &amp; conditions</a> have changed. Please read them and accept to carry on playing.</p><div class="mrow"><button class="btn lime" id="iwTermsOk">I accept</button><a class="btn ghost" href="account.html#close">Close my account</a></div></div>';
    document.body.appendChild(d); document.getElementById('iwTermsOk').onclick=async()=>{ try{ await acceptTerms(); d.remove(); checkin(); }catch(e){} }; }
  // £50+/day check-in (responsible play) — once per day per device, after a spend
  function checkin(){ if(!TOKEN)return; const KEY='iw_checkin_day', today=new Date().toLocaleDateString('en-GB'); try{ if(localStorage.getItem(KEY)===today)return; }catch(e){}
    fetch('/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'limits',token:TOKEN})}).then(r=>r.json()).then(l=>{ if(!l||!(l.spent_today_p>=5000)||document.getElementById('iwChk')||document.getElementById('iwTerms'))return;
      const d=document.createElement('div'); d.id='iwChk'; d.className='ldm'; d.style.zIndex=70;
      d.innerHTML='<div class="modal"><h2>Quick check-in</h2><p>You have spent <b>'+gbp(l.spent_today_p)+'</b> on tickets today'+(l.daily_limit_p!=null?' against a limit of '+gbp(l.daily_limit_p):' and have no daily limit set')+'. Prizes are a matter of luck and most tickets win nothing. Happy to carry on?</p><div class="mrow"><button class="btn lime" id="iwChkGo">Carry on</button><a class="btn ghost" href="account.html#limits">Set a limit / take a break</a></div><p class="m" style="margin:12px 0 0">Support: GamCare 0808 8020 133 · <a href="responsible-play.html">Responsible play</a></p></div>';
      document.body.appendChild(d); document.getElementById('iwChkGo').onclick=()=>{ try{localStorage.setItem(KEY,today);}catch(e){} d.remove(); }; }).catch(()=>{}); }
  return {TABLE,CAP,PACKS,gbp,TOKEN,state,mine,buy,reveal,revealAll,header,acceptTerms,profile,termsModal,checkin};
})();
document.addEventListener('DOMContentLoaded',()=>{C2.header(); C2.mine().then(m=>{C2.header(m); if(m&&m.terms_due)C2.termsModal();}).catch(()=>{});});

window.__site=fetch('/api/site',{cache:'no-store'}).then(r=>r.json()).then(d=>{ d=d||{}; if(d.live)document.querySelectorAll('.testmode').forEach(e=>e.remove()); document.documentElement.classList.toggle('games-on',!!d.games); return d; }).catch(()=>({}));
