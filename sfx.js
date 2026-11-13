/* InstantWins sound: synthesised in-browser with Web Audio (no audio files). SND.mode: 'all' | 'sfx' | 'off' */
const SND=(()=>{
  let ctx=null, master=null, sfxBus=null, musBus=null, musicOn=false, musTimer=null, duck=null;
  let mode='all'; try{ mode=localStorage.getItem('iw_snd')||'all'; }catch(e){} if(mode!=='off')mode='all';
  const now=()=>ctx.currentTime;
  function init(){ if(ctx)return true; const AC=window.AudioContext||window.webkitAudioContext; if(!AC)return false; ctx=new AC();
    master=ctx.createGain(); master.gain.value=0.9; const comp=ctx.createDynamicsCompressor(); comp.threshold.value=-14; comp.ratio.value=4; master.connect(comp); comp.connect(ctx.destination);
    sfxBus=ctx.createGain(); sfxBus.connect(master); musBus=ctx.createGain(); musBus.gain.value=0; musBus.connect(master); duck=musBus.gain; return true; }
  function ok(){ if(mode==='off')return false; if(!init())return false; if(ctx.state!=='running'){ try{ const p=ctx.resume(); if(p&&p.then)p.then(()=>{ if(mode==='all'&&!musicOn)musicStart(); }).catch(()=>{}); }catch(e){} } return true; }
  // ---- primitives ----
  function env(g,t,a,d,s,r,peak){ peak=peak==null?1:peak; g.gain.cancelScheduledValues(t); g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(peak,t+a); g.gain.exponentialRampToValueAtTime(Math.max(0.0001,peak*s),t+a+d); g.gain.exponentialRampToValueAtTime(0.0001,t+a+d+r); }
  function tone(type,f0,f1,t,dur,vol,dest){ const o=ctx.createOscillator(), g=ctx.createGain(); o.type=type; o.frequency.setValueAtTime(f0,t); if(f1&&f1!==f0)o.frequency.exponentialRampToValueAtTime(f1,t+dur); env(g,t,0.004,dur*0.4,0.3,dur*0.6,vol); o.connect(g); g.connect(dest||sfxBus); o.start(t); o.stop(t+dur+0.05); return o; }
  let noiseBuf=null; function noise(){ if(noiseBuf)return noiseBuf; const b=ctx.createBuffer(1,ctx.sampleRate*2,ctx.sampleRate), d=b.getChannelData(0); let last=0; for(let i=0;i<d.length;i++){ const w=Math.random()*2-1; last=(last+0.02*w)/1.02; d[i]=w*0.6+last*3; } noiseBuf=b; return b; }
  function burst(t,dur,vol,fc,q,type,dest){ const s=ctx.createBufferSource(); s.buffer=noise(); s.loop=true; const f=ctx.createBiquadFilter(); f.type=type||'bandpass'; f.frequency.value=fc||2000; f.Q.value=q||1; const g=ctx.createGain(); env(g,t,0.003,dur*0.3,0.25,dur*0.7,vol); s.connect(f); f.connect(g); g.connect(dest||sfxBus); s.start(t); s.stop(t+dur+0.05); return {s,f,g}; }
  function bell(t,f,dur,vol){ const parts=[[1,1],[2.76,.5],[5.4,.25],[8.93,.12]]; parts.forEach(([m,a],i)=>{ const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sine'; o.frequency.value=f*m; env(g,t,0.003,dur*(0.25-i*0.04),0.15,dur*0.6,vol*a); o.connect(g); g.connect(sfxBus); o.start(t); o.stop(t+dur+0.1); }); }
  let boosted=false; const musVol=()=>(theme?theme.vol:0.12)*(boosted?1.3:1);
  function duckMusic(ms){ if(!musBus||!musicOn)return; const t=now(); duck.cancelScheduledValues(t); duck.setTargetAtTime(musVol()*0.6,t,0.03); duck.setTargetAtTime(musVol(),t+ms/1000,0.4); }
  // ---- public SFX ----
  const S={};
  S.boost=(on)=>{ boosted=!!on; if(!musBus||!musicOn)return; const t=now(); duck.cancelScheduledValues(t); duck.setTargetAtTime(musVol(),t,on?0.25:1.2); };
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
  S.pop=()=>{ if(!ok())return; const t=now(); tone('sine',720,300,t,0.09,0.18); burst(t,0.03,0.12,2500,1.5); };
  S.tick=(vol)=>{ if(!ok())return; const t=now(); burst(t,0.025,(vol||0.5)*0.5,3200,4); tone('square',1800,1200,t,0.02,0.07); };
  S.wheel=(dur)=>{ if(!ok())return; let el=0; const total=dur*1000; (function sched(){ const k=el/total; if(k>=1)return; const gap=18+Math.pow(k,2.4)*300; S.tick(0.35+0.3*k); el+=gap; setTimeout(sched,gap); })(); };
  S.flip=()=>{ if(!ok())return; const t=now(); burst(t,0.08,0.4,1500,1); tone('triangle',500,900,t,0.08,0.15); };
  S.none=()=>{ if(!ok())return; const t=now(); tone('triangle',330,220,t,0.28,0.25); tone('triangle',262,175,t+0.18,0.32,0.22); };
  S.win=(p)=>{ if(!ok())return; const t=now(); duckMusic(p>=100000?3200:1600);
    const big=p>=100000, mid=p>=1000; const seq=big?[523,659,784,1047,1319,1568,2093]:mid?[523,659,784,1047,1319]:[659,784,1047];
    seq.forEach((f,i)=>{ tone('triangle',f,null,t+i*(big?0.11:0.09),0.35,0.28); tone('sine',f*2,null,t+i*(big?0.11:0.09),0.3,0.1); });
    bell(t+seq.length*0.1,seq[seq.length-1],big?2.5:1.2,0.5); if(mid)S.sparkle(); if(big){ setTimeout(()=>S.sparkle(),400); setTimeout(()=>S.sparkle(),900); tone('sine',65,65,t,2.5,0.5); } };
  S.reelSpin=(dur)=>{ if(!ok())return; let el=0; const total=dur*1000; (function sched(){ const k=el/total; if(k>=1)return; const gap=40+Math.pow(k,2)*120; S.tick(0.25); el+=gap; setTimeout(sched,gap); })(); };
  S.reelStop=()=>{ if(!ok())return; const t=now(); tone('sine',260,120,t,0.14,0.5); burst(t,0.06,0.4,1200,1,'lowpass'); };
  S.candyPop=()=>{ if(!ok())return; const t=now(); tone('sine',900+Math.random()*600,1800,t,0.07,0.25); burst(t,0.03,0.2,3000,2); };
  S.candyGold=()=>{ if(!ok())return; const t=now(); bell(t,1568+Math.random()*400,0.6,0.35); };
  S.blip=(hi)=>{ if(!ok())return; const t=now(); tone('square',hi?1320:880,hi?1320:880,t,0.05,0.07); tone('sine',hi?2640:1760,null,t,0.06,0.12); };
  S.kick=()=>{ if(!ok())return; const t=now(); tone('sine',140,50,t,0.18,0.8); const b=burst(t,0.3,0.5,600,0.8); b.f.frequency.exponentialRampToValueAtTime(3000,t+0.3); };
  S.crowd=(cheer)=>{ if(!ok())return; const t=now(); const b=burst(t,cheer?1.6:1.1,cheer?0.5:0.3,cheer?1400:500,0.6,'bandpass'); b.f.frequency.setValueAtTime(cheer?900:700,t); b.f.frequency.exponentialRampToValueAtTime(cheer?2400:300,t+(cheer?0.5:1)); if(cheer){ tone('sawtooth',440,660,t,0.6,0.08); tone('sawtooth',554,830,t+0.05,0.6,0.06); } else { tone('sawtooth',330,220,t,0.8,0.06); } duckMusic(1500); };
  // feeder: crunch (paper being chewed), zap (electric read), rip (stub tearing off)
  S.crunch=(vol)=>{ if(!ok())return; const t=now(); vol=(vol||0.7)*0.35; for(let i=0;i<7;i++){ const b=burst(t+i*0.045+Math.random()*0.01,0.05,vol*(0.5+Math.random()*0.5),500+Math.random()*1800,0.9,'bandpass'); } const o=ctx.createOscillator(), g=ctx.createGain(); o.type='sawtooth'; o.frequency.setValueAtTime(70,t); o.frequency.linearRampToValueAtTime(55,t+0.35); const f=ctx.createBiquadFilter(); f.type='lowpass'; f.frequency.value=220; env(g,t,0.02,0.2,0.6,0.15,vol*0.25); o.connect(f); f.connect(g); g.connect(sfxBus); o.start(t); o.stop(t+0.45); };
  S.zap=(vol)=>{ if(!ok())return; const t=now(); vol=(vol||0.4)*0.4; const o=ctx.createOscillator(), g=ctx.createGain(); o.type='square'; o.frequency.setValueAtTime(1800,t); o.frequency.exponentialRampToValueAtTime(240,t+0.12); const l=ctx.createOscillator(), lg=ctx.createGain(); l.type='square'; l.frequency.value=48; lg.gain.value=900; l.connect(lg); lg.connect(o.frequency); const f=ctx.createBiquadFilter(); f.type='highpass'; f.frequency.value=600; env(g,t,0.003,0.06,0.3,0.1,vol*0.35); o.connect(f); f.connect(g); g.connect(sfxBus); o.start(t); l.start(t); o.stop(t+0.2); l.stop(t+0.2); burst(t,0.08,vol*0.5,6000,1.5,'highpass'); };
  S.rip=()=>{ if(!ok())return; const t=now(); const b=burst(t,0.13,0.18,2500,0.6,'bandpass'); b.f.frequency.setValueAtTime(1200,t); b.f.frequency.exponentialRampToValueAtTime(4500,t+0.12); tone('triangle',180,90,t+0.1,0.08,0.2); };
  // ---- music: one generative theme per game (16 steps per bar) ----
  const mtof=m=>440*Math.pow(2,(m-69)/12);
  const THEMES={
    scratch:{bpm:92,chords:[[57,60,64,67],[53,57,60,64],[48,52,55,59],[55,59,62,65]],pad:'saw',padCut:[600,1400],bass:{wave:'sine',on:[0,10]},kick:[0,8],snare:[8],hat:[0,2,4,6,8,10,12,14],open:[14],lead:{wave:'sine',prob:.45,on:[2,6,10,14],oct:12},echo:.75,vol:.14},
    drop:{bpm:124,chords:[[60,64,67],[65,69,72],[67,71,74],[57,60,64]],pad:'square',padCut:[900,2200],bass:{wave:'square',on:[0,3,6,8,11,14]},kick:[0,8],snare:[4,12],hat:[2,6,10,14],open:[],arp:{wave:'square',on:[0,2,4,6,8,10,12,14],oct:12},echo:.5,vol:.11},
    striker:{bpm:138,chords:[[60,64,67],[60,64,67],[55,59,62,65],[55,59,62,65],[60,64,67],[65,69,72],[55,59,62,65],[60,64,67]],stab:{wave:'sawtooth',on:[4,12]},bass:{wave:'triangle',on:[0,8],alt:true},kick:[0,8],snare:[4,12],hat:[0,4,8,12],open:[],lead:{wave:'square',prob:.6,on:[0,2,4,6,8,10,12,14],oct:12,run:true},echo:.25,vol:.12},
    chest:{bpm:100,chords:[[50,53,57],[46,50,53],[53,57,60],[45,49,52]],drone:true,pad:'sawtooth',padCut:[300,700],bass:{wave:'sine',on:[0,6,8,14]},kick:[],tom:[0,6,8,14],snare:[],hat:[],open:[],lead:{wave:'triangle',prob:.55,on:[0,3,6,8,11,14],oct:12},echo:.75,vol:.13},
    bingo:{bpm:112,swing:.18,chords:[[60,64,67,70],[57,60,64,67],[53,57,60,64],[55,59,62,65]],organ:true,bass:{wave:'triangle',on:[0,4,8,12],walk:true},kick:[0,8],snare:[4,12],hat:[0,2,4,6,8,10,12,14],open:[6,14],stab:{wave:'organ',on:[2,6,10,14]},echo:.3,vol:.12},
    wheel:{bpm:126,chords:[[57,60,64,67],[62,65,69,72],[55,59,62,65],[60,64,67,71]],bass:{wave:'sawtooth',on:[0,2,4,6,8,10,12,14],oct:true},kick:[0,4,8,12],snare:[4,12],hat:[0,2,4,6,8,10,12,14],open:[2,6,10,14],stab:{wave:'sawtooth',on:[0,3,8,11],brass:true},arp:{wave:'sine',on:[1,5,9,13],oct:24},echo:.5,vol:.12},
    dip:{bpm:72,chords:[[60,64,67,71],[57,60,64,67],[65,69,72,76],[55,59,62,67]],pad:'sine',padCut:[800,1600],bass:{wave:'sine',on:[0]},kick:[],snare:[],hat:[],open:[],lead:{wave:'sine',prob:.3,on:[0,4,8,12],oct:12},echo:.75,vol:.12},
    reels:{bpm:118,chords:[[57,60,64,67],[55,59,62,65],[53,57,60,64],[52,55,59,62]],bass:{wave:'sawtooth',on:[0,3,6,10,12,14]},kick:[0,6,8,14],snare:[4,12],hat:[2,6,10,14],open:[14],stab:{wave:'sawtooth',on:[2,10],brass:true},arp:{wave:'sine',on:[0,4,8,12],oct:24},echo:.5,vol:.11},
    candy:{bpm:132,chords:[[60,64,67],[62,65,69],[65,69,72],[67,71,74]],pad:'square',padCut:[1200,2600],bass:{wave:'triangle',on:[0,4,8,12]},kick:[0,8],snare:[4,12],hat:[0,2,4,6,8,10,12,14],open:[],arp:{wave:'sine',on:[0,2,4,6,8,10,12,14],oct:24},lead:{wave:'triangle',prob:.5,on:[1,5,9,13],oct:12},echo:.5,vol:.11},
    words:{bpm:88,chords:[[62,65,69,72],[58,62,65,69],[60,64,67,71],[57,60,64,67]],pad:'sine',padCut:[900,1800],bass:{wave:'sine',on:[0,8]},kick:[],snare:[],hat:[4,12],open:[],arp:{wave:'triangle',on:[0,3,6,9,12],oct:12},echo:.75,vol:.12},
    boxes:{bpm:96,chords:[[48,51,55],[46,50,53],[44,48,51],[43,47,50]],drone:true,pad:'sawtooth',padCut:[250,600],bass:{wave:'sine',on:[0,10]},kick:[0],tom:[6,14],snare:[],hat:[2,6,10,14],open:[],lead:{wave:'sine',prob:.35,on:[4,12],oct:24},echo:1,vol:.12},
    quick:{bpm:138,chords:[[57,60,64,67],[62,65,69,72],[53,57,60,64],[55,59,62,66]],pad:'square',padCut:[1400,3200],bass:{wave:'sawtooth',on:[0,2,3,6,8,10,11,14],oct:true},kick:[0,4,8,12],snare:[4,12],hat:[0,2,4,6,8,10,12,14],open:[2,6,10,14],stab:{wave:'sawtooth',on:[0,3,6,8,11,13],brass:true},arp:{wave:'square',on:[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],oct:24},lead:{wave:'square',prob:.7,on:[1,5,9,13],oct:12,run:true},echo:.375,vol:.3},
    penalty:{bpm:120,chords:[[57,60,64],[57,60,64],[53,57,60],[55,59,62]],bass:{wave:'triangle',on:[0,8]},kick:[0,4,8,12],tom:[6,14],snare:[4,12],hat:[2,6,10,14],open:[],stab:{wave:'sawtooth',on:[0,6,8],brass:true},echo:.5,vol:.12}
  };
  let theme=null, step=0, nextT=0;
  function voice(wave,f,t,dur,vol,cut,detune){ const o=ctx.createOscillator(), g=ctx.createGain(); o.type=wave==='organ'?'sine':wave; o.frequency.value=f; if(detune)o.detune.value=detune; let n=o; if(cut){ const fl=ctx.createBiquadFilter(); fl.type='lowpass'; fl.frequency.value=cut; o.connect(fl); n=fl; } env(g,t,0.01,dur*0.4,0.5,dur*0.5,vol); n.connect(g); g.connect(musBus); o.start(t); o.stop(t+dur+0.2); if(wave==='organ'){ const o2=ctx.createOscillator(), g2=ctx.createGain(); o2.type='sine'; o2.frequency.value=f*2; env(g2,t,0.01,dur*0.4,0.5,dur*0.5,vol*0.4); o2.connect(g2); g2.connect(musBus); o2.start(t); o2.stop(t+dur+0.2); } }
  function pad(t,notes,dur,th){ notes.forEach(n=>{ [-7,7].forEach(cents=>{ const o=ctx.createOscillator(), g=ctx.createGain(); o.type=th.pad; o.frequency.value=mtof(n); o.detune.value=cents; const f=ctx.createBiquadFilter(); f.type='lowpass'; f.frequency.setValueAtTime(th.padCut[0],t); f.frequency.linearRampToValueAtTime(th.padCut[1],t+dur*0.5); f.frequency.linearRampToValueAtTime(th.padCut[0],t+dur); env(g,t,0.25,dur*0.5,0.7,dur*0.45,th.pad==='square'?0.02:0.045); o.connect(f); f.connect(g); g.connect(musBus); o.start(t); o.stop(t+dur+0.3); }); }); }
  function drone(t,n,dur){ voice('sawtooth',mtof(n-24),t,dur,0.05,260,-5); voice('sawtooth',mtof(n-24),t,dur,0.05,260,5); }
  function bassN(t,n,dur,th,wave){ voice(wave||'sine',mtof(n-12),t,dur,wave==='sawtooth'?0.22:0.45,wave==='sawtooth'?900:undefined); if(wave==='sine'){ voice('triangle',mtof(n-12),t,0.25,0.12); } }
  function hat(t,open){ burst(t,open?0.18:0.05,open?0.07:0.06,9000,1.2,'highpass',musBus); }
  function kick(t){ const o=ctx.createOscillator(), g=ctx.createGain(); o.frequency.setValueAtTime(150,t); o.frequency.exponentialRampToValueAtTime(45,t+0.12); env(g,t,0.002,0.12,0.2,0.2,0.55); o.connect(g); g.connect(musBus); o.start(t); o.stop(t+0.4); }
  function tom(t){ const o=ctx.createOscillator(), g=ctx.createGain(); o.frequency.setValueAtTime(110,t); o.frequency.exponentialRampToValueAtTime(70,t+0.2); env(g,t,0.003,0.2,0.2,0.3,0.4); o.connect(g); g.connect(musBus); o.start(t); o.stop(t+0.6); }
  function snare(t){ burst(t,0.12,0.12,1800,0.8,'bandpass',musBus); tone('triangle',200,120,t,0.1,0.1,musBus); }
  function stab(t,chord,dur,th){ chord.forEach(n=>{ if(th.stab.brass){ voice('sawtooth',mtof(n),t,dur,0.05,1800,-6); voice('sawtooth',mtof(n),t,dur,0.05,1800,6); } else voice(th.stab.wave,mtof(n),t,dur,th.stab.wave==='organ'?0.07:0.05,th.stab.wave==='sawtooth'?1400:undefined); }); }
  let leadI=0; function lead(t,chord,dur,th){ const L=th.lead; if(!L.run&&Math.random()>L.prob)return; const n=(L.run?chord[(leadI++)%chord.length]:chord[Math.floor(Math.random()*chord.length)])+L.oct; const o=ctx.createOscillator(), g=ctx.createGain(); o.type=L.wave; o.frequency.value=mtof(n); env(g,t,0.02,dur*0.4,0.3,dur*0.5,L.wave==='square'?0.05:0.09); const d=ctx.createDelay(); d.delayTime.value=60/theme.bpm*th.echo; const dg=ctx.createGain(); dg.gain.value=0.35; o.connect(g); g.connect(musBus); g.connect(d); d.connect(dg); dg.connect(musBus); dg.connect(d); o.start(t); o.stop(t+dur+1); }
  function arp(t,chord,dur,th,i){ const n=chord[i%chord.length]+th.arp.oct; voice(th.arp.wave,mtof(n),t,dur*0.9,th.arp.wave==='square'?0.035:0.06,th.arp.wave==='square'?3000:undefined); }
  function schedule(){ const th=theme; if(!th)return; const beat=60/th.bpm, st=beat/4; while(nextT<now()+0.4){ const bar=Math.floor(step/16)%th.chords.length, sub=step%16, chord=th.chords[bar]; const sw=(th.swing&&sub%2)?st*th.swing:0, t=nextT+sw;
      if(sub===0){ if(th.pad)pad(t,chord,beat*4,th); if(th.drone)drone(t,chord[0],beat*4); }
      if(th.bass.on.includes(sub)){ let n=chord[0]; if(th.bass.alt&&sub===8)n=chord[2]-12; if(th.bass.walk)n=chord[[0,2,1,3][sub/4|0]%chord.length]; if(th.bass.oct&&sub%4===2)n+=12; bassN(t,n,st*2.5,th,th.bass.wave); }
      if(th.kick.includes(sub))kick(t); if(th.tom&&th.tom.includes(sub))tom(t); if(th.snare.includes(sub))snare(t); if(th.hat.includes(sub))hat(t,false); if(th.open.includes(sub))hat(t,true);
      if(th.stab&&th.stab.on.includes(sub))stab(t,chord,st*1.6,th); if(th.lead&&th.lead.on.includes(sub))lead(t,chord,st*2,th); if(th.arp&&th.arp.on.includes(sub))arp(t,chord,st*1.8,th,step/2|0);
      step++; nextT+=st; } }
  function musicStart(){ if(!theme||!ok()||mode!=='all'||musicOn)return; if(ctx.state!=='running')return; musicOn=true; step=0; nextT=now()+0.05; musBus.gain.setTargetAtTime(musVol(),now(),0.8); musTimer=setInterval(schedule,120); schedule(); }
  function musicStop(){ if(!musicOn)return; musicOn=false; clearInterval(musTimer); musBus.gain.setTargetAtTime(0,now(),0.3); }
  S.playing=()=>musicOn;
  S.dbg=()=>({mode,theme:!!theme,musicOn,ctx:ctx&&ctx.state,gain:musBus&&musBus.gain.value});
  S.setTheme=name=>{ const was=musicOn; if(was)musicStop(); theme=THEMES[name]||null; if(was&&theme)setTimeout(musicStart,350); };
  S.music=musicStart; S.musicStop=musicStop;
  S.setMode=m=>{ mode=m; try{localStorage.setItem('iw_snd',m);}catch(e){} if(m==='all'){musicStart();} else {musicStop();} paintBtn(); };
  function note(msg,ms){ let t=document.getElementById('sndNote'); if(!t){ t=document.createElement('div'); t.id='sndNote'; t.className='sndnote'; document.body.appendChild(t); } t.textContent=msg; t.classList.add('show'); clearTimeout(note.tm); note.tm=setTimeout(()=>t.classList.remove('show'),ms||2200); }
  // plain test beep on a fresh context created inside the click — bypasses the whole engine
  function beep(){ try{ const AC=window.AudioContext||window.webkitAudioContext; const c=new AC(); const o=c.createOscillator(), g=c.createGain(); o.frequency.value=660; g.gain.value=0.2; o.connect(g); g.connect(c.destination); o.start(); o.stop(c.currentTime+0.18); c.resume(); setTimeout(()=>c.close(),600); return c.state; }catch(e){ return 'beep failed: '+e.message; } }
  S.cycle=()=>{ S.setMode(mode==='off'?'all':'off'); if(mode!=='off'){ S.click(); const bs=beep(); setTimeout(()=>{ const st=ctx?ctx.state:'none'; if(st!=='running')note('Engine '+st+' · test '+bs+' · '+(navigator.userAgent.match(/Chrome|Safari|Firefox/)||['?'])[0],5000); },700); }
    setTimeout(()=>{ const st=ctx?ctx.state:'no audio engine'; note(mode==='off'?'Sound off':'Sound on'+(st!=='running'?' — browser is blocking audio ('+st+'). Check the tab isn\'t muted.':''),2600); },350); };
  let warned=false; function checkRunning(){ if(warned||mode==='off'||!ctx)return; setTimeout(()=>{ if(ctx.state!=='running'&&!warned){ warned=true; note('Sound is blocked by your browser — tap the speaker, or unmute this tab.',4000); } },1500); }
  S.getMode=()=>mode;
  // ---- UI ----
  function paintBtn(){ document.querySelectorAll('.sndbtn').forEach(b=>{ b.dataset.m=mode; b.classList.toggle('nomusic',!theme); b.innerHTML=(mode==='off'?'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M19 9l-4 6M15 9l4 6"/></svg>':'<svg viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9z"/><path d="M16 9a4 4 0 0 1 0 6"/>'+(mode==='all'?'<path d="M18.5 6.5a8 8 0 0 1 0 11"/>':'')+'</svg>')+'<span>'+(mode==='off'?'Sound off':'Sound on')+'</span>'; b.title=mode==='off'?'Sound is off. Tap to turn on':'Sound is on. Tap to mute'; }); }
  function mount(){ const hr=document.querySelector('.top .hr'); if(hr&&!document.querySelector('.sndbtn')){ const b=document.createElement('button'); b.className='sndbtn'; b.type='button'; b.onclick=e=>{e.preventDefault();S.cycle();}; hr.insertBefore(b,hr.firstChild); } paintBtn();
    document.addEventListener('click',e=>{ const t=e.target.closest('.btn,.pack,.game,.atabs a,.tabs button,.mbar a,.pill,.sw'); if(t&&!t.classList.contains('sndbtn'))S.click(); },true);
    const unlock=()=>{ if(mode==='off'||!init())return; const go=()=>{ if(mode==='all')musicStart(); }; if(ctx.state!=='running'){ const p=ctx.resume(); if(p&&p.then)p.then(go).catch(()=>{}); else go(); checkRunning(); } else go(); }; ['pointerdown','mousedown','touchend','click','keydown'].forEach(ev=>document.addEventListener(ev,unlock,{once:false,passive:true,capture:true}));
    document.addEventListener('visibilitychange',()=>{ if(!ctx)return; if(document.hidden){ if(musicOn)musBus.gain.setTargetAtTime(0,now(),0.1); } else if(musicOn){ musBus.gain.setTargetAtTime(theme?theme.vol:0.12,now(),0.5); } }); }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount); else mount();
  return S;
})();
window.SND=SND;
