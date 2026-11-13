(function(){
let curKey=null, curName='';
function when(t){ return new Date(t).toLocaleString('en-GB',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}); }
async function loadThreads(){ try{ const t=await api('/api/admin',{action:'threads',token:s.token});
  $('threads').innerHTML=t.length?t.map(x=>'<div class="krow'+(x.unread>0?' hot':'')+'"><span class="nm">'+(x.unread>0?'<b class="dot"></b>':'')+esc(x.name)+(x.member?'':' <small class="pill">not a member</small>')+'<small>'+esc(x.email)+' · '+(x.channel==='email'?'email':'site')+(x.subject?' · '+esc(x.subject):'')+' · '+when(x.last_at)+' · '+x.count+' msg'+(x.unread>0?' · <b style="color:var(--lime)">'+x.unread+' new</b>':'')+'</small></span>'
    +'<button class="pill" style="cursor:pointer;border:none" data-key="'+esc(x.key)+'" data-name="'+esc(x.name)+'">Open</button></div>').join(''):'<span class="m">Inbox empty.</span>';
  $('threads').querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>openThread(b.dataset.key,b.dataset.name));
  const unread=t.reduce((a,x)=>a+(x.unread||0),0); const tile=$('tSup'); if(tile)tile.textContent=unread?unread+' new':t.length;
 }catch(e){ $('threads').innerHTML='<span class="m">'+esc(e.message)+'</span>'; } }
async function openThread(key,name){ curKey=key; curName=name; $('threadPanel').style.display=''; $('threadTitle').textContent=name;
  const m=await api('/api/admin',{action:'thread',token:s.token,key});
  $('threadMeta').textContent=(key.startsWith('mail:')?key.slice(5)+' — not a member, replies go by email only':'Member — replies go by email and into their site thread');
  $('reTo').textContent='Sends to '+(key.startsWith('mail:')?key.slice(5):'their account email');
  $('thread').innerHTML=m.map(x=>'<div class="msg '+(x.sender==='admin'?'user':'admin')+'">'+(x.subject&&x.sender!=='admin'?'<div class="t" style="margin:0 0 6px;color:var(--cyan)">'+esc(x.subject)+'</div>':'')+esc(x.body).replace(/\n/g,'<br>')+'<div class="t">'+(x.sender==='admin'?'InstantWins':name)+' · '+(x.channel==='email'?'email':'site')+' · '+when(x.at)+'</div></div>').join('')||'<span class="m">No messages.</span>';
  $('threadPanel').scrollIntoView({behavior:'smooth'}); loadThreads(); }
$('reGo').onclick=async()=>{ const b=$('reBody').value.trim(); if(!b||!curKey)return; $('reGo').disabled=true; $('reErr').className='err'; $('reErr').textContent='';
  try{ await api('/api/admin',{action:'reply',token:s.token,key:curKey,body:b}); $('reBody').value=''; $('reErr').className='err ok'; $('reErr').textContent='Sent.'; openThread(curKey,curName); }
  catch(e){ $('reErr').textContent=e.message; } $('reGo').disabled=false; };
$('mcGo').onclick=async()=>{ $('mcErr').className='err'; $('mcErr').textContent=''; $('mcGo').disabled=true;
  try{ const r=await api('/api/admin',{action:'mailone',token:s.token,to:$('mcTo').value,subject:$('mcSub').value,body:$('mcBody').value}); $('mcErr').className='err ok'; $('mcErr').textContent='Sent to '+r.to+(r.member?'':' (not a member)'); $('mcBody').value=''; $('mcSub').value=''; if(typeof loadThreads==='function')loadThreads(); }
  catch(e){ $('mcErr').textContent=e.message; } $('mcGo').disabled=false; };

fetch('/api/inbound').then(r=>{ $('inStat').textContent=r.status===405?'endpoint live':'check'; $('inStat').className='pill '+(r.status===405?'ok':'warn'); }).catch(()=>{});
(async()=>{ if(await guard()){ loadThreads(); setInterval(loadThreads,45000); } })();
})();
