-- Purpose: reusable shared desktop/phone map views, follow controls and room tint.
-- Runtime/location: sources/MapView.lua; LÖVE 11.5 or the Decky Lua drawing bridge.
-- Inputs: existing GameInfo/Players, update delta, bundled assets and UI actions.
-- Outputs: map drawing, compact cards and UI-only GameInfo.mapview state.
-- Hint colors reuse PuzzleHints and existing main-tracker knowledge flags.
-- Forest artwork bounds and the recorded maze-exit guide come from MapER.lua;
-- forest card floor labels are omitted while hospital floor labels remain.
-- Safety: read-only packaged assets and existing state; no disc or user-cache access.
-- In B the panel under the map shows the session line (character // scenario //
-- difficulty) instead of the clock, SP radar and item sets the cards already show.
-- Run: B = cards beside map, N = map above cards; assets load automatically.
-- Check: luajit tools-n-shit/tracker-tests/maps/check-runtime-maps.lua .
local Data=require "MapData"
local Session=require "MapSession"
local Effects=require "PlayerEffects"
local Catalog=require "MapCatalog"
local Hints=require "PuzzleHints"
local Arena=require "MapArena"
local okER,ER=pcall(require,"MapER")
if not okER then ER={} end
local V={mode=0,follow=true,target=nil,floor=1,zoom=1,panX=0,panY=0,hits={},cacheKey=""}
V.colors=Effects.slotColors
local function read(path)
    if love.filesystem then return love.filesystem.read(path) end
    local f=io.open(path,"rb")
    if not f then return end
    local bytes=f:read("*a"); f:close(); return bytes
end
function V.reset()
    V.zoom,V.panX,V.panY=1,0,0
    V.frozenCenter=nil
end
function V.setMode(mode)
    V.mode=mode; V.drag=nil; V.hits={}
end
-- Each phase keeps the legacy hard/very-hard and easy/normal room lists.
local gasPatterns = {
    [0] = {{{4,14,20},{14,20}}, {{7,10,12},{7,12}}, {{9,13,27},{9,13}}, {{5,7,21},{5,21}}, {{4,10,11},{10,11}}, {{5,15,16},{15,16}}, {{4,11,13},{4,11}}, {{14,15,21},{14,15}}, {{11,20,27},{11,20}}, {{5,9,16},{5,9}}},
    [1] = {{{7,10,16},{10,16}}, {{4,14,27},{14,27}}, {{7,16,20},{7,20}}, {{9,13,21},{9,13}}, {{10,12,15},{12,15}}, {{5,16,21},{5,21}}, {{5,11,27},{11,27}}, {{4,7,20},{4,20}}, {{10,12,13},{12,13}}, {{7,15,21},{7,21}}}
}
function V.gas(game)
    if game.scenario~="desperate times" or game.fighttime2==0 then return {} end
    local phases=gasPatterns[(game.gasrandom or 0)%2]
    local difficulty=(game.difficulty=="hard" or game.difficulty=="very hard") and 1 or 2
    local rooms={}
    for i,entry in ipairs(phases) do
        if game.gasflag==2^(i-1) then
            for _,room in ipairs(entry[difficulty]) do rooms[room]=true end
        end
    end
    return rooms
end
-- Remote players remain enabled and keep current coordinates while inGame=0
-- outside the loaded room. Enemy slots retain their separate inGame guard.
local function active(p) return p and p.enabled and (p.roomID or 0)>0 end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1000000 end
function V.candidates(map,player)
    local matches={}
    if not active(player) then return matches end
    for i,f in ipairs(map.floors) do
        for _,p in ipairs(f.places) do
            if map.rooms[p.record].id==player.roomID then matches[#matches+1]=i; break end
        end
    end
    if #matches>1 and player.heightAvailable==true and finite(player.height) then
        -- The game's floor records are lower height thresholds, not nearest
        -- planes. DT Main Hall changes to 2F at 400, not halfway up the stairs.
        local selected=matches[1]
        for _,index in ipairs(matches) do
            if player.height>=map.floors[index].height then selected=index end
        end
        return {selected}
    end
    return matches
end
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end end
function V.marker(map,floor,player)
    local f=map.floors[floor]
    local matches=V.candidates(map,player)
    if not contains(matches,floor) then return end
    if #matches==1 and finite(player.positionX) and finite(player.positionY) then
        local x,y=Data.position(f,player.positionX,player.positionY)
        -- Forest artwork includes the maze omitted from the game's texture.
        -- Its recorded-coordinate fit supplies complete bounds for live markers.
        if f.fullArtwork and x>=f.minX and x<=f.maxX and y>=f.minY and y<=f.maxY then return x,y,false end
        -- The DT Front Gate's playable space extends beyond its small map
        -- outline. Its known room/floor is sufficient to show the actual point.
        if player.roomID==27 and map.path and map.path:match("/015$") then
            x,y=V.clampToRoom(map,floor,player.roomID,x,y,V.markerMargin);return x,y,false
        end
        -- Out-of-piece reads (loading/stale state) fall back to the room, never
        -- a plausible-looking marker on a different room or floor.
        for _,p in ipairs(f.places) do
            local r=map.rooms[p.record]
            if r.id==player.roomID and x>=p.x and x<p.x+r.w and y>=p.y and y<p.y+r.h then
                x,y=V.clampToRoom(map,floor,player.roomID,x,y,V.markerMargin);return x,y,false
            end
        end
    end
    for _,p in ipairs(f.places) do
        local r=map.rooms[p.record]
        if r.id==player.roomID then return p.x+r.w/2,p.y+r.h/2,true end
    end
end
-- Enemy slots share the player layout (X/Z +0x38/+0x40, room +0x1E2). Only
-- enabled, in-game, living slots hold a live position; the others keep stale
-- values from earlier rooms, so they are never drawn. Positions are shown as
-- read, then kept inside the drawn room (V.clampToRoom).
-- Screen rotation for a player's chevron: forward (map X, map Y) is the
-- transform's (+0x70, +0x50); 0 means pointing up the map.
function V.heading(p)
    local fx,fy=p and p.forwardX,p and p.forwardY
    if finite(fx) and finite(fy) and fx*fx+fy*fy>.25 then return math.atan2(fx,-fy) end
    return 0
end
-- Screen-space proximity controls only the floating map labels. Hysteresis
-- restores labels after separation without flickering at the boundary.
function V.hiddenPlayerLabels(points,previous)
    local hidden={}
    for i=1,4 do for j=i+1,4 do
        local a,b=points[i],points[j]
        if a and b then
            local distance=(previous and (previous[i] or previous[j])) and 52 or 44
            if (a.x-b.x)^2+(a.y-b.y)^2<distance^2 then hidden[i]=true;hidden[j]=true end
        end
    end end
    return hidden
end
-- Room items are shown only for the room YOU are in (the loaded room, whose
-- item list the reader keeps current). Pickup X/Z sit at record +8/+16.
-- Taken items (no ID, 0xFFFF count, mix flag 0x20, or picked but absent) are skipped.
function V.itemMarker(map,floor,room,it)
    if not (it and it.id and it.id~=-1 and type(it.type)=="number" and it.type>=0 and it.count~=0xFFFF and it.mix~=0x20) then return end
    if (it.pick or 0)>0 and (it.present or 0)==0 then return end
    if not (finite(it.positionX) and finite(it.positionY)) or (it.positionX==0 and it.positionY==0) then return end
    local candidates=V.candidates(map,{enabled=true,roomID=room,height=it.height,heightAvailable=finite(it.height)})
    if not contains(candidates,floor) then return end
    if #candidates>1 and it.floor and it.floor~=floor then return end
    local f=map.floors[floor]
    for _,p in ipairs(f.places) do
        if map.rooms[p.record].id==room then
            local x,y=Data.position(f,it.positionX,it.positionY)
            return V.clampToRoom(map,floor,room,x,y,V.markerMargin)
        end
    end
end
-- Enemy identity comes from the reader's existing GetEnemyName table. Include
-- Giant Moth/Rafflesia and the distinct Gigabyte boss (64, not Megabyte18).
local bossIds={[9]=true,[15]=true,[19]=true,[20]=true,[29]=true,[32]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,[47]=true,[51]=true,[64]=true}
function V.isBoss(e) return e and bossIds[e.nameID] or false end
-- Traps and explosives from the enemy name table (structs.h GetEnemyName):
-- 54 Mine (End of the Road, some Elimination maps), 58 Gas.Tank. They are drawn
-- orange with a red glow, carry no HP label and are not counted as enemies.
local hazardIds={[54]=true,[58]=true}
function V.isHazard(e) return e and hazardIds[e.nameID] or false end
function V.enemyMarker(map,floor,e)
    if not (e and e.enabled and e.inGame and finite(e.positionX) and finite(e.positionY)) then return end
    local hp,maxHP=e.HP or 0,e.maxHP or 0
    if maxHP<=0 or maxHP>=60000 or hp<=0 or hp>maxHP then return end
    local f=map.floors[floor]
    for _,p in ipairs(f.places) do
        if map.rooms[p.record].id==e.roomID then
            local x,y=Data.position(f,e.positionX,e.positionY)
            return V.clampToRoom(map,floor,e.roomID,x,y,V.markerMargin)
        end
    end
end
function V.update(game,players,dt,items)
    V.elapsed=(V.elapsed or 0)+(dt or 0)
    local key=tostring(game.currentFile)..":"..tostring(game.scenario)..":"..tostring(game.release)
    if V.cacheKey~=key then
        V.cacheKey=key; V.map=nil; V.er=nil; V.error=nil; V.floor=1; V.target=nil; V.follow=true; V.reset()
        -- Elimination and Showdown have no game map: Room View / Grid View.
        V.arena=Arena.isArena(game.scenario);V.arenaSeen={};V.arenaRoom=nil;V.arenaView=V.arenaView or "room"
        -- U.S. File 1 map files (mapNNNe.dat) equal the Japanese ones in rooms,
        -- floors and placements (2026-11-20), so the bundled jp1 maps serve both.
        if game.release=="us" and game.currentFile~=1 then V.error="U.S. maps are not enabled yet"
        else
            local ok,map,message=pcall(Data.load,game.currentFile,game.scenario,read)
            if ok then V.map,V.error=map,message else V.error="Map data is damaged in this build" end
            if V.map then
                local loaded,err=pcall(function()
                    V.fill=love.graphics.newImage(V.map.path.."-fill.png")
                    V.walls=love.graphics.newImage(V.map.path.."-walls.png")
                    V.quads={}
                    for i,r in ipairs(V.map.rooms) do
                        if r.w>0 and r.h>0 then V.quads[i]=love.graphics.newQuad(r.x,r.y,r.w,r.h,1024,V.map.height) end
                    end
                end)
                if not loaded then V.map=nil; V.error="Map artwork is missing from this build" end
                local code=V.map and V.map.path:match("(%d%d%d)$")
                V.er=V.map and ER[game.currentFile] and ER[game.currentFile][code] or nil
                for index,layers in pairs(V.er or {}) do
                    local floor=V.map.floors[index]
                    for _,layer in ipairs(layers) do
                        if layer.fullBounds then
                            floor.fullArtwork=true
                            floor.minX=-layer.tx/layer.sx;floor.minY=-layer.ty/layer.sy
                            floor.maxX=(layer.w/layer.scale-layer.tx)/layer.sx
                            floor.maxY=(layer.h/layer.scale-layer.ty)/layer.sy
                        end
                    end
                end
            end
        end
    end
    V.players=players
    -- YOU comes from the game's local-slot byte (0-based, frames + 5). The
    -- first active record is not the local player online (slot order follows
    -- the room, not the console), so it is only a fallback without that byte.
    V.you=nil
    local slot=tonumber(game.localSlot)
    if slot and slot>=0 and slot<=3 and players[slot+1] and players[slot+1].enabled then V.you=slot+1
    else for i=1,4 do if active(players[i]) then V.you=i; break end end end
    if not active(players[V.target or 0]) then
        V.target=nil
        if active(players[V.you or 0]) then V.target=V.you
        else for i=1,4 do if active(players[i]) then V.target=i; break end end end
    end
    if V.map and V.follow and V.target then
        local choices=V.candidates(V.map,players[V.target])
        local selected=contains(choices,V.floor) and V.floor or choices[1]
        if selected and V.floor~=selected then V.floor=selected;V.panX=0;V.panY=0;V.frozenCenter=nil;V.tabsManual=false end
    end
    local ownFloors=V.map and V.candidates(V.map,players[V.you or 0]) or {}
    Session.update(game,players,V.you,items,#ownFloors==1 and ownFloors[1] or nil)
    V.gasRooms=V.gas(game)
    if V.arena then
        -- Rooms YOU has entered are known even with no enemy entries (count 0).
        if V.arenaFrames and (tonumber(game.frames) or 0)+60<V.arenaFrames then V.arenaSeen={} end
        V.arenaFrames=tonumber(game.frames) or 0
        local you=players[V.you or 0]
        if active(you) then V.arenaSeen[you.roomID]=true end
    end
    game.mapview={mode=V.mode,following=V.follow,floor=V.floor,target=V.target or 0,available=V.map~=nil}
end
local Layout=require "MapPresentationLayout"
-- Evil Resource artwork fitted to the game's own map coordinates (generated by
-- tools-n-shit/research/fit-er-maps.py). Floors listed there draw Evil Resource
-- layers; the others keep the game's own map art.
V.erImages={}
V.erQuads={}
local function erImage(path)
    if V.erImages[path]==nil then
        local ok,img=pcall(love.graphics.newImage,path)
        V.erImages[path]=ok and img or false
    end
    return V.erImages[path] or nil
end
-- Ear-clipping triangulation in plain Lua, so concave Evil Resource room
-- outlines can be filled through any backend (including the Decky bridge).
local function triangulate(points)
    local n=#points/2;local idx={}
    if n<3 then return {} end
    local area=0
    for i=1,n do local j=i%n+1;area=area+points[2*i-1]*points[2*j]-points[2*j-1]*points[2*i] end
    for i=1,n do idx[i]=area>0 and i or n-i+1 end
    local function pt(k) return points[2*k-1],points[2*k] end
    local tris,guard={},0
    while #idx>3 and guard<10000 do
        guard=guard+1
        local found=false
        for i=1,#idx do
            local a,b,c=idx[(i-2)%#idx+1],idx[i],idx[i%#idx+1]
            local ax,ay=pt(a);local bx,by=pt(b);local cx,cy=pt(c)
            if (bx-ax)*(cy-ay)-(by-ay)*(cx-ax)>0 then
                local inside=false
                for _,k in ipairs(idx) do
                    if k~=a and k~=b and k~=c then
                        local px,py=pt(k)
                        local d1=(bx-ax)*(py-ay)-(by-ay)*(px-ax)
                        local d2=(cx-bx)*(py-by)-(cy-by)*(px-bx)
                        local d3=(ax-cx)*(py-cy)-(ay-cy)*(px-cx)
                        if d1>=0 and d2>=0 and d3>=0 then inside=true;break end
                    end
                end
                if not inside then
                    tris[#tris+1]={ax,ay,bx,by,cx,cy};table.remove(idx,i);found=true;break
                end
            end
        end
        if not found then break end
    end
    if #idx==3 then
        local ax,ay=pt(idx[1]);local bx,by=pt(idx[2]);local cx,cy=pt(idx[3])
        tris[#tris+1]={ax,ay,bx,by,cx,cy}
    end
    return tris
end
V.triangulate=triangulate
-- Immutable fitted room geometry is shared across frames; triangulate once.
local fittedGeometry=setmetatable({}, {__mode="k"})
local function geometry(poly,layer)
    local cached=fittedGeometry[poly]
    if cached then return cached.points,cached.triangles end
    local pts={}
    for k=1,#poly,2 do pts[k]=(poly[k]-layer.tx)/layer.sx;pts[k+1]=(poly[k+1]-layer.ty)/layer.sy end
    local tris=triangulate(pts);fittedGeometry[poly]={points=pts,triangles=tris}
    return pts,tris
end
-- Marker containment ------------------------------------------------------
local function insidePolygon(pts,x,y)
    local inside=false;local n=#pts/2;local j=n
    for i=1,n do
        local xi,yi,xj,yj=pts[2*i-1],pts[2*i],pts[2*j-1],pts[2*j]
        if (yi>y)~=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi then inside=not inside end
        j=i
    end
    return inside
end
local function nearestOnPolygon(pts,x,y)
    local bx,by,best=nil,nil,math.huge;local n=#pts/2
    for i=1,n do
        local j=i%n+1
        local ax,ay,cx,cy=pts[2*i-1],pts[2*i],pts[2*j-1],pts[2*j]
        local dx,dy=cx-ax,cy-ay;local len=dx*dx+dy*dy
        local t=len>0 and math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/len)) or 0
        local px,py=ax+t*dx,ay+t*dy;local d=(px-x)^2+(py-y)^2
        if d<best then bx,by,best=px,py,d end
    end
    return bx,by,best
end
-- Keep a marker inside its room's drawn shape: the Evil Resource outline when
-- the shown floor has one, otherwise the game's map piece. A point outside
-- (doorways, the Desperate Times Front Gate crowd, items by walls) moves to the
-- nearest point inside, margin floor pixels from the border where the room is
-- wide enough. Returns the point unchanged when the room has no shape here.
function V.clampToRoom(map,floor,room,x,y,margin)
    local f=map and map.floors[floor]
    if not (f and finite(x) and finite(y)) then return x,y end
    local shapes={}
    for _,layer in ipairs(map==V.map and V.er and V.er[floor] or {}) do
        for _,poly in ipairs(layer.rooms[room] or {}) do shapes[#shapes+1]=(geometry(poly,layer)) end
    end
    if #shapes==0 then
        for _,p in ipairs(f.places) do
            local r=map.rooms[p.record]
            if r.id==room and r.w>0 and r.h>0 then shapes[#shapes+1]={p.x,p.y,p.x+r.w,p.y,p.x+r.w,p.y+r.h,p.x,p.y+r.h} end
        end
    end
    if #shapes==0 then return x,y end
    margin=margin or 2
    local function inside(px,py)
        for _,pts in ipairs(shapes) do if insidePolygon(pts,px,py) then return true end end
        return false
    end
    local function border(px,py)
        local d=math.huge
        for _,pts in ipairs(shapes) do local _,_,dk=nearestOnPolygon(pts,px,py);d=math.min(d,dk) end
        return math.sqrt(d)
    end
    -- Inside and clear of the border: unchanged.
    if inside(x,y) and border(x,y)>=margin then return x,y end
    local bx,by,best
    for _,pts in ipairs(shapes) do
        local px,py,d=nearestOnPolygon(pts,x,y)
        if px and d<(best or math.huge) then bx,by,best=px,py,d end
    end
    if inside(x,y) then bx,by=x,y end
    -- Step inward from there: of eight directions take the inside point that is
    -- furthest from the border, shrinking the step for narrow rooms.
    for _,m in ipairs{margin,margin/2,margin/4} do
        local cx,cy,clear=nil,nil,-1
        for a=0,7 do
            local px,py=bx+m*math.cos(a*math.pi/4),by+m*math.sin(a*math.pi/4)
            if inside(px,py) then
                local d=border(px,py)
                if d>clear then cx,cy,clear=px,py,d end
            end
        end
        if cx and clear>=m*.7 then return cx,cy end
        if cx and m==margin/4 then return cx,cy end
    end
    return bx,by
end
local SP=require "SPTracking"
local white={1,1,1,1}
local yellow={232/255,230/255,160/255,1}
local muted={138/255,143/255,153/255,1}
local function text(value,b,color)
    local g=love.graphics
    g.setFont(MapFonts and MapFonts[b.size or 11] or MiniFont)
    local plain=value
    if type(value)=="table" then
        local parts={};for _,part in ipairs(value) do if type(part)=="string" then parts[#parts+1]=part end end
        plain=table.concat(parts)
    else value=tostring(value or "");plain=value end
    local width=b.w
    local scale=b.fit and math.min(1,width/math.max(1,g.getFont():getWidth(value))) or 1
    g.push();g.translate(b.x,b.y);g.scale(scale,1)
    local ink=color or b.color or white
    if (ink[1]+ink[2]+ink[3])>.9 then g.setColor(0,0,0,1);g.printf(plain,1,1,width/scale,b.align or "left") end
    g.setColor(unpack(color or b.color or white));g.printf(value,0,0,width/scale,b.align or "left")
    g.pop()
end
local function rect(b,color,mode)
    love.graphics.setColor(unpack(color or b.color or white))
    love.graphics.rectangle(mode or "fill",b.x,b.y,b.w,b.h)
end
local function sprite(name,b,atlas,tint)
    atlas=atlas or MapUIAtlas or UIAtlas
    local q=atlas.quads[name]
    if not q then return end
    local _,_,w,h=q:getViewport()
    love.graphics.setColor(unpack(tint or white))
    atlas:draw(name,b.x,b.y,0,b.w/w,b.h/h)
end
local function plate(fill,frame,name)
    rect(fill); sprite(name or "title bar",frame)
end
local function hit(b,action)
    V.hits[#V.hits+1]={x=b.x,y=b.y,w=b.w,h=b.h,action=action}
end
-- Following a player jumps straight to their floor, so a tap on a card or
-- portrait shows where they are at once instead of on the next update.
local function follow(i)
    V.target=i; V.follow=true; V.panX=0;V.panY=0;V.frozenCenter=nil
    local p=V.players and V.players[i]
    if V.map and p then
        local choices=V.candidates(V.map,p)
        if #choices>0 and not contains(choices,V.floor) then V.floor=choices[1] end
    end
end
local function icon(player,x,y,size)
    local tint=Effects.adlib(player,V.elapsed) and {0,1,.15,1} or white
    if Effects.adlib(player,V.elapsed) then
        love.graphics.setColor(0,1,.15,.3+.3*Effects.pulse(V.elapsed))
        love.graphics.circle("fill",x+size/2,y+size/2,size*.55)
    end
    sprite("icon"..tostring(player.type),{x=x,y=y,w=size,h=size},nil,tint)
end
local function shortFloor(name)
    if name=="Area near the zoo" then return "GF" end
    if name=="Raccoon City Zoo" then return "Zoo" end
    if name:find("ROOFTOP") or name=="Rooftop" then return "RF" end
    if name=="Police station basement" then return "B1" end
    return name:match("([B]?%d+F)$") or name:gsub("Area ","A")
end
-- Repeated records are height bands of the same named floor. Tabs select the
-- named floor; room membership still chooses its band without guessing height.
function V.floorGroups()
    local groups={}
    if not V.map then return groups end
    for i,f in ipairs(V.map.floors) do
        local group
        for _,entry in ipairs(groups) do if entry.name==f.name then group=entry; break end end
        if not group then group={name=f.name,indices={},label=shortFloor(f.name)}; groups[#groups+1]=group end
        group.indices[#group.indices+1]=i
    end
    return groups
end
function V.dimensions()
    if V.mode==1 then return 760,740 end
    if love.isDecky then return 390,844 end
    return 300,740
end
local function clip(b,l)
    local w,h=love.window.getMode()
    love.graphics.setScissor(b.x*w/l.width,b.y*h/l.height,b.w*w/l.width,b.h*h/l.height)
end
local function cropCard(i,b,sx,sy,sw,sh,l,portraitOnly)
    local g=love.graphics
    clip(b,l);g.setColor(1,1,1,1)
    g.push();g.translate(b.x,b.y);g.scale(b.w/sw,b.h/sh);g.translate(-sx,-sy)
    PlayerCards[i]:draw(0,0,portraitOnly)
    g.pop();g.setScissor()
end
local function offset(b,dy)
    return {x=b.x,y=b.y+dy,w=b.w,h=b.h,size=b.size,align=b.align,color=b.color}
end
local function cardFloor(p)
    if not V.map then return "" end
    local choices=V.candidates(V.map,p)
    local f=V.map.floors[contains(choices,V.floor) and V.floor or choices[1]]
    return f and shortFloor(f.name) or ""
end
function V.cardFloorVisible(game,p)
    if game.scenario=="wild things" then return false end
    if game.scenario=="flashback" and p then
        local room=p.roomID or 0
        if (room>=1 and room<=5) or room==29 or room==30 then return false end
    end
    return true
end
local function compactCards(l,game,players)
    local g=love.graphics
    for i,b in ipairs(l.cards) do
        local p=players[i];local dy=b.y-l.cards[1].y
        rect(b,{0,0,0,1})
        Effects.background(p,b.x,b.y,b.w,b.h,V.elapsed)
        if p and p.enabled then
            cropCard(i,offset(l.status,dy),0,2,112,36,l)
            local inv=offset(l.inventory,dy)
            -- Crop the whole inventory frame PlayerCard draws at (0,37): Yoko,
            -- David and Cindy use "invDouble" (210 px wide); everyone else uses
            -- "invSingle" (0-112) plus "invSpecial" at x 110 (62 px), ending at 172.
            local extended=p.type=="Yoko" or p.type=="David" or p.type=="Cindy"
            local sourceWidth=extended and 210 or 172
            local scale=math.min(inv.h/108,(l.bust.x-inv.x-4)/sourceWidth)
            local full={x=inv.x,y=inv.y+(inv.h-108*scale)/2,w=sourceWidth*scale,h=108*scale}
            cropCard(i,full,0,37,sourceWidth,108,l)
            local bust=offset(l.bust,dy)
            cropCard(i,bust,176,26,124,118,l,true)

            local showFloor=V.cardFloorVisible(game,p)
            if showFloor then text(cardFloor(p),offset(l.cardFloor,dy),yellow) end
            local room=offset(l.cardRoom,dy)
            if not showFloor then room.x=l.cardFloor.x end
            room.w=l.inventory.x-room.x-4
            text(GetRoomName(game.scenario,p.roomID),room)
            if V.gasRooms[p.roomID] then
                rect(b,{1,.85,0,.08});g.setLineWidth(2);rect({x=1,y=b.y+1,w=b.w-2,h=b.h-2},{1,.85,0,.75},"line")
            elseif V.follow and V.target==i then
                local c=V.colors[i];g.setLineWidth(1);rect({x=.5,y=b.y+.5,w=b.w-1,h=b.h-1},{c[1],c[2],c[3],.4},"line")
            end
        end
        rect({x=0,y=b.y+b.h-1,w=b.w,h=1},{.102,.165,.282,1})
        hit(b,function() follow(i) end)
    end
end
local function clock(game,b,sp)
    if (game.frames or 0)<=0 then return end
    local g=love.graphics
    local radar=type(sp)=="table" and sp.available==true
    local radarWidth=radar and 70 or 0
    if radar then
        -- Compass direction stays relative to the local player; reserve its
        -- full glow bounds (-9.2..27.2) without extra caption text.
        g.push();g.translate(b.x+3,b.y+10)
        SP.draw(sp,-141,0,DefaultFont);g.pop()
    end
    local value,warning=Effects.clockText(game)
    local width=b.w-radarWidth
    local scale=math.min(width/math.max(1,TimeFont:getWidth(value)),22/TimeFont:getHeight())
    g.push();g.translate(b.x+radarWidth,b.y+8);g.scale(scale,scale)
    g.setFont(TimeFont)
    Effects.drawClock(function(dx,dy) g.printf(value,dx,dy,width/scale,"right") end,warning,V.elapsed)
    g.pop()
end
local function gasTimer(game,b)
    if (game.fighttime2 or 0)==0 then return end
    local g=love.graphics
    g.setColor(1,1,1,1)
    g.push();g.translate(b.x,b.y);g.scale(b.w/42,b.h/45)
    ItemIcons:draw("2/11511",0,0,0,.7)
    text(Time2string3(game.gastime or 0),{x=0,y=29,w=42,size=11,align="center"},{1,1,0,1})
    g.pop()
end
-- Japanese titles as printed on the game's scenario tiles (assets/ui.png).
local scenarioTitles={
    ["outbreak"]="発生 outbreak",["below freezing point"]="零下 below freezing point",
    ["the hive"]="巣窟 the hive",["hellfire"]="獄炎 hellfire",
    ["decisions,decisions"]="決意 decisions, decisions",
    ["wild things"]="咆哮 wild things",["underbelly"]="異界 underbelly",
    ["flashback"]="記憶 flashback",["desperate times"]="死守 desperate times",
    ["end of the road"]="突破 end of the road",
    ["elimination 1"]="殲滅1 elimination 1",["elimination 2"]="殲滅2 elimination 2",
    ["elimination 3"]="殲滅3 elimination 3",
    ["showdown 1"]="対峙1 showdown 1",["showdown 2"]="対峙2 showdown 2",["showdown 3"]="対峙3 showdown 3",
}
-- Session line for the cards-beside-map view: local character, scenario,
-- difficulty, then room options. game.nightmare and game.infinity are shown
-- only when a reader supplies them; none does yet.
function V.sessionText(game,you)
    local parts={}
    if you and you.enabled and (you.name or you.type) then parts[#parts+1]=tostring(you.name or you.type):upper() end
    if game.scenario and game.scenario~="" then parts[#parts+1]=scenarioTitles[game.scenario] or game.scenario end
    if game.difficulty and game.difficulty~="" then parts[#parts+1]=tostring(game.difficulty):upper() end
    if game.nightmare==true then parts[#parts+1]="NIGHTMARE" end
    if game.infinity==true then parts[#parts+1]="INFINITY" end
    return table.concat(parts," // ")
end
local sessionGray={.72,.72,.74,1}
-- Gray text with a full black outline, so it stays readable on gray art too.
-- Returns the height used (0 when there is nothing to show).
function V.drawSessionLine(game,you,b)
    local value=V.sessionText(game,you)
    if value=="" then return 0 end
    local g=love.graphics
    g.setFont(MapFonts and MapFonts[b.size or 13] or MiniFont)
    for _,o in ipairs{{-1,0},{1,0},{0,-1},{0,1},{1,1}} do
        g.setColor(0,0,0,1);g.printf(value,b.x+o[1],b.y+o[2],b.w,"left")
    end
    g.setColor(unpack(sessionGray));g.printf(value,b.x,b.y,b.w,"left")
    local _,lines=g.getFont():getWrap(value,b.w)
    return #lines*g.getFont():getHeight()
end
local function scenario(l,game)
    local g=love.graphics;local b=l.information
    if l.tile then sprite(game.scenario,l.tile) end
    if V.mode==1 then
        -- The cards on the left already show the clock, SP radar, item sets and
        -- escape/medal readouts; this panel keeps the session line, the
        -- Desperate Times fight/garage/gas readout and puzzle hints.
        local used=V.drawSessionLine(game,V.players and V.players[V.you or 0],{x=b.x,y=b.y+1,w=b.w,size=13})
        if used>0 then used=used+5 end
        local lines={}
        if game.scenario=="desperate times" then
            local ft=game.fighttime2==65535 and game.fighttime or game.fighttime2
            if game.fighttime2==0 then lines[#lines+1]=tostring(game.killedzombies or 0).." kills"
            else
                lines[#lines+1]="Fight "..Time2string3(ft or 0).."   Garage "..Time2string3(game.garagetime or 0).."   Gas "..Time2string3(game.gastime or 0)
            end
            local rooms={};for id in pairs(V.gasRooms) do rooms[#rooms+1]=GetRoomName(game.scenario,id) end
            table.sort(rooms);if #rooms>0 then lines[#lines+1]="GAS: "..table.concat(rooms,", ") end
        end
        local info=table.concat(lines,"\n")
        local hint=V.hint and V.hint~="" and Hints.text(game,V.hint) or nil
        local content=info
        if hint then
            content={white,info~="" and info.."\n" or ""}
            for _,part in ipairs(hint) do content[#content+1]=part end
        end
        text(content,{x=b.x,y=b.y+used,w=b.w,h=b.h-used,size=13})
        return
    end
    local clockWidth=math.min(222,b.w*.68)
    local sp=SP.forMap(SP.state(game),V.players and V.players[V.you or 0])
    clock(game,{x=b.x,y=b.y,w=clockWidth,h=22},sp)
    local setsX=b.x+clockWidth+4
    local itemNumbers=tostring((game.itemrandom or 0)+1).."\n"..tostring(math.floor((game.itemrandom2 or 0)/10)+1)
    text(itemNumbers,{x=setsX+4,y=b.y+1,w=23,size=14,align="center"},yellow)
    if V.setLetter then text(V.setLetter,{x=setsX+39,y=b.y+12,w=24,size=12,align="center"},yellow) end
    local lines={}
    if game.scenario=="desperate times" then
        local ft=game.fighttime2==65535 and game.fighttime or game.fighttime2
        if game.fighttime2==0 then lines[#lines+1]=tostring(game.killedzombies or 0).." kills"
        else
            lines[#lines+1]="Fight "..Time2string3(ft or 0).."   Garage "..Time2string3(game.garagetime or 0).."   Gas "..Time2string3(game.gastime or 0)
        end
        local rooms={};for id in pairs(V.gasRooms) do rooms[#rooms+1]=GetRoomName(game.scenario,id) end
        table.sort(rooms);if #rooms>0 then lines[#lines+1]="GAS: "..table.concat(rooms,", ") end
    elseif game.scenario=="wild things" then
        lines[#lines+1]=tostring(game.coin or 0).." medals"
        if (game.wttime or 0)>0 and game.wttime~=65535 then lines[#lines+1]="Escape "..Time2string3(game.wttime) end
    elseif (game.escapetime or 0)>0 and game.escapetime~=65535 then
        lines[#lines+1]="Escape "..Time2string3(game.escapetime)
    end
    local info=table.concat(lines,"\n")
    local hint=V.hint and V.hint~="" and Hints.text(game,V.hint) or nil
    local content=info
    if hint then
        content={white,info~="" and info.."\n" or ""}
        for _,part in ipairs(hint) do content[#content+1]=part end
    end
    local hintY=39
    text(content,{x=b.x,y=b.y+hintY,w=b.w,h=b.h-hintY,size=V.mode==1 and 13 or 11})
end
local function drawMap(l,game,players,enemies,items)
    local g=love.graphics;local vp=l.viewport;local f=V.map and V.map.floors[V.floor]
    V.viewport=vp
    rect(vp,{0,0,0,1})
    if not f then text(V.error or "Open a Japanese scenario to use the map",{x=vp.x+12,y=vp.y+20,w=vp.w-24,size=13});return end
    clip(vp,l)
    local fit=math.min((vp.w-8)/math.max(1,f.maxX-f.minX),(vp.h-48)/math.max(1,f.maxY-f.minY))
    if V.mode==1 and l.art then fit=fit*l.art.w/(vp.w-8) end
    local scale=fit*V.zoom
    local cx,cy=(f.minX+f.maxX)/2,(f.minY+f.maxY)/2
    if not V.follow and V.frozenCenter then cx,cy=unpack(V.frozenCenter) end
    local player=players[V.target or 0]
    if V.follow and player and V.zoom>1 then
        local px,py=V.marker(V.map,V.floor,player)
        if px then cx,cy=px,py end
    end
    V.drawScale=scale;V.visibleCenter={cx,cy}
    -- Markers stay about 9 screen pixels inside their room's border.
    V.markerMargin=9/math.max(.01,scale)
    local ox,oy=vp.x+vp.w/2+V.panX,vp.y+vp.h/2+V.panY
    if g.mapBegin then
        local continuity=table.concat({V.cacheKey,V.floor,V.mode,vp.w,V.zoom,tostring(V.follow),V.panX,V.panY},":")
        g.mapBegin(vp.x,vp.y,vp.w,vp.h,V.panX,V.panY,ox-cx*scale,oy-cy*scale,continuity)
    end
    g.push();g.translate(ox,oy);g.scale(scale);g.translate(-cx,-cy)
    local layers=V.er and V.er[V.floor]
    local gasOutlines={}
    local pulse=.5+.5*math.sin((V.elapsed or 0)*math.pi)
    V.erDrawn=0
    -- Room tint: YOU's room red, other occupied rooms light blue, gas yellow.
    -- With Evil Resource layers the tint follows their room outline.
    for _,p in ipairs(f.places) do
        local r=V.map.rooms[p.record];local color
        if V.gasRooms[r.id] then color={1,.85,0,.28+.18*pulse}
        elseif active(players[V.you or 0]) and players[V.you].roomID==r.id then color={1,0,0,.25}
        else
            for i=1,4 do
                if active(players[i]) and players[i].roomID==r.id then
                    color={115/255,178/255,249/255,.25};break
                end
            end
        end
        if not color and Session.visited[r.id] then color={.4,1,.55,.22} end
        if color then
            local drawn=false
            for _,layer in ipairs(layers or {}) do
                for _,poly in ipairs(layer.rooms[r.id] or {}) do
                    local pts,tris=geometry(poly,layer)
                    if V.gasRooms[r.id] then gasOutlines[#gasOutlines+1]=pts end
                    g.setColor(unpack(color))
                    for _,t in ipairs(tris) do g.polygon("fill",t) end
                    drawn=true
                end
            end
            if not drawn and V.quads[p.record] then g.setColor(unpack(color));g.draw(V.fill,V.quads[p.record],p.x,p.y) end
        end
    end
    if layers and #layers>0 then
        -- Evil Resource art, placed through the fitted conversion (PNG pixels are
        -- Evil Resource pixels times layer.scale).
        for _,layer in ipairs(layers) do
            local img=erImage(layer.image)
            if img then
                -- The Decky bridge requires the explicit quad overload of draw.
                local quad=V.erQuads[layer.image]
                if not quad then
                    quad=g.newQuad(0,0,layer.w,layer.h,layer.w,layer.h)
                    V.erQuads[layer.image]=quad
                end
                g.setColor(1,1,1,1)
                g.draw(img,quad,-layer.tx/layer.sx,-layer.ty/layer.sy,0,1/(layer.sx*layer.scale),1/(layer.sy*layer.scale))
                V.erDrawn=V.erDrawn+1
            end
        end
    end
    if V.erDrawn==0 then
        for _,p in ipairs(f.places) do
            if V.quads[p.record] then g.setColor(43/255,116/255,211/255,1);g.draw(V.walls,V.quads[p.record],p.x,p.y) end
        end
    end
    -- Layer soft yellow outlines behind a bright edge; widths stay constant
    -- on screen as the map zooms. The room fill and halo pulse together.
    for _,pts in ipairs(gasOutlines) do
        g.setLineWidth(8/scale);g.setColor(1,.85,0,.08+.08*pulse);g.polygon("line",pts)
        g.setLineWidth(4/scale);g.setColor(1,.85,0,.16+.12*pulse);g.polygon("line",pts)
        g.setLineWidth(1.25/scale);g.setColor(1,1,.35,.7+.3*pulse);g.polygon("line",pts)
    end
    g.setLineWidth(1)
    g.pop()
    -- Scanlines and slot-coloured full-viewport crosshair are in the board.
    for y=vp.y,vp.y+vp.h,3 do rect({x=vp.x,y=y,w=vp.w,h=1},{0,0,0,.22}) end
    -- The cyan guide follows recorded maze movement. It stays beneath players,
    -- items and enemy HP, with constant screen width at every zoom level.
    V.routeDrawn=0
    for _,layer in ipairs(layers or {}) do
        local route=layer.route
        if route then
            local travelled=0
            local function point(i)
                return ox+((route[i]-layer.tx)/layer.sx-cx)*scale,
                       oy+((route[i+1]-layer.ty)/layer.sy-cy)*scale
            end
            for i=1,#route-2,2 do
                local ax,ay=point(i);local bx,by=point(i+2)
                local dx,dy=bx-ax,by-ay;local length=math.sqrt(dx*dx+dy*dy)
                if length>0 then
                    local nx,ny=-dy/length,dx/length
                    local function stroke(width,color)
                        g.setColor(unpack(color));g.polygon("fill",{ax+nx*width,ay+ny*width,bx+nx*width,by+ny*width,bx-nx*width,by-ny*width,ax-nx*width,ay-ny*width})
                    end
                    stroke(2.6,{0,0,0,.8});stroke(1.15,{0,.95,1,.95})
                    travelled=travelled+length
                    if travelled>=50 or i==#route-2 then
                        g.setColor(0,.95,1,1)
                        g.polygon("fill",{bx+dx/length*5,by+dy/length*5,bx-dx/length*5+nx*4,by-dy/length*5+ny*4,bx-dx/length*5-nx*4,by-dy/length*5-ny*4})
                        travelled=0
                    end
                end
            end
            local ex,ey=point(#route-1)
            text("EXIT",{x=math.max(vp.x+4,math.min(ex-20,vp.x+vp.w-44)),y=math.max(vp.y+4,math.min(ey-20,vp.y+vp.h-16)),w=40,size=11,align="center"},{0,.95,1,1})
            V.routeDrawn=V.routeDrawn+1
        end
    end
    -- Observed room items persist for this run. Scenario items come from the
    -- already-refreshed global pickup table and remain visible until taken.
    V.itemsDrawn=0
    V.itemHits={}
    local function itemHit(x,y,name)
        V.itemHits[#V.itemHits+1]={x=x-11,y=y-11,w=22,h=22,name=name}
    end
    V.spDrawn=0
    local ordinaryItems,scenarioItems={},{}
    for _,it in pairs(Session.items) do
        local list=(it.type or 0)>=10000 and scenarioItems or ordinaryItems
        list[#list+1]=it
    end
    local spItems={};for _,it in pairs(Session.spItems) do spItems[#spItems+1]=it end
    local function byId(a,b) return (a.id or 0)<(b.id or 0) end
    table.sort(ordinaryItems,byId);table.sort(scenarioItems,byId);table.sort(spItems,byId)
    local function drawItem(it)
        local ix,iy=V.itemMarker(V.map,V.floor,it.roomID,it)
        if ix then
            local x,y=ox+(ix-cx)*scale,oy+(iy-cy)*scale
            local key=(it.type or 0)>=10000
            rect({x=x-10,y=y-10,w=20,h=20},key and {1,.38,0,.95} or {0,0,0,.7})
            g.setColor(1,1,1,1)
            ItemIcons:draw(tostring(game.currentFile).."/"..tostring(it.type),x-8,y-8,0,16/48,16/48)
            V.itemsDrawn=V.itemsDrawn+1
            itemHit(x,y,Catalog.items[it.type] or ("Item "..tostring(it.type)))
        end
    end
    local function drawSP(it)
        local probe={id=it.id+1,type=0,count=1,positionX=it.positionX,positionY=it.positionY,height=it.height,floor=it.floor}
        local ix,iy=V.itemMarker(V.map,V.floor,it.roomID,probe)
        if ix then
            local x,y=ox+(ix-cx)*scale,oy+(iy-cy)*scale
            local entry=Catalog.sp[game.currentFile] and Catalog.sp[game.currentFile][it.id]
            local personal=entry and entry.owner~=nil
            g.setColor(0,0,0,.85);g.circle("fill",x,y,7)
            g.setColor(personal and .2 or .15,personal and .6 or 1,personal and 1 or .2,1)
            g.polygon("fill",{x,y-6,x+6,y,x,y+6,x-6,y})
            local label=entry and entry.name or ("SP "..it.id)
            if personal then label=label.." ("..entry.owner..")" end
            itemHit(x,y,label);V.spDrawn=V.spDrawn+1
        end
    end
    -- Enemies: small white diamonds with a dark edge, under the player markers.
    V.enemiesDrawn=0
    local enemyLabels={}
    for _,e in ipairs(enemies or {}) do
        local ex,ey=V.enemyMarker(V.map,V.floor,e)
        if ex then
            local x,y=ox+(ex-cx)*scale,oy+(ey-cy)*scale
            if V.isHazard(e) then
                -- Soft red glow behind an orange marker; no HP for traps.
                Effects.pulseColor("danger",V.elapsed,1,.08,.02,.45,.45)
                g.circle("fill",x,y,12);g.circle("fill",x,y,9)
                Effects.endPulse()
                g.setColor(0,0,0,.85);g.circle("fill",x,y,6.5)
                g.setColor(1,.55,.05,1);g.circle("fill",x,y,5)
            else
                g.setColor(0,0,0,.85);g.polygon("fill",{x,y-7,x+7,y,x,y+7,x-7,y})
                g.setColor(1,V.isBoss(e) and .05 or 1,V.isBoss(e) and .05 or 1,1);g.polygon("fill",{x,y-5,x+5,y,x,y+5,x-5,y})
                -- Remaining HP as a percentage beside the marker.
                local pct=math.floor(e.HP/e.maxHP*100+.5)
                enemyLabels[#enemyLabels+1]={value=pct.."%",x=x+7,y=y-15}
            end
            V.enemiesDrawn=V.enemiesDrawn+1
        end
    end
    local points={}
    for i=1,4 do
        local px,py,fallback=V.marker(V.map,V.floor,players[i])
        if px then points[i]={x=ox+(px-cx)*scale,y=oy+(py-cy)*scale,fallback=fallback} end
    end
    local labelContext=V.cacheKey..":"..V.floor
    if V.labelContext~=labelContext then V.labelHidden=nil;V.labelContext=labelContext end
    V.labelHidden=V.hiddenPlayerLabels(points,V.labelHidden)
    for i=1,4 do
        local point=points[i]
        if point then
            local x,y,fallback=point.x,point.y,point.fallback
            if g.actorBegin then g.actorBegin(i,x,y,V.cacheKey..":"..V.floor..":"..players[i].roomID) end
            local c=Effects.markerColor(players[i],V.colors[i],V.elapsed)
            local speaking=Effects.adlib(players[i],V.elapsed)
            if speaking then
                g.setColor(0,1,.15,.25+.35*Effects.pulse(V.elapsed));g.circle("fill",x,y,14)
            end
            if V.follow and i==V.target then
                rect({x=vp.x,y=y,w=vp.w,h=1},{c[1],c[2],c[3],.7})
                rect({x=x,y=vp.y,w=1,h=vp.h},{c[1],c[2],c[3],.7})
            end
            g.setColor(c[1],c[2],c[3],.15);g.circle("fill",x,y,speaking and 12 or 19)
            g.setColor(c[1],c[2],c[3],1);g.setLineWidth(1)
            if fallback then
                g.circle("line",x,y,11);icon(players[i],x-9,y-9,18)
            else
                -- The chevron points along the player's forward axis (map X/Y,
                -- y down like the map). Without a usable facing it stays upright.
                g.push();g.translate(x,y);g.rotate(V.heading(players[i]))
                g.polygon("fill",{0,-12,10,10,0,4,-10,10})
                g.pop()
            end
            if not V.labelHidden[i] then text(i==V.you and "YOU" or "P"..i,{x=x+12,y=y-24,w=35,size=13},c) end
            if g.actorEnd then g.actorEnd() end
        end
    end
    -- Foreground priority: players < regular items < SP < scenario items < HP.
    for _,it in ipairs(ordinaryItems) do drawItem(it) end
    for _,it in ipairs(spItems) do drawSP(it) end
    for _,it in ipairs(scenarioItems) do drawItem(it) end
    for _,label in ipairs(enemyLabels) do
        rect({x=label.x-1,y=label.y-1,w=29,h=13},{0,0,0,.8})
        text(label.value,{x=label.x,y=label.y,w=40,size=10},white)
    end
    if g.mapEnd then g.mapEnd() end
    g.setScissor()
    local hover=V.hover
    if hover then
        for i=#V.itemHits,1,-1 do
            local h=V.itemHits[i]
            if hover.x>=h.x and hover.x<h.x+h.w and hover.y>=h.y and hover.y<h.y+h.h then
                local width=math.min(vp.w-8,math.max(90,#h.name*6))
                local x=math.max(vp.x+4,math.min(hover.x+12,vp.x+vp.w-width-4))
                local y=math.max(vp.y+4,math.min(hover.y-25,vp.y+vp.h-24))
                rect({x=x,y=y,w=width,h=22},{.02,.04,.08,.96})
                text(h.name,{x=x+4,y=y+4,w=width-8,size=12,fit=true})
                break
            end
        end
    end
    if next(V.gasRooms) then
        local chip=l.gasChip or {x=vp.x+vp.w-46,y=vp.y+50,w=40,h=43,color={0,0,0,.75}}
        rect(chip);gasTimer(game,l.gasChipContent or chip)
    end
end
-- Elimination / Showdown ------------------------------------------------------
local enemyBlue={.35,.65,1,1}
local function roomLabel(game,id)
    local name=GetRoomName and GetRoomName(game.scenario,id)
    if type(name)~="string" or name=="" or id==0 then return "Room "..tostring(id) end
    return name
end
-- One room box: name, enemies left ("x 02", gray when none or unknown) and the
-- icons of players inside. A Danger/Down occupant makes it flash and glow red.
-- Rooms YOU has not entered are black; entered rooms are light green with dark
-- text (user request, 2026-11-21 recording notes).
local enteredFill={.50,.82,.54,1}
local enteredInk={0,0,0,1}
local enteredMuted={.16,.34,.19,1}
local enteredBlue={.02,.22,.72,1}
local function arenaBox(game,id,b,occupants,alive,known,current,entered)
    local g=love.graphics
    local alert=nil
    for _,i in ipairs(occupants) do alert=Effects.worst(alert,Effects.health(V.players[i])) end
    if alert then
        for n=3,1,-1 do
            Effects.pulseColor(alert,V.elapsed,1,.05,.05,.18*n/3+.1,.15)
            g.rectangle("fill",b.x-2*n,b.y-2*n,b.w+4*n,b.h+4*n,4+2*n,4+2*n)
        end
        Effects.endPulse()
    end
    rect(b,entered and enteredFill or {0,0,0,1})
    if alert then
        Effects.pulseColor(alert,V.elapsed,1,0,0,.55,.1);g.rectangle("fill",b.x,b.y,b.w,b.h);Effects.endPulse()
    end
    local ink,dim,blue=entered and enteredInk or white,entered and enteredMuted or muted,entered and enteredBlue or enemyBlue
    g.setLineWidth(current and 2 or 1)
    rect(b,current and {.95,.85,.35,1} or {.3,.45,.75,1},"line");g.setLineWidth(1)
    local size=b.w>=150 and 13 or (b.w>=95 and 11 or (b.w>=70 and 10 or 9))
    local font=MapFonts and MapFonts[size] or MiniFont
    local lineHeight=font:getHeight()
    local nameLines=b.h>=lineHeight*3+6 and 2 or 1
    local name=roomLabel(game,id)
    if nameLines==1 then text(name,{x=b.x+3,y=b.y+2,w=b.w-6,size=size,fit=true},ink)
    else
        g.setScissor(b.x+2,b.y+1,b.w-4,lineHeight*2+1)
        text(name,{x=b.x+3,y=b.y+2,w=b.w-6,size=size},ink);g.setScissor()
    end
    -- Enemies left, bottom left.
    local count=alive[id];local y=b.y+b.h-lineHeight-3
    local none=not known[id] or (count or 0)==0
    local d=math.max(3,lineHeight*.3);local cx,cy=b.x+4+d,y+lineHeight/2
    g.setColor(unpack(none and dim or blue))
    g.polygon("fill",{cx,cy-d,cx+d,cy,cx,cy+d,cx-d,cy})
    local value=known[id] and string.format("x %02d",math.min(99,count or 0)) or "x --"
    text(value,{x=cx+d+3,y=y,w=b.w/2,size=size},none and dim or ink)
    -- Players inside, bottom right.
    local iconSize=math.min(lineHeight+4,(b.w/2-4)/math.max(1,#occupants))
    local xx=b.x+b.w-3-#occupants*(iconSize+1)
    for _,i in ipairs(occupants) do icon(V.players[i],xx,b.y+b.h-iconSize-3,iconSize);xx=xx+iconSize+1 end
end
-- A straight connector as a filled quad (the Decky bridge has no line command).
local function segment(x1,y1,x2,y2,width)
    local len=math.sqrt((x2-x1)^2+(y2-y1)^2)
    if len<.5 then return end
    local nx,ny=-(y2-y1)/len*width/2,(x2-x1)/len*width/2
    love.graphics.polygon("fill",{x1+nx,y1+ny,x2+nx,y2+ny,x2-nx,y2-ny,x1-nx,y1-ny})
end
local function arrow(x1,y1,x2,y2,color)
    local g=love.graphics
    g.setColor(unpack(color));segment(x1,y1,x2,y2,2)
    local a=math.atan2(y2-y1,x2-x1);local s=8
    g.polygon("fill",{x2,y2,x2-s*math.cos(a-.45),y2-s*math.sin(a-.45),x2-s*math.cos(a+.45),y2-s*math.sin(a+.45)})
end
-- Point where the segment from a box centre toward (tx,ty) leaves the box.
local function edgePoint(b,tx,ty)
    local cx,cy=b.x+b.w/2,b.y+b.h/2;local dx,dy=tx-cx,ty-cy
    local t=math.min(dx~=0 and (b.w/2)/math.abs(dx) or math.huge,dy~=0 and (b.h/2)/math.abs(dy) or math.huge)
    return cx+dx*t,cy+dy*t
end
-- Room View art: the main-scenario map room each arena room reuses
-- (MapArena.sources), loaded once per map file and kept for the session.
V.arenaMaps={}
local function arenaSource(game,room)
    local src=Arena.sources[game.scenario] and Arena.sources[game.scenario][room]
    if not src then return end
    local key=src[1]..":"..src[2]
    if V.arenaMaps[key]==nil then
        V.arenaMaps[key]=false
        local name
        for _,e in ipairs(Data.scenarios[src[1]] or {}) do if e[1]==src[2] then name=e[2] end end
        local ok,map=pcall(Data.load,src[1],name,read)
        if ok and map then
            local loaded=pcall(function()
                map.fillImage=love.graphics.newImage(map.path.."-fill.png")
                map.wallImage=love.graphics.newImage(map.path.."-walls.png")
                map.quads={}
                for i,r in ipairs(map.rooms) do
                    if r.w>0 and r.h>0 then map.quads[i]=love.graphics.newQuad(r.x,r.y,r.w,r.h,1024,map.height) end
                end
            end)
            if loaded then V.arenaMaps[key]=map end
        end
    end
    local map=V.arenaMaps[key]
    local f=map and map.floors[src[4]]
    if not f then return end
    for _,p in ipairs(f.places) do
        if map.rooms[p.record].id==src[3] and map.quads[p.record] then return map,f,p,src end
    end
end
V.arenaSource=arenaSource
-- Room View: the room drawn from its source map with live players, enemies and
-- room items; each neighbouring room sits outside it as a box, with an arrow from
-- the door the run recorded (MapArena.doors) or, without one, from the room edge
-- in the direction the room lies on the diagram. Without source art the room is
-- a box as well.
local function drawRoomView(l,game,players,enemies,graph,room,vp,box,alive,known,occupants)
    local g=love.graphics
    local list=graph and Arena.neighbours(graph,room) or {}
    local nw,nh=math.min(vp.w*.27,124),46
    local map,f,p,src=arenaSource(game,room)
    local doors=Arena.doors[game.scenario] and Arena.doors[game.scenario][room] or {}
    local here=graph and graph.cells[room]
    -- Which side of the room each neighbour box goes on: nearest side to its
    -- door (room-relative), or toward the room's direction on the diagram.
    local r=map and map.rooms[p.record]
    local sides={top={},bottom={},left={},right={}}
    local entries={}
    for n,id in ipairs(list) do
        local u,v,door
        if doors[id] and map then
            local px,py=Data.position(f,doors[id][1],doors[id][2])
            u,v=(px-p.x)/r.w,(py-p.y)/r.h;door=doors[id]
        else
            local c=graph.cells[id]
            local a=here and c and math.atan2(c[2]-here[2],c[1]-here[1]) or (n/#list*2*math.pi)
            u,v=.5+math.cos(a)*10,.5+math.sin(a)*10
        end
        local side,best="top",v
        if 1-v<best then side,best="bottom",1-v end
        if u<best then side,best="left",u end
        if 1-u<best then side,best="right",1-u end
        local e={id=id,u=math.max(0,math.min(1,u)),v=math.max(0,math.min(1,v)),door=door,side=side}
        entries[#entries+1]=e;local l2=sides[side];l2[#l2+1]=e
    end
    -- Room area: margins only on sides that hold boxes; the bottom strip stays
    -- free for the enemy count and the FOLLOW button.
    local left=#sides.left>0 and nw+16 or 8
    local right=#sides.right>0 and nw+16 or 8
    local top=#sides.top>0 and nh+16 or 8
    local bottom=(#sides.bottom>0 and nh+16 or 8)+34
    local area={x=vp.x+left,y=vp.y+top,w=vp.w-left-right,h=vp.h-top-bottom}
    local cx,cy=area.x+area.w/2,area.y+area.h/2
    local main,frame,toScreen,scale
    V.roomArtDrawn=false
    if map then
        -- main is the fitted room frame the neighbour boxes sit around; zoom and
        -- pan (+/-, wheel, drag) magnify only the room drawing inside that frame, about
        -- the room centre or, zoomed in while following, the followed player.
        local fitScale=math.min(area.w/r.w,area.h/r.h)
        scale=fitScale*V.zoom
        main={x=cx-r.w/2*fitScale,y=cy-r.h/2*fitScale,w=r.w*fitScale,h=r.h*fitScale}
        frame={x=main.x-8,y=main.y-8,w=main.w+16,h=main.h+16}
        local mx,my=p.x+r.w/2,p.y+r.h/2
        local target=players[V.target or 0]
        if not V.follow and V.frozenCenter and V.frozenCenter[3]==room then mx,my=V.frozenCenter[1],V.frozenCenter[2]
        elseif V.follow and V.zoom>1 and active(target) and target.roomID==room and finite(target.positionX) and finite(target.positionY) then
            mx,my=Data.position(f,target.positionX,target.positionY)
        end
        V.visibleCenter={mx,my,room}
        local ox,oy=cx+V.panX-mx*scale,cy+V.panY-my*scale
        toScreen=function(x,z,margin)
            if not (finite(x) and finite(z)) then return end
            local px,py=Data.position(f,x,z)
            px,py=V.clampToRoom(map,src[4],src[3],px,py,(margin or 9)/scale)
            return ox+px*scale,oy+py*scale
        end
        local alert=nil
        for _,i in ipairs(occupants[room] or {}) do alert=Effects.worst(alert,Effects.health(players[i])) end
        clip(frame,l)
        g.push();g.translate(ox,oy);g.scale(scale)
        if alert then Effects.pulseColor(alert,V.elapsed,1,0,0,.55,.2) else g.setColor(115/255,178/255,249/255,.22) end
        g.draw(map.fillImage,map.quads[p.record],p.x,p.y)
        if alert then Effects.endPulse() end
        g.setColor(43/255,116/255,211/255,1);g.draw(map.wallImage,map.quads[p.record],p.x,p.y)
        g.pop()
        g.setScissor()
        V.roomArtDrawn=true
    else
        local cw,ch=math.min(area.w,220),math.min(area.h,130)
        main={x=cx-cw/2,y=cy-ch/2,w=cw,h=ch}
    end
    -- Boxes are ordered by where their doors are in the fitted frame; the arrow
    -- starts at the door as drawn (zoomed), kept inside that frame.
    for _,e in ipairs(entries) do
        local x,y=main.x+e.u*main.w,main.y+e.v*main.h
        e.along=(e.side=="top" or e.side=="bottom") and x or y
        if e.door and toScreen then
            local dx,dy=toScreen(e.door[1],e.door[2],4)
            if dx then
                e.inside=dx>=frame.x and dx<=frame.x+frame.w and dy>=frame.y and dy<=frame.y+frame.h
                e.dx=math.max(frame.x,math.min(frame.x+frame.w,dx));e.dy=math.max(frame.y,math.min(frame.y+frame.h,dy))
            end
        end
    end
    local function spread(items,size,lo,hi)
        table.sort(items,function(a,b) return a.along<b.along end)
        local gap=6
        for i,it in ipairs(items) do
            it.c=math.max(lo+size/2,math.min(hi-size/2,it.along))
            if i>1 then it.c=math.max(it.c,items[i-1].c+size+gap) end
        end
        local over=#items>0 and items[#items].c+size/2-hi or 0
        if over>0 then for _,it in ipairs(items) do it.c=it.c-over end end
    end
    spread(sides.top,nw,vp.x+2,vp.x+vp.w-2);spread(sides.bottom,nw,vp.x+2,vp.x+vp.w-2)
    spread(sides.left,nh,vp.y+2,vp.y+vp.h-36);spread(sides.right,nh,vp.y+2,vp.y+vp.h-36)
    local function place(it,b)
        local x1,y1=it.dx,it.dy
        if not x1 then x1,y1=edgePoint(main,b.x+b.w/2,b.y+b.h/2) end
        local x2,y2=edgePoint(b,x1,y1)
        arrow(x1,y1,x2,y2,{.95,.6,.15,.9})
        if it.dx and it.inside then g.setColor(.95,.6,.15,1);g.circle("fill",x1,y1,4) end
        box(it.id,b)
    end
    if not map then
    for _,it in ipairs(sides.top) do place(it,{x=it.c-nw/2,y=math.max(vp.y+2,main.y-14-nh),w=nw,h=nh}) end
    for _,it in ipairs(sides.bottom) do place(it,{x=it.c-nw/2,y=math.min(vp.y+vp.h-36-nh,main.y+main.h+14),w=nw,h=nh}) end
    for _,it in ipairs(sides.left) do place(it,{x=math.max(vp.x+2,main.x-14-nw),y=it.c-nh/2,w=nw,h=nh}) end
    for _,it in ipairs(sides.right) do place(it,{x=math.min(vp.x+vp.w-2-nw,main.x+main.w+14),y=it.c-nh/2,w=nw,h=nh}) end
        box(room,main);return
    end
    -- Enemies left here, under the room.
    local count=alive[room];local none=not known[room] or (count or 0)==0
    g.setColor(unpack(none and muted or enemyBlue))
    local ex,ey=vp.x+10,vp.y+vp.h-20
    g.polygon("fill",{ex,ey-5,ex+5,ey,ex,ey+5,ex-5,ey})
    text(known[room] and string.format("x %02d",math.min(99,count or 0)) or "x --",{x=ex+9,y=ey-7,w=80,size=12},none and muted or white)
    clip(frame,l)
    -- Room items YOU has seen here.
    for _,it in pairs(Session.items) do
        if it.roomID==room then
            local x,y=toScreen(it.positionX,it.positionY)
            if x then
                rect({x=x-9,y=y-9,w=18,h=18},(it.type or 0)>=10000 and {1,.38,0,.95} or {0,0,0,.7})
                g.setColor(1,1,1,1)
                ItemIcons:draw(tostring(game.currentFile).."/"..tostring(it.type),x-7,y-7,0,14/48,14/48)
            end
        end
    end
    -- Enemies in this room (live slots only describe the loaded room).
    for _,e in ipairs(enemies or {}) do
        local hp,maxHP=e.HP or 0,e.maxHP or 0
        if e.enabled and e.inGame and e.roomID==room and maxHP>0 and maxHP<60000 and hp>0 and hp<=maxHP then
            local x,y=toScreen(e.positionX,e.positionY,6)
            if x and V.isHazard(e) then
                Effects.pulseColor("danger",V.elapsed,1,.08,.02,.45,.45);g.circle("fill",x,y,11);Effects.endPulse()
                g.setColor(0,0,0,.85);g.circle("fill",x,y,6.5);g.setColor(1,.55,.05,1);g.circle("fill",x,y,5)
            elseif x then
                g.setColor(0,0,0,.85);g.polygon("fill",{x,y-7,x+7,y,x,y+7,x-7,y})
                local boss=V.isBoss(e)
                g.setColor(1,boss and .05 or 1,boss and .05 or 1,1);g.polygon("fill",{x,y-5,x+5,y,x,y+5,x-5,y})
            end
        end
    end
    -- Players here: slot colour with a facing chevron.
    for i=1,4 do
        local pl=players[i]
        if active(pl) and pl.roomID==room then
            local x,y=toScreen(pl.positionX,pl.positionY)
            if x then
                local c=Effects.markerColor(pl,V.colors[i],V.elapsed)
                g.setColor(c[1],c[2],c[3],.2);g.circle("fill",x,y,13)
                g.push();g.translate(x,y);g.rotate(V.heading(pl))
                g.setColor(0,0,0,.9);g.polygon("fill",{0,-10,8,7,0,3,-8,7})
                g.setColor(c[1],c[2],c[3],1);g.polygon("fill",{0,-8,6,5,0,2,-6,5})
                g.pop()
            end
        end
    end
    g.setScissor()
    for _,it in ipairs(sides.top) do place(it,{x=it.c-nw/2,y=math.max(vp.y+2,main.y-14-nh),w=nw,h=nh}) end
    for _,it in ipairs(sides.bottom) do place(it,{x=it.c-nw/2,y=math.min(vp.y+vp.h-36-nh,main.y+main.h+14),w=nw,h=nh}) end
    for _,it in ipairs(sides.left) do place(it,{x=math.max(vp.x+2,main.x-14-nw),y=it.c-nh/2,w=nw,h=nh}) end
    for _,it in ipairs(sides.right) do place(it,{x=math.min(vp.x+vp.w-2-nw,main.x+main.w+14),y=it.c-nh/2,w=nw,h=nh}) end
end
local function drawArena(l,game,players,key,enemies)
    local g=love.graphics
    local graph=Arena.graphs[game.scenario]
    local left=V.mode==1 and 300 or 0
    local stripWidth=V.mode==1 and 460 or l.width
    V.tabStrip=nil;V.viewport=nil
    -- Room View / Grid View replace the floor tabs. Grid View flashes red while
    -- a teammate is in Danger or Down and the Room View is shown.
    local teammate=nil
    for i=1,4 do if i~=V.you and active(players[i]) then teammate=Effects.worst(teammate,Effects.health(players[i])) end end
    local half=stripWidth/2
    for i,view in ipairs{"room","grid"} do
        local b={x=left+(i-1)*half+4,y=l.tabs[1].y-4,w=half-8,h=42}
        local on=V.arenaView==view
        rect(b,on and {.08,.13,.25,.95} or {.025,.045,.085,.85})
        if view=="grid" and teammate and not on then
            Effects.pulseColor(teammate,V.elapsed,1,0,0,.7,.1);g.rectangle("fill",b.x,b.y,b.w,b.h);Effects.endPulse()
        end
        g.setLineWidth(1);rect(b,on and {.4,.6,1,1} or {.18,.28,.48,1},"line")
        text(view=="room" and "ROOM VIEW" or "GRID VIEW",{x=b.x+4,y=b.y+12,w=b.w-8,size=key=="phone" and 15 or 13,fit=true,align="center"},on and yellow or muted)
        hit(b,function() V.arenaView=view end)
    end
    local vp=l.viewport
    rect(vp,{0,0,0,1})
    local alive,known,loaded=Arena.counts(V.enemyList,V.arenaSeen,V.isHazard,graph)
    local occupants={}
    for i=1,4 do
        if active(players[i]) then
            local list=occupants[players[i].roomID] or {};list[#list+1]=i;occupants[players[i].roomID]=list
        end
    end
    local target=players[V.target or 0]
    local room=(not V.follow and V.arenaRoom) or (active(target) and target.roomID) or V.arenaRoom
    V.arenaDrawn={}
    local function box(id,b)
        -- Entered: YOU has been in the room while the tracker ran, or the game has
        -- loaded the room's enemies (their list flag; covers a tracker started
        -- mid-scenario).
        arenaBox(game,id,b,occupants[id] or {},alive,known,id==room,V.arenaSeen[id] or loaded[id])
        V.arenaDrawn[#V.arenaDrawn+1]=id
        hit(b,function() V.arenaRoom=id;V.follow=false;V.arenaView="room";V.reset();V.frozenCenter=nil end)
    end
    if V.arenaView=="grid" then
        local cells,columns,rows={}, graph and graph.columns or 4,graph and graph.rows or 1
        if graph then cells=graph.cells
        else
            -- Showdown: no transcribed layout; show the rooms seen so far in order.
            local ids={};for id in pairs(known) do ids[#ids+1]=id end
            for id in pairs(occupants) do if not known[id] then ids[#ids+1]=id end end
            table.sort(ids)
            for n,id in ipairs(ids) do cells[id]={(n-1)%columns,math.floor((n-1)/columns)} end
            rows=math.max(1,math.ceil(#ids/columns))
            text("Showdown room layout is not mapped yet",{x=vp.x+8,y=vp.y+4,w=vp.w-16,size=11,align="center"},muted)
        end
        -- Leave the bottom strip free for the FOLLOW button drawn over the view.
        -- Boxes are inset in their cells so links run in the gaps between them
        -- and never under a box (user note, 2026-11-21).
        local top=vp.y+(graph and 4 or 24);local usable=vp.h-(top-vp.y)-40
        local gx=vp.x+4
        local cellW=(vp.w-8)/columns;local cellH=math.min(96,usable/rows)
        local padX=math.max(8,cellW*.11);local bw=cellW-2*padX
        local bh=math.min(cellH-math.max(14,cellH*.24),70)
        local occupied={}
        for id,c in pairs(cells) do occupied[c[1]..","..c[2]]=id end
        local function boxOf(id)
            local c=cells[id];local x,y=gx+(c[1]+.5)*cellW,top+(c[2]+.5)*cellH
            return {x=x-bw/2,y=y-bh/2,w=bw,h=bh,cx=x,cy=y,c=c[1],r=c[2]}
        end
        local function empty(c,r) return not occupied[c..","..r] end
        -- A link as a polyline: straight when the cells between are empty, an L
        -- through an empty corner cell, otherwise along the gaps between boxes.
        -- Links sharing a gap get their own lane (0, +4, -4, +8, ...), and of the
        -- two gap routes the one through less-used gaps is taken.
        local usage={}
        local function lane(key,take)
            local n=usage[key] or 0
            if take then usage[key]=n+1 end
            local k=math.ceil(n/2)*4;return n%2==1 and k or -k
        end
        local function route(a,b)
            local A,B=boxOf(a),boxOf(b)
            local dc,dr=B.c-A.c,B.r-A.r
            local sx,sy=dc>0 and 1 or -1,dr>0 and 1 or -1
            if dr==0 then
                local clear=true
                for c=math.min(A.c,B.c)+1,math.max(A.c,B.c)-1 do if not empty(c,A.r) then clear=false end end
                if clear then return {A.cx+sx*bw/2,A.cy,B.cx-sx*bw/2,B.cy} end
                local row=A.r<rows-1 and A.r+1 or A.r;local e=row>A.r and bh/2 or -bh/2
                local o=lane("h"..row,true);local y=top+row*cellH+o
                return {A.cx+o,A.cy+e,A.cx+o,y,B.cx+o,y,B.cx+o,B.cy+e}
            end
            if dc==0 then
                local clear=true
                for r=math.min(A.r,B.r)+1,math.max(A.r,B.r)-1 do if not empty(A.c,r) then clear=false end end
                if clear then return {A.cx,A.cy+sy*bh/2,B.cx,B.cy-sy*bh/2} end
                local col=A.c<columns-1 and A.c+1 or A.c;local e=col>A.c and bw/2 or -bw/2
                local o=lane("v"..col,true);local x=gx+col*cellW+o
                return {A.cx+e,A.cy+o,x,A.cy+o,x,B.cy+o,B.cx+e,B.cy+o}
            end
            if math.abs(dc)==1 and math.abs(dr)==1 then
                if empty(B.c,A.r) then return {A.cx+sx*bw/2,A.cy,B.cx,A.cy,B.cx,B.cy-sy*bh/2} end
                if empty(A.c,B.r) then return {A.cx,A.cy+sy*bh/2,A.cx,B.cy,B.cx-sx*bw/2,B.cy} end
            end
            -- First: out of A's top/bottom into the row gap beside A, then the
            -- column gap beside B. Second: out of A's side into the column gap
            -- beside A, then the row gap beside B.
            local row1,col1=A.r+(dr>0 and 1 or 0),B.c+(dc>0 and 0 or 1)
            local col2,row2=A.c+(dc>0 and 1 or 0),B.r+(dr>0 and 0 or 1)
            if (usage["h"..row1] or 0)+(usage["v"..col1] or 0)<=(usage["v"..col2] or 0)+(usage["h"..row2] or 0) then
                local oy,ox=lane("h"..row1,true),lane("v"..col1,true)
                local y,x=top+row1*cellH+oy,gx+col1*cellW+ox
                return {A.cx+ox,A.cy+sy*bh/2,A.cx+ox,y,x,y,x,B.cy+oy,B.cx-sx*bw/2,B.cy+oy}
            end
            local ox,oy=lane("v"..col2,true),lane("h"..row2,true)
            local x,y=gx+col2*cellW+ox,top+row2*cellH+oy
            return {A.cx+sx*bw/2,A.cy+oy,x,A.cy+oy,x,y,B.cx+ox,y,B.cx+ox,B.cy-sy*bh/2}
        end
        local function polyline(pts,width)
            for i=1,#pts-3,2 do
                segment(pts[i],pts[i+1],pts[i+2],pts[i+3],width)
                if i>1 then g.rectangle("fill",pts[i]-width/2,pts[i+1]-width/2,width,width) end
            end
            g.circle("fill",pts[1],pts[2],width+1.5);g.circle("fill",pts[#pts-1],pts[#pts],width+1.5)
        end
        local lit={}
        for n,link in ipairs(graph and graph.links or {}) do
            if cells[link[1]] and cells[link[2]] then
                local pts=route(link[1],link[2])
                if link[1]==room or link[2]==room then lit[#lit+1]=pts
                else g.setColor(.85,.55,.15,.8);polyline(pts,2) end
            end
        end
        g.setColor(.95,.85,.35,1)
        for _,pts in ipairs(lit) do polyline(pts,3) end
        for id in pairs(cells) do box(id,boxOf(id)) end
    else
        if not room or room==0 then
            text("Waiting for a room",{x=vp.x,y=vp.y+vp.h/2-8,w=vp.w,size=13,align="center"},muted)
            return
        end
        V.viewport=vp
        drawRoomView(l,game,players,enemies,graph,room,vp,box,alive,known,occupants)
    end
end
function V.draw(game,players,enemies,items)
    if V.mode==0 then return end
    -- Private providers publish after love.update; observe their current frame
    -- here as well. This only consumes snapshots and never reads memory.
    local ownFloors=V.map and V.candidates(V.map,players[V.you or 0]) or {}
    Session.update(game,players,V.you,items,#ownFloors==1 and ownFloors[1] or nil)
    local g=love.graphics
    local key=V.mode==1 and "wide" or (love.isDecky and "phone" or "vertical")
    if game.scenario=="desperate times" and key~="phone" then key=key=="wide" and "gasWide" or "gasVertical" end
    local l=Layout.select(key,game,V.hint);V.layout=l;V.hits={}
    rect({x=V.mode==1 and 300 or 0,y=0,w=V.mode==1 and 460 or l.width,h=l.height},{0,0,0,1})
    plate(l.floorFill,l.floorFrame);plate(l.roomFill,l.roomFrame,"slot bar")
    local f=V.map and V.map.floors[V.floor]
    local title=f and f.name or "MAP"
    if V.arena then title=tostring(game.scenario):upper()
    elseif game.scenario=="desperate times" and f then title="R.P.D. "..shortFloor(f.name)
    elseif game.scenario=="wild things" and f then title=shortFloor(f.name) end
    text(title,l.floorText,yellow)
    local p=players[V.target or 0]
    -- Room View of a tapped room names that room, not the followed player's.
    local shownRoom=V.arena and V.arenaView=="room" and not V.follow and V.arenaRoom or (p and p.roomID)
    text(shownRoom and GetRoomName(game.scenario,shownRoom) or "",l.roomText)
    if V.arena then drawArena(l,game,players,key,enemies) else
        local groups=V.floorGroups();local selected=1
        for i,group in ipairs(groups) do if contains(group.indices,V.floor) then selected=i end end
        local left=V.mode==1 and 300 or 0
        local stripWidth=V.mode==1 and 460 or l.width
        -- Two rows and a minimum cell width keep four portraits plus gas readable.
        local count=math.min(5,#groups,math.max(1,math.floor(stripWidth/110)))
        V.tabCount=count
        V.tabStrip={x=left,y=l.tabs[1].y-4,w=stripWidth,h=42}
        local start=math.max(1,math.min(V.tabOffset or 1,math.max(1,#groups-count+1)))
        if not V.tabsManual then
            if selected<start then start=selected elseif selected>=start+count then start=selected-count+1 end
        end
        V.tabOffset=start
        local tabWidth=stripWidth/math.max(1,count)
        for i=1,count do
            local group=groups[start+i-1]
            local b={x=left+(i-1)*tabWidth+4,y=V.tabStrip.y,w=tabWidth-8,h=V.tabStrip.h}
            local occupants={};local hasGas=false;local danger=nil
            for id=1,4 do
                local choices=V.map and V.candidates(V.map,players[id]) or {}
                for _,index in ipairs(group.indices) do
                    if contains(choices,index) then
                        occupants[#occupants+1]=id
                        danger=Effects.worst(danger,Effects.health(players[id]))
                        break
                    end
                end
            end
            local selectedFloor=contains(group.indices,V.floor)
            rect(b,selectedFloor and {.08,.13,.25,.95} or {.025,.045,.085,.85})
            if danger then
                Effects.pulseColor(danger,V.elapsed,1,0,0,.6,.25)
                g.rectangle("fill",b.x,b.y,b.w,b.h);Effects.endPulse()
            end
            g.setLineWidth(1);rect(b,selectedFloor and {.4,.6,1,1} or {.18,.28,.48,1},"line")
            text(group.label,{x=b.x+4,y=b.y+1,w=b.w-8,size=key=="phone" and 15 or 12,fit=true,align="center"},selectedFloor and yellow or muted)
            for _,index in ipairs(group.indices) do
                for _,place in ipairs(V.map.floors[index].places) do
                    if V.gasRooms[V.map.rooms[place.record].id] then hasGas=true end
                end
            end
            local number=#occupants+(hasGas and 1 or 0)
            local gap=3
            local size=math.min(key=="phone" and 24 or 18,(b.w-8-math.max(0,number-1)*gap)/math.max(1,number))
            local rowWidth=number*size+math.max(0,number-1)*gap
            local xx=b.x+(b.w-rowWidth)/2
            for _,id in ipairs(occupants) do icon(players[id],xx,b.y+16,size);xx=xx+size+gap end
            if hasGas then sprite("2/11511",{x=xx,y=b.y+16,w=size,h=size},ItemIcons) end
            hit({x=left+(i-1)*tabWidth,y=b.y,w=tabWidth,h=V.tabStrip.h},function()
                V.floor=group.indices[1];V.follow=false;V.tabsManual=false;V.reset()
            end)
        end
        drawMap(l,game,players,enemies,items)
    end
    local function control(box,labelBox,label,action,color)
        rect(box,color or {.35,.35,.38,.85});text(label,labelBox,color and {0,0,0,1} or white);hit(box,action)
    end
    if not V.arena or V.arenaView=="room" then
        control(l.plus,l.plusText,"+",function() V.scale(1.25) end)
        control(l.minus,l.minusText,"−",function() V.scale(.8) end)
        if l.fit then control(l.fit,l.fitText,"FIT",function() V.follow=false;V.reset() end) end
    end
    local c=V.colors[V.target or 1]
    control(l.follow,l.followText,V.mode==1 and ("FOLLOW P"..tostring(V.target or 1)) or "FOLLOW",function() V.follow=true;V.arenaRoom=nil;V.reset() end,V.follow and {c[1],c[2],c[3],1} or nil)
    plate(l.legendFill,l.legendFrame)
    local cellWidth=(l.legendFrame.w-16)/4
    for i=1,4 do
        local p=players[i]
        local name=p and p.enabled and tostring(p.name or p.type or "--"):upper() or "--"
        local prefix=i==V.you and "YOU" or "P"..i
        local size=V.mode==1 and 13 or (l.width==390 and 12 or 11)
        local font=(MapFonts and MapFonts[size]) or MiniFont or DefaultFont
        local width=font:getWidth(prefix.." "..name)
        local scale=math.min(1,(cellWidth-6)/math.max(1,width))
        local x=l.legendFrame.x+8+(i-1)*cellWidth
        local y=l.legendFrame.y+(l.legendFrame.h-font:getHeight()*scale)/2
        g.setFont(font);g.setColor(1,1,1,1)
        g.printf({V.colors[i],prefix,{1,1,1,1}," "..name},x,y,cellWidth/scale,"center",0,scale,scale)
        hit({x=x,y=l.legendFrame.y,w=cellWidth,h=l.legendFrame.h},function() follow(i) end)
    end
    scenario(l,game)
    if l.cards then compactCards(l,game,players)
    else
        for i=1,4 do
            if players[i] and players[i].enabled then
                -- Tapping a full card (portrait included) follows that player.
                hit({x=0,y=(i-1)*145,w=300,h=145},function() follow(i) end)
            end
        end
    end
    g.setLineWidth(1);g.setColor(1,1,1,1)
end
function V.step(delta)
    if not V.map then return end
    V.floor=(V.floor-1+delta)%#V.map.floors+1; V.follow=false; V.reset()
end
function V.scrollFloors(delta)
    local count=#V.floorGroups();V.tabsManual=true
    V.tabOffset=math.max(1,math.min(math.max(1,count-(V.tabCount or 5)+1),(V.tabOffset or 1)+delta))
end
function V.scale(factor)
    V.zoom=math.max(.4,math.min(8,V.zoom*factor))
end
function V.input(action,x,y)
    if V.mode==0 then return end
    local vp=V.viewport
    local tabs=V.tabStrip
    local inTabs=tabs and x>=tabs.x and x<tabs.x+tabs.w and y>=tabs.y and y<tabs.y+tabs.h
    local inside=vp and x>=vp.x and x<=vp.x+vp.w and y>=vp.y and y<=vp.y+vp.h
    if action=="hover" then V.hover=inside and {x=x,y=y} or nil;return end
    if action=="down" then
        V.hover=inside and {x=x,y=y} or nil
        if inTabs then V.floorDrag={x=x,y=y,moved=false};return end
        for _,h in ipairs(V.hits) do
            if x>=h.x and x<h.x+h.w and y>=h.y and y<h.y+h.h then h.action();return end
        end
        if inside then V.drag={x=x,y=y};V.frozenCenter=V.visibleCenter;V.follow=false end
    elseif action=="move" and V.floorDrag then
        if math.abs(x-V.floorDrag.x)>35 then
            V.scrollFloors(x<V.floorDrag.x and 1 or -1);V.floorDrag.x=x;V.floorDrag.moved=true
        end
    elseif action=="move" and V.drag then
        V.panX=V.panX+x-V.drag.x;V.panY=V.panY+y-V.drag.y;V.drag={x=x,y=y}
    elseif action=="up" then
        if V.floorDrag and not V.floorDrag.moved then
            local point=V.floorDrag
            for _,h in ipairs(V.hits) do
                if point.x>=h.x and point.x<h.x+h.w and point.y>=h.y and point.y<h.y+h.h then h.action();break end
            end
        end
        V.drag=nil;V.floorDrag=nil
    elseif action=="in" and inside then V.scale(1.2)
    elseif action=="out" and inside then V.scale(1/1.2)
    elseif action=="fit" and inside then V.follow=false; V.reset()
    elseif (action=="in" or action=="out") and inTabs then V.scrollFloors(action=="in" and -1 or 1) end
end
return V
