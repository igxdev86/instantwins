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
    if(!TOKEN){ box.innerHTML='<a class="cta" href="signin.html">Sign in</a>'; return; }
    if(!m){ try{m=JSON.parse(localStorage.getItem('iw_c2hdr'));}catch(e){} } else { try{localStorage.setItem('iw_c2hdr',JSON.stringify({bank:m.bank,balance_p:m.balance_p}));}catch(e){} }
    const bank=m&&m.bank!=null?m.bank:'–', bal=m&&m.balance_p!=null?gbp(m.balance_p):'–';
    box.innerHTML='<a class="bk" href="account.html" title="My tickets"><svg viewBox="0 0 24 24"><path d="M3 9a2 2 0 0 0 2-2V5h14v2a2 2 0 0 0 0 4v2a2 2 0 0 0 0 4v2H5v-2a2 2 0 0 0-2-2z"/><path d="M12 5v14" stroke-dasharray="2 2"/></svg><b id="bankN">'+bank+'</b><small>tickets</small></a><a class="bal" id="balN" href="account.html">'+bal+'</a><a class="cta" href="index.html#buy">Buy</a>'; }
  return {TABLE,CAP,PACKS,gbp,TOKEN,state,mine,buy,reveal,revealAll,header};
})();
document.addEventListener('DOMContentLoaded',()=>{C2.header(); C2.mine().then(m=>C2.header(m)).catch(()=>{});});

fetch('/api/site',{cache:'no-store'}).then(r=>r.json()).then(d=>{if(d&&d.live)document.querySelectorAll('.testmode').forEach(e=>e.remove());}).catch(()=>{});
