-- Purpose: reads the whole Lua API of the tracker's native reader once, for the
-- gameplay-frame tests (the same calls on every platform and in the Decky runner).
-- Location/runtime: tests/automation/frames_dump.lua; LuaJIT (LÖVE or plain).
-- Inputs: the loaded reader module (luaoutbreaktracker). Outputs: one table:
-- game, lobby[20], slotplayer[4], player[4], enemy[12], enemylist[80], item,
-- item2[255], mapitems, door[19], roommaster[128] (index = room + 1), spmap.
-- getLockCounter is left out: it keeps internal caches and cooldowns, and the
-- player cards already exercise it in the views. Read-only; no files.
-- Run/check: called by tests/automation/main.lua and tests/decky_frames.py.
local M = {}
local function call(tracker, name, ...)
    local f = tracker[name]
    if type(f) ~= "function" then return nil end
    return f(...)
end
function M.api(tracker)
    local d = {}
    d.game = call(tracker, "getGameInfo")
    d.lobby, d.slotplayer, d.player, d.enemy, d.enemylist = {}, {}, {}, {}, {}
    d.item2, d.door, d.roommaster = {}, {}, {}
    for i = 1, 20 do d.lobby[i] = call(tracker, "getLobby", i) or false end
    for i = 1, 4 do d.slotplayer[i] = call(tracker, "getSlotPlayer", i) or false end
    for i = 1, 4 do d.player[i] = call(tracker, "getPlayer", i) or false end
    for i = 1, 12 do d.enemy[i] = call(tracker, "getEnemy", i) or false end
    for i = 1, 80 do d.enemylist[i] = call(tracker, "getEnemyList", i) or false end
    d.item = call(tracker, "getItem", 1)
    for i = 1, 255 do d.item2[i] = call(tracker, "getItem2", i) or false end
    d.mapitems = call(tracker, "getMapItems")
    for i = 1, 19 do d.door[i] = call(tracker, "getDoor", i) or false end
    for room = 0, 127 do d.roommaster[room + 1] = call(tracker, "getRoomMaster", room) or false end
    d.spmap = call(tracker, "getSPMapState")
    return d
end
return M
