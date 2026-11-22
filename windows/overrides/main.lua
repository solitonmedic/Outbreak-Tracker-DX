-- Load the Windows reader DLL from the fused executable's folder. LÖVE's own C
-- loader cannot load a library from a mounted folder (it joins the real folder
-- with the virtual path), so put that folder on Lua's search path instead and
-- keep the default path after it. The extension follows the system so the same
-- file can be checked on macOS (tracker-tests/desktop/check-desktop-smoke.py).
local runtimeDirectory = love.filesystem.getSourceBaseDirectory()
local extension = love.system.getOS() == "Windows" and "dll" or "so"
package.cpath = runtimeDirectory .. "/?." .. extension .. ";" .. package.cpath

local trackerMain, err = love.filesystem.load("tracker-main.lua")
assert(trackerMain, err)
trackerMain()
