(function(){
const ST={new:'New',contacted:'Contacted',replied:'Replied',joined:'Joined',no:'No'};
function when(t){ return t?new Date(t).toLocaleDateString('en-GB',{day:'numeric',month:'short'}):''; }
function parsePaste(txt){ const lines=txt.split(/\r?\n/).map(l=>l.trim()).filter(Boolean); if(!lines.length)return [];
  const sep=lines[0].includes('\t')?'\t':(lines[0].split(',').length>2?',':null);
  let cols=null, start=0; if(sep){ const h=lines[0].split(sep).map(x=>x.replace(/^"|"$/g,'').trim().toLowerCase()); if(h.some(x=>/domain|target|url|website/.test(x))){ cols=h; start=1; } }
  const rows=[]; for(const l of lines.slice(start)){ const c=sep?l.split(sep).map(x=>x.replace(/^"|"$/g,'').trim()):[l];
    const pick=re=>{ if(!cols)return null; const i=cols.findIndex(x=>re.test(x)); return i>=0?c[i]:null; };
    const domain=(cols?(pick(/^(target|domain|website|url|site)/)||c[0]):c[0])||''; if(!domain)continue;
    rows.push({domain, dr:pick(/^(dr|domain rating)$/)||null, traffic:pick(/traffic|organic/)||null, email:pick(/e-?mail/)||null, name:pick(/^(name|title)$/)||null}); }
  return rows; }
const FREE=/^(gmail|googlemail|hotmail|outlook|live|yahoo|icloud|me|aol|btinternet|sky|virginmedia|protonmail|proton|msn|talktalk|ntlworld)\.(com|co\.uk|net|org)$/i;
function parseContacts(txt){ const lines=txt.split(/\r?\n/).map(l=>l.trim()).filter(Boolean); if(!lines.length)return [];
  const sep=lines[0].includes('\t')?'\t':',';
  const h=lines[0].split(sep).map(x=>x.replace(/^"|"$/g,'').trim().toLowerCase()); let cols=null,start=0; if(h.some(x=>/e-?mail/.test(x))&&!/@/.test(lines[0])){ cols=h; start=1; }
  const out=[]; for(const l of lines.slice(start)){ let email=null,name=null,domain=null;
    if(cols){ const c=l.split(sep).map(x=>x.replace(/^"|"$/g,'').trim()); const pick=re=>{ const i=cols.findIndex(x=>re.test(x)); return i>=0?c[i]:null; }; email=pick(/e-?mail/); name=pick(/^(name|full name|contact|first)/)||[pick(/first/),pick(/last|surname/)].filter(Boolean).join(' ')||null; domain=pick(/domain|website|site|url|company/); }
    else { const m=l.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i); if(!m)continue; email=m[0]; const rest=l.replace(m[0],' ').replace(/[<>,;|]/g,' ').split(/\s{2,}|\s(?=[a-z0-9.-]+\.[a-z]{2,}$)/i); for(const t of rest.map(x=>x.trim()).filter(Boolean)){ if(/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(t)) domain=t; else if(!name) name=t; } }
    if(!email)continue; email=email.toLowerCase(); const ed=email.split('@')[1]; if(!domain){ domain=FREE.test(ed)?'':ed; }
    out.push({domain:domain||'',email,name:name||null,source:'contacts'}); }
  return out; }
async function load(){ try{ const d=await api('/api/admin',{action:'outreach',token:s.token,status:$('orStatus').value,q:$('orQ').value});
  const c=d.counts||{}; $('orCounts').textContent=['new','contacted','replied','joined','no'].filter(k=>c[k]).map(k=>c[k]+' '+ST[k].toLowerCase()).join(' · ');
  if(!$('orSub').value&&d.subject){ $('orSub').value=d.subject; $('orBody').value=d.body||''; }
  const rows=d.rows||[]; $('orList').innerHTML=rows.length?rows.map(o=>'<div class="orow" data-d="'+esc(o.domain)+'">'
    +'<div class="orhead">'+(o.domain.includes('@')?'<b>'+esc(o.name||o.domain)+'</b>'+(o.name?' <span class="m">'+esc(o.domain)+'</span>':''):'<a href="https://'+esc(o.domain)+'" target="_blank" rel="noopener"><b>'+esc(o.domain)+'</b></a>'+(o.name?' <span class="m">'+esc(o.name)+'</span>':''))+'<span class="pill '+(o.status==='joined'?'ok':o.status==='replied'?'warn':'')+'">'+ST[o.status]+'</span></div>'
    +'<div class="ormeta">'+(o.dr!=null?'DR '+o.dr+' · ':'')+(o.traffic!=null?o.traffic.toLocaleString()+' visits · ':'')+(o.contacted_at?'emailed '+when(o.contacted_at)+' · ':'')+(o.aff_code?'code '+esc(o.aff_code)+' · ':'')+(o.domain.includes('@')?'contact':'<a href="https://app.ahrefs.com/site-explorer/overview/v2/subdomains/live?target='+encodeURIComponent(o.domain)+'" target="_blank" rel="noopener">Ahrefs</a>')+(o.contact_url?' · <a href="'+esc(o.contact_url)+'" target="_blank" rel="noopener">contact page</a>':'')+'</div>'
    +'<div class="orform"><input class="orEmail" placeholder="email" value="'+esc(o.email||'')+'" list="dl-'+esc(o.domain).replace(/\W/g,'')+'"><datalist id="dl-'+esc(o.domain).replace(/\W/g,'')+'">'+(o.emails_found||[]).map(e=>'<option value="'+esc(e)+'">').join('')+'</datalist>'
    +(o.domain.includes('@')?'':'<button class="pill act" data-a="scan">Find contact</button>')<button class="pill act" data-a="send">Send welcome</button><button class="pill act" data-a="copy">Copy message</button>'
    +'<select class="sel orSt" style="width:auto;margin:0;padding:6px 10px">'+Object.keys(ST).map(k=>'<option value="'+k+'"'+(k===o.status?' selected':'')+'>'+ST[k]+'</option>').join('')+'</select>'
    +'<button class="pill act" data-a="join">Create affiliate</button><button class="pill act" data-a="del" title="remove">&times;</button></div>'
    +'<input class="orNotes" placeholder="notes" value="'+esc(o.notes||'')+'">'
    +'</div>').join(''):'<span class="m">Nothing here yet — import from Ahrefs above.</span>';
  wire(); }catch(e){ $('orErr').textContent=e.message; } }
function wire(){ $('orList').querySelectorAll('.orow').forEach(row=>{ const d=row.dataset.d; const em=row.querySelector('.orEmail'), st=row.querySelector('.orSt'), nt=row.querySelector('.orNotes');
  em.onchange=()=>set(d,{email:em.value}); st.onchange=()=>set(d,{status:st.value}); nt.onchange=()=>set(d,{notes:nt.value});
  row.querySelectorAll('[data-a]').forEach(b=>b.onclick=async()=>{ const a=b.dataset.a; $('orErr').textContent=''; b.disabled=true; try{
    if(a==='scan'){ b.textContent='Scanning…'; const r=await api('/api/admin',{action:'outreach_scan',token:s.token,domain:d}); if(r.best){ em.value=r.best; } b.textContent=r.emails.length?r.emails.length+' found':'none found'; setTimeout(load,1200); }
    if(a==='send'){ if(!em.value){ throw new Error('add an email first'); } if(em.value!==(row.dataset.saved||em.value))await set(d,{email:em.value}); await set(d,{email:em.value}); if(!confirm('Send the welcome to '+em.value+'?'))return; const r=await api('/api/admin',{action:'outreach_send',token:s.token,domain:d}); b.textContent='Sent'; load(); }
    if(a==='copy'){ const r=await api('/api/admin',{action:'outreach_render',token:s.token,domain:d}); await navigator.clipboard.writeText(r.subject+'\n\n'+r.text); b.textContent='Copied'; if(row.querySelector('.orSt').value==='new'){ await set(d,{status:'contacted'}); load(); } }
    if(a==='join'){ const code=prompt('Affiliate code for '+d+' (letters/numbers):',d.split('.')[0].replace(/[^a-z0-9]/gi,'').slice(0,16)); if(!code)return; const r=await api('/api/admin',{action:'aff_create',token:s.token,name:row.querySelector('.orhead .m')?row.querySelector('.orhead .m').textContent:d,email:em.value,code,rate:1000}); await set(d,{status:'joined',aff_code:code}); load(); }
    if(a==='del'){ if(!confirm('Remove '+d+'?'))return; await api('/api/admin',{action:'outreach_delete',token:s.token,domain:d}); load(); }
   }catch(e){ $('orErr').textContent=e.message; } b.disabled=false; }); }); }
async function set(d,fields){ try{ await api('/api/admin',{action:'outreach_set',token:s.token,domain:d,fields}); }catch(e){ $('orErr').textContent=e.message; } }
$('orImport').onclick=async()=>{ const rows=parsePaste($('orPaste').value); $('orImpErr').className='err'; if(!rows.length){ $('orImpErr').textContent='Nothing to import.'; return; } try{ const r=await api('/api/admin',{action:'outreach_import',token:s.token,rows}); $('orImpErr').className='err ok'; $('orImpErr').textContent=r.imported+' sites imported.'; $('orPaste').value=''; load(); }catch(e){ $('orImpErr').textContent=e.message; } };
$('orImportC').onclick=async()=>{ const rows=parseContacts($('orContacts').value); $('orImpErrC').className='err'; if(!rows.length){ $('orImpErrC').textContent='No email addresses found.'; return; } try{ const r=await api('/api/admin',{action:'outreach_import',token:s.token,rows}); $('orImpErrC').className='err ok'; $('orImpErrC').textContent=r.imported+' contacts imported.'; $('orContacts').value=''; load(); }catch(e){ $('orImpErrC').textContent=e.message; } };
$('orAdd').onclick=async()=>{ const v=$('orOne').value.trim(); if(!v)return; try{ await api('/api/admin',{action:'outreach_import',token:s.token,rows:[{domain:v,source:'manual'}]}); $('orOne').value=''; load(); }catch(e){ $('orImpErr').textContent=e.message; } };
$('orScanAll').onclick=async()=>{ const rows=[...$('orList').querySelectorAll('.orow')].filter(r=>r.querySelector('.orSt').value==='new'&&!r.querySelector('.orEmail').value).slice(0,15); $('orScanAll').disabled=true; let n=0; for(const r of rows){ $('orScanAll').textContent='Scanning '+(++n)+'/'+rows.length+'…'; try{ await api('/api/admin',{action:'outreach_scan',token:s.token,domain:r.dataset.d}); }catch(e){} } $('orScanAll').textContent='Find contacts for all new'; $('orScanAll').disabled=false; load(); };
$('orTplSave').onclick=async()=>{ $('orTplErr').className='err'; try{ await api('/api/admin',{action:'outreach_template',token:s.token,subject:$('orSub').value,body:$('orBody').value}); $('orTplErr').className='err ok'; $('orTplErr').textContent='Saved.'; }catch(e){ $('orTplErr').textContent=e.message; } };
$('orStatus').onchange=load; let qt; $('orQ').oninput=()=>{ clearTimeout(qt); qt=setTimeout(load,300); };
(async()=>{ if(await guard()){ load(); } })();
})();
