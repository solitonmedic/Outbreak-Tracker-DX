-- This harness replaces tracker globals (the asset loader, the atlas selector and
-- the fonts) with fakes, which selene would otherwise report.
--# selene: allow(incorrect_standard_library_use, global_usage)
-- Purpose: reusable integration check of the primitive UNLOCK bar drawn by the
-- actual shared love.draw / PlayerCard:draw over Alyssa's pick-tool icon.
-- Location/runtime: tests/unit/lock/check-unlock-bar.lua; Homebrew LuaJIT.
-- Inputs: repository root argv[1], shared Lua files; synthetic tracker/graphics.
-- Outputs: PASS lines only; no files, native module, live PINE or recordings.
-- Safety: all game data/graphics are in-memory fixtures; no capture/game writes.
-- Run from repo-merged: luajit tests/unit/lock/check-unlock-bar.lua .
-- Check: the bar is drawn only inside a pick-hint spot (File 1 and File 2), only while the
-- reader returns a counter of 1..200, with fill = (200 - counter) / 200; the
-- reader gets the hint spot and the door/container flag; nothing is drawn for
-- other characters, outside the spot or a reader without getLockCounter;
-- labelled spots pass true/false and unlabelled ones nil; colour and font are restored.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local noop = function() end
local texts, rects, colors, lockCalls = {}, {}, {}, {}
local counter = nil
local font = {
    getWidth = function(_, s)
        return #tostring(s) * 8
    end,
    getHeight = function()
        return 18
    end,
    getWrap = function(_, s)
        return 10, { tostring(s) }
    end,
}
local currentFont = font
local atlas = {
    tex = {},
    quads = setmetatable({}, {
        __index = function()
            return {
                getViewport = function()
                    return 0, 0, 100, 100
                end,
            }
        end,
    }),
    draw = noop,
    addSB = noop,
}
love = {
    graphics = setmetatable({
        printf = function(s)
            texts[#texts + 1] = s
        end,
        print = noop,
        rectangle = function(mode, x, y, w, h)
            rects[#rects + 1] = { mode, x, y, w, h }
        end,
        setColor = function(r, g, b, a)
            colors[#colors + 1] = { r, g, b, a }
        end,
        getColor = function()
            return 0, 1, 0, 1
        end,
        setFont = function(f)
            currentFont = f
        end,
        getFont = function()
            return currentFont
        end,
        newSpriteBatch = function()
            return { setColor = noop, add = noop }
        end,
    }, {
        __index = function()
            return noop
        end,
    }),
    window = {
        getMode = function()
            return 300, 740, {}
        end,
        getPosition = function()
            return 0, 0, 1
        end,
        setMode = noop,
        setPosition = noop,
    },
    audio = {
        newSource = function()
            return { play = noop }
        end,
    },
    event = { quit = noop },
}
local game = setmetatable({
    currentFile = 1,
    release = "jp",
    playernum = 1,
    frames = 300,
    scenario = "outbreak",
    difficulty = "normal",
    hostscenario = "outbreak",
    hostdifficulty = "normal",
}, {
    __index = function()
        return 0
    end,
})
local tracker = {
    init = function()
        return true
    end,
    update = noop,
    updateRoom = noop,
    updateLobby = noop,
    getGameInfo = function()
        return game
    end,
    getSlotPlayer = function()
        return { enabled = false }
    end,
    getPlayer = function()
        return { enabled = false }
    end,
    getEnemy = function()
        return { enabled = false }
    end,
    getItem = function()
        return {}
    end,
    getDoor = function()
        return {}
    end,
    getRoomMaster = function()
        return { enabled = false, roommaster = 0 }
    end,
    getLockCounter = function(id, x, y, container)
        lockCalls[#lockCalls + 1] = { id, x, y, container }
        return counter
    end,
}
package.preload.luaoutbreaktracker = function()
    return tracker
end
dofile(repo .. "/sources/main.lua")
LoadAssets = function()
    UIAtlas, ItemIcons, ItemIcons2 = atlas, atlas, atlas
    for _, name in ipairs({
        "DefaultFont",
        "SmallFont",
        "VerySmallFont",
        "MiniFont",
        "TimeFont",
        "VirusFont",
        "ItemCountFont",
    }) do
        _G[name] = font
    end
end
SelectUIAtlas = noop
love.load({})
love.update(0.2)
Label.draw = noop

local alyssa = setmetatable({
    enabled = true,
    inGame = true,
    roomID = 1,
    name = "Alyssa",
    type = "Alyssa",
    status = "Fine",
    HP = 100,
    maxHP = 100,
    positionX = 9222.1,
    positionY = 12619.3,
    inventory = {},
    specialInventory = {},
    specialItem = { id = -1, type = 0 },
}, {
    __index = function()
        return 0
    end,
})
for i = 1, 4 do
    alyssa.inventory[i] = { id = -1 }
    alyssa.specialInventory[i] = { id = -1 }
end
Players[1] = alyssa
local card = PlayerCards[1]

local function has(list, text)
    for _, v in ipairs(list) do
        if v == text then
            return true
        end
    end
    return false
end
local function draw(value)
    counter = value
    texts, rects, colors, lockCalls = {}, {}, {}, {}
    card:draw(0, 0)
end
local function barFill()
    -- background, track, fill: the fill is the last rectangle the bar draws
    for i = #rects, 1, -1 do
        if rects[i][2] == 120 and rects[i][3] == 131 then
            return rects[i][4]
        end
    end
end

for _, v in ipairs({ false, 0, -1, -4, 201 }) do
    draw(v or nil)
    assert(not has(texts, "UNLOCK"), "hidden for " .. tostring(v))
end
assert(
    #lockCalls == 1
        and lockCalls[1][1] == 1
        and lockCalls[1][2] == 9222.11
        and lockCalls[1][3] == 12619.26
        and lockCalls[1][4] == false
)
draw(200)
assert(has(texts, "UNLOCK") and math.abs(barFill() - 0) < 1e-9)
draw(77)
assert(has(texts, "UNLOCK") and math.abs(barFill() - 40 * (123 / 200)) < 1e-9)
draw(1)
assert(math.abs(barFill() - 40 * (199 / 200)) < 1e-9)
local after
for i, c in ipairs(colors) do
    if c[1] == 1 and c[2] == 0.8 and c[3] == 0.1 then
        after = colors[i + 1]
    end
end
assert(after and after[1] == 0 and after[2] == 1 and after[3] == 0 and after[4] == 1, "colour restored after the bar")
assert(currentFont == font, "font restored")
print("PASS bar shown only for counters 1..200, fill from the counter, hint spot passed, colour/font restored")

alyssa.positionX = 9222.1 + 300
draw(77)
assert(#lockCalls == 0 and not has(texts, "UNLOCK"))
alyssa.positionX = 9222.1
alyssa.roomID = 5
draw(77)
assert(#lockCalls == 0)
alyssa.positionX = 8672.1
alyssa.positionY = 13019.3
draw(77)
assert(#lockCalls == 1 and lockCalls[1][2] == 8672.10 and has(texts, "UNLOCK"))
alyssa.roomID = 7
alyssa.positionX = 9158.6
alyssa.positionY = 12452.5
draw(77)
assert(#lockCalls == 1 and lockCalls[1][4] == true, "cabinet passes container flag")
print("PASS outside the spot / wrong room skip the reader; Staff Room door and Drawing Room cabinet spots")

alyssa.type = "Kevin"
draw(77)
assert(#lockCalls == 0 and not has(texts, "UNLOCK"))
alyssa.type = "Alyssa"
alyssa.status = "Dead"
draw(77)
assert(#lockCalls == 0)
alyssa.status = "Fine"
game.scenario = "outbreak"
alyssa.roomID = 1
alyssa.positionX = 9222.1
alyssa.positionY = 12619.3
tracker.getLockCounter = nil
draw(77)
assert(not has(texts, "UNLOCK"))
print("PASS other characters, dead Alyssa and readers without getLockCounter draw no bar")

tracker.getLockCounter = function(id, x, y, container)
    lockCalls[#lockCalls + 1] = { id, x, y, container }
    return counter
end
game.currentFile = 2
game.scenario = "desperate times"
alyssa.roomID = 2
alyssa.positionX = 2118.41
alyssa.positionY = 8902.26
draw(77)
assert(
    #lockCalls == 1 and lockCalls[1][2] == 2118.41 and lockCalls[1][4] == true and has(texts, "UNLOCK"),
    "File 2 drawer"
)
game.scenario = "wild things"
alyssa.roomID = 58
alyssa.positionX = 13030.73
alyssa.positionY = 13372.11
draw(150)
assert(#lockCalls == 1 and lockCalls[1][4] == nil and has(texts, "UNLOCK"), "unlabelled spot passes nil")
draw(0)
assert(not has(texts, "UNLOCK"))
print("PASS File 2 spots: labelled drawer passes true, unlabelled Wild Things spot passes nil, hidden at 0")
