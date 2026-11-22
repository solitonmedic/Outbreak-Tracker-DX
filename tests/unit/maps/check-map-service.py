"""Reusable offline bundled-map, actual bridge and LAN-route check.

Location/runtime: tests/unit/maps/check-map-service.py; Python3/Pillow + LuaJIT.
Inputs: repository sources and bundled sampled assets; optional --preview-dir
creates a fresh reusable fixture. Requires no disc, ISO, user cache or import.
Outputs: PASS lines; temporary fixture/frame files self-clean unless preview requested.
The fake native module also serves two live J's BAR enemies and one stale
slot (2026-11-20) so previews show enemy markers; players face east/south/
west/north and J's BAR holds one room item, for chevron and item previews.
Safety: fake native module and loopback HTTP only; no PINE, recordings, workbook,
source-disc writes or installed plugin changes. Art stays outside Git.
Run from repo root with Python containing Pillow:
python3 tests/unit/maps/check-map-service.py
Check: B/N frames load with empty HOME/bogus legacy cache, bounded
map actions work; five approved layouts and phone gas render with exact compact
crop bounds and full extra/special inventories; fitted Evil Resource PNGs decode,
appear in Outbreak/Desperate Times frames and are served byte-for-byte over HTTP;
image commands contain explicit crops/transforms; packaged without the game's map
files (unfitted floors draw traced outlines from sources/MapGeometry.lua);
YOU's room is red and other occupied rooms light blue even when local slot changes;
DT gas rooms emit pulsing yellow fills with layered halo/bright outline commands;
the removed import UI/API/drop hooks stay absent. Map9 also requires the SP
facing radar/counter in actual wide/phone/Wild Things frames, vertical ITEM
values, GF/Zoo floor labels, overlay priority, close-label suppression, smaller
voice circles and omitted Wild Things card floors (synthetic state only).
Map11 checks removed captions and existing WT/DT/UB hint colors in actual main
and B/N frames, including separate Underbelly clues and unrelated/reset bits.
Map12 checks Flashback Forest1–4 art, the maze guide (Easy/Normal at the fake's
Normal difficulty, only on the Mountain path floor, no text over the walls), live
maze markers, omitted forest card floors and preserved hospital card floors.
The fake also takes TRACKER_PREVIEW_DIFFICULTY ("-" = absent), _OPTIONS and
_STATES ("difficulty/scenario;..." per update) for check-flashback-guides.py.
Preview: append --preview-dir DIR to keep the fixture, whose frames show the real
UI on synthetic game state.
Skipped (exit status 77) without Pillow or LuaJIT: pip install pillow.
"""

import argparse
import http.client
import importlib.util
import json
import re
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import sys

try:
    from PIL import Image
except ImportError:
    print("SKIP: check-map-service.py needs Pillow (pip install pillow)")
    sys.exit(77)
if not shutil.which("luajit"):
    print("SKIP: check-map-service.py needs LuaJIT")
    sys.exit(77)

ROOT = Path(__file__).resolve().parents[3]
NATIVE = r"""
local function values(t) return setmetatable(t or {},{__index=function()return 0 end}) end
local game=values{currentFile=1,release="jp",scenario="outbreak",frames=12345,playernum=4,localSlot=1,
 hostscenario="outbreak",difficulty="normal",hostdifficulty="normal",hoststatus=6}
game.spTracking={available=true,limit=8,collected=4,radarState="direction",bearing=.6,glow=true}
if os.getenv("TRACKER_PREVIEW_SCENARIO")=="desperate-times" then
 game.currentFile=2;game.scenario="desperate times";game.hostscenario=game.scenario
 game.gasrandom=0;game.gasflag=1;game.fighttime=500;game.fighttime2=65535;game.garagetime=400;game.gastime=180
elseif os.getenv("TRACKER_PREVIEW_SCENARIO")=="wild-things" then
 game.currentFile=2;game.scenario="wild things";game.hostscenario=game.scenario
 game.itemrandom=2;game.itemrandom2=90;game.coin=12;game.gasrandom=14
elseif os.getenv("TRACKER_PREVIEW_SCENARIO")=="underbelly" then
 game.currentFile=2;game.scenario="underbelly";game.hostscenario=game.scenario
elseif os.getenv("TRACKER_PREVIEW_SCENARIO")=="flashback" then
 game.currentFile=2;game.scenario="flashback";game.hostscenario=game.scenario
end
-- Flashback guide checks: base difficulty ("-" = field absent, "(empty)" = ""), options, and
-- a per-update sequence "difficulty/scenario;..." for transitions.
local noDifficulty=false
getmetatable(game).__index=function(_,k) if k=="difficulty" and noDifficulty then return nil end return 0 end
local function setDifficulty(value)
 if value=="(empty)" then value="" end
 noDifficulty=value=="-";game.difficulty=(not noDifficulty) and value or nil
end
if os.getenv("TRACKER_PREVIEW_DIFFICULTY") then setDifficulty(os.getenv("TRACKER_PREVIEW_DIFFICULTY")) end
for option in (os.getenv("TRACKER_PREVIEW_OPTIONS") or ""):gmatch("[^,]+") do game[option]=true end
local states,step={},0
for entry in (os.getenv("TRACKER_PREVIEW_STATES") or ""):gmatch("[^;]+") do states[#states+1]=entry end
local function nextState()
 if #states==0 then return end
 step=math.min(step+1,#states)
 local difficulty,scenario=states[step]:match("^([^/]*)/?(.*)$")
 setDifficulty(difficulty)
 if scenario~="" then game.scenario=scenario;game.hostscenario=scenario end
end
local knowledge=tonumber(os.getenv("TRACKER_PREVIEW_KNOWLEDGE"))
if knowledge then game.passwt=knowledge;game.passdt3=knowledge;game.passub3=knowledge;game.fighttime=0 end
local players={}
for i,kind in ipairs({"Kevin","Alyssa","Yoko","George"}) do
 local p=values{enabled=true,inGame=true,type=kind,name=kind,status="Fine",HP=1700,maxHP=2000,
  power=1,basePower=1,roomID=(game.currentFile==2 and {1,14,20,9} or {1,4,12,8})[i],
  positionX=8950,positionY=12400,virus=12.34,
  forwardX=({1,0,-1,0})[i],forwardY=({0,1,0,-1})[i],
  inventory={},specialInventory={},specialItem=values{id=-1,type=0}}
 for j=1,9 do p.inventory[j]=values{id=-1,type=0};p.specialInventory[j]=values{id=-1,type=0} end
 if kind=="Yoko" or kind=="David" or kind=="Cindy" then
  for j=1,4 do
   p.inventory[j]=values{id=j,type=19,count=j}
   p.specialInventory[j]=values{id=j+4,type=19,count=j+4}
  end
 end
 players[i]=p
end
if game.scenario=="wild things" then
 local D=require "MapData"
 local map=assert(D.load(2,"wild things"))
 local floor=map.floors[2]
 for _,place in ipairs(floor.places) do
  local r=map.rooms[place.record]
  if r.id==27 then
   for i,p in ipairs(players) do
    p.roomID=27;p.heightAvailable=true;p.height=0
    p.positionX=floor.refX+(place.x+r.w*(.2+.15*i))*100/floor.ppu
    p.positionY=floor.refZ+(place.y+r.h*.55)*100/floor.ppu
   end
  end
 end
end
if game.scenario=="flashback" then
 local positions={{3,3257,9229},{3,3735,10584},{5,9229,3095},{7,10430,5814}}
 for i,p in ipairs(players) do
  p.roomID=positions[i][1];p.positionX=positions[i][2];p.positionY=positions[i][3];p.height=0;p.heightAvailable=true
 end
 local room=tonumber(os.getenv("TRACKER_PREVIEW_FOREST_ROOM"))
 local alternate={[1]={2000,600},[4]={5871,2594},[5]={9229,3095},[7]={10430,5814}}
 if room and alternate[room] then
  players[2].roomID=room;players[2].positionX=alternate[room][1];players[2].positionY=alternate[room][2]
 end
 players[2].positionX=players[2].positionX+(tonumber(os.getenv("TRACKER_PREVIEW_MAZE_SHIFT")) or 0)
end
-- Synthetic enemies (File 1 only): two live ones in J's BAR and one stale slot
-- that the map must not draw.
local enemies={}
for i=1,12 do enemies[i]=values{enabled=false,inGame=false} end
if game.currentFile==1 then
 enemies[1]=values{enabled=true,inGame=true,HP=150,maxHP=200,roomID=1,positionX=8292,positionY=12715,name="Zombie",nameID=1,type=9}
 enemies[2]=values{enabled=true,inGame=true,HP=80,maxHP=200,roomID=1,positionX=9005,positionY=12360,name="Zombie",nameID=1,type=9}
 enemies[3]=values{enabled=true,inGame=false,HP=200,maxHP=200,roomID=1,positionX=7940,positionY=13485,name="Zombie",nameID=1,type=9}
end
local items={roomitem={}}
for i=1,32 do items.roomitem[i]=values{id=-1,type=0} end
if game.currentFile==1 then
 items.roomitem[1]=values{id=3,type=309,count=1,pick=0,present=1,mix=0,positionX=8400,positionY=13300}
end
local effectTime=0
local function noop()end
if os.getenv("TRACKER_PREVIEW_EFFECTS")=="1" then
 players[1].HP=200;players[1].antivirustime=45;players[1].bleedtime=10
 players[2].HP=0;players[2].status="Down"
 players[3].status="Dead";players[3].HP=0
 players[4].basePower=1.2;players[4].power=1
 game.spTracking={available=true,limit=8,collected=2,room=players[2].roomID,collectedIds={},roomItems={}}
 local anchor=players[2]
 if game.currentFile==1 then
  -- Loaded room deliberately shared so all marker types are visible together.
  for i=1,4 do players[i].roomID=1;players[i].positionX=8000+i*250;players[i].positionY=12400 end
  game.spTracking.room=1
  game.spTracking.roomItems={{id=0,enabled=true,x=8000,y=13200,height=0},{id=160,enabled=true,x=9000,y=13200,height=0}}
  game.mapItems={{id=44,type=10100,count=1,pick=0,present=1,roomID=1,positionX=8500,positionY=13600}}
 end
 noop=function()
  effectTime=effectTime+.2;game.frames=12345+math.floor(effectTime*30)
  players[4].voiceId=1+math.floor(effectTime/5);players[4].voiceTicks=10
  players[4].positionX=9000+180*math.sin(effectTime)
 end
end
return {init=function()return true end,update=function()nextState();noop()end,updateRoom=noop,updateLobby=noop,
getGameInfo=function()return game end,getMapItems=function()return game.mapItems or {} end,
getPlayer=function(i)return players[i]end,
getSlotPlayer=function()return {enabled=false}end,getItem=function()return items end,
getEnemy=function(i)return enemies[i] or {enabled=false}end,
getRoomMaster=function(i)return {enabled=os.getenv("TRACKER_PREVIEW_EFFECTS")=="1",roommaster=1}end,
getDoor=function()return values{HP=500,flag=0}end}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="tracker-map-") as tmp:
        stage = args.preview_dir.resolve() if args.preview_dir else Path(tmp)
        if args.preview_dir:
            stage.mkdir(parents=True, exist_ok=False)
        (stage / "shared").mkdir()
        for source in (ROOT / "sources").glob("*.lua"):
            shutil.copy2(source, stage / "shared" / source.name)
        (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE)
        shutil.copytree(ROOT / "decky/web", stage / "web")
        shutil.copy2(ROOT / "decky/reader.lua", stage / "reader.lua")
        # As packaged: the sampled game map files stay out (maps come from
        # sources/MapGeometry.lua and the Evil Resource art).
        shutil.copytree(
            ROOT / "assets",
            stage / "assets",
            ignore=lambda folder, names: ["game"] if Path(folder) == ROOT / "assets" / "maps" else [],
        )
        assert not (stage / "shared/MapImport.lua").exists()
        assert "map-import" not in (stage / "web/index.html").read_text()
        assert "map-import" not in (stage / "web/app.js").read_text()
        assert "directorydropped" not in (stage / "shared/main.lua").read_text()
        assert "filedropped" not in (stage / "shared/main.lua").read_text()
        assert not (stage / "assets/maps/game").exists()
        print("PASS packaged without the game's map files")
        er_images = list((stage / "assets/maps/er").rglob("*.png"))
        assert er_images, "Fitted Evil Resource artwork is missing"
        for path in er_images:
            with Image.open(path) as im:
                im.load()
                assert im.convert("RGBA").getbbox(), path
        print(f"PASS all {len(er_images)} fitted Evil Resource PNGs decode and contain artwork")
        spec = importlib.util.spec_from_file_location("font_metrics", ROOT / "decky/scripts/font_metrics.py")
        metrics = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(metrics)
        metrics.generate(ROOT / "assets", stage / "fontmetrics.lua")
        (stage / "empty-home").mkdir()
        env = dict(os.environ, HOME=str(stage / "empty-home"), OUTBREAK_MAP_CACHE="/no-legacy-map-cache")
        result = subprocess.run(
            ["luajit", "reader.lua"],
            input="b\nn\nmap/down/20/160,map/move/40/180,map/up/40/180\nf\n",
            text=True,
            capture_output=True,
            cwd=stage,
            env=env,
            check=True,
        )
        frames = [json.loads(line) for line in result.stdout.splitlines()]

        def check_image_commands(frame):
            for command in frame["commands"]:
                if command[0] == "image":
                    assert isinstance(command[2], list) and len(command[2]) == 4, command[:3]
                    assert isinstance(command[3], list) and len(command[3]) == 9, command[:4]

        for frame in frames:
            assert frame["state"] == "connected", frame.get("message")
            assert frame["game"]["mapview"]["available"] is True
            assert any(c[0] == "image" and c[1].startswith("assets/maps/er/file1/outbreak/") for c in frame["commands"])
            assert (
                sum(c[0] == "clipPush" for c in frame["commands"])
                == sum(c[0] == "clipPop" for c in frame["commands"])
                >= 1
            )
            check_image_commands(frame)
        assert (frames[0]["width"], frames[0]["height"]) == (760, 740)
        busts = [
            c for c in frames[0]["commands"] if c[0] == "image" and c[1].endswith("ui.png") and c[2][2:] == [256, 256]
        ]
        assert busts and all(c[4][:3] == [1, 1, 1] for c in busts), (
            "Healthy cards inherited a prior player's badge tint"
        )
        for frame in frames:
            assert (
                sum(c[0] == "mapBegin" for c in frame["commands"])
                == sum(c[0] == "mapEnd" for c in frame["commands"])
                == 1
            )
            assert (
                sum(c[0] == "actorBegin" for c in frame["commands"])
                == sum(c[0] == "actorEnd" for c in frame["commands"])
                >= 1
            )
        for frame in frames[:2]:
            assert any(c[0] == "text" and c[1] == "SP" for c in frame["commands"]), "Map SP counter/radar absent"
            assert any(c[0] == "rotate" and abs(c[1] - 0.6) < 1e-9 for c in frame["commands"]), (
                "Map SP facing arrow absent"
            )
        assert (frames[1]["width"], frames[1]["height"]) == (390, 844)
        assert frames[2]["game"]["mapview"]["following"] is False
        assert frames[3]["game"]["mapview"]["following"] is True
        for label, frame in zip(("wide", "phone"), frames):
            (stage / f"frame-{label}.json").write_text(json.dumps(frame))

        def room_tints(frame):
            return {
                tuple(c[2]): tuple(round(v, 6) for v in c[3])
                for c in frame["commands"]
                if c[0] == "polygon" and c[1] == "fill" and c[3][3] == 0.25
            }

        red, blue = (1, 0, 0, 0.25), tuple(round(v, 6) for v in (115 / 255, 178 / 255, 249 / 255, 0.25))
        original_tints = room_tints(frames[1])
        assert set(original_tints.values()) == {red, blue}
        (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE.replace("localSlot=1", "localSlot=0"))
        result = subprocess.run(
            ["luajit", "reader.lua"], input="n\n", text=True, capture_output=True, cwd=stage, env=env, check=True
        )
        swapped_tints = room_tints(json.loads(result.stdout))
        assert swapped_tints == {points: (blue if tint == red else red) for points, tint in original_tints.items()}
        (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE)
        print("PASS YOU's room stays red and other occupied rooms light blue when local slot changes")
        # reader.lua is edited by its text; the pattern allows any spacing (StyLua formats it) and
        # must match exactly once, so a layout change cannot turn this into a silent no-op.
        desktop_reader, edits = re.subn(r"isDecky\s*=\s*true", "isDecky = false", (stage / "reader.lua").read_text())
        assert edits == 1, "reader.lua: isDecky = true not found"
        (stage / "reader-desktop.lua").write_text(desktop_reader)
        desktop = subprocess.run(
            ["luajit", "reader-desktop.lua"],
            input="n\n",
            text=True,
            capture_output=True,
            cwd=stage,
            env=env,
            check=True,
        )
        desktop_frame = json.loads(desktop.stdout)
        check_image_commands(desktop_frame)
        assert (desktop_frame["width"], desktop_frame["height"]) == (300, 740)
        (stage / "frame-vertical.json").write_text(json.dumps(desktop_frame))
        # Assert real emitted crops stay in the three approved compact sections,
        # rather than accepting a small copy of the complete 300x145 card.
        for frame, card_y, status_x, inv_x, bust_x in (
            (desktop_frame, 452, 2, 128, 222),
            (frames[1], 558, 4, 160, 308),
        ):
            clips = [c[1:] for c in frame["commands"] if c[0] == "clipPush"]
            assert [status_x, card_y + 3, 112, 36] in clips
            assert any(c[0] == inv_x and c[1] >= card_y and c[2] > 60 for c in clips)
            # Yoko's complete eight-slot region must fit before the separate bust.
            extended = [
                c for c in clips if c[0] == inv_x and c[1] >= card_y + 2 * (72 if frame["width"] == 300 else 71)
            ]
            assert extended and all(c[0] + c[2] <= bust_x - 3 for c in extended)
            assert [bust_x, card_y + 1, 74, 70] in clips
            assert len(clips) == 13

        def visible_extra_counts(frame):
            matrix = (1, 1, 0, 0)
            stack = []
            clip = None
            clips = []
            visible = set()
            for command in frame["commands"]:
                op, *a = command
                if op == "push":
                    stack.append(matrix)
                elif op == "pop":
                    matrix = stack.pop()
                elif op == "translate":
                    sx, sy, tx, ty = matrix
                    matrix = (sx, sy, tx + a[0] * sx, ty + a[1] * sy)
                elif op == "scale":
                    sx, sy, tx, ty = matrix
                    matrix = (sx * a[0], sy * a[1], tx, ty)
                elif op == "clipPush":
                    clips.append(clip)
                    clip = a
                elif op == "clipPop":
                    clip = clips.pop()
                elif op == "text" and str(a[0]) in ("5", "6", "7", "8") and clip:
                    # Each count is right-aligned at icon.x+46, below its image.
                    sx, sy, tx, ty = matrix
                    x = tx + (a[2][0] + 40) * sx
                    y = ty + (a[2][1] + 5) * sy
                    if clip[0] <= x < clip[0] + clip[2] and clip[1] <= y < clip[1] + clip[3]:
                        visible.add(str(a[0]))
            return visible

        for kind in ("Yoko", "David", "Cindy"):
            (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE.replace('"Yoko"', json.dumps(kind), 1))
            for reader in ("reader.lua", "reader-desktop.lua"):
                result = subprocess.run(
                    ["luajit", reader], input="n\n", text=True, capture_output=True, cwd=stage, env=env, check=True
                )
                frame = json.loads(result.stdout)
                assert visible_extra_counts(frame) == {"5", "6", "7", "8"}, (kind, reader, "extra slots clipped")
        print("PASS visible extra-slot counts 5–8 for Yoko, David and Cindy in phone and desktop compact cards")
        gas_native = (
            NATIVE.replace("currentFile=1", "currentFile=2")
            .replace('"outbreak"', '"desperate times"')
            .replace(
                "hoststatus=6}",
                "hoststatus=6,gasrandom=0,gasflag=1,fighttime=500,fighttime2=65535,garagetime=400,gastime=180}",
            )
        )
        (stage / "shared/luaoutbreaktracker.lua").write_text(gas_native)
        for label, reader, key in (
            ("gas-wide", "reader.lua", "b"),
            ("gas-vertical", "reader-desktop.lua", "n"),
            ("gas-phone", "reader.lua", "n"),
        ):
            result = subprocess.run(
                ["luajit", reader], input=key + "\n", text=True, capture_output=True, cwd=stage, env=env, check=True
            )
            frame = json.loads(result.stdout)
            assert frame["state"] == "connected"
            check_image_commands(frame)
            assert any(
                c[0] == "image" and c[1].startswith("assets/maps/er/file2/desperate-times/") for c in frame["commands"]
            )
            assert any(c[0] == "polygon" and c[1] == "line" and c[3][:3] == [1, 1, 0.35] for c in frame["commands"])
            assert sum(c[0] == "clipPush" for c in frame["commands"]) == sum(
                c[0] == "clipPop" for c in frame["commands"]
            )
            (stage / f"frame-{label}.json").write_text(json.dumps(frame))
        result = subprocess.run(
            ["luajit", "reader.lua"], input="n\n\n", text=True, capture_output=True, cwd=stage, env=env, check=True
        )
        pulse_frames = [json.loads(line) for line in result.stdout.splitlines()]

        def gas_alphas(frame):
            return {
                c[3][3] for c in frame["commands"] if c[0] == "polygon" and c[1] == "fill" and c[3][:3] == [1, 0.85, 0]
            }

        assert all(gas_alphas(frame) for frame in pulse_frames)
        assert gas_alphas(pulse_frames[0]) != gas_alphas(pulse_frames[1])
        print("PASS DT gas rooms pulse with yellow fills and glowing room outlines")
        (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE)
        print(
            "PASS actual wide, desktop vertical, phone and three gas views; "
            "exact compact crop bounds and balanced clips"
        )
        wt_env = dict(env, TRACKER_PREVIEW_SCENARIO="wild-things")
        result = subprocess.run(
            ["luajit", "reader.lua"], input="n\n", text=True, capture_output=True, cwd=stage, env=wt_env, check=True
        )
        wt = json.loads(result.stdout)
        assert wt["state"] == "connected"
        texts = [c[1] for c in wt["commands"] if c[0] == "text"]
        assert "3\n10" in texts and "ITEM" not in texts, "Stacked values or caption removal incorrect"
        assert "SP —" not in texts, "Unavailable SP-set placeholder remained"
        assert "GF" in texts and "Zoo" in texts, "Wild Things abbreviated floor labels missing"
        assert texts.count("Zoo") == 4, "Wild Things compact cards still draw redundant floor labels"
        assert not any(isinstance(t, str) and "Raccoon City Zoo" in t for t in texts), "Long floor label remained"
        assert any(c[0] == "rotate" and abs(c[1] - 0.6) < 1e-9 for c in wt["commands"]), "Wild Things map radar absent"
        (stage / "frame-wild-things-phone.json").write_text(json.dumps(wt))
        print("PASS Wild Things vertical ITEM values, GF/Zoo labels, four-player floor row and SP radar")
        grey = [127 / 255, 127 / 255, 127 / 255, 1]
        green = [0, 200 / 255, 0, 1]

        def near(a, b):
            return len(a) == len(b) and all(abs(x - y) < 1e-10 for x, y in zip(a, b))

        for scene, clues, bits in [
            ("wild-things", ["9AAA"], [0, 4, 128, 132, 0]),
            ("desperate-times", ["2236"], [0, 4, 128, 132, 0]),
            ("underbelly", ["DESK", "2916"], [0, 16, 32, 48, 128, 0]),
        ]:
            for bit in bits:
                state_env = dict(env, TRACKER_PREVIEW_SCENARIO=scene, TRACKER_PREVIEW_KNOWLEDGE=str(bit))
                frames_by_view = []
                for key in ("", "b", "n"):
                    result = subprocess.run(
                        ["luajit", "reader.lua"],
                        input=key + "\n",
                        text=True,
                        capture_output=True,
                        cwd=stage,
                        env=state_env,
                        check=True,
                    )
                    checked = json.loads(result.stdout)
                    assert checked["state"] == "connected"
                    frames_by_view.append(checked)
                for i, clue in enumerate(clues):
                    mask = (32 if i == 0 else 16) if scene == "underbelly" else 4
                    expected = green if bit & mask else grey
                    assert any(
                        c[0] == "text" and c[1] == clue and near(c[4], expected) for c in frames_by_view[0]["commands"]
                    ), "Main hint color incorrect"
                    for frame in frames_by_view[1:]:
                        matched = False
                        for c in frame["commands"]:
                            if c[0] != "text" or not isinstance(c[1], list):
                                continue
                            color = None
                            for part in c[1]:
                                if isinstance(part, list):
                                    color = part
                                elif clue in part and near(color, expected):
                                    matched = True
                        assert matched, "Map learned-clue colors differ from main tracker"
                if scene == "wild-things" and bit == 4:
                    (stage / "frame-learned-hint-phone.json").write_text(json.dumps(frames_by_view[2]))
        print(
            "PASS existing WT/DT/UB clue colors agree across main/B/N views; "
            "independent UB clues, unrelated bits and reset"
        )
        fb_env = dict(env, TRACKER_PREVIEW_SCENARIO="flashback")

        def forest_frame(extra=None):
            result = subprocess.run(
                ["luajit", "reader.lua"],
                input="n\n",
                text=True,
                capture_output=True,
                cwd=stage,
                env=dict(fb_env, **(extra or {})),
                check=True,
            )
            frame = json.loads(result.stdout)
            assert frame["state"] == "connected"
            return frame

        fb = forest_frame()
        labels = [c[1] for c in fb["commands"] if c[0] == "text"]
        assert labels.count("Forest 2") == 4 and "Forest 4" not in labels, "Forest card floor labels remained"
        assert labels.count("1F") == 2, "Hospital card floor label was hidden"
        assert "EXIT" not in labels, "Maze guide text drawn over the walls"
        assert fb["game"]["mapview"].get("guide") == "00", "Normal difficulty must select the Easy/Normal guide"
        assert any(c[0] == "polygon" and c[3] == [0, 0.95, 1, 0.95] for c in fb["commands"]), "Maze guide missing"
        start = next(c[2:4] for c in fb["commands"] if c[0] == "actorBegin" and c[1] == 2)
        moved = forest_frame({"TRACKER_PREVIEW_MAZE_SHIFT": "100"})
        end = next(c[2:4] for c in moved["commands"] if c[0] == "actorBegin" and c[1] == 2)
        assert abs(end[0] - start[0]) > 2, "Maze player still fell back to a stationary room center"
        for room, image in ((1, "forest1"), (3, "forest2"), (4, "forest3"), (5, "forest4"), (7, "hospital1f")):
            checked = forest_frame({"TRACKER_PREVIEW_FOREST_ROOM": str(room)})
            assert any(
                c[0] == "image" and c[1].endswith("reoutbreak2_" + image + ".png") for c in checked["commands"]
            ), image + " artwork absent"
            if room != 3:
                assert not any(c[0] == "polygon" and c[3] == [0, 0.95, 1, 0.95] for c in checked["commands"]), (
                    "Forest guide leaked onto " + image
                )
        (stage / "frame-flashback-phone.json").write_text(json.dumps(fb))
        print(
            "PASS Flashback Forest1–4 art/guide/live maze markers, no forest card floors and retained hospital floors"
        )
        fallback_native = NATIVE.replace('"outbreak"', '"below freezing point"')
        (stage / "shared/luaoutbreaktracker.lua").write_text(fallback_native)
        result = subprocess.run(
            ["luajit", "reader.lua"], input="n\n", text=True, capture_output=True, cwd=stage, env=env, check=True
        )
        frame = json.loads(result.stdout)
        assert frame["state"] == "connected" and frame["game"]["mapview"]["available"] is True
        check_image_commands(frame)
        # Below Freezing Point is scenario 35: map 035 (002 is Hellfire; fixed
        # 2026-11-20). Its floors draw its own game art or its fitted Evil
        # Resource art, never another scenario's.
        images = [c[1] for c in frame["commands"] if c[0] == "image" and c[1].startswith("assets/maps/")]
        assert images and all(i.startswith("assets/maps/er/file1/below-freezing-point/") for i in images), images
        (stage / "shared/luaoutbreaktracker.lua").write_text(NATIVE)
        print("PASS Below Freezing Point draws only its own fitted Evil Resource art, no game files")
        # Combined presentation fixture: real cards, active SP/scenario items,
        # countdown-driven voice events and the exact native menu implementation.
        effect_env = dict(env, TRACKER_PREVIEW_EFFECTS="1")
        effect = subprocess.run(
            ["luajit", "reader.lua"],
            input="n\n" + "\n" * 30,
            text=True,
            capture_output=True,
            cwd=stage,
            env=effect_env,
            check=True,
        )
        effects = [json.loads(line) for line in effect.stdout.splitlines()]
        assert all(f["state"] == "connected" for f in effects)
        first = effects[0]
        assert any(c[0] == "rectangle" and c[6] == [1, 0.38, 0, 0.95] for c in first["commands"]), (
            "Scenario item is not bright orange"
        )
        assert any(c[0] == "polygon" and c[3] == [0.2, 0.6, 1, 1] for c in first["commands"]), (
            "Personal SP marker missing"
        )
        assert any(c[0] == "polygon" and c[3] == [0.15, 1, 0.2, 1] for c in first["commands"]), (
            "Regular SP marker missing"
        )
        assert any(c[0] == "image" and c[4] == [1, 0.08, 0.08, 1] for c in first["commands"]), "Dead bust was not red"
        assert any(c[0] == "circle" and c[5][:3] == [0, 1, 0.15] for f in effects[20:] for c in f["commands"]), (
            "Voice event did not glow"
        )
        commands = effects[-1]["commands"]
        last_actor = max(i for i, c in enumerate(commands) if c[0] == "actorEnd")
        regular = [
            i
            for i, c in enumerate(commands)
            if c[0] == "rectangle" and c[1] == "fill" and c[4:6] == [20, 20] and c[6] == [0, 0, 0, 0.7]
        ]
        sp = [i for i, c in enumerate(commands) if c[0] == "polygon" and c[3] in ([0.2, 0.6, 1, 1], [0.15, 1, 0.2, 1])]
        scenario = [i for i, c in enumerate(commands) if c[0] == "rectangle" and c[6] == [1, 0.38, 0, 0.95]]
        hp = [i for i, c in enumerate(commands) if c[0] == "text" and c[1] in ("75%", "40%")]
        assert regular and sp and scenario and hp
        assert (
            last_actor < min(regular) and max(regular) < min(sp) and max(sp) < min(scenario) and max(scenario) < min(hp)
        ), "Foreground priority is wrong"
        in_actor = False
        for c in commands:
            if c[0] == "actorBegin":
                in_actor = True
            elif c[0] == "actorEnd":
                in_actor = False
            elif in_actor and c[0] == "text":
                assert c[1] not in ("YOU", "P1", "P2", "P3", "P4"), "Crowded actor labels remained"
        green = [c for c in commands if c[0] == "circle" and c[5][:3] == [0, 1, 0.15]]
        assert green and all(c[4] <= 14 for c in green), "Ad-lib pulse stayed oversized"
        print("PASS overlay order: actors < items < SP < scenario < HP; crowded labels hidden and smaller voice pulse")
        (stage / "frame-effects-phone.json").write_text(json.dumps(effects[-1]))
        menu_reader = desktop_reader.replace("love.load({})", 'love.load({})\nrequire("TrackerMenu").open=true')
        (stage / "reader-menu.lua").write_text(menu_reader)
        menu = subprocess.run(
            ["luajit", "reader-menu.lua"],
            input="\n",
            text=True,
            capture_output=True,
            cwd=stage,
            env=effect_env,
            check=True,
        )
        menu_frame = json.loads(menu.stdout)
        assert menu_frame["state"] == "connected"
        assert any(c[0] == "text" and c[1] == "TRACKER CONTROLS" for c in menu_frame["commands"])
        assert any(c[0] == "text" and c[1] == "MAIN TRACKER" for c in menu_frame["commands"])
        (stage / "frame-menu.json").write_text(json.dumps(menu_frame))
        print("PASS combined scenario/SP markers, dead tint, voice glow and native main-tracker menu")
        spec = importlib.util.spec_from_file_location("tracker_service", ROOT / "decky/tracker_service.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        service = module.TrackerService(stage, port=0)
        service.reader_loop = lambda: service.stopping.wait()
        service.start()
        port = service.server.server_address[1]

        def request(path, data=None, origin=None):
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            headers = {"Content-Type": "application/json"}
            if origin:
                headers["Origin"] = origin
            client.request(
                "POST" if data is not None else "GET", path, json.dumps(data) if data is not None else None, headers
            )
            response = client.getresponse()
            body = response.read()
            client.close()
            return response.status, body

        try:
            assert request("/api/map", {"action": "move", "x": 20, "y": 160})[0] == 200
            assert service.keys.get_nowait() == "map/move/20.00/160.00"
            assert request("/api/key", {"key": "n"})[0] == 200
            assert request("/api/key", {"key": "home"})[0] == 200
            assert request("/api/map", {"action": "hover", "x": 20, "y": 160})[0] == 200
            assert request("/api/map", {"action": "shell", "x": 0, "y": 0})[0] == 400
            assert request("/api/map", {"action": "down", "x": True, "y": 0})[0] == 400
            assert request("/api/map", {"action": "down", "x": 1e20, "y": 0})[0] == 400
            assert request("/api/map", {"action": "down", "x": 0, "y": 0}, "https://elsewhere.example")[0] == 403
            for image_path in er_images:
                path = "/" + image_path.relative_to(stage).as_posix()
                status, body = request(path)
                assert status == 200 and body == image_path.read_bytes(), path
            assert request("/assets/arialbd.ttf")[0] == 200
            assert request("/maps/../../shared/MapData.lua")[0] == 404
            assert request("/maps/jp1/index")[0] == 404
            assert request("/api/map-import", {"path": "/not-a-disc.iso"})[0] == 404
        finally:
            service.stop()
        print(
            "PASS actual HTTP routes: packaged art and bounded map actions; import API absent; "
            "traversal and origin rejection; no native reader started"
        )
        if args.preview_dir:
            print("Preview fixture:", stage)


if __name__ == "__main__":
    main()
