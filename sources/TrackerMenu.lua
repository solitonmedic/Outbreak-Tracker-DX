-- Purpose: reusable clickable tracker-styled controls on native desktop clients.
-- Runtime/location: sources/TrackerMenu.lua; LÖVE 11.5/LuaJIT, shared UI assets.
-- Inputs: pointer/keyboard controls and view dimensions. Outputs: menu drawing
-- and existing whitelisted love.keypressed actions; no files/PINE/game writes.
-- Run: click CONTROLS or right-click/Tab; Decky uses the matching browser sheet.
-- Check: tracker-tests/maps/check-presentation.lua and synthetic desktop preview.
local M={open=false,scroll=0,hits={}}
M.groups={
    {"VIEWS",{{"home","MAIN TRACKER"},{"f1","HELP"},{"f2","ITEM VIEWS"},{"f3","NEXT ROOM"},{"l","LANGUAGE"}}},
    {"SHOW",{{"i","ROOM ITEMS"},{"t","TIMERS"},{"q","PUZZLE HINTS"},{"e","ENEMY HP"},{"f4","ENEMY LIST"}}},
    {"SOUND",{{"m","SP RADAR SOUND"}}},
    {"LAYOUT",{{"v","VERTICAL"},{"h","HORIZONTAL"},{"d","DEFAULT SIZE"},{"a","AUTO SIZE"}}},
    {"MAP",{{"n","MAP + CARDS"},{"b","CARDS BESIDE MAP"},{"f","FOLLOW PLAYER"}}},
    {"PLAYERS SHOWN",{{"1","1"},{"2","2"},{"3","3"},{"4","4"}}},
    {"ENEMY LIST",{{"kp0","ALL"},{"kp1","P1"},{"kp2","P2"},{"kp3","P3"},{"kp4","P4"}}},
}
local function inside(b,x,y) return b and x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h end
local function frame(b)
    local g=love.graphics
    g.setColor(.025,.045,.085,.98);g.rectangle("fill",b.x,b.y,b.w,b.h)
    g.setLineWidth(1);g.setColor(.22,.35,.62,1);g.rectangle("line",b.x,b.y,b.w,b.h)
    g.setColor(.06,.12,.24,1);g.rectangle("line",b.x+2,b.y+2,b.w-4,b.h-4)
end
function M.draw(width,height,mapActive)
    if love.isDecky then return end
    local g=love.graphics
    M.launcher={x=width-83,y=mapActive and 5 or height-23,w=78,h=18}
    frame(M.launcher);g.setColor(1,1,.72,1);g.setFont(MiniFont or DefaultFont)
    g.printf("CONTROLS",M.launcher.x,M.launcher.y+2,M.launcher.w,"center")
    if not M.open then return end
    local oldFont=g.getFont()
    g.setColor(0,0,0,.8);g.rectangle("fill",0,0,width,height)
    local w=math.min(width-12,360);local h=math.min(height-18,680)
    local b={x=(width-w)/2,y=(height-h)/2,w=w,h=h};M.panel=b;M.hits={}
    frame(b)
    g.setColor(.9,.9,.65,1);g.setFont(SmallFont or DefaultFont);g.printf("TRACKER CONTROLS",b.x+8,b.y+9,w-65,"left")
    local close={x=b.x+w-56,y=b.y+5,w=50,h=25,key="close"};frame(close)
    g.setColor(1,1,1,1);g.setFont(MiniFont or DefaultFont);g.printf("CLOSE",close.x,close.y+6,close.w,"center")
    M.hits[#M.hits+1]=close
    local sw,sh=love.window.getMode()
    g.setScissor((b.x+5)*sw/width,(b.y+36)*sh/height,(w-10)*sw/width,(h-42)*sh/height)
    local y=b.y+38-M.scroll
    for _,group in ipairs(M.groups) do
        g.setColor(.6,.75,1,1);g.printf(group[1],b.x+10,y,w-20,"left");y=y+18
        local cols=group[1]=="PLAYERS SHOWN" and 4 or group[1]=="ENEMY LIST" and 5 or 2
        local cell=(w-24-(cols-1)*5)/cols
        for n,entry in ipairs(group[2]) do
            local button={x=b.x+12+(n-1)%cols*(cell+5),y=y+math.floor((n-1)/cols)*29,w=cell,h=25,key=entry[1]}
            frame(button);g.setColor(1,1,1,1)
            local label=entry[2]
            if entry[1]=="m" then label=label..(GameInfo.spsoundenabled==false and ": OFF" or ": ON") end
            g.printf(label,button.x+3,button.y+6,button.w-6,"center")
            if button.y>=b.y+36 and button.y+button.h<=b.y+h-5 then M.hits[#M.hits+1]=button end
        end
        y=y+math.ceil(#group[2]/cols)*29+9
    end
    M.maxScroll=math.max(0,y+M.scroll-(b.y+h-6))
    g.setScissor();g.setFont(oldFont);g.setColor(1,1,1,1)
end
function M.pointer(action,x,y,button)
    if love.isDecky then return false end
    if action=="down" and button==2 then M.open=not M.open;return true end
    if action=="down" and inside(M.launcher,x,y) then M.open=true;M.scroll=0;return true end
    if not M.open then return false end
    if action=="down" then
        for _,h in ipairs(M.hits) do if inside(h,x,y) then
            if h.key=="close" then M.open=false else love.keypressed(h.key);if h.key~="m" and h.key~="t" and h.key~="q" and h.key~="e" then M.open=false end end
            return true
        end end
        if not inside(M.panel,x,y) then M.open=false end
    end
    return true
end
function M.wheel(delta)
    if not M.open or love.isDecky then return false end
    M.scroll=math.max(0,math.min(M.maxScroll or 0,M.scroll-delta*35));return true
end
return M
