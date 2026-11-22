// Reusable renderer math check. Node.js stdlib; reads decky/web/app.js and runs
// only its camera/actor interpolation prefix with a synthetic document/clock.
// No browser, PINE, recordings or writes. From repo root:
// node tests/unit/maps/check-map-motion.js
// PASS means follow camera/actors agree, pan snaps and room changes don't slide.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
let now=1000;
const source=fs.readFileSync('decky/web/app.js','utf8').split('async function animate')[0];
const context=vm.createContext({document:{querySelector:()=>({getContext:()=>({})})},performance:{now:()=>now},Math,Map,Set});
vm.runInContext(source,context);
function run(js){return vm.runInContext(js,context);}
function frame(camera,actor,key='same',room='room1') {
 context.frame={width:390,height:844,commands:[['mapBegin',0,0,390,500,0,0,camera,0,key],['actorBegin',1,actor,50,room]]};run('prepareMotion(frame)');
}
frame(-50,50);now=1200;frame(-100,50);
assert.equal(run('actorPoint(cameraMotion,1300).x+actorPoint(actorMotion.get(1),1300).x'),50,'Follow marker drifted away from camera centre');
assert.equal(run('actorPoint(cameraMotion,1300).x'),-75,'Camera did not interpolate');
now=1400;frame(-200,20,'panned');assert.equal(run('actorPoint(cameraMotion,1400).x'),-200,'Pan was delayed');
now=1600;frame(-200,300,'panned','room2');assert.equal(run('actorPoint(actorMotion.get(1),1600).x'),500,'Room transition slid across the map');
console.log('PASS shared camera/actor interpolation, immediate pan, discontinuity snap');
