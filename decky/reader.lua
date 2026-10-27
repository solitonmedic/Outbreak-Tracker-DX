-- Purpose: reusable live-reader/browser drawing bridge running the shared Lua UI.
-- Runtime/location: LuaJIT, plugin reader.lua; shared Lua, fonts and native module.
-- Inputs: newline-delimited comma-separated whitelisted keys on stdin, live PINE.
-- Outputs: one JSON drawing frame per input tick on stdout, in memory only.
-- Includes ellipse/polygon/rotation/line-width commands for the shared SP UI.
-- Safety: native reader performs reads only; no recording, game writes or disk frames.
-- Run: launched by tracker_service.py from the installed plugin directory.
-- Check: browser displays original cards; offline synthetic checks use a fake tracker.
package.path = "shared/?.lua;" .. package.path
package.cpath = "bin/?.so;" .. package.cpath
local metrics = dofile("fontmetrics.lua")
local commands, color, font = {}, {1, 1, 1, 1}, nil
local width, height = 300, 740
local lineWidth = 1
local function emit(op, ...)
    local values = {op, ...}
    commands[#commands + 1] = values
end
local function rgba(...)
    local v = {...}
    if type(v[1]) == "table" then v = v[1] end
    return {v[1] or 1, v[2] or 1, v[3] or 1, v[4] or 1}
end
local function codepoint(character)
    local a,b,c,d = character:byte(1,4)
    if a < 128 then return a end
    if a < 224 then return (a-192)*64+b-128 end
    if a < 240 then return (a-224)*4096+(b-128)*64+c-128 end
    return (a-240)*262144+(b-128)*4096+(c-128)*64+d-128
end
local function textplain(text)
    if type(text) ~= "table" then return tostring(text or "") end
    local parts = {}
    for _,part in ipairs(text) do if type(part) == "string" then parts[#parts+1]=part end end
    return table.concat(parts)
end
local function makefont(path, size, characters)
    local m = assert(metrics[path .. (size and ":" .. size or "")], "Missing font metrics")
    local f = {path=path, size=size, characters=characters, ascent=m.ascent, height=m.height}
    function f:setFilter() end
    function f:getHeight() return m.height end
    function f:getWidth(text)
        local total=0
        for ch in textplain(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            total=total+(m.widths[codepoint(ch)] or size or 8)
        end
        return total
    end
    function f:getWrap(text, limit)
        local lines, line, maximum = {}, "", 0
        for raw in (textplain(text).."\n"):gmatch("(.-)\n") do
            for word in raw:gmatch("%S+") do
                local nextline = line == "" and word or line .. " " .. word
                if line ~= "" and self:getWidth(nextline) > limit then
                    lines[#lines+1]=line; maximum=math.max(maximum,self:getWidth(line)); line=word
                else line=nextline end
            end
            lines[#lines+1]=line; maximum=math.max(maximum,self:getWidth(line)); line=""
        end
        return maximum, lines
    end
    return f
end
local function describe(f)
    return {path=f.path,size=f.size,characters=f.characters,ascent=f.ascent,height=f.height}
end
local function sprite(image, quad, x,y,r,sx,sy,ox,oy,kx,ky, tint)
    if not quad then return end
    local c = tint or {1,1,1,1}
    emit("image",image.path,quad,{x or 0,y or 0,r or 0,sx or 1,sy or sx or 1,ox or 0,oy or 0,kx or 0,ky or 0},
        {color[1]*c[1],color[2]*c[2],color[3]*c[3],color[4]*c[4]})
end
love = {graphics={},window={},audio={},event={}}
local g=love.graphics
function g.newFont(path,size) return makefont(path,size) end
function g.newImageFont(path,characters) return makefont(path,nil,characters) end
function g.newImage(path) return {path=path} end
function g.newQuad(x,y,w,h)
    local q={x,y,w,h}
    function q:getViewport() return self[1],self[2],self[3],self[4] end
    return q
end
function g.newSpriteBatch(image)
    local batch={image=image,entries={},tint={1,1,1,1}}
    function batch:setColor(...) self.tint=rgba(...) end
    function batch:add(quad,x,y,r,sx,sy,ox,oy,kx,ky)
        self.entries[#self.entries+1]={quad=quad,args={x,y,r,sx,sy,ox,oy,kx,ky},tint=self.tint}
    end
    return batch
end
function g.draw(image,quad,...)
    if image.entries then
        for _,entry in ipairs(image.entries) do
            local a=entry.args
            sprite(image.image,entry.quad,a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],entry.tint)
        end
    else sprite(image,quad,...) end
end
function g.setColor(...) color=rgba(...) end
function g.getColor() return unpack(color) end
function g.setFont(f) font=f or DefaultFont end
function g.getFont() return font or DefaultFont end
function g.print(text,x,y,r,sx,sy,ox,oy,kx,ky)
    emit("text",text,describe(g.getFont()),{x or 0,y or 0,r or 0,sx or 1,sy or sx or 1,ox or 0,oy or 0,kx or 0,ky or 0},color)
end
function g.printf(text,x,y,limit,align,r,sx,sy,ox,oy,kx,ky)
    emit("text",text,describe(g.getFont()),{x or 0,y or 0,r or 0,sx or 1,sy or sx or 1,ox or 0,oy or 0,kx or 0,ky or 0},color,limit,align or "left")
end
function g.push() emit("push") end
function g.pop() emit("pop") end
function g.translate(x,y) emit("translate",x,y) end
function g.scale(x,y) emit("scale",x,y or x) end
function g.rotate(angle) emit("rotate",angle) end
function g.getLineWidth() return lineWidth end
function g.setLineWidth(value) lineWidth=value; emit("lineWidth",value) end
function g.rectangle(mode,x,y,w,h,rx,ry) emit("rectangle",mode,x,y,w,h,color,rx or 0,ry or rx or 0) end
function g.circle(mode,x,y,r) emit("circle",mode,x,y,r,color) end
function g.ellipse(mode,x,y,rx,ry) emit("ellipse",mode,x,y,rx,ry,color) end
function g.polygon(mode,...)
    local points={...}
    if type(points[1])=="table" then points=points[1] end
    emit("polygon",mode,points,color)
end
function love.window.getMode() return width,height,{} end
function love.window.setMode(w,h) width,height=w,h end
function love.window.getPosition() return 0,0,1 end
function love.window.setPosition() end
function love.audio.newSource() return {play=function() end,stop=function() end,isPlaying=function() return false end,setLooping=function() end} end
function love.event.quit() end

local function json(value)
    local kind=type(value)
    if kind=="string" then
        return '"'..value:gsub('[%z\1-\31\\"]',function(c)
            local map={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
            return map[c] or string.format("\\u%04x",c:byte())
        end)..'"'
    elseif kind=="number" then return (value==value and math.abs(value)~=math.huge) and tostring(value) or "null"
    elseif kind=="boolean" then return value and "true" or "false"
    elseif kind=="table" then
        local result={}
        if #value>0 or next(value)==nil then
            for i=1,#value do result[#result+1]=json(value[i]) end
            return "["..table.concat(result,",").."]"
        end
        for k,v in pairs(value) do if type(v)~="function" then result[#result+1]=json(k)..":"..json(v) end end
        return "{"..table.concat(result,",").."}"
    end
    return "null"
end
require("main")
love.load({})
for input in io.lines() do
    commands={}
    color={1,1,1,1}
    local ok,err=pcall(function()
        for key in input:gmatch("[^,]+") do love.keypressed(key) end
        love.update(0.2)
        love.draw()
    end)
    local frame={width=width,height=height,commands=commands,game=GameInfo,
        state=ok and (GameInfo.currentFile and GameInfo.currentFile~=255 and "connected" or "waiting") or "error"}
    if not ok then frame.message=tostring(err); frame.commands={} end
    io.write(json(frame).."\n"); io.flush()
end
