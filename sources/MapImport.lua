-- Purpose: reusable command-line disc importer used by the Decky service.
-- Runtime/location: sources/MapImport.lua; LuaJIT; MapData.lua beside this file.
-- Inputs: arg[1] disc folder/ISO, arg[2] existing private cache directory.
-- Outputs: maps/jpN cache files via atomic replacements; status on stdout.
-- Safety: read-only disc; writes cache only, no PINE, recordings or workbook.
-- Run from plugin: luajit shared/MapImport.lua /path/to/disc /path/to/cache
-- Check: five cached .dat maps and an index, then reopen a map view.
local directory=arg[0]:match("^(.*[/\\])") or "./"
package.path=directory.."?.lua;"..package.path
local Data=require "MapData"
local cache=assert(arg[2],"Cache directory required")
local game=Data.import(assert(arg[1],"Disc path required"),function(path,bytes)
    local target=cache.."/"..path
    local file=assert(io.open(target..".tmp","wb"),"Cannot write map cache")
    assert(file:write(bytes)); assert(file:close())
    assert(os.rename(target..".tmp",target),"Cannot publish map cache")
end)
print("Imported Japanese File "..game.." maps")
