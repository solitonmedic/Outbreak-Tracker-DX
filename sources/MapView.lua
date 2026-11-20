-- Purpose: reusable shared desktop/phone map views, follow controls and room tint.
-- Runtime/location: sources/MapView.lua; LÖVE 11.5 or the Decky Lua drawing bridge.
-- Inputs: existing GameInfo/Players, update delta, bundled assets and UI actions.
-- Outputs: map drawing, compact cards and UI-only GameInfo.mapview state.
-- Safety: read-only packaged assets and existing state; no disc or user-cache access.
-- Run: B = cards beside map, N = map above cards; assets load automatically.
-- Check: luajit tools-n-shit/tracker-tests/maps/check-runtime-maps.lua .
local Data=require "MapData"
local Session=require "MapSession"
local Effects=require "PlayerEffects"
local Catalog=require "MapCatalog"
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
        -- The DT Front Gate's playable space extends beyond its small map
        -- outline. Its known room/floor is sufficient to show the actual point.
        if player.roomID==27 and map.path and map.path:match("/015$") then return x,y,false end
        -- Out-of-piece reads (loading/stale state) fall back to the room, never
        -- a plausible-looking marker on a different room or floor.
        for _,p in ipairs(f.places) do
            local r=map.rooms[p.record]
            if r.id==player.roomID and x>=p.x and x<p.x+r.w and y>=p.y and y<p.y+r.h then
                return x,y,false
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
-- read, even just outside the drawn room (doorways, the Desperate Times gate).
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
        if map.rooms[p.record].id==room then return Data.position(f,it.positionX,it.positionY) end
    end
end
-- Enemy identity comes from the reader's existing GetEnemyName table. Include
-- Giant Moth/Rafflesia and the distinct Gigabyte boss (64, not Megabyte18).
local bossIds={[9]=true,[15]=true,[19]=true,[20]=true,[29]=true,[32]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,[47]=true,[51]=true,[64]=true}
function V.isBoss(e) return e and bossIds[e.nameID] or false end
function V.enemyMarker(map,floor,e)
    if not (e and e.enabled and e.inGame and finite(e.positionX) and finite(e.positionY)) then return end
    local hp,maxHP=e.HP or 0,e.maxHP or 0
    if maxHP<=0 or maxHP>=60000 or hp<=0 or hp>maxHP then return end
    local f=map.floors[floor]
    for _,p in ipairs(f.places) do
        if map.rooms[p.record].id==e.roomID then return Data.position(f,e.positionX,e.positionY) end
    end
end
function V.update(game,players,dt,items)
    V.elapsed=(V.elapsed or 0)+(dt or 0)
    local key=tostring(game.currentFile)..":"..tostring(game.scenario)..":"..tostring(game.release)
    if V.cacheKey~=key then
        V.cacheKey=key; V.map=nil; V.er=nil; V.error=nil; V.floor=1; V.target=nil; V.follow=true; V.reset()
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
local SP=require "SPTracking"
local white={1,1,1,1}
local yellow={232/255,230/255,160/255,1}
local muted={138/255,143/255,153/255,1}
local function text(value,b,color)
    local g=love.graphics
    g.setFont(MapFonts and MapFonts[b.size or 11] or MiniFont)
    local value=tostring(value or "")
    local width=b.w
    local scale=b.fit and math.min(1,width/math.max(1,g.getFont():getWidth(value))) or 1
    g.push();g.translate(b.x,b.y);g.scale(scale,1)
    g.setColor(0,0,0,1);g.printf(value,1,1,width/scale,b.align or "left")
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

            if game.scenario~="wild things" then text(cardFloor(p),offset(l.cardFloor,dy),yellow) end
            local room=offset(l.cardRoom,dy)
            if game.scenario=="wild things" then room.x=l.cardFloor.x end
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
    local radarWidth=radar and 98 or 0
    if radar then
        -- Include the glow's full bounds (-9.2..27.2), and label
        -- whose facing the compass uses when the map is following someone else.
        g.push();g.translate(b.x+3,b.y+10)
        SP.draw(sp,-141,0,DefaultFont);g.pop()
        text("YOU",{x=b.x+67,y=b.y+12,w=27,size=9},yellow)
    end
    local value=Time2string(game.frames/.03)
    local width=b.w-radarWidth
    local scale=math.min(width/math.max(1,TimeFont:getWidth(value)),22/TimeFont:getHeight())
    g.push();g.translate(b.x+radarWidth,b.y+8);g.scale(scale,scale)
    g.setColor(1,1,1,1);g.setFont(TimeFont)
    g.printf(value,0,0,width/scale,"right");g.pop()
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
local function scenario(l,game)
    local g=love.graphics;local b=l.information
    if l.tile then sprite(game.scenario,l.tile) end
    local clockWidth=math.min(222,b.w*.68)
    local sp=SP.forMap(game.spTracking,V.players and V.players[V.you or 0])
    clock(game,{x=b.x,y=b.y,w=clockWidth,h=22},sp)
    local setsX=b.x+clockWidth+4
    local setsWidth=b.w-clockWidth-4
    text("ITEM",{x=setsX,y=b.y+12,w=27,size=10},yellow)
    local itemNumbers=tostring((game.itemrandom or 0)+1).."\n"..tostring(math.floor((game.itemrandom2 or 0)/10)+1)
    text(itemNumbers,{x=setsX+29,y=b.y+1,w=23,size=14,align="center"},yellow)
    text("SP "..tostring(V.setLetter or "—"),{x=setsX+57,y=b.y+12,w=setsWidth-57,size=11,fit=true,align="right"},yellow)
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
    if V.hint and V.hint~="" then lines[#lines+1]="HINT: "..V.hint end
    local hintY=39
    text(table.concat(lines,"\n"),{x=b.x,y=b.y+hintY,w=b.w,h=b.h-hintY,size=V.mode==1 and 13 or 11})
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
            g.setColor(0,0,0,.85);g.polygon("fill",{x,y-7,x+7,y,x,y+7,x-7,y})
            g.setColor(1,V.isBoss(e) and .05 or 1,V.isBoss(e) and .05 or 1,1);g.polygon("fill",{x,y-5,x+5,y,x,y+5,x-5,y})
            -- Remaining HP as a percentage beside the marker.
            local pct=math.floor(e.HP/e.maxHP*100+.5)
            enemyLabels[#enemyLabels+1]={value=pct.."%",x=x+7,y=y-15}
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
    if game.scenario=="desperate times" and f then title="R.P.D. "..shortFloor(f.name)
    elseif game.scenario=="wild things" and f then title=shortFloor(f.name) end
    text(title,l.floorText,yellow)
    local p=players[V.target or 0]
    text(p and GetRoomName(game.scenario,p.roomID) or "",l.roomText)
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
        local occupants={};local hasGas=false;local danger=false
        for id=1,4 do
            local choices=V.map and V.candidates(V.map,players[id]) or {}
            for _,index in ipairs(group.indices) do
                if contains(choices,index) then
                    occupants[#occupants+1]=id
                    local state=Effects.health(players[id]);danger=danger or state=="danger" or state=="down"
                    break
                end
            end
        end
        local selectedFloor=contains(group.indices,V.floor)
        rect(b,selectedFloor and {.08,.13,.25,.95} or {.025,.045,.085,.85})
        if danger then rect(b,{1,0,0,.15+.45*Effects.pulse(V.elapsed)}) end
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
    local function control(box,labelBox,label,action,color)
        rect(box,color or {.35,.35,.38,.85});text(label,labelBox,color and {0,0,0,1} or white);hit(box,action)
    end
    control(l.plus,l.plusText,"+",function() V.scale(1.25) end)
    control(l.minus,l.minusText,"−",function() V.scale(.8) end)
    if l.fit then control(l.fit,l.fitText,"FIT",function() V.follow=false;V.reset() end) end
    local c=V.colors[V.target or 1]
    control(l.follow,l.followText,V.mode==1 and ("FOLLOW P"..tostring(V.target or 1)) or "FOLLOW",function() V.follow=true;V.reset() end,V.follow and {c[1],c[2],c[3],1} or nil)
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
