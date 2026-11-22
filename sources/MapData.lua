-- Purpose: reusable map layout for the ten Japanese scenario maps (also used for
-- U.S. File 1, whose map files hold the same rooms, floors and placements).
-- Runtime/location: sources/MapData.lua; LuaJIT (desktop LÖVE or Decky).
-- Inputs: sources/MapGeometry.lua, numbers exported from the game's map files by
-- tools-n-shit/research/export-map-geometry.py (no game files at run time).
-- M.parse still reads a map file's bytes; the checks use it to compare.
-- Outputs: fresh room/floor tables per load; performs no filesystem access.
-- Safety: no disc, ISO, PINE, recordings, workbook or user-cache access.
-- Run: maps load automatically when opening a supported scenario.
-- Check from repo root: luajit tools-n-shit/tracker-tests/maps/check-map-geometry.lua .
local Geometry = require "MapGeometry"
local M = {}
M.scenarios = {
    -- Codes are the game's scenario IDs (structs.h GetScenarioName): 002 holds
    -- Hellfire's Apple Inn rooms and 035 Below Freezing Point's B7F lab rooms
    -- (room names in the map files; corrected 2026-11-20, they were swapped).
    [1] = {{"001", "outbreak"}, {"002", "hellfire"}, {"028", "the hive"},
           {"035", "below freezing point"}, {"041", "decisions,decisions"}},
    [2] = {{"006", "end of the road"}, {"010", "underbelly"}, {"015", "desperate times"},
           {"026", "flashback"}, {"040", "wild things"}}
}
local function u16(s, o)
    local a,b = s:byte(o+1,o+2); assert(b, "Truncated map data")
    return a+b*256
end
local function u32(s, o) return u16(s,o)+u16(s,o+2)*65536 end
local function i16(s,o) local v=u16(s,o); return v>=32768 and v-65536 or v end
local function name(s,o)
    local chars={}
    for n=o+1,o+32 do
        local c=s:byte(n)
        if c==0 or c==255 then break end
        c=255-c
        if c<32 or c>126 then return "" end
        chars[#chars+1]=string.char(c)
    end
    return table.concat(chars)
end
function M.parse(s)
    assert(#s>=32 and #s<=2*1024*1024, "Invalid map size")
    local nr,nf,ft,tex=u32(s,4),u32(s,12),u32(s,16),u32(s,28)
    assert(u32(s,0)==#s and u32(s,8)==32 and nr>0 and nr<=256 and nf>0 and nf<=256,
           "Invalid map header")
    assert(32+nr*88<=ft and ft+nf*92<=tex and tex<#s and (#s-tex)%512==0, "Invalid map tables")
    local map={rooms={},floors={},width=1024,height=(#s-tex)*2/1024}
    for n=0,nr-1 do
        local o=32+n*88
        local page,id,u,v=s:byte(o+1,o+4)
        local r={id=id,x=page%4*256+u,y=math.floor(page/4)*256+v,w=u16(s,o+4),h=u16(s,o+6),name=name(s,o+40)}
        assert(r.x+r.w<=1024 and r.y+r.h<=map.height, "Map crop outside texture")
        map.rooms[n+1]=r
    end
    for n=0,nf-1 do
        local o=ft+n*92
        local count=s:byte(o+67)
        local po=u32(s,o+68)
        assert(po>=ft+nf*92 and po+count*6<=tex, "Invalid map placements")
        local f={name=name(s,o+32),level=s:byte(o+66),flag=s:byte(o+65),height=i16(s,o+76),ppu=i16(s,o+72),refX=i16(s,o+74),refZ=i16(s,o+78),
                 places={},minX=math.huge,minY=math.huge,maxX=-math.huge,maxY=-math.huge}
        if f.name=="" then f.name="Area "..(n+1) end
        assert(f.ppu>0 and f.ppu<=1000, "Invalid map scale")
        for k=0,count-1 do
            local p=po+k*6
            local rec=s:byte(p+1)+1
            local r=assert(map.rooms[rec], "Missing room record")
            local place={record=rec,x=i16(s,p+2),y=i16(s,p+4)}
            f.places[#f.places+1]=place
            f.minX=math.min(f.minX,place.x); f.minY=math.min(f.minY,place.y)
            f.maxX=math.max(f.maxX,place.x+r.w); f.maxY=math.max(f.maxY,place.y+r.h)
        end
        if count==0 then f.minX,f.minY,f.maxX,f.maxY=0,0,1,1 end
        map.floors[#map.floors+1]=f
    end
    return map
end
function M.position(f,x,z) return (x-f.refX)*f.ppu/100,(z-f.refZ)*f.ppu/100 end

-- A fresh copy per load: MapView adjusts floor bounds for full-artwork floors.
-- Rooms carry their traced outlines (room-local pixels); map.code is the map's
-- scenario code ("001" ...). The third argument of older callers is ignored.
function M.load(game,scenario)
    local code
    for _,entry in ipairs(M.scenarios[game] or {}) do
        if entry[2]==scenario then code=entry[1]; break end
    end
    if not code then return nil,"No map is available for this scenario" end
    local data=Geometry[game] and Geometry[game][code]
    if not data then return nil,"Map data is missing from this build" end
    local map={game=game,code=code,rooms={},floors={}}
    for i,r in ipairs(data.rooms) do map.rooms[i]={id=r[1],w=r[2],h=r[3],outlines=r[4]} end
    for i,f in ipairs(data.floors) do
        local floor={name=f.name,height=f.height,ppu=f.ppu,refX=f.refX,refZ=f.refZ,places={},
                     minX=f.bounds[1],minY=f.bounds[2],maxX=f.bounds[3],maxY=f.bounds[4]}
        for k=1,#f.places,3 do
            floor.places[#floor.places+1]={record=f.places[k],x=f.places[k+1],y=f.places[k+2]}
        end
        map.floors[i]=floor
    end
    return map
end
return M
