-- Purpose: reusable packaged-map/parser and shared map UI regression check.
-- Runtime/location: tests/unit/maps/check-runtime-maps.lua; LuaJIT.
-- Inputs: repository root arg[1], sources/MapGeometry.lua via MapData, shared UI; the
-- parser truncation case also reads the local assets/maps/game/jp1/001.dat when present.
-- Outputs: PASS lines only; no writes, discs, user cache, PINE, recordings or workbook.
-- Safety: actual UI runs on the existing synthetic native/graphics fixture.
-- Run from repo-merged: luajit tests/unit/maps/check-runtime-maps.lua .
-- Check (2026-11-21 addition, last PASS line): V.roomTint gives arena boxes the
-- floor-map tints; an arena box taps on release, a drag from it pans.
-- Check: ten maps load from the committed layout table without an importer or game files; signed crops/origin and floor
-- ambiguity, manual pan/follow, all40 gas lists and actual B/N/V draw handlers;
-- enemy markers only for enabled, in-game, living slots on the shown floor;
-- U.S. File 1 loads the matching Japanese map data, U.S. File 2 stays off;
-- chevron heading from forward (+0x70,+0x50); YOU from the local-slot byte;
-- room items (+8/+16) only for valid items in YOU's room; Evil Resource
-- layers from sources/MapER.lua and plain-Lua triangulation of room outlines.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local Data = require("MapData")
local function read(path)
    local file = io.open(repo .. "/" .. path, "rb")
    if not file then
        return
    end
    local bytes = file:read("*a")
    file:close()
    return bytes
end
assert(Data.import == nil and Data.png == nil, "Runtime disc importer was retained")
for game = 1, 2 do
    local rooms, floors = 0, 0
    for _, scenario in ipairs(Data.scenarios[game]) do
        local map = assert(Data.load(game, scenario[2]))
        rooms = rooms + #map.rooms
        floors = floors + #map.floors
        assert(map.code == scenario[1] and map.path == nil, "Map still names a game file")
    end
    assert(rooms == (game == 1 and 194 or 156) and floors == (game == 1 and 39 or 41))
end
local map = Data.load(1, "outbreak")
local x, y = Data.position(map.floors[3], 8950, 12400)
assert(x == 84 and y == 18)
assert(not pcall(Data.parse, "short"))
local dat = read("assets/maps/game/jp1/001.dat")
if dat then
    assert(not pcall(Data.parse, dat:sub(1, -2)))
end
local under = Data.load(2, "underbelly")
assert(under.floors[12].places[1].x == -3 and under.floors[12].places[1].y == -6)
local flash = Data.load(2, "flashback")
assert(#flash.rooms[27].outlines > 0 and flash.rooms[27].x == nil, "Room outline missing or texture position exported")
print(
    "PASS ten Japanese main scenarios load from MapGeometry with no game files; signed placements, outlines and reference origin"
)

dofile(repo .. "/tests/unit/authority/check-crown-hive.lua")
local V = require("MapView")
local p = Players[1]
p.roomID = 1
p.positionX = 8950
p.positionY = 12400
p.inGame = true
for i = 2, 4 do
    Players[i] = { enabled = false }
end
local choices = V.candidates(map, p)
assert(#choices > 0)
local px, py = V.marker(map, choices[1], p)
assert(px and py)
assert(
    V.marker(map, choices[1], { enabled = true, inGame = false, roomID = 1, positionX = 8950, positionY = 12400 }),
    "Enabled remote player was hidden"
)
assert(
    not V.marker(map, choices[1], { enabled = false, inGame = false, roomID = 1, positionX = 8950, positionY = 12400 }),
    "Disabled player was drawn"
)
local stairs
for id = 1, 127 do
    p.roomID = id
    if #V.candidates(map, p) > 1 then
        stairs = id
        break
    end
end
assert(stairs)
local floors = V.candidates(map, p)
assert(select(3, V.marker(map, floors[1], p)) == true)
p.roomID = 1
V.map = map
V.floor = choices[1]
V.gasRooms = {}
V.target = 1
V.you = 1
-- Evil Resource layers: J's BAR 1F is fitted; concave outlines triangulate fully.
local ERdata = require("MapER")
V.er = {}
for index in ipairs(map.floors) do
    V.er[index] = V.floorLayers(map, index, ERdata[1]["001"][index])
end
assert(V.er[choices[1]] and V.er[choices[1]][1].map == "reoutbreak_jsbar1f", "J's BAR 1F has no Evil Resource layer")
-- The fake graphics cannot decode PNGs; stand in for the layer image (the
-- service check loads the real files).
V.erImages[V.er[choices[1]][1].image] = {}
local tris = V.triangulate({ 0, 0, 4, 0, 4, 1, 1, 1, 1, 4, 0, 4 })
local area = 0
for _, t in ipairs(tris) do
    area = area + math.abs((t[3] - t[1]) * (t[6] - t[2]) - (t[4] - t[2]) * (t[5] - t[1])) / 2
end
assert(#tris == 4 and math.abs(area - 7) < 1e-9, "L-shaped outline did not triangulate to its area")
-- Enemy markers: only enabled, in-game, living slots in a room on the shown
-- floor get a marker; stale, dead, off-floor and corrupt slots never do.
local live = {
    enabled = true,
    inGame = true,
    HP = 100,
    maxHP = 200,
    roomID = 1,
    positionX = 8292,
    positionY = 12715,
    name = "Zombie",
    nameID = 1,
    type = 9,
}
assert(V.enemyMarker(map, choices[1], live), "Live enemy in J's BAR has no marker")
for _, e in ipairs({
    { enabled = true, inGame = false, HP = 100, maxHP = 200, roomID = 1, positionX = 8292, positionY = 12715 },
    { enabled = true, inGame = true, HP = 0, maxHP = 200, roomID = 1, positionX = 8292, positionY = 12715 },
    { enabled = true, inGame = true, HP = 100, maxHP = 200, roomID = 7, positionX = 8292, positionY = 12715 },
    { enabled = true, inGame = true, HP = 100, maxHP = 200, roomID = 1, positionX = 0 / 0, positionY = 12715 },
    { enabled = false, inGame = true, HP = 100, maxHP = 200, roomID = 1, positionX = 8292, positionY = 12715 },
}) do
    assert(not V.enemyMarker(map, choices[1], e), "Stale, dead, off-floor or corrupt enemy drawn")
end
-- Chevron heading follows forward (+0x70,+0x50); missing facing stays upright.
local function near(a, b)
    return math.abs(a - b) < 1e-9
end
assert(
    near(V.heading({ forwardX = 1, forwardY = 0 }), math.pi / 2)
        and near(V.heading({ forwardX = 0, forwardY = 1 }), math.pi)
)
assert(
    near(V.heading({ forwardX = 0, forwardY = -1 }), 0)
        and V.heading({}) == 0
        and V.heading({ forwardX = 0 / 0, forwardY = 1 }) == 0
)
-- Room items: only valid, present items with a position in YOU's room.
local item = { id = 3, type = 309, count = 1, pick = 0, present = 1, mix = 0, positionX = 8950, positionY = 12400 }
assert(V.itemMarker(map, choices[1], 1, item), "Present item in J's BAR has no marker")
for _, it in ipairs({
    { id = -1, type = 0 },
    { id = 3, type = 309, count = 0xFFFF, positionX = 8950, positionY = 12400 },
    { id = 3, type = 309, count = 1, pick = 1, present = 0, positionX = 8950, positionY = 12400 },
    { id = 3, type = 309, count = 1, positionX = 0, positionY = 0 },
}) do
    assert(not V.itemMarker(map, choices[1], 1, it), "Taken or empty item drawn")
end
assert(not V.itemMarker(map, choices[1], 7, item), "Item drawn for a room not on this floor")
Items = { { roomitem = { item, { id = -1, type = 0 } } } }
Enemies =
    { live, { enabled = true, inGame = false, HP = 50, maxHP = 50, roomID = 1, positionX = 9000, positionY = 12500 } }
for i = 3, 12 do
    Enemies[i] = { enabled = false, inGame = false, HP = 0, maxHP = 0 }
end
GameInfo.scenario = "outbreak"
GameInfo.release = "jp"
love.keypressed("f2")
local drawCard = PlayerCard.draw
local cards = 0
PlayerCard.draw = function(self, ...)
    cards = cards + 1
    return drawCard(self, ...)
end
love.keypressed("b")
assert(V.mode == 1)
love.draw()
assert(cards > 0, "Map entry did not restore player cards")
assert(V.enemiesDrawn == 1, "Expected exactly the one live enemy marker")
assert(V.itemsDrawn == 1, "Expected exactly the one room item")
assert(V.erDrawn == 1, "Wide view did not draw the Evil Resource layer")
PlayerCard.draw = drawCard
love.keypressed("n")
assert(V.mode == 2)
love.draw()
assert(V.layout.width == 300 and V.layout.height == 740, "Desktop vertical used the phone layout")
assert(V.viewport.y == 102 and V.viewport.h == 276)
assert(V.layout.cards[1].y == 452 and V.layout.cards[4].y == 668)
local groups = V.floorGroups()
assert(#groups == 6 and groups[3].label == "1F" and #groups[3].indices == 2)
local before = V.floor
local oldOffset = V.tabOffset
V.input("out", 100, 65)
assert(V.tabOffset ~= oldOffset and V.floor == before, "Floor strip must scroll without selecting a different floor")
V.floor = before
V.follow = true
love.isDecky = true
love.draw()
assert(V.layout.width == 390 and V.layout.cards[1].y == 558)
love.isDecky = nil
love.draw()
V.input("down", 20, 160)
V.input("move", 35, 180)
V.input("up", 35, 180)
assert(not V.follow and V.panX == 15 and V.panY == 20)
love.keypressed("f")
assert(V.follow and V.panX == 0)
V.step(1)
assert(not V.follow)
love.keypressed("v")
assert(V.mode == 0)
local gas =
    V.gas({ scenario = "desperate times", fighttime2 = 65535, gasrandom = 0, gasflag = 2, difficulty = "normal" })
assert(gas[7] and gas[12] and not gas[10])
-- Compare every map phase against the legacy scenario strip, rather than
-- restating the implementation's own table as its expected output.
local sourceFile = assert(io.open(repo .. "/sources/main.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
-- The strip is found by its text, so the patterns allow any spacing (the code is formatted by StyLua).
local even = assert(source:find("if%s*%(gr%s*%%%s*2%s*==%s*0%)", 1))
local odd = assert(source:find("if%s*%(gr%s*%%%s*2%s*==%s*1%)", even))
local ending = assert(source:find('elseif%s*%(?s%s*==%s*"below freezing point"', odd))
for parity, block in ipairs({ source:sub(even, odd - 1), source:sub(odd, ending - 1) }) do
    local line = 0
    for expression in block:gmatch("love%.graphics%.printf%((.-),%s*gasroom_x") do
        line = line + 1
        local expected = {}
        for id in expression:gmatch("GetRoomName%(s,%s*(%d+)%)") do
            expected[tonumber(id)] = true
        end
        local actual = V.gas({
            scenario = "desperate times",
            fighttime2 = 65535,
            gasrandom = parity - 1,
            gasflag = 2 ^ math.floor((line - 1) / 2),
            difficulty = line % 2 == 1 and "hard" or "normal",
        })
        for id in pairs(expected) do
            assert(actual[id], "Missing legacy gas room " .. id)
        end
        for id in pairs(actual) do
            assert(expected[id], "Extra map gas room " .. id)
        end
    end
    assert(line == 20)
end
print("PASS all 40 gas phase/difficulty lists match the existing scenario strip")
assert(next(V.gas({ scenario = "desperate times", fighttime2 = 0, gasrandom = 0, gasflag = 2 })) == nil)
-- YOU follows the game's local-slot byte, not the first active record.
Players[2] =
    { enabled = true, inGame = true, roomID = 1, positionX = 8292, positionY = 12715, type = "Alyssa", name = "RITA" }
GameInfo.localSlot = 1
V.update(GameInfo, Players)
assert(V.you == 2, "YOU must follow the game's local slot")
GameInfo.localSlot = nil
V.update(GameInfo, Players)
assert(V.you == 1)
Players[2] = { enabled = false }
GameInfo.release = "us"
GameInfo.currentFile = 1
V.cacheKey = ""
V.update(GameInfo, Players)
assert(V.map and not V.error, "U.S. File 1 should use the matching Japanese map data")
GameInfo.currentFile = 2
V.cacheKey = ""
V.update(GameInfo, Players)
assert(V.map == nil and V.error:find("U.S."))
print(
    "PASS actual B/N/V map drawing; enemy markers only for live in-game slots; ambiguous floors use room-only markers; pan/manual floor/follow; gas selection; U.S. File 1 maps on, U.S. File 2 off; chevron heading; YOU from the local slot; room items in YOU's room only; Evil Resource layers and outline tints"
)
-- Cards-beside-map session line: local character // scenario // difficulty // options.
assert(
    V.sessionText({ scenario = "end of the road", difficulty = "very hard" }, { enabled = true, type = "Alyssa" })
        == "ALYSSA // 突破 end of the road // VERY HARD"
)
assert(
    V.sessionText(
        { scenario = "showdown 3", difficulty = "normal", nightmare = true, infinity = true },
        { enabled = true, name = "Kevin" }
    ) == "KEVIN // 対峙3 showdown 3 // NORMAL // NIGHTMARE // INFINITY"
)
assert(
    V.sessionText({ scenario = "outbreak", difficulty = "easy" }, { enabled = false, name = "Kevin" })
        == "発生 outbreak // EASY"
)
print("PASS cards-beside-map session line: character, Japanese scenario title, difficulty and optional room options")

-- Item/visit history uses fresh snapshots even with the main widgets hidden.
local native = package.loaded.luaoutbreaktracker
local originalPlayer, originalItem = native.getPlayer, native.getItem
local pc, ic = 0, 0
native.getPlayer = function()
    pc = pc + 1
    return { enabled = false }
end
native.getItem = function()
    ic = ic + 1
    return { roomitem = {} }
end
love.update(0.2)
assert(pc == 4 and ic == 1, "Hidden widgets left session history on stale snapshots")
native.getPlayer, native.getItem = originalPlayer, originalItem
-- Following a teammate upstairs must not stamp YOUR downstairs items upstairs.
local g = { currentFile = 2, release = "jp", scenario = "desperate times", frames = 300, localSlot = 0 }
local ps = {
    { enabled = true, inGame = true, roomID = 1, height = 0, heightAvailable = true },
    { enabled = true, inGame = false, roomID = 1, height = 400, heightAvailable = true },
}
local its = { { roomitem = { { id = 7, type = 0, count = 1, positionX = 100, positionY = 100 } } } }
V.update(g, ps, 0.2, its)
V.target = 2
V.follow = true
V.zoom = 2.75
V.update(g, ps, 0.2, its)
assert(V.floor == 3 and V.zoom == 2.75, "Follow floor transition reset the zoom")
assert(require("MapSession").items[7].floor == 2, "Following a partner changed your item's remembered floor")
print("PASS hidden-widget snapshot freshness, local item floor and zoom across followed floor changes")
-- Native callback integration: the launcher opens the real Lua menu; its HOME
-- hit dispatches through love.keypressed and returns to the main tracker.
love.isDecky = false
local Menu = require("TrackerMenu")
V.mode = 2
Menu.open = false
-- The CONTROLS button stays hidden until the pointer is over the window, and a
-- click on the hidden button reaches the map instead of opening the menu.
Menu.alpha, Menu.hover, Menu.idle = 0, false, 0
Menu.draw(300, 740, true)
love.mousepressed(Menu.launcher.x + 4, Menu.launcher.y + 4, 1)
love.mousereleased(Menu.launcher.x + 4, Menu.launcher.y + 4, 1)
assert(not Menu.open, "a hidden CONTROLS button opened the menu")
love.mousefocus(true)
love.mousemoved(Menu.launcher.x + 4, Menu.launcher.y + 4)
Menu.update(0.1)
assert(Menu.alpha > 0.4 and Menu.alpha < 0.6, "CONTROLS should be half faded in after 0.1 s")
Menu.update(0.2)
assert(Menu.alpha == 1, "CONTROLS did not finish fading in")
Menu.update(2.6)
assert(Menu.alpha == 1, "CONTROLS faded before 3 s without pointer activity")
Menu.update(0.3)
assert(Menu.alpha > 0 and Menu.alpha < 1, "CONTROLS did not start fading after 3 s idle")
Menu.update(0.4)
assert(Menu.alpha == 0, "CONTROLS did not finish fading out when idle")
love.mousemoved(10, 10)
Menu.update(0.25)
assert(Menu.alpha == 1, "pointer motion did not bring CONTROLS back")
love.mousefocus(false)
Menu.update(0.6)
assert(Menu.alpha == 0, "CONTROLS stayed after the pointer left the window")
print("PASS CONTROLS fades in under the pointer and out on leaving or 3 s idle")
love.mousefocus(true)
love.mousemoved(Menu.launcher.x + 4, Menu.launcher.y + 4)
Menu.update(0.25)
love.mousepressed(Menu.launcher.x + 4, Menu.launcher.y + 4, 1)
assert(Menu.open)
love.mousefocus(false)
Menu.update(1)
assert(Menu.alpha == 1, "CONTROLS faded while the menu was open")
Menu.draw(300, 740, true)
local home
for _, h in ipairs(Menu.hits) do
    if h.key == "home" then
        home = h
    end
end
assert(home, "Native menu has no main-tracker hit")
love.mousepressed(home.x + home.w / 2, home.y + home.h / 2, 1)
assert(V.mode == 0 and not Menu.open, "Native main-tracker click did not return home")
print("PASS native clickable controls launcher and main-tracker return callbacks")
assert(
    V.isHazard({ nameID = 54 })
        and V.isHazard({ nameID = 58 })
        and not V.isHazard({ nameID = 41 })
        and not V.isHazard(nil)
)
print("PASS mines (54) and gas tanks (58) are hazards; Tyrant is not")
-- Arena boxes and floor-map rooms share one tint (user request 2026-11-21: the
-- visited green must match the normal scenarios).
local P = {
    { enabled = true, inGame = true, roomID = 3 },
    { enabled = true, inGame = true, roomID = 4 },
    {
        enabled = false,
    },
    {
        enabled = false,
    },
}
V.you = 1
local tint = V.roomTint(P, 3, true)
assert(tint[1] == 1 and tint[2] == 0 and tint[4] == 0.25, "YOU's room is not red")
tint = V.roomTint(P, 4, false)
assert(math.abs(tint[1] - 115 / 255) < 1e-9 and tint[4] == 0.25, "occupied room is not light blue")
tint = V.roomTint(P, 5, true)
assert(tint[1] == 0.4 and tint[2] == 1 and tint[3] == 0.55 and tint[4] == 0.22, "visited green differs from floor maps")
assert(V.roomTint(P, 6, false) == nil, "unvisited room is not black")
-- A press on a map hit (arena room box) taps on release, pans when dragged, and
-- controls drawn over the map win.
local tapped = 0
V.mode = 2
V.viewport = { x = 0, y = 0, w = 200, h = 200 }
V.tabStrip = nil
V.panX, V.panY = 0, 0
V.hits = {
    {
        x = 50,
        y = 50,
        w = 40,
        h = 40,
        map = true,
        action = function()
            tapped = tapped + 1
        end,
    },
}
V.input("down", 60, 60)
assert(tapped == 0, "box fired on press")
V.input("up", 61, 60)
assert(tapped == 1, "box tap did not fire on release")
V.input("down", 60, 60)
V.input("move", 90, 60)
V.input("up", 90, 60)
assert(tapped == 1 and V.panX == 30, "drag from a box did not pan")
V.hits[#V.hits + 1] = {
    x = 55,
    y = 55,
    w = 10,
    h = 10,
    action = function()
        tapped = tapped + 10
    end,
}
V.input("down", 58, 58)
V.input("up", 58, 58)
assert(tapped == 11, "control over the map lost to a box")
print("PASS shared room tint (visited green as on floor maps); arena box taps on release, drags pan, controls win")
