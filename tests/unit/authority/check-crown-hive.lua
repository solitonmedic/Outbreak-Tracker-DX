-- This harness replaces tracker globals (the asset loader, the atlas selector and
-- the fonts) with fakes, which selene would otherwise report.
--# selene: allow(incorrect_standard_library_use, global_usage)
-- Purpose: reusable integration check of actual shared love.draw/key/update and
-- PlayerCard:draw for Hive hints, Q toggling, crown selection and room bounds.
-- Location/runtime: tests/unit/authority/check-crown-hive.lua; Homebrew LuaJIT.
-- Inputs: repository root argv[1], shared Lua files; synthetic tracker/graphics.
-- Outputs: PASS lines only; no files, native module, live PINE or recordings.
-- Safety: all game data/graphics are in-memory fixtures; no capture/game writes.
-- Run from repo-merged: luajit tests/unit/authority/check-crown-hive.lua .
-- Check: actual drawing emits active codes/leading zero, suppresses unavailable
-- and Q-disabled hints, draws only the current room's active owner crown, and
-- update requests exactly room indices0..127. No screenshot/runtime claim.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local noop = function() end
local texts, sprites, queried = {}, {}, {}
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
    draw = function(_, name)
        sprites[#sprites + 1] = name
    end,
    addSB = noop,
}
love = {
    graphics = setmetatable({
        printf = function(s)
            texts[#texts + 1] = s
        end,
        print = noop,
        getFont = function()
            return font
        end,
        getColor = function()
            return 1, 1, 1, 1
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
    release = "us",
    playernum = 3,
    frames = 300,
    scenario = "the hive",
    difficulty = "normal",
    hostscenario = "the hive",
    hostdifficulty = "normal",
    hivecodesavailable = true,
    hiveb2f = 9867,
    hiverooftop = 1065,
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
    getRoomMaster = function(id)
        assert(id >= 0 and id < 128 and id == math.floor(id))
        queried[id] = true
        return { enabled = false, roommaster = 0 }
    end,
}
package.preload.luaoutbreaktracker = function()
    return tracker
end
dofile(repo .. "/sources/main.lua")
LoadAssets = function()
    UIAtlas, ItemIcons, ItemIcons2 = atlas, atlas, atlas
    for _, name in ipairs({ "DefaultFont", "SmallFont", "VerySmallFont", "TimeFont", "VirusFont", "ItemCountFont" }) do
        _G[name] = font
    end
end
SelectUIAtlas = noop
ItemCard.draw = noop
DoorCard.draw = noop
love.load({})
love.update(0.2)
local count = 0
for _ in pairs(queried) do
    count = count + 1
end
assert(count == 128)
local function contains(list, text)
    for _, v in ipairs(list) do
        if v == text then
            return true
        end
    end
    return false
end
local function draw()
    texts, sprites = {}, {}
    love.draw()
end
draw()
assert(contains(texts, "9867-1065") and not contains(texts, "3555-0930"))
game.hiverooftop = 567
draw()
assert(contains(texts, "9867-0567"))
love.keypressed("q")
draw()
assert(not contains(texts, "9867-0567"))
love.keypressed("q")
draw()
assert(contains(texts, "9867-0567"))
game.hivecodesavailable = false
draw()
assert(not contains(texts, "9867-0567") and not contains(texts, "3555-0930"))
game.release = "jp"
draw()
assert(contains(texts, "3555-0930"))
print("PASS actual Hive drawing, leading zeros, Q toggle, unavailable suppression and Japanese hints")

local player = setmetatable({
    enabled = true,
    inGame = true,
    roomID = 127,
    name = "Kevin",
    type = "Kevin",
    status = "Fine",
    HP = 100,
    maxHP = 100,
    inventory = {},
    specialInventory = {},
    specialItem = { id = -1, type = 0 },
}, {
    __index = function()
        return 0
    end,
})
for i = 1, 4 do
    player.inventory[i] = { id = -1 }
    player.specialInventory[i] = { id = -1 }
end
Players[1] = player
Label.draw = noop
local card = PlayerCards[1]
local function crown(expected)
    sprites = {}
    card:draw(0, 0)
    assert(contains(sprites, "room master crown") == expected)
end
RoomMasters = { [127] = { enabled = true, roommaster = 1 } }
crown(true)
RoomMasters[127].roommaster = 2
crown(false)
RoomMasters[127].roommaster = 1
RoomMasters[127].enabled = false
crown(false)
RoomMasters[127].enabled = true
player.inGame = false
crown(false)
player.inGame = true
player.roomID = 128
crown(false)
player.roomID = 0
RoomMasters[0] = { enabled = true, roommaster = 1 }
crown(false)
player.roomID = 127
RoomMasters[127] = nil
crown(false)
print("PASS actual player-card crowns: own room, other owner, unavailable, inactive, missing and boundary rooms")
print("PASS update requests exactly room indices0..127")
