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
  function header(m){ const el=document.getElementById('bankN'), b=document.getElementById('balN'), a=document.getElementById('hdrAct');
    if(!TOKEN){ if(el)el.textContent='0'; if(b)b.textContent='Sign in'; if(a){a.textContent='Sign in';a.href='v1/signup.html';} return; }
    if(m){ if(el)el.textContent=m.bank; if(b)b.textContent=gbp(m.balance_p); } if(a){a.textContent='Buy';a.href='index.html#buy';} }
  return {TABLE,CAP,PACKS,gbp,TOKEN,state,mine,buy,reveal,header};
})();
document.addEventListener('DOMContentLoaded',()=>{C2.header(); C2.mine().then(m=>C2.header(m)).catch(()=>{});});
