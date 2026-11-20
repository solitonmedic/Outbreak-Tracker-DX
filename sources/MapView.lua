-- Purpose: reusable shared desktop/phone map views, follow controls and room tint.
-- Runtime/location: sources/MapView.lua; LÖVE 11.5 or the Decky Lua drawing bridge.
-- Inputs: existing GameInfo/Players, MapData disc cache, pointer/keyboard actions.
-- Outputs: map drawing, compact cards and UI-only GameInfo.mapview state.
-- Safety: no new memory reads; disc import writes only the user's local cache.
-- Run: B = cards beside map, N = map above cards; drag a Japanese disc/ISO to import.
-- Check: luajit tools-n-shit/tracker-tests/maps/check-runtime-maps.lua .
local Data=require "MapData"
local V={mode=0,follow=true,target=nil,floor=1,zoom=1,panX=0,panY=0,hits={},cacheKey=""}
V.colors={{1,0,0},{115/255,178/255,249/255},{242/255,247/255,61/255},{101/255,218/255,80/255}}
local function read(path)
    if love.filesystem then return love.filesystem.read(path) end
    local f=io.open((os.getenv("OUTBREAK_MAP_CACHE") or ".").."/"..path,"rb")
    if not f then return end
    local s=f:read("*a"); f:close(); return s
end
function V.import(path)
    local ok,result=pcall(Data.import,path,function(name,bytes)
        assert(love.filesystem,"Use the phone import form")
        assert(love.filesystem.createDirectory(name:match("^(.*)/")))
        assert(love.filesystem.write(name..".tmp",bytes))
        assert(os.rename(love.filesystem.getSaveDirectory().."/"..name..".tmp",love.filesystem.getSaveDirectory().."/"..name))
    end)
    V.cacheKey=""; V.notice=ok and ("Imported Japanese File "..result.." maps") or tostring(result)
    return ok,V.notice
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
function V.update(game,players)
    local key=tostring(game.currentFile)..":"..tostring(game.scenario)..":"..tostring(game.release)
    local index=read("maps/jp"..tostring(game.currentFile).."/index") or ""
    if V.cacheKey~=key..index then
        V.cacheKey=key..index; V.map=nil; V.error=nil; V.floor=1; V.target=nil; V.follow=true; V.reset()
        if game.release=="us" then V.error="U.S. maps are not enabled yet"
        else
            local ok,map,message=pcall(Data.load,game.currentFile,game.scenario,read)
            if ok then V.map,V.error=map,message else V.error="Map cache is damaged; import the disc again" end
            if V.map then
                local loaded,err=pcall(function()
                    V.fill=love.graphics.newImage(V.map.path.."-fill.png")
                    V.walls=love.graphics.newImage(V.map.path.."-walls.png")
                    V.quads={}
                    for i,r in ipairs(V.map.rooms) do
                        if r.w>0 and r.h>0 then V.quads[i]=love.graphics.newQuad(r.x,r.y,r.w,r.h,1024,V.map.height) end
                    end
                end)
                if not loaded then V.map=nil; V.error="Map images are missing; import the disc again" end
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
local function text(s,x,y,w,c)
    local g=love.graphics
    g.setFont(VerySmallFont); g.setColor(0,0,0,1); g.printf(s,x+1,y+1,w,"left")
    g.setColor(unpack(c or {1,1,1,1})); g.printf(s,x,y,w,"left")
end
local function button(label,x,y,w,action,c)
    local g=love.graphics
    g.setColor(.06,.12,.2,1); g.rectangle("fill",x,y,w,44)
    g.setColor(unpack(c or {.2,.42,.65,1})); g.rectangle("line",x,y,w,44)
    text(label,x+7,y+9,w-12,c)
    V.hits[#V.hits+1]={x=x,y=y,w=w,h=44,action=action}
end
local function icon(player,x,y,size)
    local key="icon"..tostring(player.type)
    local q=UIAtlas.quads[key] or UIAtlas.quads.iconNPC
    if not q then return end
    local _,_,w,h=q:getViewport()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(UIAtlas.tex,q,x,y,0,size/w,size/h)
end
function V.draw(game,players)
    if V.mode==0 then return end
    local g=love.graphics
    local x,w=V.mode==1 and 300 or 0,V.mode==1 and 460 or 390
    local bottom=V.mode==1 and 740 or 688
    V.hits={}; V.viewport={x=x+8,y=154,w=w-16,h=V.mode==1 and 350 or 200}
    g.setColor(0,0,0,1); g.rectangle("fill",x,0,w,bottom)
    g.setColor(1,1,1,1)
    if UIAtlas.quads["title bar"] then UIAtlas:draw("title bar",x,0,0,w/300,1) end
    local f=V.map and V.map.floors[V.floor]
    text(f and f.name or "MAP",x+10,8,w-20,{1,1,.65,1})
    local player=players[V.target or 0]
    local room=player and GetRoomName(game.scenario,player.roomID) or ""
    text(room,x+10,32,w-20)
    button("<",x+8,56,44,function() V.step(-1) end)
    local label=f and (V.floor.."/"..#V.map.floors.."  "..f.name) or "No map loaded"
    button(label,x+56,56,w-112,function() V.step(1) end,{1,1,.65,1})
    button(">",x+w-52,56,44,function() V.step(1) end)
    button("-",x+8,104,44,function() V.scale(.8) end)
    button("+",x+56,104,44,function() V.scale(1.25) end)
    button("Fit",x+104,104,56,function() V.follow=false; V.reset() end)
    button(V.follow and "Following" or "Follow",x+164,104,100,function() V.follow=true; V.reset() end)
    button("Cards",x+w-92,104,84,function() love.keypressed("v") end)
    local vp=V.viewport
    g.setColor(.01,.025,.045,1); g.rectangle("fill",vp.x,vp.y,vp.w,vp.h)
    if V.map then
        local sx,sy=love.window.getMode()
        local lw,lh=V.mode==1 and 760 or 390,V.mode==1 and 740 or 844
        g.setScissor(vp.x*sx/lw,vp.y*sy/lh,vp.w*sx/lw,vp.h*sy/lh)
        local fit=math.min((vp.w-24)/math.max(1,f.maxX-f.minX),(vp.h-24)/math.max(1,f.maxY-f.minY))
        local scale=fit*V.zoom
        local cx,cy=(f.minX+f.maxX)/2,(f.minY+f.maxY)/2
        if not V.follow and V.frozenCenter then cx,cy=unpack(V.frozenCenter) end
        if V.follow and player then
            local px,py=V.marker(V.map,V.floor,player)
            if px then cx,cy=px,py end
        end
        V.drawScale=scale
        V.visibleCenter={cx,cy}
        g.push(); g.translate(vp.x+vp.w/2+V.panX,vp.y+vp.h/2+V.panY); g.scale(scale); g.translate(-cx,-cy)
        for _,p in ipairs(f.places) do
            local r=V.map.rooms[p.record]
            local color
            if V.gasRooms[r.id] then color={1,.85,0,.55} end
            for i=1,4 do
                if active(players[i]) and players[i].roomID==r.id then
                    local c=V.colors[i]; color=color or {c[1],c[2],c[3],.3}
                end
            end
            if color and V.quads[p.record] then g.setColor(unpack(color)); g.draw(V.fill,V.quads[p.record],p.x,p.y) end
        end
        for _,p in ipairs(f.places) do
            if V.quads[p.record] then
                g.setColor(43/255,116/255,211/255,1); g.draw(V.walls,V.quads[p.record],p.x,p.y)
            end
        end
        for i=1,4 do
            local px,py,fallback=V.marker(V.map,V.floor,players[i])
            if px then
                local c=V.colors[i]; local radius=7/scale
                g.setColor(c[1],c[2],c[3],1); g.circle("line",px,py,radius)
                if fallback then icon(players[i],px-radius*.7,py-radius*.7,radius*1.4)
                else g.circle("fill",px,py,3/scale) end
                if i==V.target and V.follow then
                    g.setColor(c[1],c[2],c[3],.7)
                    g.rectangle("fill",px-14/scale,py-.5/scale,28/scale,1/scale)
                    g.rectangle("fill",px-.5/scale,py-14/scale,1/scale,28/scale)
                end
            end
        end
        g.pop(); g.setScissor()
    else
        text(V.error or "Open a Japanese scenario to use the map",vp.x+12,vp.y+20,vp.w-24)
        text("Drag your disc folder, NETBIO00.DAT or ISO onto this window. On a phone, use Import maps in Controls.",vp.x+12,vp.y+70,vp.w-24)
    end
    local y=vp.y+vp.h+6
    text(V.notice or "Drag to pan / scroll to zoom. Ring + portrait = room only.",x+8,y,w-16)
    y=y+32
    for i=1,4 do
        local p=players[i]
        if V.mode==2 then
            local top=400+(i-1)*72
            g.setColor(0,0,0,1); g.rectangle("fill",0,top,w,72)
            if p and p.enabled then
                if V.gasRooms[p.roomID] then g.setColor(.32,.26,0,1); g.rectangle("fill",0,top,w,72) end
                -- Keep the real card's health, inventory, bust and virus artwork.
                g.setColor(1,1,1,1)
                g.push(); g.translate(0,top); g.scale(.49); PlayerCards[i]:draw(0,0); g.pop()
                text((i==V.you and "YOU " or "").."P"..i.." "..tostring(p.type),156,top+8,224,V.colors[i])
                text(GetRoomName(game.scenario,p.roomID),156,top+29,224)
            end
            V.hits[#V.hits+1]={x=0,y=top,w=w,h=72,action=function() V.target=i; V.follow=true; V.reset() end}
        else
            local label=(i==V.you and "YOU " or "").."P"..i.."  "..(p and p.enabled and tostring(p.type).." / "..GetRoomName(game.scenario,p.roomID) or "--")
            button(label,x+8,y+(i-1)*44,w-16,function() V.target=i; V.follow=true; V.reset() end,V.colors[i])
        end
    end
    if V.mode==1 then
        g.setColor(1,1,1,1)
        if UIAtlas.quads[game.scenario] then UIAtlas:draw(game.scenario,x+8,710,0,.7) end
        text("B: wide / N: vertical / F: follow",x+150,713,w-158)
    end
    if game.scenario=="desperate times" and next(V.gasRooms) then
        text("GAS "..Time2string3(game.gastime or 0),x+w-140,35,130,{1,1,0,1})
    end
    g.setColor(1,1,1,1)
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
    local inside=vp and x>=vp.x and x<=vp.x+vp.w and y>=vp.y and y<=vp.y+vp.h
    if action=="down" then
        for _,h in ipairs(V.hits) do
            if x>=h.x and x<h.x+h.w and y>=h.y and y<h.y+h.h then h.action(); return end
        end
        if inside then V.drag={x=x,y=y}; V.frozenCenter=V.visibleCenter; V.follow=false end
    elseif action=="move" and V.drag then
        V.panX=V.panX+x-V.drag.x; V.panY=V.panY+y-V.drag.y; V.drag={x=x,y=y}
    elseif action=="up" then V.drag=nil
    elseif action=="in" and inside then V.scale(1.2)
    elseif action=="out" and inside then V.scale(1/1.2)
    elseif action=="fit" and inside then V.follow=false; V.reset() end
end
return V
