-- Purpose: temporary run-local room visits, observed items and remembered SP items.
-- Runtime/location: sources/MapSession.lua; shared LuaJIT/LÖVE or Decky bridge.
-- Inputs: existing reader snapshots and supported SP room-item state; no new reads.
-- Output: in-memory visit/item tables, reset on scenario/release/new-run clock change.
-- Safety: no files, PINE, recordings, workbook or game writes; history is not saved.
-- Run: MapView.update feeds snapshots; check tracker-tests/maps/check-presentation.lua.
local M = { visited = {}, items = {}, spItems = {} }
local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 1000000
end
function M.clear()
    M.visited = {}
    M.items = {}
    M.spItems = {}
    M.key = nil
    M.frames = nil
end
function M.present(it)
    return it
        and type(it.id) == "number"
        and it.id > 0
        and type(it.type) == "number"
        and it.type >= 0
        and it.count ~= 0xffff
        and it.mix ~= 0x20
        and it.world ~= false
        and not ((it.pick or 0) > 0 and (it.present or 0) == 0)
        and finite(it.positionX)
        and finite(it.positionY)
        and not (it.positionX == 0 and it.positionY == 0)
end
local function copy(it, room, floor)
    return {
        id = it.id,
        type = it.type,
        count = it.count,
        pick = it.pick,
        present = it.present,
        mix = it.mix,
        positionX = it.positionX,
        positionY = it.positionY,
        height = it.height,
        roomID = room,
        floor = floor,
    }
end
function M.update(game, players, you, items, floor)
    local key = tostring(game.currentFile) .. ":" .. tostring(game.release) .. ":" .. tostring(game.scenario)
    local frames = tonumber(game.frames) or 0
    if game.scenario == "" or game.currentFile == 255 then
        M.clear()
        return
    end
    if M.key ~= key or (M.frames and frames > 0 and frames + 60 < M.frames) then
        M.clear()
        M.key = key
    end
    if frames > 0 then
        M.frames = frames
    end
    local p = players[you or 0]
    if not (p and p.enabled and p.inGame and (p.roomID or 0) > 0 and frames > 0) then
        return
    end
    M.visited[p.roomID] = true
    local observed = items and items[1] and items[1].roomitem
    if observed then
        local present = {}
        for _, it in ipairs(observed) do
            if M.present(it) then
                present[it.id] = true
                M.items[it.id] = copy(it, p.roomID, floor)
            end
        end
        for id, it in pairs(M.items) do
            if it.roomID == p.roomID and not present[id] then
                M.items[id] = nil
            end
        end
    end
    -- The reader already refreshes the pickup array. Global rows are used only
    -- for known scenario objects, and to retire known items after a pickup.
    for _, it in ipairs(type(game.mapItems) == "table" and game.mapItems or {}) do
        if M.present(it) then
            if it.type >= 10000 or M.items[it.id] then
                local old = M.items[it.id]
                local room = it.roomID or it.roomid
                M.items[it.id] = copy(it, room, old and old.roomID == room and old.floor or nil)
            end
        elseif it.id and M.items[it.id] then
            M.items[it.id] = nil
        end
    end
    local sp = require("SPTracking").state(game)
    if type(sp) == "table" and sp.available == true and type(sp.roomItems) == "table" and sp.room == p.roomID then
        local present = {}
        for _, it in ipairs(sp.roomItems) do
            if it.enabled and not it.collected and finite(it.x) and finite(it.y) then
                present[it.id] = true
                M.spItems[it.id] = {
                    id = it.id,
                    positionX = it.x,
                    positionY = it.y,
                    height = it.height,
                    roomID = sp.room,
                    floor = floor,
                }
            end
        end
        for id, it in pairs(M.spItems) do
            if it.roomID == sp.room and not present[id] then
                M.spItems[id] = nil
            end
        end
        for _, id in ipairs(sp.collectedIds or {}) do
            M.spItems[id] = nil
        end
    end
end
return M
