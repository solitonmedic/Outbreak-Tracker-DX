-- Purpose: reusable pure-Lua check of the Elimination/Showdown room graphs and
-- enemy counts in sources/MapArena.lua.
-- Location/runtime: tests/unit/maps/check-arena.lua; LuaJIT.
-- Inputs: repository root arg[1]; sources/MapArena.lua, sources/roomnames.lua;
-- synthetic enemy-list entries. Outputs: PASS lines.
-- Safety: no PINE, recordings, discs, workbook or file writes.
-- Run from repo-merged: luajit tests/unit/maps/check-arena.lua .
-- Check: every Elimination/Showdown room in the disc name table has one cell; cells are
-- unique and inside the grid; links join placed rooms once; counts use the whole
-- list (unloaded entries too) and ignore killed (65535) and hazard entries; the E3
-- run's room changes are links; Showdown 3 stages are links in ID order, rounds
-- are labelled ROUND n + boss, Showdown has no doors; sources
-- exist except the listed unsourced rooms.
local repo = assert(arg[1])
package.path = repo .. "/sources/?.lua;" .. package.path
local A = require("MapArena")
local names = require("roomnames")
for _, scenario in ipairs({
    "elimination 1",
    "elimination 2",
    "elimination 3",
    "showdown 1",
    "showdown 2",
    "showdown 3",
}) do
    local g = assert(A.graphs[scenario], scenario)
    local used = {}
    for id, c in pairs(g.cells) do
        assert(names[scenario][id], scenario .. " cell for unknown room " .. id)
        assert(c[1] >= 0 and c[1] < g.columns and c[2] >= 0 and c[2] < g.rows, scenario .. " cell outside grid " .. id)
        local key = c[1] .. "," .. c[2]
        assert(not used[key], scenario .. " two rooms share cell " .. key)
        used[key] = id
    end
    for id in pairs(names[scenario]) do
        if id > 0 then
            assert(g.cells[id], scenario .. " room " .. id .. " has no cell")
        end
    end
    local seen = {}
    for _, l in ipairs(g.links) do
        assert(g.cells[l[1]] and g.cells[l[2]] and l[1] ~= l[2], scenario .. " bad link")
        local key = math.min(l[1], l[2]) .. ":" .. math.max(l[1], l[2])
        assert(not seen[key], scenario .. " duplicate link " .. key)
        seen[key] = true
    end
end
local n = A.neighbours(A.graphs["elimination 1"], 10)
table.sort(n)
assert(table.concat(n, ",") == "1,6,11", "E1 1F RPD East Hall neighbours")
-- Disc names (read-arena-rooms.py): E2 5/8 and E3 21 corrected from the old table.
assert(names["elimination 2"][5] == "1F passway" and names["elimination 2"][8] == "1F passage B")
assert(names["elimination 3"][21] == "Unloading passage" and names["showdown 2"][6] == "Elephant Stage")
assert(A.graphs["elimination 2"].cells[5][1] == 3 and A.graphs["elimination 2"].cells[5][2] == 1, "E2 1F passway cell")
print(
    "PASS Elimination 1-3 and Showdown 1-3 graphs: every disc-named room placed once, links valid, E1 room 10 neighbours, E2 5/8 fixed"
)
assert(A.isArena("elimination 2") and A.isArena("showdown 3") and not A.isArena("flashback"))
local list = {
    { flag = 1, roomID = 10, HP = 650, maxHP = 650, nameID = 1 },
    { flag = 1, roomID = 10, HP = 65535, maxHP = 650, nameID = 1 },
    { flag = 1, roomID = 11, HP = 1, maxHP = 1, nameID = 54 },
    { flag = 0, roomID = 12, HP = 650, maxHP = 650, nameID = 1 },
    { flag = 1, roomID = 2, HP = 1500, maxHP = 1500, nameID = 34 },
    { flag = 1, roomID = 2, HP = 1, maxHP = 1, nameID = 60 },
}
local alive, known, loaded = A.counts(list, { [7] = true }, function(e)
    return e.nameID == 54
end)
assert(alive[10] == 1 and known[10] and loaded[10], "killed entry counted")
assert(alive[11] == 0 and known[11], "mine counted as an enemy")
assert(alive[12] == 1 and known[12] and not loaded[12], "unloaded (flag 0) room not counted from the list")
assert(alive[7] == 0 and known[7], "visited room without entries should read 0")
assert(not known[3], "room known without a graph or entries")
assert(alive[2] == 0 and known[2], "Tentacles or Fire counted as enemies left")
local _, knownGraph = A.counts(list, {}, nil, A.graphs["elimination 1"])
assert(knownGraph[3] and knownGraph[18], "filled list should make every graph room known")
local _, knownEmpty = A.counts({ { flag = 0, roomID = 0, HP = 0, maxHP = 0 } }, {}, nil, A.graphs["elimination 1"])
assert(not knownEmpty[3], "empty list made rooms known")
-- Showdown 3 run of 2026-11-21, checkpoint 170 (stage 11): earlier stages keep
-- untouched minions; L.Tentacles (32767) and 1-HP parts are not enemies.
local sd = {
    { roomID = 1, nameID = 29, HP = 65535, maxHP = 9900, flag = 49 },
    { roomID = 1, nameID = 30, HP = 200, maxHP = 200, flag = 48 },
    { roomID = 2, nameID = 56, HP = 32767, maxHP = 32767, flag = 48 },
    { roomID = 8, nameID = 63, HP = 1, maxHP = 1, flag = 45 },
    { roomID = 10, nameID = 42, HP = 4800, maxHP = 5800, flag = 48 },
    { roomID = 11, nameID = 41, HP = 65535, maxHP = 13000, flag = 49 },
    { roomID = 11, nameID = 41, HP = 9000, maxHP = 9000, flag = 47 },
    { roomID = 12, nameID = 23, HP = 1700, maxHP = 1700, flag = 0 },
}
local sdAlive = A.counts(sd, {}, nil, A.graphs["showdown 3"], 11)
assert(
    sdAlive[1] == 0 and sdAlive[10] == 0 and sdAlive[11] == 1,
    "Showdown cleared stages or the current stage miscounted"
)
local sdLive = A.counts(sd, {}, nil, A.graphs["showdown 3"], 1)
assert(
    sdLive[1] == 0 and sdLive[2] == 0 and sdLive[8] == 0 and sdLive[10] == 1 and sdLive[11] == 1,
    "L.Tentacles, 1-HP parts or a cleared round (G-Mutant dead) counted as enemies"
)
print(
    "PASS enemy counts: whole list counted (flag 0 too), killed and hazard entries excluded, filled list knows every room; Showdown stages before the current one read 0, L.Tentacles and 1-HP parts excluded"
)
-- Every room change of the Elimination 3 run of 2026-11-21 (room-positions.py)
-- is a diagram link; it fixed the two Stairwells (5-6-7 and 9-10-11).
local links = {}
for _, l in ipairs(A.graphs["elimination 3"].links) do
    links[math.min(l[1], l[2]) .. ":" .. math.max(l[1], l[2])] = true
end
for _, t in ipairs({
    { 1, 2 },
    { 2, 3 },
    { 3, 4 },
    { 4, 5 },
    { 5, 6 },
    { 6, 7 },
    { 7, 8 },
    { 8, 9 },
    { 9, 10 },
    { 10, 11 },
    { 11, 12 },
    { 11, 15 },
    { 11, 17 },
    { 12, 13 },
    { 12, 16 },
    { 13, 15 },
    { 15, 16 },
    { 17, 18 },
}) do
    assert(links[t[1] .. ":" .. t[2]], "E3 run transition " .. t[1] .. "-" .. t[2] .. " is not a link")
end
print("PASS Elimination 3: all 18 room changes of the 2026-11-21 run are diagram links")
-- Showdown 3 VH run of 2026-11-21: stages 1 to 11 in ID order; Showdown 1 and 2
-- take the same rooms' art and spots.
links = {}
for _, l in ipairs(A.graphs["showdown 3"].links) do
    links[math.min(l[1], l[2]) .. ":" .. math.max(l[1], l[2])] = true
end
for id = 1, 10 do
    assert(links[id .. ":" .. (id + 1)], "Showdown 3 stage " .. id .. "-" .. (id + 1) .. " is not a link")
end
for id = 1, 11 do
    assert(A.sources["showdown 3"][id], "Showdown 3 room " .. id .. " has no source")
end
assert(
    A.sources["showdown 1"][3] == A.sources["showdown 3"][3]
        and A.sources["showdown 2"][8] == A.sources["showdown 3"][8]
)
assert(
    not A.doors["showdown 3"] and A.isShowdown("showdown 2") and not A.isShowdown("elimination 1"),
    "Showdown has no door boxes"
)
-- Grid labels: ROUND n in room order with the room's first list entry (its boss).
local rounds = A.rounds(A.graphs["showdown 2"], {
    { roomID = 7, maxHP = 9000, name = "Lion" },
    { roomID = 6, maxHP = 14000, name = "Titan" },
    { roomID = 6, maxHP = 1, name = "ID:62" },
    { roomID = 7, maxHP = 2100, name = "Stalker" },
    { roomID = 0, maxHP = 0, name = "" },
})
assert(
    rounds[6][1] == "ROUND 1" and rounds[6][2] == "TITAN" and rounds[7][1] == "ROUND 2" and rounds[7][2] == "LION",
    "Showdown round labels"
)
assert(rounds[10][1] == "ROUND 5" and rounds[10][2] == nil, "Showdown round without list entry")
-- Round cleared once every entry of the boss's kind is dead (round 7: three
-- Lions; round 10: Nyx-Core while Nyx and Nyx-Tyrant live on).
local done = A.roundsCleared({
    { roomID = 7, nameID = 33, HP = 65535, maxHP = 10000 },
    { roomID = 7, nameID = 33, HP = 2100, maxHP = 2100 },
    { roomID = 10, nameID = 44, HP = 65535, maxHP = 12000 },
    { roomID = 10, nameID = 42, HP = 4800, maxHP = 5800 },
    { roomID = 10, nameID = 15, HP = 300, maxHP = 3000 },
})
assert(not done[7] and done[10], "Showdown round clear rule")
local left = A.counts(
    { { roomID = 10, nameID = 44, HP = 65535, maxHP = 12000 }, { roomID = 10, nameID = 42, HP = 4800, maxHP = 5800 } },
    {},
    nil,
    A.graphs["showdown 3"],
    10
)
assert(left[10] == 0, "cleared current round still counts its minions")
print(
    "PASS Showdown 3: the 2026-11-21 run's ten stage changes are links; Showdown 1/2 share its room art; no door boxes; ROUND n + boss labels; a round is cleared when its boss kind is dead"
)
-- Room View sources and doors (match-arena-rooms.py, 2026-11-20 runs).
local Data = require("MapData")
local function read(path)
    local f = io.open(repo .. "/" .. path, "rb")
    if not f then
        return nil
    end
    local b = f:read("*a")
    f:close()
    return b
end
local maps = {}
for scenario, rooms in pairs(A.sources) do
    for id, src in pairs(rooms) do
        assert(names[scenario][id], scenario .. " source for unknown room " .. id)
        local key = src[1] .. src[2]
        if not maps[key] then
            local name
            for _, e in ipairs(Data.scenarios[src[1]]) do
                if e[1] == src[2] then
                    name = e[2]
                end
            end
            maps[key] = assert(Data.load(src[1], name, read), key)
        end
        local f = assert(maps[key].floors[src[4]], scenario .. " room " .. id .. " floor")
        local found = false
        for _, p in ipairs(f.places) do
            if maps[key].rooms[p.record].id == src[3] then
                found = true
            end
        end
        assert(found, scenario .. " room " .. id .. " source room not on its floor")
    end
    local missing = A.unsourced[scenario] or {}
    for id in pairs(names[scenario]) do
        if id > 0 then
            assert(rooms[id] or missing[id], scenario .. " room " .. id .. " has no source")
        end
    end
end
for scenario, rooms in pairs(A.doors) do
    for id, from in pairs(rooms) do
        local linked = {}
        for _, k in ipairs(A.neighbours(A.graphs[scenario], id)) do
            linked[k] = true
        end
        for other in pairs(from) do
            assert(linked[other], scenario .. " door " .. id .. "<-" .. other .. " is not a diagram link")
        end
    end
end
print(
    "PASS Elimination 1/2/3 and Showdown 1/2/3 Room View sources exist on their floors; recorded doors follow diagram links"
)
