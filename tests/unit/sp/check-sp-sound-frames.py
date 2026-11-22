"""Purpose: reusable check that the SP found sound reaches the Decky phone view once per play.
Location/runtime: tests/unit/sp/check-sp-sound-frames.py; Python 3, LuaJIT, Node.js.
Inputs: current decky/reader.lua and decky/web/app.js; a synthetic main.lua that loads
assets/sp-found.wav and plays it on a key; synthetic count sequences for the browser.
Optional --reader PATH selects the original bridge when the staged debug bridge
also requires native recorder/probe libraries outside this synthetic fixture.
Outputs: PASS lines; temporary files self-clean. Safety: no native module, PINE,
recordings, workbook or network access (the browser code runs with stubbed audio/fetch).
Run from the repository root: python3 tests/unit/sp/check-sp-sound-frames.py
Skipped (exit status 77) without LuaJIT or Node.js.
Check: reader frames carry sounds {"assets/sp-found.wav": n} from the first frame, n rises
by one per play(); the page's playSounds() plays once per rise and never for the first
frame, a repeated frame, a reader restart (lower count) or while audio is still locked (those
rises are counted as missed); unlockAudio() resumes a suspended or iOS "interrupted" context
and plays one silent sample, and leaves a running context alone.
Also checks shared M state in real bridge frames, the service key whitelist,
and actual browser control creation/clicks/On-Off/ARIA updates using a fake DOM.
"""

import ast
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

for tool in ("luajit", "node"):
    if not shutil.which(tool):
        print("SKIP: check-sp-sound-frames.py needs %s" % tool)
        sys.exit(77)  # skipped

ROOT = Path(__file__).resolve().parents[3]
SOUND = "assets/sp-found.wav"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reader", type=Path, default=ROOT / "decky/reader.lua")
args = parser.parse_args()

with tempfile.TemporaryDirectory(prefix="sp-sound-") as directory:
    stage = Path(directory)
    (stage / "shared").mkdir()
    (stage / "fontmetrics.lua").write_text("return {}")
    (stage / "shared/main.lua").write_text(f'''
GameInfo={{currentFile=1,spsoundenabled=true}}
function love.load() Sound=love.audio.newSource("{SOUND}","static") end
function love.keypressed(key)
 if key=="m" then GameInfo.spsoundenabled=not GameInfo.spsoundenabled end
 if key=="x" and GameInfo.spsoundenabled then Sound:play() end
end
function love.update() end
function love.draw() end
''')
    result = subprocess.run(
        ["luajit", str(args.reader.resolve())],
        input="\nx\n\nx,x\nm,x\nm,x\n",
        text=True,
        cwd=stage,
        capture_output=True,
        check=True,
    )
    frames = [json.loads(line) for line in result.stdout.splitlines()]
    counts = [frame["sounds"] for frame in frames]
    assert counts == [{SOUND: n} for n in [0, 1, 1, 3, 3, 4]], counts
    assert [frame["game"]["spsoundenabled"] for frame in frames] == [True, True, True, True, False, True]
print("PASS Decky frames carry shared M toggle state and sound counts: 0, 1, 1, 3, 3, 4")

app = (ROOT / "decky/web/app.js").read_text()
functions = [
    re.search(r"\n((?:async )?function %s\(.*?\n\}\n)" % name, app, re.S).group(1)
    for name in ("unlockAudio", "sound", "playSounds")
]
script = """
const sounds=new Map(), soundCounts=new Map(), soundStats={played:0,missed:0};
let audio=null, soundBaseline=false, started=0;
const window={};
const fetch=async()=>({ok:true,arrayBuffer:async()=>new ArrayBuffer(8)});
%s
const steps=JSON.parse(process.argv[1]), results=[];
(async()=>{
  for(const [state,counts] of steps) {
    audio=state==="none"?null:{state,decodeAudioData:(data,resolve)=>resolve({}),destination:{},
      createBufferSource:()=>({connect(){},start(){started++;}})};
    const before=started;await playSounds(counts);results.push(started-before);
  }
  // unlockAudio: creates the context on the first gesture, then resumes and plays a
  // silent sample whenever it is not running (suspended, or interrupted on iOS).
  const unlock=[];
  let state="suspended";
  window.AudioContext=function(){created++;return context;};
  let created=0, resumed=0, silent=0;
  const context={get state(){return state;},resume(){resumed++;return Promise.resolve();},destination:{},
    createBuffer:(channels,length)=>({channels,length}),
    createBufferSource:()=>({connect(){},start(){silent++;}})};
  audio=null;
  for(const s of ["suspended","interrupted","running"]){state=s;unlockAudio();unlock.push([created,resumed,silent]);}
  console.log(JSON.stringify({results,stats:soundStats,unlock}));
})();
""" % "".join(functions)
S = SOUND
steps = [
    ["running", {S: 4}],  # page opened mid-run: baseline only
    ["running", {S: 4}],  # repeated frame
    ["running", {S: 5}],  # one play
    ["running", {S: 5}],  # same frame polled again
    ["running", {S: 0}],  # reader restarted
    ["running", {S: 1}],  # first play after the restart
    ["suspended", {S: 2}],  # audio still locked: recorded, not played
    ["running", {S: 2}],  # unlocking does not replay it
    ["none", {S: 3}],  # no audio support
    ["running", []],  # empty Lua table serialises as an array
    ["running", {S: 4}],
    ["running", {"assets/other.wav": 1}],  # a file first seen after the baseline plays
]
output = json.loads(
    subprocess.run(["node", "-e", script, json.dumps(steps)], capture_output=True, text=True, check=True).stdout
)
assert output["results"] == [0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1], output
assert output["stats"] == {"played": 4, "missed": 2}, output  # locked (suspended) and no-audio rises
print("PASS phone page plays once per count rise; first frame, repeats, restarts and locked audio stay silent")
assert output["unlock"] == [[1, 1, 1], [1, 2, 2], [1, 2, 2]], output
print("PASS unlock resumes suspended and interrupted audio with a silent sample; running audio is left alone")

service = ast.parse((ROOT / "decky/tracker_service.py").read_text())
keys = next(
    ast.literal_eval(n.value)
    for n in service.body
    if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "KEYS" for t in n.targets)
)
assert "m" in keys, "service rejects the sound toggle"

startup = app.split("const sheet =")[0]
control_script = (
    r"""
const sent=[];
function element(){return {children:[],handlers:{},attributes:{},append(...nodes){this.children.push(...nodes);},
  addEventListener(name,fn){this.handlers[name]=fn;},setAttribute(name,value){this.attributes[name]=value;}};}
const nodes={"#tracker":{getContext(){return {}; }},"#message":element(),"#controls":element()};
const document={querySelector:id=>nodes[id],createElement:element};
const fetch=async(url,options)=>{sent.push(JSON.parse(options.body).key);return {ok:true};};
"""
    + startup
    + r"""
(async()=>{
 if(!controls.some(([key])=>key==="m"))throw Error("keyboard whitelist lacks M");
 if(spSoundButton.textContent!=="SP RADAR SOUND: ON"||spSoundButton.attributes["aria-pressed"]!=="true")
   throw Error("sound control does not default On");
 updateSoundControl(false);
 if(spSoundButton.textContent!=="SP RADAR SOUND: OFF"||spSoundButton.attributes["aria-pressed"]!=="false")
   throw Error("sound control ignores shared Off state");
 await spSoundButton.handlers.click();
 if(sent.length!==1||sent[0]!=="m")throw Error("sound button did not send M");
 updateSoundControl(true);
 if(spSoundButton.textContent!=="SP RADAR SOUND: ON"||spSoundButton.attributes["aria-pressed"]!=="true")
   throw Error("sound control did not return On");
 updateSoundControl(undefined);
 if(spSoundButton.attributes["aria-pressed"]!=="true")throw Error("missing state did not default On");
 console.log("PASS phone sound button defaults On, sends M, and follows shared On/Off with accessible state; " +
  "service accepts M");
})().catch(error=>{console.error(error);process.exitCode=1;});
"""
)
print(subprocess.run(["node", "-e", control_script], capture_output=True, text=True, check=True).stdout.strip())
