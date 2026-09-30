-- Mount the fused executable's directory so LÖVE can load the Windows reader DLL.
local runtimeDirectory = love.filesystem.getSourceBaseDirectory()
assert(love.filesystem.mount(runtimeDirectory, "windows-runtime"), "Could not mount the Windows runtime directory")
love.filesystem.setCRequirePath("windows-runtime/??;" .. love.filesystem.getCRequirePath())

local trackerMain, err = love.filesystem.load("tracker-main.lua")
assert(trackerMain, err)
trackerMain()
