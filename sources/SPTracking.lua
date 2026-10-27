-- Purpose: reusable shared SP counter and facing-relative radar renderer.
-- Location/runtime: sources/SPTracking.lua, LuaJIT with LÖVE 11.5 or Decky bridge.
-- Inputs: validated current-run SP state, timer position, password-hint font,
-- and sources/layout.lua; bearing is clockwise from player forward.
-- Output: drawing commands only; returns whether an SP component was drawn.
-- Safety: no PINE, recording, workbook, files or game writes.
-- Run: invoked by sources/main.lua during tracker drawing on supported clients.
-- Check: packaged Decky saved-frame replay checks counter and arrow drawing.
local layout = require("layout").spTracking
local SPTracking = {}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
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
