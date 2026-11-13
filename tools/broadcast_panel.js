(function(){
async function counts(){ try{ const c=await api('/api/admin',{action:'mailcounts',token:s.token}); $('bcMembers').textContent=c.members; $('bcOpt').textContent=c.opted_in; $('bcBuy').textContent=c.buyers; $('bcPend').textContent=c.pending; }catch(e){} }
$('bcGo').onclick=async()=>{ const aud=$('bcAud').value; $('bcErr').className='err'; $('bcErr').textContent='';
  if(aud!=='test'&&!confirm('Send this to '+(aud==='all'?$('bcOpt').textContent:$('bcBuy').textContent)+' people? It cannot be recalled.'))return;
  $('bcGo').disabled=true; try{ const r=await api('/api/admin',{action:'mailall',token:s.token,subject:$('bcSub').value,body:$('bcBody').value,audience:aud}); $('bcErr').className='err ok'; $('bcErr').textContent=r.queued+' queued — they go out over the next few minutes.'; counts(); }
  catch(e){ $('bcErr').textContent=e.message; } $('bcGo').disabled=false; };
(async()=>{ if(await guard()){ counts(); } })();
})();
