// Purpose: reusable Canvas renderer for original Lua tracker drawing commands.
// Runtime: phone/desktop browser. Inputs: private fragment, drawing frames, fonts.
// Outputs: responsive tracker and whitelisted touch/keyboard commands.
// Safety: no emulator access or saved game data; token stays in session storage.
// Run: open the private phone link in Decky. Check: cards and controls update.
"use strict";
const canvas = document.querySelector("#tracker"), ctx = canvas.getContext("2d");
const message = document.querySelector("#message");
const token = location.hash.slice(1) || sessionStorage.getItem("outbreakToken") || "";
if (token) sessionStorage.setItem("outbreakToken", token);
history.replaceState(null, "", location.pathname);
const images = new Map(), imageFonts = new Map(), tinted = new Map();
const groups = [
  ["Views", false, [["f1","Help"],["f2","Item views"],["f3","Next room"],["l","Language"]]],
  ["Show", false, [["i","Room items"],["t","Timers"],["q","Puzzle hints"],["e","Enemy HP"],["f4","Enemy list"]]],
  ["Layout", false, [["v","Vertical"],["h","Horizontal"],["d","Default size"],["a","Auto size"]]],
  ["Players shown", true, [["1","1"],["2","2"],["3","3"],["4","4"]]],
  ["Enemy list shows", true, [["kp0","All"],["kp1","P1"],["kp2","P2"],["kp3","P3"],["kp4","P4"]]],
];
const controls = groups.flatMap(([, , keys]) => keys);
async function sendKey(key) {
  try {
    const response = await fetch("/api/key", {method:"POST",headers:{"Authorization":"Bearer "+token,"Content-Type":"application/json"},body:JSON.stringify({key}),signal:AbortSignal.timeout(5000)});
    if (!response.ok) throw new Error("Control request failed; reopen the link from Decky.");
  } catch(error) { message.textContent=error.message; }
}
const controlsRoot = document.querySelector("#controls");
for(const [title,segmented,keys] of groups) {
  const group=document.createElement("div"), heading=document.createElement("h3"), row=document.createElement("div");
  group.className="group"; heading.textContent=title; row.className=segmented?"row segmented":"row";
  for(const [key,label] of keys) {
    const button=document.createElement("button"); button.type="button"; button.textContent=label; button.title=key.toUpperCase();
    button.addEventListener("click",()=>sendKey(key)); row.append(button);
  }
  group.append(heading,row); controlsRoot.append(group);
}
const sheet = document.querySelector("#sheet"), menu = document.querySelector("#menu");
function setSheet(open) { sheet.hidden=!open; menu.setAttribute("aria-expanded",String(open)); }
menu.addEventListener("click",()=>setSheet(true));
document.querySelector("#close").addEventListener("click",()=>setSheet(false));
document.querySelector("#backdrop").addEventListener("click",()=>setSheet(false));
addEventListener("keydown",event=>{
  const key=event.code.startsWith("Numpad") ? "kp"+event.code.slice(6) : event.key.toLowerCase();
  if(key==="escape"&&!sheet.hidden){setSheet(false);return;}
  if(controls.some(([allowed])=>allowed===key)&&!event.ctrlKey&&!event.metaKey&&!event.altKey) {
    event.preventDefault(); if(!event.repeat) void sendKey(key);
  }
});
async function image(path) {
  if(!images.has(path)) images.set(path,new Promise((resolve,reject)=>{
    const img=new Image(); img.onload=()=>resolve(img); img.onerror=()=>reject(new Error("Unable to load tracker artwork")); img.src="/"+path;
  }));
  return images.get(path);
}
function color(value) {
  const [r,g,b,a=1]=value; ctx.fillStyle=ctx.strokeStyle="rgb("+(r*255)+" "+(g*255)+" "+(b*255)+")"; ctx.globalAlpha=a;
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
// Safari hides its toolbar but floats the address pill over the page and reports no safe area,
// so when a touch phone shows the page at full screen height, keep the tracker clear of both.
function updateInsets() {
  const portrait=innerHeight>innerWidth, fullHeight=Math.max(screen.width,screen.height);
  const immersive=portrait&&matchMedia("(pointer: coarse)").matches&&innerHeight>=fullHeight-60;
  document.documentElement.style.setProperty("--reserve-top",immersive?"100px":"0px");
  document.documentElement.style.setProperty("--reserve-bottom",immersive?"24px":"0px");
}
async function render(frame) {
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
  let depth=0;
  for(const command of frame.commands) {
    const [op,...a]=command;
    if(op==="push"){ctx.save();depth++;}
    else if(op==="pop"){if(depth){ctx.restore();depth--;}}
    else if(op==="translate")ctx.translate(...a);
    else if(op==="scale")ctx.scale(...a);
    else if(op==="image")drawTinted(await image(a[0]),a[1],a[2],a[3],a[0]);
    else if(op==="text")await drawText(...a);
    else if(op==="rectangle"){color(a[5]);ctx.beginPath();ctx.roundRect(a[1],a[2],a[3],a[4],Math.max(0,Math.min(a[6],Math.abs(a[3])/2,Math.abs(a[4])/2)));a[0]==="fill"?ctx.fill():ctx.stroke();}
    else if(op==="circle"){color(a[4]);ctx.beginPath();ctx.arc(a[1],a[2],Math.max(0,a[3]),0,Math.PI*2);a[0]==="fill"?ctx.fill():ctx.stroke();}
  }while(depth-->0)ctx.restore();
}
async function poll() {
  if(!token){message.textContent="Open the phone link shown in the Outbreak Tracker Decky panel.";return;}
  try {
    const response=await fetch("/api/frame",{headers:{"Authorization":"Bearer "+token},signal:AbortSignal.timeout(5000)});
    if(!response.ok)throw new Error(response.status===401?"This connection link has expired. Open the current link from Decky.":"Tracker service unavailable");
    const frame=await response.json();
    message.textContent=frame.state==="connected"?"":frame.message||(frame.state==="waiting"?"Waiting for game":frame.state);canvas.classList.toggle("stale",frame.state!=="connected");await render(frame);
  }catch(error){message.textContent=error.message;canvas.classList.add("stale");}
  setTimeout(poll,200);
}
Promise.all([document.fonts.load("18px TrackerBold"),document.fonts.load("11px TrackerNarrow")]).then(poll).catch(error=>{message.textContent=error.message;});
