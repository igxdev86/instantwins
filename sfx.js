/* InstantWins sound: synthesised in-browser with Web Audio (no audio files). SND.mode: 'all' | 'sfx' | 'off' */
const SND=(()=>{
  let ctx=null, master=null, sfxBus=null, musBus=null, musicOn=false, musTimer=null, duck=null;
  let mode='all'; try{ mode=localStorage.getItem('iw_snd')||'all'; }catch(e){}
  const now=()=>ctx.currentTime;
  function init(){ if(ctx)return true; const AC=window.AudioContext||window.webkitAudioContext; if(!AC)return false; ctx=new AC();
    master=ctx.createGain(); master.gain.value=0.9; const comp=ctx.createDynamicsCompressor(); comp.threshold.value=-14; comp.ratio.value=4; master.connect(comp); comp.connect(ctx.destination);
    sfxBus=ctx.createGain(); sfxBus.connect(master); musBus=ctx.createGain(); musBus.gain.value=0; musBus.connect(master); duck=musBus.gain; return true; }
  function ok(){ if(mode==='off')return false; if(!init())return false; if(ctx.state==='suspended')ctx.resume(); return true; }
  // ---- primitives ----
  function env(g,t,a,d,s,r,peak){ peak=peak==null?1:peak; g.gain.cancelScheduledValues(t); g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(peak,t+a); g.gain.exponentialRampToValueAtTime(Math.max(0.0001,peak*s),t+a+d); g.gain.exponentialRampToValueAtTime(0.0001,t+a+d+r); }
  function tone(type,f0,f1,t,dur,vol,dest){ const o=ctx.createOscillator(), g=ctx.createGain(); o.type=type; o.frequency.setValueAtTime(f0,t); if(f1&&f1!==f0)o.frequency.exponentialRampToValueAtTime(f1,t+dur); env(g,t,0.004,dur*0.4,0.3,dur*0.6,vol); o.connect(g); g.connect(dest||sfxBus); o.start(t); o.stop(t+dur+0.05); return o; }
  let noiseBuf=null; function noise(){ if(noiseBuf)return noiseBuf; const b=ctx.createBuffer(1,ctx.sampleRate*2,ctx.sampleRate), d=b.getChannelData(0); let last=0; for(let i=0;i<d.length;i++){ const w=Math.random()*2-1; last=(last+0.02*w)/1.02; d[i]=w*0.6+last*3; } noiseBuf=b; return b; }
  function burst(t,dur,vol,fc,q,type,dest){ const s=ctx.createBufferSource(); s.buffer=noise(); s.loop=true; const f=ctx.createBiquadFilter(); f.type=type||'bandpass'; f.frequency.value=fc||2000; f.Q.value=q||1; const g=ctx.createGain(); env(g,t,0.003,dur*0.3,0.25,dur*0.7,vol); s.connect(f); f.connect(g); g.connect(dest||sfxBus); s.start(t); s.stop(t+dur+0.05); return {s,f,g}; }
  function bell(t,f,dur,vol){ const parts=[[1,1],[2.76,.5],[5.4,.25],[8.93,.12]]; parts.forEach(([m,a],i)=>{ const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sine'; o.frequency.value=f*m; env(g,t,0.003,dur*(0.25-i*0.04),0.15,dur*0.6,vol*a); o.connect(g); g.connect(sfxBus); o.start(t); o.stop(t+dur+0.1); }); }
  function duckMusic(ms){ if(!musBus||!musicOn)return; const t=now(); duck.cancelScheduledValues(t); duck.setTargetAtTime(0.04,t,0.03); duck.setTargetAtTime(0.14,t+ms/1000,0.4); }
  // ---- public SFX ----
  const S={};
  S.click=()=>{ if(!ok())return; const t=now(); burst(t,0.05,0.5,2600,2); tone('sine',1400,900,t,0.045,0.18); };
  S.buy=()=>{ if(!ok())return; const t=now(); burst(t,0.06,0.5,3000,2); tone('square',2200,2200,t+0.05,0.05,0.08); bell(t+0.1,1760,0.6,0.35); bell(t+0.22,2349,0.7,0.3); duckMusic(900); };
  S.peg=()=>{ if(!ok())return; const t=now(); tone('sine',800+Math.random()*700,500,t,0.07,0.25); burst(t,0.025,0.25,4000,3); };
  S.land=()=>{ if(!ok())return; const t=now(); tone('sine',200,90,t,0.18,0.6); burst(t,0.08,0.4,900,1,'lowpass'); };
  S.whoosh=(dur)=>{ if(!ok())return; const t=now(); const b=burst(t,dur||0.4,0.45,400,0.8); b.f.frequency.setValueAtTime(300,t); b.f.frequency.exponentialRampToValueAtTime(2600,t+(dur||0.4)); };
  S.thud=()=>{ if(!ok())return; const t=now(); tone('sine',120,45,t,0.3,0.9); burst(t,0.12,0.6,700,0.7,'lowpass'); duckMusic(600); };
  S.riser=(dur)=>{ if(!ok())return; const t=now(); tone('triangle',220,1200,t,dur||0.8,0.22); const b=burst(t,dur||0.8,0.25,800,1.5); b.f.frequency.exponentialRampToValueAtTime(5000,t+(dur||0.8)); };
  S.bell=(big)=>{ if(!ok())return; const t=now(); bell(t,big?880:1175,big?2.2:1.2,0.7); if(big){bell(t+0.08,1319,2,0.4);} burst(t,0.05,0.4,3500,2); duckMusic(1800); };
  let scr=null; S.scratchStart=()=>{ if(!ok()||scr)return; const t=now(); const s=ctx.createBufferSource(); s.buffer=noise(); s.loop=true; const f=ctx.createBiquadFilter(); f.type='bandpass'; f.frequency.value=1800; f.Q.value=0.7; const g=ctx.createGain(); g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.35,t+0.04); s.connect(f); f.connect(g); g.connect(sfxBus); s.start(t); scr={s,g,f}; };
  S.scratchMove=()=>{ if(!scr)return; scr.f.frequency.setTargetAtTime(1200+Math.random()*1800,now(),0.02); };
  S.scratchStop=()=>{ if(!scr)return; const t=now(); scr.g.gain.setTargetAtTime(0.0001,t,0.05); scr.s.stop(t+0.3); scr=null; };
  S.creak=()=>{ if(!ok())return; const t=now(); const o=ctx.createOscillator(), g=ctx.createGain(), l=ctx.createOscillator(), lg=ctx.createGain(); o.type='sawtooth'; o.frequency.setValueAtTime(90,t); o.frequency.exponentialRampToValueAtTime(160,t+0.6); l.frequency.value=22; lg.gain.value=18; l.connect(lg); lg.connect(o.frequency); const f=ctx.createBiquadFilter(); f.type='lowpass'; f.frequency.value=900; env(g,t,0.05,0.3,0.5,0.3,0.12); o.connect(f); f.connect(g); g.connect(sfxBus); o.start(t); l.start(t); o.stop(t+0.8); l.stop(t+0.8); };
  S.sparkle=()=>{ if(!ok())return; const t=now(); const sc=[1568,1976,2349,2637,3136,3520,3951]; for(let i=0;i<9;i++){ tone('sine',sc[Math.floor(Math.random()*sc.length)],null,t+i*0.045,0.25,0.14); } };
  S.pop=()=>{ if(!ok())return; const t=now(); tone('sine',720,300,t,0.09,0.4); burst(t,0.03,0.3,2500,1.5); };
  S.tick=(vol)=>{ if(!ok())return; const t=now(); burst(t,0.025,vol||0.5,3200,4); tone('square',1800,1200,t,0.02,0.07); };
  S.wheel=(dur)=>{ if(!ok())return; let el=0; const total=dur*1000; (function sched(){ const k=el/total; if(k>=1)return; const gap=18+Math.pow(k,2.4)*300; S.tick(0.35+0.3*k); el+=gap; setTimeout(sched,gap); })(); };
  S.flip=()=>{ if(!ok())return; const t=now(); burst(t,0.08,0.4,1500,1); tone('triangle',500,900,t,0.08,0.15); };
  S.none=()=>{ if(!ok())return; const t=now(); tone('triangle',330,220,t,0.28,0.25); tone('triangle',262,175,t+0.18,0.32,0.22); };
  S.win=(p)=>{ if(!ok())return; const t=now(); duckMusic(p>=100000?3200:1600);
    const big=p>=100000, mid=p>=1000; const seq=big?[523,659,784,1047,1319,1568,2093]:mid?[523,659,784,1047,1319]:[659,784,1047];
    seq.forEach((f,i)=>{ tone('triangle',f,null,t+i*(big?0.11:0.09),0.35,0.28); tone('sine',f*2,null,t+i*(big?0.11:0.09),0.3,0.1); });
    bell(t+seq.length*0.1,seq[seq.length-1],big?2.5:1.2,0.5); if(mid)S.sparkle(); if(big){ setTimeout(()=>S.sparkle(),400); setTimeout(()=>S.sparkle(),900); tone('sine',65,65,t,2.5,0.5); } };
  // ---- music: lo-fi generative loop ----
  const BPM=96, CH=[[57,60,64,67],[53,57,60,64],[48,52,55,59],[55,59,62,65]]; // Am7 F C G (midi)
  const mtof=m=>440*Math.pow(2,(m-69)/12); let step=0, nextT=0;
  function pad(t,notes,dur){ notes.forEach(n=>{ [-7,7].forEach(cents=>{ const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sawtooth'; o.frequency.value=mtof(n); o.detune.value=cents; const f=ctx.createBiquadFilter(); f.type='lowpass'; f.frequency.setValueAtTime(600,t); f.frequency.linearRampToValueAtTime(1400,t+dur*0.5); f.frequency.linearRampToValueAtTime(500,t+dur); env(g,t,0.25,dur*0.5,0.7,dur*0.45,0.045); o.connect(f); f.connect(g); g.connect(musBus); o.start(t); o.stop(t+dur+0.3); }); }); }
  function bass(t,n,dur){ const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sine'; o.frequency.value=mtof(n-12); env(g,t,0.01,dur*0.4,0.5,dur*0.5,0.5); o.connect(g); g.connect(musBus); o.start(t); o.stop(t+dur+0.1); const o2=ctx.createOscillator(), g2=ctx.createGain(); o2.type='triangle'; o2.frequency.value=mtof(n-12); env(g2,t,0.01,0.1,0.2,0.2,0.12); o2.connect(g2); g2.connect(musBus); o2.start(t); o2.stop(t+0.5); }
  function hat(t,open){ burst(t,open?0.18:0.05,open?0.07:0.06,9000,1.2,'highpass',musBus); }
  function kick(t){ const o=ctx.createOscillator(), g=ctx.createGain(); o.frequency.setValueAtTime(150,t); o.frequency.exponentialRampToValueAtTime(45,t+0.12); env(g,t,0.002,0.12,0.2,0.2,0.55); o.connect(g); g.connect(musBus); o.start(t); o.stop(t+0.4); }
  function snare(t){ burst(t,0.12,0.12,1800,0.8,'bandpass',musBus); tone('triangle',200,120,t,0.1,0.1,musBus); }
  function lead(t,chord,dur){ if(Math.random()<0.45)return; const n=chord[Math.floor(Math.random()*chord.length)]+12; const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sine'; o.frequency.value=mtof(n); env(g,t,0.02,dur*0.4,0.3,dur*0.5,0.09); const d=ctx.createDelay(); d.delayTime.value=60/BPM*0.75; const dg=ctx.createGain(); dg.gain.value=0.35; o.connect(g); g.connect(musBus); g.connect(d); d.connect(dg); dg.connect(musBus); dg.connect(d); o.start(t); o.stop(t+dur+1); }
  function schedule(){ const beat=60/BPM; while(nextT<now()+0.4){ const bar=Math.floor(step/8)%4, sub=step%8, chord=CH[bar]; if(sub===0)pad(nextT,chord,beat*4); if(sub===0||sub===5)bass(nextT,chord[0],beat*1.5); if(sub%2===0)kick(nextT); if(sub===4)snare(nextT); hat(nextT,sub===7); if(sub%2===1)lead(nextT,chord,beat); step++; nextT+=beat/2; } }
  function musicStart(){ if(!ok()||mode!=='all'||musicOn)return; musicOn=true; step=0; nextT=now()+0.05; musBus.gain.setTargetAtTime(0.14,now(),0.8); musTimer=setInterval(schedule,150); schedule(); }
  function musicStop(){ if(!musicOn)return; musicOn=false; clearInterval(musTimer); musBus.gain.setTargetAtTime(0,now(),0.3); }
  S.music=musicStart; S.musicStop=musicStop;
  S.setMode=m=>{ mode=m; try{localStorage.setItem('iw_snd',m);}catch(e){} if(m==='all'){musicStart();} else {musicStop();} paintBtn(); };
  S.cycle=()=>{ S.setMode(mode==='all'?'sfx':mode==='sfx'?'off':'all'); if(mode!=='off')S.click(); };
  S.getMode=()=>mode;
  // ---- UI ----
  function paintBtn(){ document.querySelectorAll('.sndbtn').forEach(b=>{ b.dataset.m=mode; b.innerHTML=(mode==='off'?'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M19 9l-4 6M15 9l4 6"/></svg>':'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16 9a4 4 0 0 1 0 6"/>'+(mode==='all'?'<path d="M18.5 6.5a8 8 0 0 1 0 11"/>':'')+'</svg>')+'<span>'+(mode==='all'?'Music':mode==='sfx'?'SFX':'Muted')+'</span>'; b.title=mode==='all'?'Music + sound on. Tap: sound effects only':mode==='sfx'?'Sound effects only. Tap: mute':'Muted. Tap: music + sound'; }); }
  function mount(){ const hr=document.querySelector('.top .hr'); if(hr&&!document.querySelector('.sndbtn')){ const b=document.createElement('button'); b.className='sndbtn'; b.type='button'; b.onclick=e=>{e.preventDefault();S.cycle();}; hr.insertBefore(b,hr.firstChild); } paintBtn();
    document.addEventListener('click',e=>{ const t=e.target.closest('.btn,.pack,.game,.atabs a,.tabs button,.mbar a,.pill,.sw'); if(t&&!t.classList.contains('sndbtn'))S.click(); },true);
    const unlock=()=>{ if(mode!=='off'&&init()){ if(ctx.state==='suspended')ctx.resume(); if(mode==='all')musicStart(); } }; ['pointerdown','keydown','touchstart'].forEach(ev=>document.addEventListener(ev,unlock,{once:false,passive:true}));
    document.addEventListener('visibilitychange',()=>{ if(!ctx)return; if(document.hidden){ if(musicOn)musBus.gain.setTargetAtTime(0,now(),0.1); } else if(musicOn){ musBus.gain.setTargetAtTime(0.14,now(),0.5); } }); }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount); else mount();
  return S;
})();
