-- Purpose: reserve readable scenario/clock/set rows in every shared map layout.
-- Runtime/location: sources/MapPresentationLayout.lua; shared LuaJIT/LÖVE/Decky.
-- Inputs: generated MapLayout geometry and scenario/timer/hint availability;
-- outputs independent layout copies, reserving space only where it is needed.
-- Safety: static geometry only, no files/memory/game writes. Reusable adaptation.
-- Run: MapView requires automatically. Check: maps/check-presentation.lua and preview.
local function clone(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = clone(v)
    end
    return out
end
local function build(shift)
    local layouts = clone(require("MapLayout"))
    for key, l in pairs(layouts) do
        -- Labels and portraits occupy separate rows above the map.
        l.viewport.y = l.viewport.y + 20
        l.viewport.h = l.viewport.h - 20
        if l.cards then
            l.viewport.h = l.viewport.h - shift
            for _, name in ipairs({
                "legendFill",
                "legendFrame",
                "clock",
                "itemset",
                "plus",
                "plusText",
                "minus",
                "minusText",
                "fit",
                "fitText",
                "follow",
                "followText",
            }) do
                if l[name] then
                    l[name].y = l[name].y - shift
                end
            end
            for _, entry in ipairs(l.legends) do
                entry.slot.y = entry.slot.y - shift
                entry.name.y = entry.name.y - shift
            end
            l.information = {
                x = 6,
                y = l.legendFrame.y + l.legendFrame.h + 4,
                w = l.width - 12,
                h = l.cards[1].y - l.legendFrame.y - l.legendFrame.h - 8,
            }
        else
            l.information = { x = 436, y = 640, w = 314, h = 96 }
        end
    end
    return layouts
end
local variants = { [16] = build(16), [40] = build(40), [60] = build(60) }
local M = {}
function M.select(key, game, hint)
    -- Reserve the radar row even during a dropped sample: avoid map resizing.
    local shift = 16
    if game.scenario == "desperate times" or game.scenario == "wild things" then
        shift = 60
    elseif game.scenario == "underbelly" and (game.escapetime or 0) > 0 and game.escapetime ~= 65535 then
        shift = 60
    elseif (hint and hint ~= "") or ((game.escapetime or 0) > 0 and game.escapetime ~= 65535) then
        shift = 40
    end
    return variants[shift][key]
end
return M
