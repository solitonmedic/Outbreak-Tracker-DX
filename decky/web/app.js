// Purpose: reusable Canvas renderer for original Lua tracker drawing commands.
// Runtime: phone/desktop browser. Inputs: drawing frames from the Deck on the local network, fonts.
// Outputs: responsive tracker and whitelisted touch/keyboard commands.
// Safety: no emulator access or saved game data; nothing is stored in the browser.
// Run: open the private phone link in Decky. Check: cards and controls update.
// SP vector commands: ellipse, polygon, rotation and line width from shared Lua.
// Sounds: frame.sounds counts plays per file; a rise plays it once (after the first tap).
// M toggles SP radar sound in the shared UI; frame.game.spsoundenabled updates
// the On/Off button (default On). Check: offline check-sp-sound-frames.py.
// Map input: pointer drag, pinch, wheel, double-tap zoom; bounded shared map actions.
// Map artwork loads from the bundled assets; there is no disc selection or import.
"use strict";
const canvas = document.querySelector("#tracker"), ctx = canvas.getContext("2d");
const message = document.querySelector("#message");
const images = new Map(), imageFonts = new Map(), tinted = new Map();
const sounds = new Map(), soundCounts = new Map();
let audio = null, soundBaseline = false;
let mapActive=false, mapMode=0, frameWidth=300, frameHeight=740;
let latestFrame=null, presentedFrame=null, painting=false, animationStarted=false, lastFrameAt=0;
let mapDescriptor=null, panPreview=null, cameraMotion=null;
const actorMotion=new Map();
function actorPoint(track,now) {
  const t=Math.max(0,Math.min(1,(now-track.at)/track.duration));
  return {x:track.fromX+(track.x-track.fromX)*t,y:track.fromY+(track.y-track.fromY)*t};
}
function prepareMotion(frame) {
  const now=performance.now(), duration=Math.max(80,Math.min(250,now-lastFrameAt||200));lastFrameAt=now;
  const seen=new Set();mapDescriptor=null;
  for(const c of frame.commands) {
    if(c[0]==="mapBegin") {
      mapDescriptor={x:c[1],y:c[2],w:c[3],h:c[4],panX:c[5],panY:c[6],cameraX:c[7]||0,cameraY:c[8]||0,key:c[9]};
      const x=mapDescriptor.cameraX,y=mapDescriptor.cameraY;
      const from=cameraMotion?.continuity===c[9]?actorPoint(cameraMotion,now):{x,y};
      cameraMotion={x,y,fromX:from.x,fromY:from.y,at:now,duration,continuity:c[9]};
    }
    if(c[0]!=="actorBegin")continue;
    const [,id,sx,sy,continuity]=c,old=actorMotion.get(id);seen.add(id);
    const x=sx-(mapDescriptor?.cameraX||0),y=sy-(mapDescriptor?.cameraY||0);
    const key=continuity+":"+mapDescriptor?.key;
    const from=old&&old.continuity===key?actorPoint(old,now):{x,y};
    const near=Math.hypot(from.x-x,from.y-y)<Math.max(frame.width,frame.height)/2;
    actorMotion.set(id,{x,y,fromX:near?from.x:x,fromY:near?from.y:y,at:now,duration,continuity:key});
  }
  for(const id of actorMotion.keys())if(!seen.has(id))actorMotion.delete(id);
  if(!mapDescriptor)cameraMotion=null;
  if(panPreview?.releasedAt&&mapDescriptor&&Math.hypot(panPreview.x-mapDescriptor.panX,panPreview.y-mapDescriptor.panY)<1)panPreview=null;
}
async function animate(now) {
  if(latestFrame&&!painting&&(mapActive||latestFrame.pulsing||latestFrame!==presentedFrame)) {
    painting=true;
    const frame=latestFrame;
    try{await render(frame,now);presentedFrame=frame;}catch(error){message.textContent=error.message;}
    finally{painting=false;}
  }
  requestAnimationFrame(animate);
}
const soundStats = {played:0, missed:0};
const groups = [
  ["Views", false, [["home","Main tracker"],["f1","Help"],["f2","Item views"],["f3","Next room"],["l","Language"]]],
  ["Show", false, [["i","Room items"],["t","Timers"],["q","Puzzle hints"],["e","Enemy HP"],["f4","Enemy list"]]],
  ["Sound", false, [["m","SP radar sound: On"]]],
  ["Layout", false, [["v","Vertical"],["h","Horizontal"],["d","Default size"],["a","Auto size"]]],
  ["Map", false, [["n","Map + compact cards"],["b","Cards beside map"],["f","Follow player"]]],
  ["Players shown", true, [["1","1"],["2","2"],["3","3"],["4","4"]]],
  ["Enemy list shows", true, [["kp0","All"],["kp1","P1"],["kp2","P2"],["kp3","P3"],["kp4","P4"]]],
];
const controls = groups.flatMap(([, , keys]) => keys);
async function sendKey(key) {
  try {
    const response = await fetch("/api/key", {method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({key}),signal:AbortSignal.timeout(5000)});
    if (!response.ok) throw new Error("Control request failed; check the phone view in Decky.");
  } catch(error) { message.textContent=error.message; }
}
const controlsRoot = document.querySelector("#controls");
let spSoundButton = null;
for(const [title,segmented,keys] of groups) {
  const group=document.createElement("div"), heading=document.createElement("h3"), row=document.createElement("div");
  group.className="group"; heading.textContent=title; row.className=segmented?"row segmented":"row";
  for(const [key,label] of keys) {
    const button=document.createElement("button"); button.type="button"; button.textContent=label; button.title=key.toUpperCase();
    if(key==="m") { spSoundButton=button; button.setAttribute("aria-pressed","true"); }
    button.addEventListener("click",()=>{void sendKey(key);if(key==="home")setSheet(false);}); row.append(button);
  }
  group.append(heading,row); controlsRoot.append(group);
}
function updateSoundControl(enabled) {
  const on=enabled!==false;
  spSoundButton.textContent="SP radar sound: "+(on?"On":"Off");
  spSoundButton.setAttribute("aria-pressed",String(on));
}
const sheet = document.querySelector("#sheet"), menu = document.querySelector("#menu");
function setSheet(open) { sheet.hidden=!open; menu.setAttribute("aria-expanded",String(open)); }
menu.addEventListener("click",()=>setSheet(true));
document.querySelector("main").addEventListener("click",()=>{if(!mapActive)setSheet(true);});
setTimeout(()=>{if(!mapActive)menu.classList.add("idle");},4000);
document.querySelector("#close").addEventListener("click",()=>setSheet(false));
document.querySelector("#backdrop").addEventListener("click",()=>setSheet(false));
addEventListener("keydown",event=>{
  if(event.target?.closest?.("input,textarea,select,[contenteditable='true']"))return;
  const key=event.code.startsWith("Numpad") ? "kp"+event.code.slice(6) : event.key.toLowerCase();
  if(key==="escape"&&!sheet.hidden){setSheet(false);return;}
  if(controls.some(([allowed])=>allowed===key)&&!event.ctrlKey&&!event.metaKey&&!event.altKey) {
    event.preventDefault(); if(!event.repeat) void sendKey(key);
  }
});
// Browsers start audio only after a tap or key press. iOS also stops it when a
// home-screen app goes to the background ("interrupted"), so each tap resumes it
// until it runs and plays one silent sample, which iOS needs to start output.
function unlockAudio() {
  const Context=window.AudioContext||window.webkitAudioContext;
  if(!audio&&Context)audio=new Context();
  if(!audio||audio.state==="running")return;
  audio.resume().catch(()=>{});
  const silent=audio.createBufferSource();
  silent.buffer=audio.createBuffer(1,1,22050);silent.connect(audio.destination);silent.start(0);
}
for(const type of ["pointerup","touchend","keydown"])addEventListener(type,unlockAudio,{passive:true});
// Returning to the app: try to resume without a tap (iOS may still need one).
addEventListener("visibilitychange",()=>{if(!document.hidden&&audio&&audio.state!=="running")audio.resume().catch(()=>{});});
function sound(path) {
  if(!sounds.has(path)) sounds.set(path,fetch("/"+path).then(response=>{
    if(!response.ok)throw new Error("Unable to load tracker sound");
    return response.arrayBuffer();
  }).then(data=>new Promise((resolve,reject)=>audio.decodeAudioData(data,resolve,reject))));
  return sounds.get(path);
}
// The first frame only records the counts, so opening the page plays nothing.
// A lower count means the reader restarted; it is recorded, not played.
async function playSounds(counts) {
  for(const [path,count] of Object.entries(counts||{})) {
    const seen=soundCounts.has(path)?soundCounts.get(path):soundBaseline?0:count;
    soundCounts.set(path,count);
    if(count<=seen)continue;
    if(!audio||audio.state!=="running"){soundStats.missed+=count-seen;continue;}
    const source=audio.createBufferSource();
    source.buffer=await sound(path);source.connect(audio.destination);source.start();
    soundStats.played++;
  }
  soundBaseline=true;
}
async function image(path) {
  if(!images.has(path)) images.set(path,new Promise((resolve,reject)=>{
    const img=new Image(); img.onload=()=>resolve(img); img.onerror=()=>reject(new Error("Unable to load tracker artwork")); img.src="/"+path;
  }));
  return images.get(path);
}
// Alpha factor from a "pulse" command: raised-cosine wave between floor and 1.
let pulseFactor=1;
function pulseAt(rate,floor,now){return floor+(1-floor)*(.5-.5*Math.cos(2*Math.PI*rate*now/1000));}
function color(value) {
  const [r,g,b,a=1]=value; ctx.fillStyle=ctx.strokeStyle="rgb("+(r*255)+" "+(g*255)+" "+(b*255)+")"; ctx.globalAlpha=a*pulseFactor;
}
function transform(values) {
  const [x,y,r,sx,sy,ox,oy,kx,ky]=values;
  ctx.translate(x,y);ctx.rotate(r);ctx.scale(sx,sy);ctx.transform(1,ky,kx,1,0,0);ctx.translate(-ox,-oy);
}
async function imageFont(font) {
  if(!imageFonts.has(font.path)) {
    const img=await image(font.path), surface=document.createElement("canvas"); surface.width=img.width;surface.height=img.height;
    const c=surface.getContext("2d",{willReadFrequently:true}); c.drawImage(img,0,0);
    const pixels=c.getImageData(0,0,img.width,img.height), separator=Array.from(pixels.data.slice(0,4));
    const same=(index)=>separator.every((n,i)=>pixels.data[index+i]===n);
    const regions=[];let start=null;
    for(let x=0;x<=img.width;x++) {
      const spacer=x===img.width||same(x*4);
      if(!spacer&&start===null)start=x;
      if(spacer&&start!==null){regions.push([start,0,x-start,img.height]);start=null;}
    }
    for(let index=0;index<pixels.data.length;index+=4)if(same(index))pixels.data[index+3]=0;
    c.putImageData(pixels,0,0);
    imageFonts.set(font.path,{surface,glyphs:new Map(Array.from(font.characters).map((ch,i)=>[ch,regions[i]]))});
  }
  return imageFonts.get(font.path);
}
function spans(text,base) {
  if(!Array.isArray(text))return [{text:String(text??""),color:base}];
  let current=base;const values=[];
  for(const part of text)if(Array.isArray(part))current=part;else values.push({text:String(part),color:current});
  return values;
}
function textWidth(text,font,bitmap) {
  if(bitmap)return Array.from(text).reduce((sum,ch)=>sum+(bitmap.glyphs.get(ch)?.[2]||0),0);
  ctx.font=font.size+"px "+(font.path.includes("arialnb")?"TrackerNarrow":"TrackerBold");return ctx.measureText(text).width;
}
async function drawText(text,font,values,tint,limit,alignment) {
  const bitmap=font.characters ? await imageFont(font) : null;
  ctx.save();transform(values);
  if(!bitmap){ctx.font=font.size+"px "+(font.path.includes("arialnb")?"TrackerNarrow":"TrackerBold");ctx.textBaseline="alphabetic";}
  const segments=spans(text,tint), glyphs=[];
  for(const part of segments)for(const ch of part.text)glyphs.push({ch,color:part.color});
  const lines=[[]];let word=[];
  function addWord(){
    if(!word.length)return;
    let line=lines.at(-1), existing=line.map(x=>x.ch).join(""), added=word.map(x=>x.ch).join("");
    if(limit&&line.length&&textWidth(existing+added,font,bitmap)>limit){lines.push([]);line=lines.at(-1);while(word[0]?.ch===" ")word.shift();}
    line.push(...word);word=[];
  }
  for(const glyph of glyphs){if(glyph.ch==="\n"){addWord();lines.push([]);}else{if(glyph.ch===" ")addWord();word.push(glyph);}}
  addWord();
  let y=0;
  for(const line of lines) {
    const total=textWidth(line.map(x=>x.ch).join(""),font,bitmap);
    let x=limit&&alignment==="right"?limit-total:limit&&alignment==="center"?(limit-total)/2:0;
    for(const glyph of line){
      color(glyph.color);
      if(bitmap){const q=bitmap.glyphs.get(glyph.ch);if(q){drawTinted(bitmap.surface,q,[x,y,0,1,1,0,0,0,0],glyph.color,font.path);x+=q[2];}}
      else{ctx.fillText(glyph.ch,x,y+font.ascent);x+=textWidth(glyph.ch,font,null);}
    }y+=font.height;
  }ctx.restore();
}
function drawTinted(img,q,values,tint,id) {
  ctx.save();transform(values);ctx.globalAlpha=tint[3]??1;ctx.imageSmoothingEnabled=false;
  if(tint.slice(0,3).every(n=>n===1)){ctx.drawImage(img,...q,0,0,q[2],q[3]);}
  else {
    const key=id+":"+q.join(",")+":"+tint.slice(0,3).join(",");
    if(!tinted.has(key)) {
      const c=document.createElement("canvas");c.width=q[2];c.height=q[3];const t=c.getContext("2d");
      t.drawImage(img,...q,0,0,q[2],q[3]);t.globalCompositeOperation="multiply";
      t.fillStyle="rgb("+(tint[0]*255)+" "+(tint[1]*255)+" "+(tint[2]*255)+")";t.fillRect(0,0,c.width,c.height);
      t.globalCompositeOperation="destination-in";t.drawImage(img,...q,0,0,q[2],q[3]);
      if(tinted.size>=512)tinted.delete(tinted.keys().next().value);tinted.set(key,c);
    }ctx.drawImage(tinted.get(key),0,0);
  }ctx.restore();
}
// With Safari's toolbar hidden the page starts below the status bar but its floating address pill
// still overlaps the top ~30 px and Safari reports no safe area for it. When a touch phone shows
// a page nearly as tall as the screen, keep the tracker clear of the pill. The diagnostics line
// in the controls sheet shows the numbers used.
const diagnostics = document.querySelector("#diagnostics");
function updateInsets() {
  const standalone=navigator.standalone===true||matchMedia("(display-mode: standalone)").matches;
  const portrait=innerHeight>innerWidth, fullHeight=Math.max(screen.width,screen.height);
  const immersive=!standalone&&portrait&&matchMedia("(pointer: coarse)").matches&&innerHeight>=fullHeight*0.85;
  const top=immersive?36:0, bottom=immersive?12:0;
  document.documentElement.style.setProperty("--reserve-top",top+"px");
  document.documentElement.style.setProperty("--reserve-bottom",bottom+"px");
  if(diagnostics)diagnostics.textContent="Page "+innerWidth+"x"+innerHeight+", screen "+screen.width+"x"+screen.height+", margins "+top+"/"+bottom+" px";
}
async function render(frame,now=performance.now()) {
  updateInsets();
  await Promise.all(frame.commands.filter(c=>c[0]==="image").map(c=>image(c[1])));
  const w=frame.width||300,h=frame.height||740;
  const area=canvas.parentElement.getBoundingClientRect();
  const available=getComputedStyle(canvas.parentElement);
  const maxWidth=area.width-parseFloat(available.paddingLeft)-parseFloat(available.paddingRight);
  const maxHeight=area.height-parseFloat(available.paddingTop)-parseFloat(available.paddingBottom);
  const cssWidth=Math.max(1,Math.floor(w*Math.min(maxWidth/w,maxHeight/h,4)));
  const cssHeight=Math.round(cssWidth*h/w);
  const ratio=(devicePixelRatio||1)*cssWidth/w;
  if(canvas.width!==Math.round(w*ratio)||canvas.height!==Math.round(h*ratio)){canvas.width=Math.round(w*ratio);canvas.height=Math.round(h*ratio);}
  canvas.style.width=cssWidth+"px";canvas.style.height=cssHeight+"px";
  ctx.setTransform(ratio,0,0,ratio,0,0);ctx.globalAlpha=1;ctx.fillStyle="#000";ctx.fillRect(0,0,w,h);
  ctx.lineWidth=1;
  let depth=0;pulseFactor=1;
  for(const command of frame.commands) {
    const [op,...a]=command;
    if(op==="pulse")pulseFactor=a.length?pulseAt(a[0],a[1],now):1;
    else if(op==="push"){ctx.save();depth++;}
    else if(op==="pop"){if(depth){ctx.restore();depth--;}}
    else if(op==="translate")ctx.translate(...a);
    else if(op==="mapBegin"){
      ctx.save();
      if(panPreview?.releasedAt&&now-panPreview.releasedAt>1500)panPreview=null;
      if(cameraMotion){const p=actorPoint(cameraMotion,now);ctx.translate(p.x-(a[6]||0),p.y-(a[7]||0));}
      if(panPreview?.moved)ctx.translate(panPreview.x-a[4],panPreview.y-a[5]);
    }
    else if(op==="mapEnd")ctx.restore();
    else if(op==="actorBegin"){
      ctx.save();const track=actorMotion.get(a[0]);
      if(track){const p=actorPoint(track,now);ctx.translate(p.x-(a[1]-(mapDescriptor?.cameraX||0)),p.y-(a[2]-(mapDescriptor?.cameraY||0)));}
    }
    else if(op==="actorEnd")ctx.restore();
    else if(op==="scale")ctx.scale(...a);
    else if(op==="rotate")ctx.rotate(a[0]);
    else if(op==="lineWidth")ctx.lineWidth=a[0];
    else if(op==="clipPush"){ctx.save();depth++;ctx.beginPath();ctx.rect(...a);ctx.clip();}
    else if(op==="clipPop"){if(depth){ctx.restore();depth--;}}
    else if(op==="image")drawTinted(await image(a[0]),a[1],a[2],a[3],a[0]);
    else if(op==="text")await drawText(...a);
    else if(op==="rectangle"){color(a[5]);ctx.beginPath();ctx.roundRect(a[1],a[2],a[3],a[4],Math.max(0,Math.min(a[6],Math.abs(a[3])/2,Math.abs(a[4])/2)));a[0]==="fill"?ctx.fill():ctx.stroke();}
    else if(op==="circle"){color(a[4]);ctx.beginPath();ctx.arc(a[1],a[2],Math.max(0,a[3]),0,Math.PI*2);a[0]==="fill"?ctx.fill():ctx.stroke();}
    else if(op==="ellipse"){color(a[5]);ctx.beginPath();ctx.ellipse(a[1],a[2],Math.max(0,a[3]),Math.max(0,a[4]),0,0,Math.PI*2);a[0]==="fill"?ctx.fill():ctx.stroke();}
    else if(op==="polygon"){
      const points=a[1];color(a[2]);ctx.beginPath();ctx.moveTo(points[0],points[1]);
      for(let i=2;i<points.length;i+=2)ctx.lineTo(points[i],points[i+1]);
      ctx.closePath();a[0]==="fill"?ctx.fill():ctx.stroke();
    }
  }while(depth-->0)ctx.restore();
}
async function poll() {
  try {
    const response=await fetch("/api/frame",{signal:AbortSignal.timeout(5000)});
    if(!response.ok)throw new Error(response.status===403?"This device is not on the Deck's local network.":"Tracker service unavailable");
    const frame=await response.json();
    mapMode=frame.game?.mapview?.mode||0;mapActive=mapMode>0;
    if(mapActive)menu.classList.remove("idle");
    frameWidth=frame.width||300;frameHeight=frame.height||740;
    canvas.style.touchAction=mapActive?"none":"auto";
    updateSoundControl(frame.game?.spsoundenabled);
    message.textContent=frame.state==="connected"?"":frame.message||(frame.state==="waiting"?"Waiting for game":frame.state);canvas.classList.toggle("stale",frame.state!=="connected");
    frame.pulsing=frame.commands.some(c=>c[0]==="pulse");
    prepareMotion(frame);latestFrame=frame;
    if(!animationStarted){animationStarted=true;requestAnimationFrame(animate);}
    playSounds(frame.sounds).catch(error=>{sounds.clear();soundStats.error=error.message||String(error);});
  }catch(error){message.textContent=error.message;canvas.classList.add("stale");}
  setTimeout(poll,200);
}
Promise.all([document.fonts.load("18px TrackerBold"),document.fonts.load("11px TrackerNarrow")]).then(poll).catch(error=>{message.textContent=error.message;});

// Local pointer positions are converted to the shared Lua view's logical pixels.
const pointers=new Map();let pinchDistance=0, lastMove=0,lastTap=0, gestureMoved=false;
let lastHover=0;
let mapActions=Promise.resolve();
function mapPoint(event) {
  const r=canvas.getBoundingClientRect();
  return {x:(event.clientX-r.left)*frameWidth/r.width,y:(event.clientY-r.top)*frameHeight/r.height};
}
function mapAction(action,point) {
  mapActions=mapActions.then(async()=>{
    const response=await fetch("/api/map",{method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({action,...point}),signal:AbortSignal.timeout(5000)});
    if(!response.ok)throw new Error("Map control unavailable");
  }).catch(error=>{message.textContent=error.message;});
  return mapActions;
}
canvas.addEventListener("pointerdown",event=>{
  if(!mapActive)return;
  event.preventDefault();canvas.setPointerCapture(event.pointerId);
  const point=mapPoint(event);pointers.set(event.pointerId,point);
  if(pointers.size===1){
    gestureMoved=false;
    const m=mapDescriptor;
    panPreview=m&&point.x>=m.x&&point.x<m.x+m.w&&point.y>=m.y&&point.y<m.y+m.h?{start:point,anchorX:m.panX,anchorY:m.panY,x:m.panX,y:m.panY,moved:false}:null;
    void mapAction("down",point);
  }else {panPreview=null;gestureMoved=true;void mapAction("up",point);pinchDistance=0;}
});
canvas.addEventListener("pointermove",event=>{
  if(!mapActive)return;
  if(!pointers.has(event.pointerId)){
    if(performance.now()-lastHover>100){lastHover=performance.now();void mapAction("hover",mapPoint(event));}
    return;
  }
  const point=mapPoint(event);pointers.set(event.pointerId,point);
  if(panPreview&&pointers.size===1){
    const dx=point.x-panPreview.start.x,dy=point.y-panPreview.start.y;
    panPreview.moved=panPreview.moved||Math.hypot(dx,dy)>3;
    panPreview.x=panPreview.anchorX+dx;panPreview.y=panPreview.anchorY+dy;
  }
  gestureMoved=true;
  if(pointers.size===2){
    const [a,b]=[...pointers.values()],distance=Math.hypot(a.x-b.x,a.y-b.y);
    if(pinchDistance&&Math.abs(Math.log(distance/pinchDistance))>.14){
      void mapAction(distance>pinchDistance?"in":"out",{x:(a.x+b.x)/2,y:(a.y+b.y)/2});pinchDistance=distance;
    }else if(!pinchDistance)pinchDistance=distance;
  }else if(performance.now()-lastMove>80){lastMove=performance.now();void mapAction("move",point);}
});
function releasePointer(event){
  if(!pointers.has(event.pointerId))return;
  const point=mapPoint(event);
  if(pointers.size===1&&gestureMoved)void mapAction("move",point);
  pointers.delete(event.pointerId);pinchDistance=0;void mapAction("up",point);
  if(panPreview)panPreview.releasedAt=performance.now();
  const now=performance.now();
  if(!gestureMoved&&now-lastTap<300)void mapAction("in",point);
  lastTap=gestureMoved?0:now;
}
canvas.addEventListener("pointerup",releasePointer);
canvas.addEventListener("pointercancel",event=>{pointers.delete(event.pointerId);pinchDistance=0;void mapAction("up",mapPoint(event));});
canvas.addEventListener("wheel",event=>{
  if(!mapActive)return;
  event.preventDefault();void mapAction(event.deltaY<0?"in":"out",mapPoint(event));
},{passive:false});
