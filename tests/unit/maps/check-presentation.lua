-- Purpose: reusable pure-Lua checks of session history and shared player effects.
-- Location/runtime: tests/unit/maps/check-presentation.lua; LuaJIT.
-- Inputs: repository root arg[1], synthetic game/player/item snapshots.
-- Outputs: PASS lines. Safety: no PINE, recordings, workbook or file writes.
-- Run from repo-merged: luajit tests/unit/maps/check-presentation.lua .
-- Check: local-only visits, remembered/taken items, run reset, health states.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local S = require("MapSession")
local E = require("PlayerEffects")
local game = { currentFile = 2, release = "jp", scenario = "desperate times", frames = 300 }
local players = { { enabled = true, inGame = true, roomID = 1 }, { enabled = true, inGame = false, roomID = 14 } }
local item = { id = 1, type = 0, count = 15, positionX = 100, positionY = 200 }
S.update(game, players, 1, { { roomitem = { item } } }, 2)
assert(S.visited[1] and not S.visited[14], "Remote rooms became visited")
assert(S.items[1] and S.items[1].type == 0, "Handgun item type zero was discarded")
players[1].roomID = 2
game.frames = 600
S.update(game, players, 1, { { roomitem = {} } }, 2)
assert(S.items[1] and S.visited[1] and S.visited[2], "Leaving a room forgot its item")
players[1].roomID = 1
game.frames = 900
S.update(game, players, 1, { { roomitem = {} } }, 2)
assert(not S.items[1], "Known pickup stayed on the map")
game.mapItems =
    { { id = 44, type = 10100, count = 1, pick = 0, present = 0, roomID = 14, positionX = 400, positionY = 500 } }
S.update(game, players, 1, nil, 2)
assert(S.items[44], "Unvisited scenario item was hidden")
game.mapItems[1].pick = 1
S.update(game, players, 1, nil, 2)
assert(not S.items[44], "Taken scenario item stayed visible")
game.mapItems = nil
S.update(game, players, 1, { { roomitem = { item } } }, 2)
game.frames = 30
S.update(game, players, 1, nil, 2)
assert(not S.items[1] and not S.visited[2], "New run kept prior history")
assert(E.health({ status = "Down+Gas", HP = 10, maxHP = 100 }) == "down")
assert(E.health({ status = "Dead", HP = 0, maxHP = 100 }) == "dead")
assert(E.health({ status = "OK", HP = 24, maxHP = 100 }) == "danger")
assert(E.health({ status = "OK", HP = 25, maxHP = 100 }) == "normal")
assert(E.markerColor({ adlib = true }, { 1, 0, 0, 1 }, 0)[2] == 1)
local vp = { enabled = true, voiceId = 12, voiceTicks = 15 }
E.update(game, { vp }, 0)
assert(not E.adlib(vp, 0), "Initial voice snapshot pulsed")
vp.voiceTicks = 8
E.update(game, { vp }, 0.2)
assert(not E.adlib(vp, 0.2))
vp.voiceId = 13
E.update(game, { vp }, 0.4)
assert(E.adlib(vp, 0.4), "New voice did not pulse")
assert(not E.adlib(vp, 3.5), "Voice pulse did not expire")
vp.voiceTicks = 20
E.update(game, { vp }, 4)
assert(E.adlib(vp, 4), "Repeated voice timer renewal did not pulse")
local Data = require("MapData")
local dt = assert(Data.load(2, "desperate times", function(path)
    local f = assert(io.open(path, "rb"))
    local b = f:read("*a")
    f:close()
    return b
end))
love = {}
local V = require("MapView")
assert(
    V.isBoss({ nameID = 64 }) and V.isBoss({ nameID = 9 }) and V.isBoss({ nameID = 46 }),
    "Boss identity coverage is incomplete"
)
assert(not V.isBoss({ nameID = 1 }) and not V.isBoss({ nameID = 18 }), "Ordinary zombie/flea became a boss")
local mainHall = { enabled = true, roomID = 1, heightAvailable = true, height = 399 }
assert(V.candidates(dt, mainHall)[1] == 2, "Main Hall switched before its 400-unit threshold")
mainHall.height = 400
assert(V.candidates(dt, mainHall)[1] == 3, "Main Hall did not reach 2F")
local gate
for index, f in ipairs(dt.floors) do
    for _, p in ipairs(f.places) do
        local r = dt.rooms[p.record]
        if r.id == 27 then
            local x = f.refX + (p.x + r.w + 10) * 100 / f.ppu
            local y = f.refZ + (p.y + r.h / 2) * 100 / f.ppu
            local mx, my, fallback = V.marker(dt, index, { enabled = true, roomID = 27, positionX = x, positionY = y })
            assert(fallback == false, "Front Gate still falls back outside its map outline")
            gate = true
            -- Kept inside the drawn piece, clear of its border, and stable.
            assert(
                mx >= p.x and mx <= p.x + r.w and my >= p.y and my <= p.y + r.h,
                "Front Gate marker drawn outside its room"
            )
            assert(mx <= p.x + r.w - 1, "Front Gate marker sits on the border")
            local ix, iy = V.itemMarker(dt, index, 27, { id = 5, type = 1, count = 1, positionX = x, positionY = y })
            assert(
                ix and ix >= p.x and ix <= p.x + r.w and iy >= p.y and iy <= p.y + r.h,
                "Front Gate item drawn outside its room"
            )
            local sx, sy = V.clampToRoom(dt, index, 27, mx, my)
            assert(sx == mx and sy == my, "Clamping is not stable")
        end
    end
end
assert(gate)
print("PASS local-only room visits, remembered/taken items, new-run reset and shared health/ad-lib presentation")
print(
    "PASS DT Main Hall exact floor threshold; Front Gate players and items kept inside the drawn room, clear of the border"
)

-- Existing provider direction/glow is authoritative; native room-only data can
-- derive YOU-relative direction without introducing new memory reads.
local SP = require("SPTracking")
local state =
    { available = true, limit = 8, collected = 0, room = 1, roomItems = { { id = 0, enabled = true, x = 100, y = 0 } } }
local you = { enabled = true, inGame = true, roomID = 1, positionX = 0, positionY = 0, forwardX = 0, forwardY = -1 }
local dir = SP.forMap(state, you)
assert(dir.radarState == "direction" and math.abs(dir.bearing - math.pi / 2) < 1e-9)
you.forwardX = 1
you.forwardY = 0
assert(math.abs(SP.forMap(state, you).bearing) < 1e-9, "Turning toward SP did not centre radar")
assert(state.bearing == nil, "Map direction mutated provider data")
state.radarState = "direction"
state.bearing = -1
state.glow = true
assert(SP.forMap(state, you) == state, "Map replaced guarded provider bearing/glow")
state.radarState = nil
you.forwardX = 0 / 0
assert(SP.forMap(state, you) == state, "Invalid facing produced a direction")
local Layout = require("MapPresentationLayout")
assert(
    Layout.select("phone", { scenario = "outbreak", spTracking = { available = false } }, "").viewport.h
        == Layout.select("phone", { scenario = "outbreak", spTracking = { available = true } }, "").viewport.h,
    "SP dropout resized the map"
)
local rooms = require("roomnames")
assert(
    rooms.outbreak[7] == "Drawing Room" and rooms["decisions,decisions"][88] == "Drawing Room",
    "Room name correction missing"
)
print("PASS local-facing SP direction, guarded glow preservation, stable radar row and Drawing Room names")

local zoo = assert(Data.load(2, "wild things", function(path)
    local f = assert(io.open(path, "rb"))
    local b = f:read("*a")
    f:close()
    return b
end))
V.map = zoo
local groups = V.floorGroups()
assert(#groups == 2 and groups[1].label == "GF" and groups[2].label == "Zoo")
assert(#groups[2].indices == 2, "Zoo height bands lost their shared tab")
print("PASS Wild Things GF/Zoo abbreviations and shared Zoo height bands")

local hidden = V.hiddenPlayerLabels({ [1] = { x = 0, y = 0 }, [2] = { x = 20, y = 20 }, [3] = { x = 100, y = 0 } })
assert(hidden[1] and hidden[2] and not hidden[3], "Close-player map labels were not suppressed")
assert(V.hiddenPlayerLabels({ [1] = { x = 0, y = 0 }, [2] = { x = 48, y = 0 } }, hidden)[1], "Label hysteresis missing")
assert(
    not V.hiddenPlayerLabels({ [1] = { x = 0, y = 0 }, [2] = { x = 60, y = 0 } }, hidden)[1],
    "Separated labels did not return"
)
assert(not V.hiddenPlayerLabels({ [1] = { x = 0, y = 0 } }, hidden)[1], "Removed teammate kept a label hidden")
print("PASS nearby map labels hide, remain stable at boundary and restore after separation")

-- Danger/Down flashing: Down is faster; worst state wins; the Decky bridge gets
-- a pulse command instead of a pre-computed alpha, and it is always closed.
local SPT = require("SPTracking")
assert(E.rates.down > E.rates.danger, "Down must flash faster than Danger")
assert(E.worst(nil, "danger") == "danger" and E.worst("danger", "down") == "down" and E.worst(nil, "normal") == nil)
assert(math.abs(E.wave(0, 1)) < 1e-9 and math.abs(E.wave(0.5, 1) - 1) < 1e-9, "Pulse wave must ease 0..1")
local calls = {}
local savedLove = love
love = {
    graphics = {
        setColor = function(...)
            calls[#calls + 1] = { "color", ... }
        end,
        setPulse = function(...)
            calls[#calls + 1] = { "pulse", ... }
        end,
        rectangle = function() end,
        setLineWidth = function() end,
    },
}
E.background({ status = "Down", HP = 0, maxHP = 100 }, 0, 0, 10, 10, 0)
assert(calls[1][1] == "pulse" and calls[1][2] == E.rates.down, "Bridge did not receive the Down pulse rate")
assert(
    calls[#calls][1] == "color" and calls[#calls - 1][1] == "pulse" and calls[#calls - 1][2] == nil,
    "Pulse was not closed"
)
love.graphics.setPulse = nil
calls = {}
E.background({ HP = 10, maxHP = 100 }, 0, 0, 10, 10, 0.25)
local a = calls[1][5]
assert(a > 0 and a < 0.36, "Desktop Danger alpha not modulated")
love = savedLove
print("PASS smooth Danger/Down pulse: faster Down, worst state, Decky pulse command closed, desktop alpha eased")
-- No SP in Elimination or Showdown.
local spState = { available = true }
assert(
    SPT.state({ scenario = "elimination 2", spTracking = spState }) == nil
        and SPT.state({ scenario = "showdown 1", spTracking = spState }) == nil
)
assert(SPT.state({ scenario = "flashback", spTracking = spState }) == spState)
print("PASS SP state hidden in Elimination and Showdown, kept elsewhere")
-- Elimination countdown replaces the game clock; red in the last 3:00.
if not Time2string then
    require("helpers")
end
local text, warn = E.clockText({ scenario = "elimination 2", eliminationtime = 53963, frames = 37 })
assert(text == "00:29:58.7" and not warn, text)
text, warn = E.clockText({ scenario = "elimination 1", eliminationtime = 4189, frames = 49811 })
assert(warn and text == "00:02:19.6", text)
text, warn = E.clockText({ scenario = "elimination 3", eliminationtime = 0, frames = 54001 })
assert(warn and text == "00:00:00.0", text)
text, warn = E.clockText({ scenario = "flashback", eliminationtime = 0, frames = 900 })
assert(text == "00:00:30.0" and not warn, text)
text, warn = E.clockText({ scenario = "showdown 2", eliminationtime = 500, frames = 900 })
assert(text == "00:00:30.0" and not warn, "Showdown must keep the game clock")
print("PASS Elimination countdown (0x491230) replaces the clock and warns under 3:00; other scenarios keep the clock")
