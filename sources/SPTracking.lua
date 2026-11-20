-- Purpose: reusable shared SP counter and facing-relative radar renderer.
-- Location/runtime: sources/SPTracking.lua, LuaJIT with LÖVE 11.5 or Decky bridge.
-- Inputs: validated current-run SP state, timer position, password-hint font,
-- and sources/layout.lua; bearing is clockwise from player forward.
-- Output: drawing commands; forMap derives optional facing from existing snapshots.
-- draw returns whether an SP component was drawn.
-- SPTracking.alert says when to play the SP found sound (once per room).
-- Safety: no PINE, recording, workbook, files or game writes.
-- Run: invoked by sources/main.lua during tracker drawing on supported clients.
-- Check: packaged Decky saved-frame replay checks counter and arrow drawing;
-- tools-n-shit/tracker-tests/sp/check-sp-sound.lua checks the alert.
local layout = require("layout").spTracking
local SPTracking = {}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
end

-- SP found alert: true the first time the radar shows an uncollected SP item
-- (radarState "direction" or "near") after each room change, and not again in
-- that room. Unavailable samples keep the current room, so a dropped read
-- cannot replay the sound; reset() forgets the room when gameplay ends.
local alertRoom, alerted = nil, false
function SPTracking.alert(state)
    if type(state) ~= "table" or state.available ~= true or not integer(state.room, 0, 0xFFFF) then
        return false
    end
    if state.room ~= alertRoom then alertRoom, alerted = state.room, false end
    if alerted or (state.radarState ~= "direction" and state.radarState ~= "near") then return false end
    alerted = true
    return true
end

function SPTracking.reset()
    alertRoom, alerted = nil, false
end

-- Map radar is always relative to YOU, including when following a teammate.
-- Keep the guarded private provider's bearing/glow intact. Desktop room-only
-- samples can derive a direction from their already-exported item/player data;
-- no proximity/prompt claim is added when that provider does not supply one.
function SPTracking.forMap(state,player)
    if type(state)~="table" or state.available~=true or state.radarState~=nil then return state end
    if not (player and player.enabled and player.inGame and player.roomID==state.room) then return state end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<1000000 end
    local px,py,fx,fy=player.positionX,player.positionY,player.forwardX,player.forwardY
    if not (finite(px) and finite(py) and finite(fx) and finite(fy)) or math.abs(fx*fx+fy*fy-1)>.06 then return state end
    local nearest,best
    for _,it in ipairs(state.roomItems or {}) do
        if it.enabled and not it.collected and finite(it.x) and finite(it.y) then
            local d=(it.x-px)^2+(it.y-py)^2
            if not best or d<best then best=d;nearest=it end
        end
    end
    if not nearest or best<.001 then return state end
    local out={};for k,v in pairs(state) do out[k]=v end
    local angle=math.atan2(nearest.x-px,-(nearest.y-py))-math.atan2(fx,-fy)
    out.radarState="direction";out.bearing=math.atan2(math.sin(angle),math.cos(angle))
    return out
end

-- State contract: current-room/run data only. Missing or invalid data stays hidden.
-- radarState is optional until proximity/bearing are known. Bearing is clockwise
-- screen-space radians relative to the player's facing; release-specific world
-- conversion and orientation validation belong to the reader. state.glow (optional
-- boolean) marks "close enough"; a glowing radar keeps its rotating arrow and uses
-- the Penpot "glow" variant (orange compass and halos). The "near" prompt state also
-- glows when it has a bearing. "glow" is not a radarState of its own.
function SPTracking.draw(state, timerX, timerY, font)
    if type(state) ~= "table" or state.available ~= true or state.limit ~= 8 or
        not integer(state.collected, 0, state.limit) then return false end

    local name = state.radarState
    if name == "glow" then return false end
    if state.collected == state.limit then name = "complete" end
    if name == "complete" and state.collected ~= state.limit then return false end
    local showRadar = name ~= nil
    if name ~= nil and not layout.variants[name] then return false end
    if name == "direction" and (type(state.bearing) ~= "number" or
        state.bearing ~= state.bearing or math.abs(state.bearing) == math.huge) then return false end

    local bearingOk = type(state.bearing) == "number" and state.bearing == state.bearing and
        math.abs(state.bearing) ~= math.huge
    local glow = (name == "direction" or name == "near") and bearingOk and
        (state.glow == true or name == "near")
    if glow then name = "glow" end
    local variant = layout.variants[name or "idle"]
    local g = love.graphics
    font = font or DefaultFont
    local oldFont, oldColor, oldWidth = g.getFont(), {g.getColor()}, g.getLineWidth()
    g.push()
    g.translate(timerX + variant.x, timerY + variant.y - layout.referenceY)
    g.setFont(font)
    -- Rotate the entire compass about its design bounds, including its trailing bar.
    -- The glow halos are circles centred on that point and are drawn unrotated.
    local pivotX, pivotY
    if name == "direction" or name == "glow" then
        local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
        for _,e in ipairs(variant.elements) do
            if e.role == "arrow" or e.role == "bar" then
                left, top = math.min(left,e.x), math.min(top,e.y)
                right, bottom = math.max(right,e.x+e.width), math.max(bottom,e.y+e.height)
            end
        end
        pivotX, pivotY = (left+right)/2, (top+bottom)/2
    end
    for _,e in ipairs(variant.elements) do
        if e.type == "text" then
            local text = e.role == "current" and tostring(state.collected) or
                e.role == "maximum" and tostring(state.limit) or e.text
            g.setColor(unpack(e.fill))
            g.print(text, e.x, e.y, 0, e.scale, e.scale)
        elseif showRadar then
            g.push()
            if pivotX and e.role ~= "haloOuter" and e.role ~= "haloInner" then
                g.translate(pivotX, pivotY)
                g.rotate(state.bearing)
                g.translate(-pivotX, -pivotY)
            end
            g.translate(e.x, e.y)
            g.setColor(unpack(e.fill))
            if e.type == "ellipse" then
                g.ellipse("fill", e.width/2, e.height/2, e.width/2, e.height/2)
                if e.strokeWidth and e.strokeWidth > 0 then
                    g.setColor(unpack(e.stroke))
                    g.setLineWidth(e.strokeWidth)
                    -- Penpot uses an inner stroke; LÖVE strokes are centred.
                    g.ellipse("line", e.width/2, e.height/2,
                        (e.width-e.strokeWidth)/2, (e.height-e.strokeWidth)/2)
                end
            elseif e.type == "rectangle" then
                g.rectangle("fill", 0, 0, e.width, e.height)
            elseif e.type == "path" then
                g.polygon("fill", e.points)
                if e.strokeWidth and e.strokeWidth > 0 then
                    g.setColor(unpack(e.stroke))
                    g.setLineWidth(e.strokeWidth)
                    g.polygon("line", e.points)
                end
            end
            g.pop()
        end
    end
    g.pop()
    g.setFont(oldFont)
    g.setColor(unpack(oldColor))
    g.setLineWidth(oldWidth)
    return true
end

return SPTracking
