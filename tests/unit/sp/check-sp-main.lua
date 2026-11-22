-- Purpose: reusable integration check of the SP hook in actual tracker draw/key handlers.
-- Location/runtime: tests/unit/sp/check-sp-main.lua; LuaJIT.
-- Inputs: repo root argv[1], existing synthetic authority harness and actual shared UI.
-- Outputs: PASS lines; no files. Safety: fake reader only; no PINE/recordings/workbook.
-- Run from repo-merged: luajit tests/unit/sp/check-sp-main.lua .
-- Check: hook receives timer position/font; hidden in wide, title, full-list and paused states.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local ui = require("SPTracking")
local calls = {}
ui.draw = function(state, x, y, font)
    calls[#calls + 1] = { state, x, y, font }
end
dofile(repo .. "/tests/unit/authority/check-crown-hive.lua")
-- Item contents are outside this hook check; permit switching full-list views.
ItemCard2.draw = function() end
ItemCard3.draw = function() end
local game = GameInfo
game.spTracking = { available = true, collected = 4, limit = 8, radarState = "near" }
game.playernum = 1
game.scenario = "the hive"
game.frames = 300
game.hivecodesavailable = true
local function draw(expected)
    calls = {}
    love.draw()
    assert(#calls == expected)
end
draw(1)
assert(calls[1][1] == game.spTracking and calls[1][2] == 0 and calls[1][3] == 145 and calls[1][4] == DefaultFont)
game.playernum = 4
draw(1)
assert(calls[1][3] == 580)
love.keypressed("h")
draw(0)
love.keypressed("v")
draw(1)
love.keypressed("f2")
draw(0)
love.keypressed("f2")
draw(0)
love.keypressed("f2")
draw(1)
game.scenario = ""
draw(0)
game.scenario = "the hive"
game.frames = 0
draw(0)
game.frames = 300
game.currentFile = 255
draw(0)
print("PASS actual SP hook: state/font/anchor, wide, item lists, title, paused and unavailable-release views")
