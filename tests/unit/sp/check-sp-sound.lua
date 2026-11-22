-- Purpose: reusable check of the SP found sound in the actual shared love.draw.
-- Location/runtime: tests/unit/sp/check-sp-sound.lua; Homebrew LuaJIT.
-- Inputs: repo root argv[1]; the authority check's synthetic tracker/graphics fixtures;
-- synthetic SP states shaped like the Decky probe's (available, room, radarState).
-- Outputs: PASS lines only; no files. Safety: no native module, PINE, recordings or workbook.
-- Run from repo-merged: luajit tests/unit/sp/check-sp-sound.lua .
-- Check: the sound plays once when the radar first shows an SP item ("direction" or
-- "near") after a room change, never again in that room (including after unavailable
-- samples), again after any room change (also back to an earlier room), and after
-- leaving gameplay; never for idle/complete/invalid/missing state; in every view.
-- Also checks default-on M muting, no delayed alert on re-enable, radar visibility,
-- preference retention across game-state changes and localized help status.
local repo = assert(arg[1])
dofile(repo .. "/tests/unit/authority/check-crown-hive.lua")
ItemCard2.draw = function() end
ItemCard3.draw = function() end
local game = GameInfo
local plays = 0
SPFoundSound = {
    play = function()
        plays = plays + 1
    end,
}
local function sp(room, radarState, extra)
    local state = { available = true, collected = 3, limit = 8, room = room, radarState = radarState, bearing = 0.5 }
    for k, v in pairs(extra or {}) do
        state[k] = v
    end
    return state
end
-- Draw each state in turn and return how many times the sound played.
local function run(states)
    local before = plays
    for _, state in ipairs(states) do
        game.spTracking = state
        love.draw()
    end
    return plays - before
end
game.scenario = "outbreak"
game.frames = 300
game.hivecodesavailable = false
game.currentFile = 1
game.release = "jp"
game.playernum = 4

assert(run({ sp(10, "idle"), sp(10, "idle") }) == 0, "idle room played")
assert(run({ sp(10, "direction") }) == 1, "first sighting did not play")
assert(run({
    sp(10, "direction"),
    sp(10, "near"),
    sp(10, "direction", { glow = true }),
    sp(10, "idle"),
    sp(10, "direction"),
}) == 0, "replayed in the same room")
assert(
    run({ { available = false, limit = 8, reason = "SP context changed during sample" }, sp(10, "direction") }) == 0,
    "unavailable sample replayed the sound"
)
print(
    "PASS SP sound plays once per room: idle silent, first direction plays, no replay in the room or after a dropped sample"
)

assert(run({ sp(11, "idle"), sp(11, "near") }) == 1, "new room near did not play")
assert(run({ sp(10, "direction") }) == 1, "returning to an earlier room did not play")
assert(run({ sp(12, "complete", { collected = 8 }), sp(12, "complete", { collected = 8 }) }) == 0, "complete played")
assert(run({ sp(13, "idle"), sp(14, "idle"), sp(15, "direction") }) == 1, "later room did not play")
print("PASS SP sound plays again after each room change, including back to an earlier room; complete is silent")

for _, bad in ipairs({
    sp(nil, "direction"),
    sp(-1, "direction"),
    sp(1.5, "direction"),
    sp("16", "direction"),
    sp(16, "direction", { available = 0 }),
    false,
    "state",
}) do
    assert(run({ bad }) == 0, "invalid state played")
end
local before = plays
game.spTracking = nil
love.draw()
assert(plays == before, "missing state played")
print("PASS SP sound ignores invalid, unavailable and missing state (the release reader supplies none)")

game.scenario = ""
run({ sp(15, "direction") })
game.scenario = "outbreak"
assert(run({ sp(15, "direction") }) == 1, "leaving gameplay did not reset")
game.frames = 0
run({ sp(15, "direction") })
game.frames = 300
assert(run({ sp(15, "direction") }) == 1, "frame reset did not reset")
love.keypressed("h")
assert(run({ sp(16, "direction") }) == 1, "wide layout silent")
love.keypressed("v")
love.keypressed("f2")
assert(run({ sp(17, "near") }) == 1, "item list view silent")
print("PASS SP sound resets when gameplay ends and plays in every layout and view")

assert(game.spsoundenabled == true, "sound did not default on")
love.keypressed("f2")
love.keypressed("f2") -- return to the normal radar view
local ui = require("SPTracking")
local originalDraw = ui.draw
local radarDraws = 0
ui.draw = function(...)
    radarDraws = radarDraws + 1
    return originalDraw(...)
end
love.keypressed("m")
assert(run({ sp(20, "direction"), sp(20, "near"), sp(21, "direction") }) == 0, "muted room played")
assert(game.spsoundenabled == false, "muted state not exported")
assert(radarDraws == 3, "muting hid the radar")
love.keypressed("m")
assert(run({ sp(21, "direction") }) == 0, "enabling replayed a muted sighting")
assert(game.spsoundenabled == true, "enabled state not exported")
assert(run({ sp(22, "direction") }) == 1, "new room silent after enabling")
love.keypressed("m")
assert(run({ sp(23, "idle") }) == 0)
love.keypressed("m")
assert(run({ sp(23, "near") }) == 1, "enabling before first sighting stayed silent")
print("PASS M defaults on, mutes across rooms without hiding radar, and resumes without replaying muted sightings")

local labels = {}
local originalPrintf = love.graphics.printf
love.graphics.printf = function(text, x, y, ...)
    labels[text] = { x, y }
    return originalPrintf(text, x, y, ...)
end
love.keypressed("f1")
love.draw()
assert(labels["M: SP radar sound: On"][2] == 46, "missing enabled help status")
love.keypressed("m")
labels = {}
love.draw()
assert(labels["M: SP radar sound: Off"][2] == 46, "missing muted help status")
game.scenario = ""
love.draw()
assert(game.spsoundenabled == false, "leaving game reset mute")
game.currentFile = 255
labels = {}
love.draw()
assert(labels["M: SP radar sound: Off"], "missing waiting-screen status")
love.keypressed("m")
labels = {}
love.draw()
assert(game.spsoundenabled == true and labels["M: SP radar sound: On"], "cannot toggle while waiting")
LanguageSwitch = 1
labels = {}
love.draw()
assert(labels["M: Звук SP-радара: Вкл."], "missing Russian enabled label")
love.keypressed("m")
labels = {}
love.draw()
assert(labels["M: Звук SP-радара: Выкл."], "missing Russian muted label")
love.graphics.printf = originalPrintf
print("PASS sound preference survives game changes, works before gameplay, and help reports On/Off in both languages")
