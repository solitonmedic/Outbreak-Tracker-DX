-- This check wraps tracker globals through _G to watch them, on purpose.
--# selene: allow(global_usage)
-- Purpose: reusable check of the SP item set letter in the actual shared love.draw.
-- Location/runtime: tests/unit/sp/check-sp-set.lua; Homebrew LuaJIT.
-- Inputs: repo root argv[1]; the authority check's synthetic tracker/graphics fixtures.
-- Outputs: PASS lines only; no files. Safety: no native module, PINE, recordings or workbook.
-- Run from repo-merged: luajit tests/unit/sp/check-sp-set.lua .
-- Check: File 1 draws "B" (selector bit 1 clear) or "A" (bit 1 set) in DefaultFont at
-- (6, 145*players+142) with the item set digits at 145*players+105, restores the font, and
-- draws no letter for File 2, an unavailable or non-numeric selector, the wide layout or hidden items.
local repo = assert(arg[1])
dofile(repo .. "/tests/unit/authority/check-crown-hive.lua")
-- Item contents are outside this check; permit switching to the full item-list views.
ItemCard2.draw = function() end
ItemCard3.draw = function() end
local game = GameInfo
local prints, printfs, fonts = {}, {}, {}
local current
love.graphics.print = function(text, x, y)
    prints[#prints + 1] = { text, x, y, current }
end
love.graphics.printf = function(text, x, y)
    printfs[#printfs + 1] = { text, x, y }
end
love.graphics.setFont = function(font)
    current = font
    fonts[#fonts + 1] = font
end
love.graphics.getFont = function()
    return current
end
-- Distinct font objects so the letter's font and the restore can be checked.
for _, name in ipairs({ "DefaultFont", "TimeFont" }) do
    local base = _G[name]
    _G[name] = setmetatable({ name = name }, { __index = base })
end
local function draw()
    prints, printfs = {}, {}
    love.draw()
end
local function letter()
    local found
    for _, p in ipairs(prints) do
        if p[1] == "A" or p[1] == "B" then
            assert(found == nil, "letter drawn twice")
            found = p
        end
    end
    return found
end
local function itemSetY()
    for _, p in ipairs(printfs) do
        if type(p[1]) == "string" and p[1]:find("^%d+\n%d+$") then
            return p[3]
        end
    end
end
game.scenario = "outbreak"
game.frames = 300
game.hivecodesavailable = false
game.currentFile = 1
game.release = "us"
game.playernum = 4
game.spsetavailable = true
for selector, expected in pairs({ [0] = "B", [1] = "B", [2] = "A", [3] = "A", [6] = "A", [255] = "A", [252] = "B" }) do
    game.spsetselector = selector
    draw()
    local l = assert(letter(), "no letter for selector " .. selector)
    assert(l[1] == expected and l[2] == 6 and l[3] == 722 and l[4] == DefaultFont, "selector " .. selector)
    assert(itemSetY() == 685)
    assert(current == TimeFont, "font not restored")
end
game.playernum = 2
game.spsetselector = 2
draw()
assert(letter()[3] == 2 * 145 + 142 and itemSetY() == 2 * 145 + 105)
game.playernum = 4
game.release = "jp"
draw()
assert(letter()[1] == "A")
print("PASS SP set letter: A/B from selector bit 1, DefaultFont at (6, 145p+142), item set at 145p+105, font restored")
game.spsetavailable = false
draw()
assert(letter() == nil and itemSetY() == 685)
game.spsetavailable = 0
draw()
assert(letter() == nil)
game.spsetavailable = true
game.spsetselector = "2"
draw()
assert(letter() == nil)
game.spsetselector = 2
game.currentFile = 2
game.release = ""
game.spsetavailable = false
game.scenario = "wild things"
draw()
assert(letter() == nil and itemSetY() == 685)
game.currentFile = 1
game.release = "us"
game.scenario = "outbreak"
game.spsetavailable = true
love.keypressed("f2")
draw()
assert(letter() == nil)
love.keypressed("f2")
love.keypressed("f2")
draw()
assert(letter())
love.keypressed("h")
draw()
assert(letter() == nil)
love.keypressed("v")
draw()
assert(letter())
game.frames = 0
draw()
assert(letter() == nil)
game.frames = 300
game.scenario = ""
draw()
assert(letter() == nil)
print(
    "PASS SP set letter hidden: File 2, unavailable or non-numeric selector, item lists, wide layout, paused, no scenario"
)
