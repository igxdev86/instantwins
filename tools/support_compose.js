$('mcGo').onclick=async()=>{ $('mcErr').className='err'; $('mcErr').textContent=''; $('mcGo').disabled=true;
  try{ const r=await api('/api/admin',{action:'mailone',token:s.token,to:$('mcTo').value,subject:$('mcSub').value,body:$('mcBody').value}); $('mcErr').className='err ok'; $('mcErr').textContent='Sent to '+r.to+(r.member?'':' (not a member)'); $('mcBody').value=''; $('mcSub').value=''; if(typeof loadThreads==='function')loadThreads(); }
  catch(e){ $('mcErr').textContent=e.message; } $('mcGo').disabled=false; };
