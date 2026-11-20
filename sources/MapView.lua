-- Purpose: reusable shared desktop/phone map views, follow controls and room tint.
-- Runtime/location: sources/MapView.lua; LÖVE 11.5 or the Decky Lua drawing bridge.
-- Inputs: existing GameInfo/Players, bundled map assets, pointer/keyboard actions.
-- Outputs: map drawing, compact cards and UI-only GameInfo.mapview state.
-- Safety: read-only packaged assets and existing state; no disc or user-cache access.
-- Run: B = cards beside map, N = map above cards; assets load automatically.
-- Check: luajit tools-n-shit/tracker-tests/maps/check-runtime-maps.lua .
local Data=require "MapData"
local V={mode=0,follow=true,target=nil,floor=1,zoom=1,panX=0,panY=0,hits={},cacheKey=""}
V.colors={{1,0,0},{115/255,178/255,249/255},{242/255,247/255,61/255},{101/255,218/255,80/255}}
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
local function active(p) return p and p.enabled and p.inGame and (p.roomID or 0)>0 end
function V.candidates(map,player)
    local matches={}
    if not active(player) then return matches end
    for i,f in ipairs(map.floors) do
        for _,p in ipairs(f.places) do
            if map.rooms[p.record].id==player.roomID then matches[#matches+1]=i; break end
        end
    end
    return matches
end
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1000000 end
function V.marker(map,floor,player)
    local f=map.floors[floor]
    local matches=V.candidates(map,player)
    if not contains(matches,floor) then return end
    if #matches==1 and finite(player.positionX) and finite(player.positionY) then
        local x,y=Data.position(f,player.positionX,player.positionY)
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
function V.enemyMarker(map,floor,e)
    if not (e and e.enabled and e.inGame and finite(e.positionX) and finite(e.positionY)) then return end
    local hp,maxHP=e.HP or 0,e.maxHP or 0
    if maxHP<=0 or maxHP>=60000 or hp<=0 or hp>maxHP then return end
    local f=map.floors[floor]
    for _,p in ipairs(f.places) do
        if map.rooms[p.record].id==e.roomID then return Data.position(f,e.positionX,e.positionY) end
    end
end
function V.update(game,players)
    local key=tostring(game.currentFile)..":"..tostring(game.scenario)..":"..tostring(game.release)
    if V.cacheKey~=key then
        V.cacheKey=key; V.map=nil; V.error=nil; V.floor=1; V.target=nil; V.follow=true; V.reset()
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
            end
        end
    end
    if not active(players[V.target or 0]) then
        V.target=nil
        -- The reader's first active gameplay record is the local player. The
        -- playernum field controls card count; it is not a local slot ID.
        for i=1,4 do if active(players[i]) then V.target=i; break end end
    end
    V.you=nil
    for i=1,4 do if active(players[i]) then V.you=i; break end end
    if V.map and V.follow and V.target then
        local choices=V.candidates(V.map,players[V.target])
        local selected=contains(choices,V.floor) and V.floor or choices[1]
        if selected and V.floor~=selected then V.floor=selected; V.reset() end
    end
    V.gasRooms=V.gas(game)
    game.mapview={mode=V.mode,following=V.follow,floor=V.floor,target=V.target or 0,available=V.map~=nil}
end
local Layout=require "MapLayout"
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
local function sprite(name,b,atlas)
    atlas=atlas or MapUIAtlas or UIAtlas
    local q=atlas.quads[name]
    if not q then return end
    local _,_,w,h=q:getViewport()
    love.graphics.setColor(1,1,1,1)
    atlas:draw(name,b.x,b.y,0,b.w/w,b.h/h)
end
local function plate(fill,frame,name)
    rect(fill); sprite(name or "title bar",frame)
end
local function hit(b,action)
    V.hits[#V.hits+1]={x=b.x,y=b.y,w=b.w,h=b.h,action=action}
end
local function follow(i) V.target=i; V.follow=true; V.reset() end
local function icon(player,x,y,size)
    sprite("icon"..tostring(player.type),{x=x,y=y,w=size,h=size})
end
local function shortFloor(name)
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
            text("P"..i,{x=bust.x+bust.w-15,y=bust.y+27,w=15,size=12},V.colors[i])
            text(cardFloor(p),offset(l.cardFloor,dy),yellow)
            local room=offset(l.cardRoom,dy);room.w=l.inventory.x-room.x-4
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
local function clock(game,b)
    if (game.frames or 0)<=0 then return end
    local g=love.graphics
    g.push();g.translate(b.x,b.y);g.scale(b.w/194,b.h/26)
    g.setColor(1,1,1,1);g.setFont(TimeFont)
    g.printf(Time2string(game.frames/.03),0,0,194,"right")
    SP.draw(game.spTracking,0,0,DefaultFont)
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
local function scenario(l,game)
    local wide=V.mode==1
    if l.tile then sprite(game.scenario,l.tile) end
    if game.scenario=="desperate times" then
        local fight=l.fight or {x=80,y=534,w=138,h=20}
        local timer=l.gasTimer or {x=274,y=532,w=24,h=26}
        local rooms=l.gasRooms or {x=300,y=532,w=88,h=25,size=10}
        local ft=game.fighttime2==65535 and game.fighttime or game.fighttime2
        if wide then
            text("Fight",{x=440,y=644,w=60,size=11},muted)
            text("Garage gate",{x=510,y=644,w=94,size=11},muted)
            text("Gas rotates in",{x=664,y=652,w=90,size=11},muted)
        end
        if game.fighttime2==0 then
            text(tostring(game.killedzombies or 0).." kills",fight)
        else
            love.graphics.setFont(TimeFont);love.graphics.setColor(1,1,1,1)
            love.graphics.push();love.graphics.translate(fight.x,fight.y);love.graphics.scale(fight.w/168,fight.h/24)
            if (ft or 0)>0 then love.graphics.printf(Time2string3(ft),0,0,70,"left") end
            if (game.garagetime or 0)>0 then love.graphics.printf(Time2string3(game.garagetime),74,0,94,"left") end
            love.graphics.pop()
            gasTimer(game,timer)
        end
        local names={}
        for id in pairs(V.gasRooms) do names[#names+1]={id=id,name=GetRoomName(game.scenario,id)} end
        table.sort(names,function(a,b)return a.id<b.id end)
        local labels={};for _,n in ipairs(names) do labels[#labels+1]=n.name end
        rooms.size=rooms.size or (wide and 13 or (#names>2 and 10 or 12))
        text(table.concat(labels,"\n"),rooms,{1,1,0,1})
    else
        local clockBox=l.clock
        local hasHint=V.hint and V.hint~="" or ((game.scenario=="flashback" or game.scenario=="wild things") and (game.escapetime or game.wttime or 0)>0)
        if hasHint and not wide then clockBox={x=l.clock.x,y=l.clock.y-2,w=l.clock.w,h=13} end
        clock(game,clockBox)
        local b=l.itemset
        text(tostring((game.itemrandom or 0)+1).."\n"..tostring(math.floor((game.itemrandom2 or 0)/10)+1).."\n"..tostring(V.setLetter or ""),{x=b.x,y=b.y,w=b.w,size=wide and 15 or 10,align="center"})
        if wide then text("Scenario",{x=438,y=644,w=150,size=11},muted) end
        local hints=V.hint or ""
        if game.scenario=="underbelly" or game.scenario=="flashback" then
            if (game.escapetime or 0)>0 and game.escapetime~=65535 then hints=Time2string3(game.escapetime) end
        elseif game.scenario=="wild things" then
            hints=(game.wttime or 0)>0 and game.wttime~=65535 and Time2string3(game.wttime) or tostring(game.coin or 0).." medals  "..hints
        end
        if hints~="" then
            local b=wide and {x=438,y=700,w=300,size=13} or {x=l.clock.x+l.clock.w+4,y=l.clock.y,w=l.width-l.clock.x-l.clock.w-6,size=10}
            -- Compact hints share the clock strip; keep them legible without
            -- moving the four card rows from their approved positions.
            if not wide then
                b={x=25,y=l.clock.y+12,w=l.width-28,size=10,align="right",fit=true}
            end
            text(hints,b)
        end
    end
end
local function drawMap(l,game,players,enemies)
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
    if V.mode==1 and l.art and V.zoom==1 and V.follow then ox=vp.x+2+(f.maxX-f.minX)*scale/2 end
    g.push();g.translate(ox,oy);g.scale(scale);g.translate(-cx,-cy)
    for _,p in ipairs(f.places) do
        local r=V.map.rooms[p.record];local color
        if V.gasRooms[r.id] then color={1,.85,0,.38} end
        for i=1,4 do
            if active(players[i]) and players[i].roomID==r.id then
                local c=V.colors[i];color=color or {c[1],c[2],c[3],.25}
            end
        end
        if color and V.quads[p.record] then g.setColor(unpack(color));g.draw(V.fill,V.quads[p.record],p.x,p.y) end
    end
    for _,p in ipairs(f.places) do
        if V.quads[p.record] then g.setColor(43/255,116/255,211/255,1);g.draw(V.walls,V.quads[p.record],p.x,p.y) end
    end
    g.pop()
    -- Scanlines and slot-coloured full-viewport crosshair are in the board.
    for y=vp.y,vp.y+vp.h,3 do rect({x=vp.x,y=y,w=vp.w,h=1},{0,0,0,.22}) end
    -- Enemies: small white diamonds with a dark edge, under the player markers.
    V.enemiesDrawn=0
    for _,e in ipairs(enemies or {}) do
        local ex,ey=V.enemyMarker(V.map,V.floor,e)
        if ex then
            local x,y=ox+(ex-cx)*scale,oy+(ey-cy)*scale
            g.setColor(0,0,0,.85);g.polygon("fill",{x,y-7,x+7,y,x,y+7,x-7,y})
            g.setColor(1,1,1,1);g.polygon("fill",{x,y-5,x+5,y,x,y+5,x-5,y})
            V.enemiesDrawn=V.enemiesDrawn+1
        end
    end
    for i=1,4 do
        local px,py,fallback=V.marker(V.map,V.floor,players[i])
        if px then
            local x,y=ox+(px-cx)*scale,oy+(py-cy)*scale
            local c=V.colors[i]
            if V.follow and i==V.target then
                rect({x=vp.x,y=y,w=vp.w,h=1},{c[1],c[2],c[3],.7})
                rect({x=x,y=vp.y,w=1,h=vp.h},{c[1],c[2],c[3],.7})
            end
            g.setColor(c[1],c[2],c[3],.15);g.circle("fill",x,y,19)
            g.setColor(c[1],c[2],c[3],1);g.setLineWidth(1)
            if fallback then
                g.circle("line",x,y,11);icon(players[i],x-9,y-9,18)
            else
                -- Fixed locator chevron, not a claimed facing read. The reader
                -- does not yet export validated map heading.
                g.polygon("fill",{x,y-12,x+10,y+10,x,y+4,x-10,y+10})
            end
            text(i==V.you and "YOU" or "P"..i,{x=x+12,y=y-24,w=35,size=13},c)
        end
    end
    g.setScissor()
    if next(V.gasRooms) then
        local chip=l.gasChip or {x=vp.x+vp.w-46,y=vp.y+50,w=40,h=43,color={0,0,0,.75}}
        rect(chip);gasTimer(game,l.gasChipContent or chip)
    end
end
function V.draw(game,players,enemies)
    if V.mode==0 then return end
    local g=love.graphics
    local key=V.mode==1 and "wide" or (love.isDecky and "phone" or "vertical")
    if game.scenario=="desperate times" and key~="phone" then key=key=="wide" and "gasWide" or "gasVertical" end
    local l=Layout[key];V.layout=l;V.hits={}
    rect({x=V.mode==1 and 300 or 0,y=0,w=V.mode==1 and 460 or l.width,h=l.height},{0,0,0,1})
    plate(l.floorFill,l.floorFrame);plate(l.roomFill,l.roomFrame,"slot bar")
    local f=V.map and V.map.floors[V.floor]
    local title=f and f.name or "MAP"
    if game.scenario=="desperate times" and f then title="R.P.D. "..shortFloor(f.name) end
    text(title,l.floorText,yellow)
    local p=players[V.target or 0]
    text(p and GetRoomName(game.scenario,p.roomID) or "",l.roomText)
    local groups=V.floorGroups();local selected=1
    for i,group in ipairs(groups) do if contains(group.indices,V.floor) then selected=i end end
    local count=#l.tabs
    local start=math.max(1,math.min(selected,#groups-count+1))
    V.tabStrip={x=V.mode==1 and 300 or 0,y=l.tabs[1].y-4,w=V.mode==1 and 460 or l.width,h=key=="phone" and 36 or 26}
    for i,b in ipairs(l.tabs) do
        local group=groups[start+i-1]
        if group then
            if contains(group.indices,V.floor) then
                local frame=l.activeTab;local dx=b.x-(key=="phone" and l.tabs[3].x or l.tabs[game.scenario=="desperate times" and 2 or 1].x)
                sprite("title bar",{x=frame.x+dx,y=frame.y,w=frame.w,h=frame.h})
            end
            text(group.label,{x=b.x,y=b.y,w=26,size=b.size,fit=true},contains(group.indices,V.floor) and yellow or muted)
            local size=key=="phone" and 24 or (V.mode==1 and 20 or 18)
            local xx=b.x+(key=="phone" and 32 or (V.mode==1 and 28 or 26))
            local occupants={};local hasGas=false
            for id=1,4 do
                local choices=V.map and V.candidates(V.map,players[id]) or {}
                for _,index in ipairs(group.indices) do
                    if contains(choices,index) then occupants[#occupants+1]=id;break end
                end
            end
            for _,index in ipairs(group.indices) do
                for _,place in ipairs(V.map.floors[index].places) do
                    if V.gasRooms[V.map.rooms[place.record].id] then hasGas=true end
                end
            end
            local right=l.tabs[i+1] and l.tabs[i+1].x-8 or (V.mode==1 and 754 or l.width-6)
            size=math.min(size,(right-xx)/math.max(1,#occupants+(hasGas and 1 or 0)))
            for _,id in ipairs(occupants) do icon(players[id],xx,b.y-2,size);xx=xx+size end
            if hasGas then sprite("2/11511",{x=xx,y=b.y-2,w=size,h=size},ItemIcons) end
            hit({x=b.x-8,y=b.y-4,w=(l.tabs[i+1] and l.tabs[i+1].x-b.x or l.width-(b.x-(V.mode==1 and 300 or 0)))-2,h=V.tabStrip.h},function()
                V.floor=group.indices[1];V.follow=false;V.reset()
            end)
        end
    end
    drawMap(l,game,players,enemies)
    local function control(box,labelBox,label,action,color)
        rect(box,color or {.35,.35,.38,.85});text(label,labelBox,color and {0,0,0,1} or white);hit(box,action)
    end
    control(l.plus,l.plusText,"+",function() V.scale(1.25) end)
    control(l.minus,l.minusText,"−",function() V.scale(.8) end)
    if l.fit then control(l.fit,l.fitText,"FIT",function() V.follow=false;V.reset() end) end
    local c=V.colors[V.target or 1]
    control(l.follow,l.followText,V.mode==1 and ("FOLLOW P"..tostring(V.target or 1)) or "FOLLOW",function() V.follow=true;V.reset() end,V.follow and {c[1],c[2],c[3],1} or nil)
    plate(l.legendFill,l.legendFrame)
    for i,b in ipairs(l.legends) do
        local p=players[i]
        local slot={x=b.slot.x,y=b.slot.y,w=i==V.you and 26 or b.slot.w,size=b.slot.size,fit=true}
        text(i==V.you and "YOU" or "P"..i,slot,V.colors[i])
        local label={x=b.name.x,y=b.name.y,w=(l.legends[i+1] and l.legends[i+1].slot.x or l.legendFrame.x+l.legendFrame.w)-b.name.x-3,size=b.name.size}
        if i==V.you and i~=4 then
            local extra=V.mode==1 and 10 or 7
            label.x=label.x+extra;label.w=label.w-extra
        end
        label.fit=true
        text(p and p.enabled and tostring(p.type):upper() or "--",label)
        hit({x=b.slot.x,y=l.legendFrame.y,w=label.x+label.w-b.slot.x,h=l.legendFrame.h},function() follow(i) end)
    end
    scenario(l,game)
    if l.cards then compactCards(l,game,players)
    else
        for i=1,4 do
            if players[i] and players[i].enabled then text("P"..i,{x=283,y=(i-1)*145+77,w=17,size=13},V.colors[i]) end
        end
    end
    g.setLineWidth(1);g.setColor(1,1,1,1)
end
function V.step(delta)
    if not V.map then return end
    V.floor=(V.floor-1+delta)%#V.map.floors+1; V.follow=false; V.reset()
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
    if action=="down" then
        if inTabs then V.floorDrag=x end
        for _,h in ipairs(V.hits) do
            if x>=h.x and x<h.x+h.w and y>=h.y and y<h.y+h.h then h.action(); return end
        end
        if inside then V.drag={x=x,y=y}; V.frozenCenter=V.visibleCenter; V.follow=false end
    elseif action=="move" and V.floorDrag then
        if math.abs(x-V.floorDrag)>50 then V.step(x<V.floorDrag and 1 or -1);V.floorDrag=x end
    elseif action=="move" and V.drag then
        V.panX=V.panX+x-V.drag.x; V.panY=V.panY+y-V.drag.y; V.drag={x=x,y=y}
    elseif action=="up" then V.drag=nil;V.floorDrag=nil
    elseif action=="in" and inside then V.scale(1.2)
    elseif action=="out" and inside then V.scale(1/1.2)
    elseif action=="fit" and inside then V.follow=false; V.reset()
    elseif (action=="in" or action=="out") and inTabs then V.step(action=="in" and -1 or 1) end
end
return V
