
(function(){
function money(p){return '£'+(p/100).toLocaleString('en-GB',{minimumFractionDigits:2});}
function when(t){return t?new Date(t).toLocaleString('en-GB',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}):'';}
async function loadCard(){ try{ const d=await api('/api/admin',{action:'cardpay',token:s.token});
  const sw=$('cardSw'); sw.className='sw'+(d.card_on?' on':''); sw.onclick=async()=>{ const on=!sw.classList.contains('on'); if(on&&!confirm('Open card deposits to all players?'))return; try{ await api('/api/admin',{action:'setting',token:s.token,key:'card_on',value:on?'true':'false'}); sw.classList.toggle('on',on); }catch(e){ $('cfErr').textContent=e.message; } };
  $('cfToday').textContent=money(d.paid_today_p||0); $('cf30').textContent=money(d.paid_30d_p||0);
  const rows=d.rows||[]; $('cfRows').innerHTML=rows.length?rows.map(x=>'<div class="krow"><span class="nm">'+money(x.amount_p)+' · <b>'+esc(x.ref)+'</b><small>'+esc(x.name||'')+' · '+esc(x.email||'')+' · '+when(x.created_at)+(x.job_ref?' · job '+esc(x.job_ref):'')+(x.note?' · '+esc(x.note):'')+'</small></span><span class="pill '+(x.status==='paid'?'ok':x.status==='pending'||x.status==='started'?'warn':'')+'">'+esc(x.status)+'</span></div>').join(''):'<span class="m">No card payments yet.</span>';
 }catch(e){ $('cfErr').textContent=e.message; } }
fetch('/api/cashflows',{cache:'no-store'}).then(r=>r.json()).then(g=>{ $('cfEnv').textContent=g.env==='live'?'live':'sandbox (gateway-int)'; $('cfStat').textContent=g.enabled?'configured':'keys missing'; $('cfStat').className='pill '+(g.enabled?'ok':'warn'); }).catch(()=>{});
(async()=>{ if(await guard()){ loadCard(); setInterval(loadCard,60000);} })();
})();
