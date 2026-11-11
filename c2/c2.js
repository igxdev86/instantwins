/* Concept 2 shared: mock ticket bank + master prize round (browser-only prototype) */
const C2=(()=>{
  // Master round: 2,000,000 tickets at £1 — £1,020,000 in prizes (51%). One table, every game plays it.
  const TABLE=[[10000000,1],[2500000,2],[500000,5],[100000,20],[25000,100],[5000,1000],[1000,10000],[500,50000],[200,100000],[100,200000]];
  const CAP=2000000;
  const PACKS=[[1,100],[5,450],[10,800],[25,1800],[50,3200],[100,6000]];
  const gbp=p=>p===0?'£0':p<100?p+'p':'£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:p%100?2:0,maximumFractionDigits:2});
  const S=()=>{try{return JSON.parse(localStorage.getItem('c2')||'{}');}catch(e){return {};}};
  const save=s=>localStorage.setItem('c2',JSON.stringify(s));
  function state(){const s=S(); if(!s.bank){s.bank=[];s.balance=5000;s.sold=412877;s.played=[];save(s);} return s;}
  // prize draw for a ticket: proportional to the table (prototype only; live = pre-allocated on the server)
  function draw(){const r=Math.random()*CAP; let acc=0; for(const [p,n] of TABLE){acc+=n; if(r<acc)return p;} return 0;}
  function buy(n,price){const s=state(); if(s.balance<price)throw new Error('Not enough credit (prototype balance '+gbp(s.balance)+')'); s.balance-=price; for(let i=0;i<n;i++){s.sold++; s.bank.push({no:s.sold,prize:draw()});} save(s); return s;}
  function play(){const s=state(); const t=s.bank.shift(); if(!t)return null; s.played.push(t); if(t.prize)s.balance+=t.prize; save(s); return t;}
  function reset(){localStorage.removeItem('c2');}
  const TOTAL=TABLE.reduce((a,[p,n])=>a+p*n,0), WINS=TABLE.reduce((a,[p,n])=>a+n,0);
  function header(){const s=state(); const el=document.getElementById('bankN'); if(el)el.textContent=s.bank.length; const b=document.getElementById('balN'); if(b)b.textContent=gbp(s.balance);}
  return {TABLE,CAP,PACKS,TOTAL,WINS,gbp,state,buy,play,reset,header};
})();
document.addEventListener('DOMContentLoaded',C2.header);
