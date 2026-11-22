-- Purpose: reusable synthetic SP UI checks: guards, state precedence, font,
-- timer-row placement, compass transform and graphics-state restoration.
-- Location/runtime: tests/unit/sp/check-sp-ui.lua; Homebrew LuaJIT.
-- Inputs: repo root argv[1], actual SPTracking/layout modules; no environment.
-- Outputs: PASS line; no files. Safety: no native reader, PINE or recordings.
-- Run from repo-merged: luajit tests/unit/sp/check-sp-ui.lua .
-- Check: assertions pass for valid/missing/stale/malformed states and all bearings.
package.path = assert(arg[1]) .. "/sources/?.lua;" .. package.path
local calls, color, width = {}, { 0.2, 0.3, 0.4, 0.5 }, 2
local originalFont, passwordFont = {}, {}
local font = originalFont
local function record(name, ...)
    calls[#calls + 1] = { name, ... }
end
love = { graphics = {} }
local g = love.graphics
for _, name in ipairs({ "push", "pop", "translate", "rotate", "print", "ellipse", "rectangle", "polygon" }) do
    g[name] = function(...)
        record(name, ...)
    end
end
g.getColor = function()
    return unpack(color)
end
g.setColor = function(...)
    color = { ... }
end
g.getFont = function()
    return font
end
g.setFont = function(value)
    font = value
    record("font", value)
end
g.getLineWidth = function()
    return width
end
g.setLineWidth = function(value)
    width = value
end
local ui = require("SPTracking")
local function contains(name, value)
    for _, call in ipairs(calls) do
        if call[1] == name and (value == nil or call[2] == value) then
            return true
        end
    end
    return false
end
local function draw(state, y)
    calls = {}
    local result = ui.draw(state, 0, y or 580, passwordFont)
    assert(font == originalFont and width == 2 and color[1] == 0.2 and color[4] == 0.5)
    return result
end
for _, state in ipairs({
    false,
    {},
    { available = false, collected = 4, limit = 8 },
    { available = true, collected = -1, limit = 8 },
    { available = true, collected = 9, limit = 8 },
    { available = true, collected = 1.5, limit = 8 },
    { available = true, collected = 4, limit = 99 },
    { available = true, collected = 4, limit = 8, radarState = "complete" },
    { available = true, collected = 4, limit = 8, radarState = "direction" },
    { available = true, collected = 4, limit = 8, radarState = "direction", bearing = 0 / 0 },
    { available = true, collected = 4, limit = 8, radarState = "direction", bearing = math.huge },
    { available = true, collected = 4, limit = 8, radarState = "made-up" },
    { available = true, collected = 4, limit = 8, radarState = "glow", bearing = 0 },
}) do
    assert(not draw(state) and #calls == 0)
end
assert(not draw(nil))
assert(draw({ available = true, collected = 0, limit = 8 }))
assert(contains("print", "0") and not contains("ellipse") and not contains("polygon"))
for _, state in ipairs({ "idle", "near", "complete" }) do
    local count = state == "complete" and 8 or 4
    assert(draw({ available = true, collected = count, limit = 8, radarState = state }))
    assert(contains("print", tostring(count)) and contains("font", passwordFont) and contains("ellipse"))
end
assert(draw({ available = true, collected = 8, limit = 8, radarState = "direction" }))
assert(contains("ellipse") and not contains("rotate")) -- capacity overrides direction
for _, angle in ipairs({ 0, math.pi / 2, math.pi, math.pi * 1.5 }) do
    assert(draw({ available = true, collected = 3, limit = 8, radarState = "direction", bearing = angle }, 145))
    assert(contains("rotate", angle) and contains("polygon") and contains("rectangle"))
    assert(calls[2][1] == "translate" and calls[2][2] == 141 and calls[2][3] == 145)
end
-- Glow uses the Penpot "glow" variant: two unrotated halos, then the rotated compass.
assert(draw({ available = true, collected = 3, limit = 8, radarState = "direction", bearing = 1, glow = true }))
local halos, rotations = 0, 0
for _, call in ipairs(calls) do
    if call[1] == "ellipse" then
        halos = halos + 1
        assert(rotations == 0)
    end
    if call[1] == "rotate" then
        rotations = rotations + 1
    end
end
assert(halos == 2 and rotations == 2 and contains("polygon") and contains("rectangle"))
print("PASS SP guards, font, count-only state, completion, timer anchor, compass, glow and graphics restoration")
