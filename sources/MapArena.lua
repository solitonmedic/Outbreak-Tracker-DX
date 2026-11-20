-- Purpose: room graphs for Elimination and Showdown, which have no game map,
-- and per-room enemy counts for their Room View and Grid View.
-- Runtime/location: sources/MapArena.lua; shared LuaJIT/LÖVE/Decky, pure Lua.
-- Inputs: scenario name, the reader's 80-entry scenario enemy list
-- (getEnemyList: roomID, HP, maxHP, nameID, flag) and rooms players have entered.
-- Outputs: graph tables and count tables; no drawing.
-- Room IDs are the reader's (sources/roomnames.lua). Cells and connections were
-- transcribed from the user's Elimination 1/2/3 room diagrams (2026-11-20) by
-- matching each diagram label to the room-name table:
--   E1 "1F Lobby" = 10 1F RPD East Hall, "Nurse Center" = 5 Doctor Station,
--      "Main Building 1F Hall" = 12, "F South Passway" = 6 B7F South Passway.
--   E2 "1F Passway" = 8 University's Access Way A, "1F Passage B" = 5,
--      "Stairs Between 1F and 3F" = 10 J's Bar Stairwell, "Rooftop" = 6.
--   E3 the right-hand "Stairwell" (beside Show Animals' Boarding House) is taken
--      as 10 Stairwell to Observation Mezzanine and the left one as 6 B2F
--      Stairwell; "Unloading Passage" is the only unmatched box and is paired
--      with 21 (table name "Pier"). Both pairings are unconfirmed.
--   E3 long bottom connections to the B2F Passage were too unclear to copy and
--      are left out.
-- Showdown has no transcribed graph yet (its room names are not in the table).
-- Enemy list (Japanese File 2 run 2026-11-20, Elimination 1): entries appear
-- when a room is first loaded; killed enemies keep HP 65535.
-- Safety: no memory, file or game access. Reusable.
-- Run: MapView requires it. Check: luajit tools-n-shit/tracker-tests/maps/check-arena.lua .
local A={}

-- cells: [roomID]={column,row}; links: room pairs joined by a door.
A.graphs={
    ["elimination 1"]={columns=5,rows=6,
        cells={[9]={0,0},[8]={1,0},[18]={3,0},[17]={4,0},
            [7]={0,1},[11]={1,1},[15]={2,1},[16]={3,1},
            [10]={1,2},[12]={2,2},[13]={3,2},
            [6]={0,3},[1]={1,3},
            [2]={2,4},[14]={3,4},
            [5]={0,5},[4]={1,5},[3]={2,5}},
        links={{9,8},{8,11},{8,7},{11,15},{11,12},{11,10},{10,6},{10,1},{7,6},{6,4},
            {4,5},{4,3},{3,2},{2,1},{1,12},{12,13},{15,16},{16,17},{17,18},{16,13},{13,14}}},
    ["elimination 2"]={columns=5,rows=4,
        cells={[1]={0,0},[2]={1,0},[3]={2,0},[4]={3,0},[6]={4,0},
            [15]={1,1},[8]={3,1},
            [14]={1,2},[11]={2,2},[9]={3,2},[7]={4,2},
            [13]={0,3},[12]={1,3},[10]={2,3},[5]={4,3}},
        links={{1,2},{2,3},{3,4},{4,6},{4,8},{6,5},{1,15},{1,14},{15,8},{11,8},{14,13},
            {13,9},{11,12},{11,10},{12,5},{10,9},{9,8},{9,7},{9,5},{7,5}}},
    ["elimination 3"]={columns=6,rows=6,
        cells={[15]={0,0},[16]={1,0},[17]={2,0},[18]={3,0},[19]={4,0},
            [11]={2,1},[9]={3,1},[20]={4,1},[21]={5,1},
            [13]={0,2},[12]={1,2},[6]={3,2},
            [8]={3,3},[7]={4,3},
            [14]={0,4},[1]={1,4},[2]={2,4},[3]={3,4},[4]={4,4},[10]={5,4},
            [5]={4,5}},
        links={{15,11},{15,16},{15,13},{16,12},{13,17},{17,11},{17,18},{18,19},{19,21},{19,20},
            {21,7},{8,7},{9,6},{6,11},{9,8},{8,3},{12,11},{12,13},{13,14},{1,2},{2,3},
            {3,4},{4,5},{5,10},{10,7}}},
}

function A.isArena(scenario)
    local s=tostring(scenario or "")
    return s:find("^elimination")~=nil or s:find("^showdown")~=nil
end

-- Neighbours of a room in its graph, in link order.
function A.neighbours(graph,id)
    local out={}
    for _,link in ipairs(graph and graph.links or {}) do
        if link[1]==id then out[#out+1]=link[2] elseif link[2]==id then out[#out+1]=link[1] end
    end
    return out
end

-- Enemies left per room. A room is known once the list has an entry for it or
-- the local player has been in it (seen[id]); unknown rooms are left out.
-- isHazard(entry) excludes mines and explosives from the count.
function A.counts(list,seen,isHazard)
    local known,alive={},{}
    for id in pairs(seen or {}) do known[id]=true;alive[id]=alive[id] or 0 end
    for _,e in pairs(list or {}) do
        local room=tonumber(e.roomID)
        if type(e)=="table" and (tonumber(e.flag) or 0)~=0 and room and room>0 then
            known[room]=true;alive[room]=alive[room] or 0
            local hp,maxHP=tonumber(e.HP) or 0,tonumber(e.maxHP) or 0
            if hp>0 and hp~=65535 and maxHP>0 and hp<=maxHP and not (isHazard and isHazard(e)) then
                alive[room]=alive[room]+1
            end
        end
    end
    return alive,known
end

return A
