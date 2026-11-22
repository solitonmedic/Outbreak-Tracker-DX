-- Purpose: share the existing tracker's learned-clue colors with the map.
-- Location/runtime: sources/PuzzleHints.lua; LÖVE 11.5/LuaJIT.
-- Inputs: existing GameInfo passwt/passdt3/passub3 and already decoded hint text.
-- Outputs: colors and LÖVE colored text; no new hint values or memory reads.
-- Safety: pure presentation; no game, recording, workbook or file writes.
-- Run: loaded by main.lua/MapView.lua. Check from repo-merged/:
-- luajit tools-n-shit/tracker-tests/maps/check-presentation.lua .
local H={}
local green={0,200/255,0,1}
local grey={127/255,127/255,127/255,1}
local white={1,1,1,1}
function H.color(game,index)
    local value,mask
    if game.scenario=="wild things" then value,mask=game.passwt,4
    elseif game.scenario=="desperate times" then value,mask=game.passdt3,4
    elseif game.scenario=="underbelly" then value,mask=game.passub3,index==2 and 16 or 32
    else return white end
    -- Same bit tests used by the main tracker; unrelated bits do not count.
    return type(value)=="number" and value%(mask*2)>=mask and green or grey
end
function H.text(game,value)
    if game.scenario=="underbelly" then
        local first,second=value:match("^(%S+) (%S+)$")
        if first then
            return {H.color(game,1),"HINT: "..first,white," ",H.color(game,2),second}
        end
    end
    return {H.color(game,1),"HINT: "..value}
end
return H
