import re
g=open('game.html').read()

# ---------- stage markup ----------
STAGES='''<div id="reels" style="display:none"><div class="reels"><div class="reel" id="r0"><div class="strip"></div></div><div class="reel" id="r1"><div class="strip"></div></div><div class="reel" id="r2"><div class="strip"></div></div><div class="payline"></div></div><div class="gtxt" id="reelTxt"></div></div><div id="candy" style="display:none"><div class="candy" id="candyGrid"></div><div class="gtxt" id="candyTxt"></div></div><div id="words" style="display:none"><div class="words" id="wordGrid"></div><div class="gtxt" id="wordTxt"></div></div><div id="boxes" style="display:none"><p class="m" style="text-align:center;margin:0 0 8px">Tap any box &mdash; every box holds this ticket&rsquo;s prize</p><div class="boxes" id="boxGrid"></div><div class="gtxt" id="boxTxt"></div></div><div id="penalty" style="display:none"><svg class="board" id="penSvg" viewBox="0 0 320 260"><defs><linearGradient id="pnGrass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2E8B3E"/><stop offset="1" stop-color="#1D5E2A"/></linearGradient><pattern id="pnNet" width="10" height="10" patternUnits="userSpaceOnUse"><path d="M0 0H10M0 0V10" stroke="#fff" stroke-opacity=".35" stroke-width="1"/></pattern></defs><rect width="320" height="260" fill="#0B0B10"/><rect y="150" width="320" height="110" fill="url(#pnGrass)"/><rect x="40" y="60" width="240" height="100" fill="url(#pnNet)" stroke="#fff" stroke-width="5"/><g id="pnKeeper" style="transform-origin:160px 130px"><circle cx="160" cy="98" r="11" fill="#F3C99A"/><rect x="146" y="108" width="28" height="36" rx="8" fill="#FFC53D"/><rect x="128" y="112" width="18" height="8" rx="4" fill="#FFC53D"/><rect x="174" y="112" width="18" height="8" rx="4" fill="#FFC53D"/><rect x="149" y="142" width="9" height="22" rx="4" fill="#0B0B10"/><rect x="162" y="142" width="9" height="22" rx="4" fill="#0B0B10"/></g><circle id="pnBall" cx="160" cy="230" r="11" fill="#fff" stroke="#0B0B10" stroke-width="2"/><text id="pnText" x="160" y="40" text-anchor="middle" font-family="Unbounded,sans-serif" font-weight="900" font-size="26" fill="#fff" opacity="0" style="paint-order:stroke;stroke:#0B0B10;stroke-width:6px"></text></svg></div>'''
g=g.replace('<div id="dip" style="display:none">',STAGES+'<div id="dip" style="display:none">')

# ---------- G map ----------
g=g.replace("wheel:{h:'PRIZE WHEEL',k:'Round and round',c:'#FFC53D',btn:'Spin',el:'wheel_'}};",
 "wheel:{h:'PRIZE WHEEL',k:'Round and round',c:'#FFC53D',btn:'Spin',el:'wheel_'},reels:{h:'LUCKY REELS',k:'Three in a row',c:'#FF3D8A',btn:'Spin'},candy:{h:'SWEET MATCH',k:'Match the sweets',c:'#FF6A1A',btn:'Match'},words:{h:'WORD HUNT',k:'Find the word',c:'#3DF2FF',btn:'Search'},boxes:{h:'MYSTERY BOXES',k:'Pick one',c:'#C6FF3D',btn:'Open a box'},penalty:{h:'PENALTY KICK',k:'Top bins',c:'#C6FF3D',btn:'Shoot'}};")

# ---------- play functions ----------
FUNCS=r'''
  // ---- Lucky Reels: a prize = three of the symbol for that value; no prize = three different symbols (never two of a kind) ----
  const SYM=[['💎',10000000],['👑',2500000],['🏆',500000],['💰',100000],['🔔',25000],['⭐',5000],['🍒',1000],['🍋',500],['🍀',200],['7️⃣',100],['🍇',0],['🍊',0],['🔔',0]];
  const SYMS=SYM.map(s=>s[0]); const uniq=[...new Set(SYMS)];
  function reelStrip(final){ const items=[]; for(let i=0;i<14;i++)items.push(uniq[Math.floor(Math.random()*uniq.length)]); items.push(final); return items; }
  function reelsInit(){ [0,1,2].forEach(i=>{ const st=$('r'+i).querySelector('.strip'); st.style.transition='none'; st.style.transform='translateY(0)'; st.innerHTML='<span>'+uniq[(i*3)%uniq.length]+'</span>'; }); }
  function reelsPlay(prize){ return new Promise(res=>{ $('reelTxt').textContent=''; let finals; if(prize){ const want=prize>=10000000?10000000:prize; const s=(SYM.find(x=>x[1]===want)||SYM[3])[0]; finals=[s,s,s]; } else { const pool=uniq.slice().sort(()=>Math.random()-.5); finals=[pool[0],pool[1],pool[2]]; }
      [0,1,2].forEach(i=>{ const st=$('r'+i).querySelector('.strip'); const items=reelStrip(finals[i]); st.style.transition='none'; st.style.transform='translateY(0)'; st.innerHTML=items.map(x=>'<span>'+x+'</span>').join(''); void st.offsetHeight; const dur=(all?0.7:1.4)+i*(all?0.25:0.55); st.style.transition='transform '+dur+'s cubic-bezier(.2,.9,.2,1)'; st.style.transform='translateY(calc(-100% + var(--cell)))'; SND.reelSpin(dur); setTimeout(()=>{SND.reelStop(); $('r'+i).classList.add('stop'); setTimeout(()=>$('r'+i).classList.remove('stop'),300);},dur*1000); });
      const total=((all?0.7:1.4)+2*(all?0.25:0.55))*1000+150; setTimeout(()=>{ $('reelTxt').textContent=prize?gbp(prize)+'!':'No match'; prize?SND.win(prize):SND.none(); setTimeout(res,all?300:900); },total); }); }

  // ---- Sweet Match: 6x6 sweets. A prize = a cascade ends with a glowing row of gold sweets carrying the value; no prize = the board settles with no line of three ----
  const SWEETS=['🍬','🍭','🍩','🍪','🧁'];
  function candyBoard(noLines){ let b; do{ b=[]; for(let i=0;i<36;i++)b.push(Math.floor(Math.random()*SWEETS.length)); }while(noLines&&candyHasLine(b)); return b; }
  function candyHasLine(b){ for(let r=0;r<6;r++)for(let c=0;c<4;c++){ if(b[r*6+c]===b[r*6+c+1]&&b[r*6+c]===b[r*6+c+2])return true; } for(let c=0;c<6;c++)for(let r=0;r<4;r++){ if(b[r*6+c]===b[(r+1)*6+c]&&b[r*6+c]===b[(r+2)*6+c])return true; } return false; }
  function candyInit(){ const b=candyBoard(true); $('candyGrid').innerHTML=b.map(v=>'<div>'+SWEETS[v]+'</div>').join(''); $('candyTxt').textContent=''; }
  function candyPlay(prize){ return new Promise(res=>{ candyInit(); const cells=[...$('candyGrid').children]; const ms=all?70:140; let i=0;
      const shuffle=[...Array(36).keys()].sort(()=>Math.random()-.5).slice(0,all?8:14);
      (function tick(){ if(i<shuffle.length){ const k=shuffle[i++]; cells[k].classList.add('pop'); SND.candyPop(); setTimeout(()=>{ cells[k].classList.remove('pop'); cells[k].textContent=SWEETS[Math.floor(Math.random()*SWEETS.length)]; },ms*0.8); setTimeout(tick,ms); return; }
        const b=candyBoard(true); cells.forEach((c,k)=>c.textContent=SWEETS[b[k]]);
        if(prize){ const r=Math.floor(Math.random()*6), c0=Math.floor(Math.random()*4); [0,1,2].forEach((d,j)=>setTimeout(()=>{ const cell=cells[r*6+c0+d]; cell.textContent='🍯'; cell.classList.add('gold'); SND.candyGold(); },j*(all?90:220)));
          setTimeout(()=>{ $('candyTxt').textContent='SWEET! '+gbp(prize); SND.win(prize); setTimeout(res,all?300:900); },3*(all?90:220)+200); }
        else { $('candyTxt').textContent='No match this time'; SND.none(); setTimeout(res,all?300:800); } })(); }); }

  // ---- Word Hunt: 8x8 letters. A prize = the hidden word WINNER lights up and the value shows; no prize = NOTHING lights up (the word, literally) ----
  function wordsBuild(word){ const N=8; const grid=Array(N*N).fill(''); const L=word.length; const dirs=[[0,1],[1,0],[1,1]]; const [dr,dc]=dirs[Math.floor(Math.random()*dirs.length)]; const r0=Math.floor(Math.random()*(N-(dr?L-1:0))), c0=Math.floor(Math.random()*(N-(dc?L-1:0))); const path=[]; for(let i=0;i<L;i++){ const k=(r0+dr*i)*N+(c0+dc*i); grid[k]=word[i]; path.push(k); } const A='ABCDEFGHIJKLMNOPRSTUVY'; for(let i=0;i<N*N;i++)if(!grid[i])grid[i]=A[Math.floor(Math.random()*A.length)]; return {grid,path}; }
  function wordsInit(){ const {grid}=wordsBuild('INSTANT'); $('wordGrid').innerHTML=grid.map(l=>'<div>'+l+'</div>').join(''); $('wordTxt').textContent=''; }
  function wordsPlay(prize){ return new Promise(res=>{ const word=prize?'WINNER':'NOTHING'; const {grid,path}=wordsBuild(word); const el=$('wordGrid'); el.innerHTML=grid.map(l=>'<div>'+l+'</div>').join(''); $('wordTxt').textContent=''; const cells=[...el.children]; const ms=all?80:220;
      const scan=[...Array(64).keys()].sort(()=>Math.random()-.5).slice(0,all?6:12); let i=0;
      (function pre(){ if(i<scan.length){ const k=scan[i++]; cells[k].classList.add('scan'); SND.blip(); setTimeout(()=>cells[k].classList.remove('scan'),ms); setTimeout(pre,ms*0.7); return; }
        path.forEach((k,j)=>setTimeout(()=>{ cells[k].classList.add(prize?'hit':'miss'); SND.blip(1); },j*ms));
        setTimeout(()=>{ $('wordTxt').textContent=prize?word+' — '+gbp(prize):'NOTHING this time'; prize?SND.win(prize):SND.none(); setTimeout(res,all?300:900); },path.length*ms+150); })(); }); }

  // ---- Mystery Boxes: nine boxes; whichever you tap opens to this ticket's prize. The other eight stay shut — they never show "what you could have had" ----
  function boxesInit(){ $('boxGrid').innerHTML=[...Array(9).keys()].map(i=>'<button type="button" class="box" data-i="'+i+'"><span class="lid"></span><span class="in">?</span></button>').join(''); $('boxTxt').textContent=''; }
  function boxesPlay(prize){ return new Promise(res=>{ boxesInit(); const boxes=[...$('boxGrid').children]; let done=false;
      function open(b){ if(done)return; done=true; boxes.forEach(x=>x.disabled=true); b.classList.add('open'); SND.creak(); b.querySelector('.in').textContent=prize?gbp(prize):'EMPTY'; b.querySelector('.in').classList.toggle('none',!prize);
        setTimeout(()=>{ $('boxTxt').textContent=prize?gbp(prize)+'!':'Empty box'; prize?SND.win(prize):SND.none(); boxes.forEach(x=>{ if(x!==b)x.classList.add('dim'); }); setTimeout(res,all?300:900); },450); }
      boxes.forEach(b=>b.onclick=()=>open(b)); if(all)setTimeout(()=>open(boxes[Math.floor(Math.random()*9)]),200); }); }

  // ---- Penalty Kick: a prize = goal; no prize = the keeper saves. Where it goes is just animation ----
  function penPlay(prize){ return new Promise(res=>{ const ball=$('pnBall'), K=$('pnKeeper'), T=$('pnText'); T.setAttribute('opacity',0); ball.setAttribute('cx',160); ball.setAttribute('cy',230); ball.setAttribute('r',11); K.style.transition='none'; K.style.transform='translate(0,0) rotate(0)';
      const side=Math.random()<0.5?-1:1; const tx=160+side*(prize?82:78), ty=prize?92:98; const dur=all?500:800; const t0=performance.now();
      SND.kick(); setTimeout(()=>{ K.style.transition='transform '+(dur*0.9)+'ms ease-out'; K.style.transform='translate('+(prize?-side*70:side*70)+'px,-10px) rotate('+(prize?-side*35:side*35)+'deg)'; },60);
      (function f(now){ const k=Math.min(1,(now-t0)/dur); ball.setAttribute('cx',160+(tx-160)*k); ball.setAttribute('cy',230-(230-ty)*(1-Math.pow(1-k,2))); ball.setAttribute('r',11-5*k); if(k<1)requestAnimationFrame(f); else { T.textContent=prize?'GOAL! '+gbp(prize):'SAVED'; T.setAttribute('opacity',1); if(prize){SND.crowd(true);SND.win(prize);} else {SND.crowd(false);SND.none();} setTimeout(res,all?350:1000); } })(t0); }); }
'''
g=g.replace("  function dipPlay(t){",FUNCS+"  function dipPlay(t){")
g=g.replace("else if(GK==='wheel')await wheelPlay(p); else await dipPlay(t);","else if(GK==='wheel')await wheelPlay(p); else if(GK==='reels')await reelsPlay(p); else if(GK==='candy')await candyPlay(p); else if(GK==='words')await wordsPlay(p); else if(GK==='boxes')await boxesPlay(p); else if(GK==='penalty')await penPlay(p); else await dipPlay(t);")
g=g.replace("if(GK==='wheel')wheelInit(); paint();","if(GK==='wheel')wheelInit(); if(GK==='reels')reelsInit(); if(GK==='candy')candyInit(); if(GK==='words')wordsInit(); if(GK==='boxes')boxesInit(); paint();")
open('game.html','w').write(g)

# ---------- CSS ----------
c=open('c2.css').read()
c+='''
/* five more games */
.gtxt{text-align:center;font-family:Unbounded,sans-serif;font-weight:900;font-size:1.3rem;min-height:1.6em;margin-top:10px}
.reels{--cell:84px;position:relative;display:grid;grid-template-columns:repeat(3,1fr);gap:8px;max-width:300px;margin:0 auto;padding:10px;background:linear-gradient(180deg,#2a1a3a,#15151d);border:2px solid var(--pink);border-radius:18px;box-shadow:0 0 40px rgba(255,61,138,.2)}
.reel{height:var(--cell);overflow:hidden;background:#fff;border-radius:10px;position:relative}
.reel .strip{display:flex;flex-direction:column;will-change:transform}.reel .strip span{height:var(--cell);display:grid;place-items:center;font-size:44px;line-height:1}
.reel::before,.reel::after{content:"";position:absolute;left:0;right:0;height:18px;z-index:1;pointer-events:none}.reel::before{top:0;background:linear-gradient(#fff,transparent)}.reel::after{bottom:0;background:linear-gradient(transparent,#fff)}
.reel.stop{animation:reelstop .3s ease}@keyframes reelstop{0%{transform:translateY(0)}40%{transform:translateY(6px)}100%{transform:translateY(0)}}
.payline{position:absolute;left:4px;right:4px;top:50%;height:3px;background:var(--pink);opacity:.8;transform:translateY(-50%);pointer-events:none;z-index:2}
.candy{display:grid;grid-template-columns:repeat(6,1fr);gap:5px;max-width:320px;margin:0 auto}
.candy div{aspect-ratio:1;display:grid;place-items:center;font-size:28px;background:rgba(255,255,255,.06);border:1px solid var(--line);border-radius:12px;transition:transform .15s}
.candy div.pop{transform:scale(.3);opacity:.3}.candy div.gold{background:linear-gradient(135deg,#FFC53D,#FF6A1A);border-color:var(--gold);box-shadow:0 0 22px rgba(255,197,61,.6);animation:bump .5s ease}
.words{display:grid;grid-template-columns:repeat(8,1fr);gap:4px;max-width:340px;margin:0 auto}
.words div{aspect-ratio:1;display:grid;place-items:center;font:800 .95rem Inter,sans-serif;background:rgba(255,255,255,.05);border:1px solid var(--line);border-radius:8px;color:var(--ink);transition:background .15s}
.words div.scan{background:rgba(61,242,255,.2)}.words div.hit{background:var(--lime);color:#0B0B10;border-color:var(--lime);box-shadow:0 0 14px rgba(198,255,61,.5)}.words div.miss{background:#2a2a38;color:var(--soft)}
.boxes{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;max-width:320px;margin:0 auto}
.box{position:relative;aspect-ratio:1;border:0;border-radius:14px;background:linear-gradient(180deg,#6b4a1c,#3d2a0e);box-shadow:inset 0 2px 0 rgba(255,255,255,.15),0 8px 18px rgba(0,0,0,.5);cursor:pointer;overflow:hidden;padding:0;color:#fff;transition:transform .15s}
.box:hover{transform:translateY(-2px)}.box .lid{position:absolute;inset:0 0 auto 0;height:38%;background:linear-gradient(180deg,#a2742f,#7a5522);border-bottom:3px solid #2a1a06;transform-origin:top;transition:transform .5s cubic-bezier(.2,.9,.2,1);z-index:2}
.box .in{position:absolute;inset:0;display:grid;place-items:center;font:900 1.1rem Unbounded,sans-serif;color:var(--gold);text-shadow:0 2px 6px #000}.box .in.none{color:var(--soft);font-size:.9rem}
.box.open .lid{transform:rotateX(-110deg)}.box.open{background:linear-gradient(180deg,#8a5e22,#3d2a0e);box-shadow:0 0 30px rgba(255,197,61,.35)}.box.dim{opacity:.35}
#penSvg{max-width:340px;margin:0 auto;display:block;border-radius:16px}
'''
open('c2.css','w').write(c)

# ---------- index tiles ----------
i=open('index.html').read()
TILES='''<a class="game" style="--c:#FF3D8A" href="game.html?g=reels"><span class="art"><svg viewBox="0 0 120 120"><rect x="14" y="30" width="92" height="64" rx="12" fill="#2a1a3a" stroke="#FF3D8A" stroke-width="4"/><rect x="24" y="40" width="22" height="44" rx="5" fill="#fff"/><rect x="49" y="40" width="22" height="44" rx="5" fill="#fff"/><rect x="74" y="40" width="22" height="44" rx="5" fill="#fff"/><circle cx="35" cy="62" r="6" fill="#FF3D8A"/><circle cx="60" cy="62" r="6" fill="#FF3D8A"/><circle cx="85" cy="62" r="6" fill="#FF3D8A"/><rect x="106" y="44" width="8" height="26" rx="4" fill="#C6FF3D"/></svg></span><span class="k">Game</span><h3>Lucky Reels</h3><p>Three reels spin. Three of a kind is your prize.</p><span class="go">Play &rarr;</span></a><a class="game" style="--c:#FF6A1A" href="game.html?g=candy"><span class="art"><svg viewBox="0 0 120 120"><g fill="#FF6A1A"><rect x="22" y="22" width="22" height="22" rx="6"/><rect x="49" y="22" width="22" height="22" rx="6" fill="#FF3D8A"/><rect x="76" y="22" width="22" height="22" rx="6" fill="#3DF2FF"/><rect x="22" y="49" width="22" height="22" rx="6" fill="#FFC53D"/><rect x="49" y="49" width="22" height="22" rx="6" fill="#FFC53D"/><rect x="76" y="49" width="22" height="22" rx="6" fill="#FFC53D"/><rect x="22" y="76" width="22" height="22" rx="6" fill="#3DF2FF"/><rect x="49" y="76" width="22" height="22" rx="6"/><rect x="76" y="76" width="22" height="22" rx="6" fill="#FF3D8A"/></g><rect x="18" y="45" width="84" height="30" rx="8" fill="none" stroke="#fff" stroke-width="3"/></svg></span><span class="k">Game</span><h3>Sweet Match</h3><p>Sweets tumble and match. A golden row is a prize.</p><span class="go">Play &rarr;</span></a><a class="game" style="--c:#3DF2FF" href="game.html?g=words"><span class="art"><svg viewBox="0 0 120 120"><g font-family="Inter,sans-serif" font-weight="800" font-size="15" fill="#A7A7B8"><text x="20" y="34">Q W I N</text><text x="20" y="58">A Z K E</text><text x="20" y="82">R T Y L</text><text x="20" y="106">M B C O</text></g><rect x="38" y="20" width="62" height="20" rx="10" fill="none" stroke="#3DF2FF" stroke-width="4"/></svg></span><span class="k">Game</span><h3>Word Hunt</h3><p>Letters light up. Find WINNER and the prize is yours.</p><span class="go">Play &rarr;</span></a><a class="game" style="--c:#C6FF3D" href="game.html?g=boxes"><span class="art"><svg viewBox="0 0 120 120"><g><rect x="18" y="18" width="36" height="36" rx="7" fill="#6b4a1c"/><rect x="66" y="18" width="36" height="36" rx="7" fill="#6b4a1c"/><rect x="18" y="66" width="36" height="36" rx="7" fill="#6b4a1c"/><rect x="66" y="66" width="36" height="36" rx="7" fill="#C6FF3D"/><g font-family="Unbounded,sans-serif" font-weight="900" font-size="20" fill="#fff" text-anchor="middle"><text x="36" y="44">?</text><text x="84" y="44">?</text><text x="36" y="92">?</text><text x="84" y="92" fill="#0B0B10">£</text></g></g></svg></span><span class="k">Game</span><h3>Mystery Boxes</h3><p>Pick any box. Every box holds your ticket&rsquo;s prize.</p><span class="go">Play &rarr;</span></a><a class="game" style="--c:#C6FF3D" href="game.html?g=penalty"><span class="art"><svg viewBox="0 0 120 120"><rect x="16" y="30" width="88" height="50" fill="none" stroke="#fff" stroke-width="4"/><path d="M16 30h88M30 30v50M44 30v50M58 30v50M72 30v50M86 30v50M16 46h88M16 62h88" stroke="#fff" stroke-opacity=".35" stroke-width="1.5"/><circle cx="60" cy="92" r="13" fill="#fff" stroke="#0B0B10" stroke-width="2"/><path d="M60 82l6 5-2 7h-8l-2-7z" fill="#0B0B10"/><circle cx="82" cy="52" r="7" fill="#F3C99A"/><rect x="74" y="58" width="16" height="20" rx="5" fill="#FFC53D"/></svg></span><span class="k">Game</span><h3>Penalty Kick</h3><p>Step up. Goal means a prize; saved means not this time.</p><span class="go">Play &rarr;</span></a>'''
i=i.replace('<a class="game" style="--c:#C6FF3D" href="game.html?g=dip">',TILES+'<a class="game" style="--c:#C6FF3D" href="game.html?g=dip">')
i=i.replace('Step 2 games grid now 7 games','')
i=re.sub(r'seven games','twelve games',i); i=re.sub(r'seven ways','twelve ways',i); i=i.replace('The seven games are','The twelve games are').replace('any of seven games','any of twelve games').replace('Coin drop, scratch, bingo, wheel&hellip;','Reels, scratch, bingo, penalties&hellip;')
open('index.html','w').write(i)
print('ok')
