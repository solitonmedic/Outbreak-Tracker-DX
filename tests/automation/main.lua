-- Purpose: test wrapper for the gameplay-frame tests. It runs the platform's own
-- main.lua (renamed frames-target.lua by tests/run_frames.py) unchanged and
-- drives it deterministically: a fixed 1/30 s step per frame, 40 warm-up frames,
-- then one control per 3 frames (the CONTROLS menu keys plus a mouse click on
-- CONTROLS). Input goes in before the tracker's update, as love.run delivers it.
-- The system's pointer events are ignored (a runner's pointer may or may not be
-- over the window); the hover/leave/rest steps move a synthetic pointer instead,
-- so the CONTROLS button's fade (views[].controls) is the same on every run.
-- Location/runtime: tests/automation/main.lua, copied into a game folder with
-- frames_dump.lua and frames_json.lua; LÖVE 11.5 on macOS, Linux or Windows.
-- Inputs: FRAMES_OUT (result JSON path), FRAMES_LOG (progress/error log path);
-- optional FRAMES_SHOTS folder and FRAMES_NAME for review screenshots (local only).
-- Outputs: FRAMES_OUT = {api = the reader API after warm-up (frames_dump.lua),
-- views = [{step, texts (drawn text in order), mapview, markers, controls (the
-- CONTROLS button's opacity)}], meta}.
-- Safety: never writes elsewhere; vsync is forced off because SDL waits for the
-- display before each present and would stall on a sleeping or virtual display.
-- A frame over 10 s, a Lua error or an early exit is logged and exits non-zero.
-- Run/check: through tests/run_frames.py, which compares the JSON.
local Json = require("frames_json")
local Dump = require("frames_dump")
local log = assert(io.open(assert(os.getenv("FRAMES_LOG")), "w"))
local function note(text)
    log:write(text, "\n")
    log:flush()
end
love.errorhandler = function(message)
    note("ERROR " .. debug.traceback(tostring(message), 2))
    log:close()
    os.exit(3)
end
love.window.setVSync(0)
for _, name in ipairs({ "setMode", "updateMode" }) do
    local original = love.window[name]
    love.window[name] = function(width, height, flags)
        local copy = {}
        for key, value in pairs(flags or {}) do
            copy[key] = value
        end
        copy.vsync = 0
        return original(width, height, copy)
    end
end
-- Drawn text, captured only while a view is being recorded.
local capture, texts = false, nil
local function flat(text)
    if type(text) == "table" then
        local parts = {}
        for _, part in ipairs(text) do
            if type(part) == "string" or type(part) == "number" then
                parts[#parts + 1] = tostring(part)
            end
        end
        return table.concat(parts)
    end
    return tostring(text)
end
for _, name in ipairs({ "print", "printf" }) do
    local original = love.graphics[name]
    love.graphics[name] = function(text, ...)
        if capture then
            texts[#texts + 1] = flat(text)
        end
        return original(text, ...)
    end
end
assert(love.filesystem.load("frames-target.lua"))()
note("LOADED")
-- Ignore the system's pointer events; the steps below send their own.
local targetFocus, targetMoved = love.mousefocus, love.mousemoved
local targetPressed, targetReleased = love.mousepressed, love.mousereleased
for _, name in ipairs({ "mousefocus", "mousemoved", "mousepressed", "mousereleased", "wheelmoved" }) do
    love[name] = function() end
end
local STEPS = {
    "main",
    "f1",
    "f1",
    "f2",
    "f2",
    "f2",
    "f3",
    "f3",
    "home",
    "l",
    "l",
    "i",
    "i",
    "t",
    "t",
    "q",
    "q",
    "e",
    "e",
    "f4",
    "f4",
    "m",
    "m",
    "v",
    "h",
    "d",
    "a",
    "1",
    "2",
    "3",
    "4",
    "kp1",
    "kp0",
    "n",
    "f",
    "f",
    "b",
    "home",
    "hover",
    "click-controls",
    "tab",
    "tab",
    "home",
    "close-controls",
    "leave",
    "wait",
    "hover",
    "rest",
}
local WARM, PER, DT = 40, 3, 1 / 30
local result = { views = {}, meta = { love = table.concat({ love.getVersion() }, "."), os = love.system.getOS() } }
local baseUpdate, baseDraw = love.update, love.draw
local frame, current, frameStart = 0, nil, love.timer.getTime()
debug.sethook(function()
    if love.timer.getTime() - frameStart > 10 then
        debug.sethook()
        note("ERROR frame took over 10 s: " .. debug.traceback("", 2))
        log:close()
        os.exit(4)
    end
end, "", 100000)
local function upvalue(fn, wanted)
    for i = 1, 200 do
        local name, value = debug.getupvalue(fn, i)
        if not name then
            return
        end
        if name == wanted then
            return value
        end
    end
end
local function controlsCentre()
    local menu = package.loaded["TrackerMenu"]
    local b = assert(menu and menu.launcher, "CONTROLS button was not placed")
    local sx, sy = upvalue(baseDraw, "scalex"), upvalue(baseDraw, "scaley")
    local wx, wy = love.window.getMode()
    return (b.x + b.w / 2) * wx / sx, (b.y + b.h / 2) * wy / sy, menu
end
local function clickControls()
    local x, y, menu = controlsCentre()
    assert(menu.alpha > 0, "CONTROLS button did not fade in under the pointer")
    targetPressed(x, y, 1)
    targetReleased(x, y, 1)
    assert(menu.open, "clicking CONTROLS did not open the menu")
end
local function hoverControls()
    local x, y = controlsCentre()
    if targetFocus then
        targetFocus(true)
    end
    if targetMoved then
        targetMoved(x, y, 0, 0, false)
    end
end
local function round(v)
    return math.floor(v * 10 + 0.5) / 10
end
local function markers()
    local V = package.loaded["MapView"]
    local m = {}
    if V and V.map and V.floor and Players then
        m.floor, m.players, m.enemies = V.floor, {}, {}
        for i = 1, 4 do
            local x, y, fallback = V.marker(V.map, V.floor, Players[i] or {})
            m.players[i] = x and { round(x), round(y), fallback and true or false } or false
        end
        for i = 1, 12 do
            local e = Enemies and Enemies[i]
            local x, y
            if e and V.enemyMarker then
                x, y = V.enemyMarker(V.map, V.floor, e)
            end
            m.enemies[i] = x and { round(x), round(y) } or false
        end
    end
    return m
end
local function copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = copy(v)
    end
    return out
end
local function finish()
    local out = assert(io.open(assert(os.getenv("FRAMES_OUT")), "w"))
    out:write(Json.encode(result))
    out:close()
    note("DONE")
    log:close()
    love.event.quit(0)
end
function love.update()
    frameStart = love.timer.getTime()
    frame = frame + 1
    if frame > WARM and (frame - WARM - 1) % PER == 0 then
        local index = (frame - WARM - 1) / PER + 1
        local step = STEPS[index]
        if not step then
            finish()
            return
        end
        current = index
        if step == "click-controls" then
            clickControls()
        elseif step == "hover" then
            hoverControls()
        elseif step == "close-controls" then
            -- Escape closes an open menu; with the menu closed it would quit.
            assert(package.loaded["TrackerMenu"].open, "the CONTROLS menu should still be open")
            love.keypressed("escape", "escape", false)
        elseif step == "leave" then
            if targetFocus then
                targetFocus(false)
            end
        elseif step == "rest" then
            package.loaded["TrackerMenu"].update(3) -- 3 s without pointer activity
        elseif step ~= "main" and step ~= "wait" then
            love.keypressed(step, step, false)
            if love.keyreleased then
                love.keyreleased(step, step)
            end
        end
        note("STEP " .. index .. " " .. step)
    end
    baseUpdate(DT)
    if frame == WARM then
        local tracker = package.loaded["luaoutbreaktracker"]
        result.api = tracker and Dump.api(tracker) or false
        note("API")
    end
end
function love.draw()
    local recording = current and (frame - WARM - 1) % PER == PER - 1
    if recording then
        capture, texts = true, {}
    end
    baseDraw()
    if recording then
        capture = false
        local menu = package.loaded["TrackerMenu"]
        result.views[current] = {
            step = STEPS[current],
            texts = texts,
            mapview = copy(GameInfo and GameInfo.mapview),
            markers = markers(),
            controls = menu and round(menu.alpha) or false,
        }
        -- Local review only (tests/run_frames.py --shots); the workflows never set it.
        local shots = os.getenv("FRAMES_SHOTS")
        if shots and shots ~= "" then
            local path =
                string.format("%s/%s-%02d-%s.png", shots, os.getenv("FRAMES_NAME") or "frame", current, STEPS[current])
            love.graphics.captureScreenshot(function(image)
                local file = io.open(path, "wb")
                if file then
                    file:write(image:encode("png"):getString())
                    file:close()
                end
            end)
        end
    end
end
