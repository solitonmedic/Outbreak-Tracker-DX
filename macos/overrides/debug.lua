-- Debug build: run the macOS tracker and record full EE-RAM checkpoints like
-- tools-n-shit/record-pine-ee-run.py. Recording starts when the tracker opens.
--
--   F9   stop the current recording, or start a new one
--   F10  add a marker (lines typed into a launching terminal are markers too)
--
-- Environment overrides:
--   OUTBREAK_RECORD_LABEL      label of the first run (default: tracker-debug-<local time>)
--   OUTBREAK_RECORD_DIR        parent folder for run folders
--   OUTBREAK_RECORD_INTERVAL   seconds between checkpoint start times (default: 10)
--   OUTBREAK_RECORD_AUTOSTART  set to 0 to wait for F9 before recording

assert(love.filesystem.load("main_mac.lua"))()

local game_dir = love.filesystem.getSource()
local open_recorder = assert(package.loadlib(game_dir .. "/luaoutbreaktracker.so", "luaopen_luaoutbreakrecorder"))
local recorder = open_recorder()

local output_dir = os.getenv("OUTBREAK_RECORD_DIR")
	or (os.getenv("HOME") or ".") .. "/Documents/Outbreak Tracker Recordings"
local interval = tonumber(os.getenv("OUTBREAK_RECORD_INTERVAL") or "") or 10
local next_label = os.getenv("OUTBREAK_RECORD_LABEL")
local base_title = "Outbreak Status Tracker (debug)"
local recording = false

local function start_recording()
	local label = next_label or ("tracker-debug-" .. os.date("%Y%m%d-%H%M%S"))
	next_label = nil
	local ok, err = recorder.start(label, output_dir, interval)
	if ok then
		recording = true
		print("Recorder: started " .. label .. " in " .. output_dir)
	else
		print("Recorder: " .. tostring(err))
		love.window.setTitle(base_title .. " - recorder: " .. tostring(err))
	end
end

local function stop_recording()
	recorder.stop()
	recording = false
end

local function update_title()
	local status = recorder.status()
	local text
	if status.state == "recording" then
		text = "REC " .. status.label .. " (" .. status.checkpoints .. " checkpoints)"
	elseif status.state == "waiting" then
		text = "waiting for PCSX2 to record " .. status.label
	elseif status.state == "error" then
		text = "recorder stopped: " .. status.message
		recording = false
	elseif status.state == "stopped" then
		text = "not recording (F9 to start)"
		recording = false
	else
		text = "not recording (F9 to start)"
	end
	love.window.setTitle(base_title .. " - " .. text)
end

local tracker_update = love.update
local title_timer = 0
function love.update(dt)
	tracker_update(dt)
	title_timer = title_timer + dt
	if title_timer >= 1 then
		title_timer = 0
		update_title()
	end
end

local tracker_keypressed = love.keypressed
function love.keypressed(key, ...)
	if key == "f9" then
		if recording then stop_recording() else start_recording() end
		update_title()
		return
	end
	if key == "f10" then
		recorder.mark("tracker hotkey")
		return
	end
	tracker_keypressed(key, ...)
end

local tracker_quit = love.quit
function love.quit()
	if tracker_quit and tracker_quit() then
		return true
	end
	stop_recording()
	return false
end

if os.getenv("OUTBREAK_RECORD_AUTOSTART") ~= "0" then
	start_recording()
end
update_title()
