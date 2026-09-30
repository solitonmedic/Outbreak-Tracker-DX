local game_dir = love.filesystem.getSource()
local parent_dir = game_dir:match("^(.*)/[^/]+$")
package.cpath = game_dir .. "/?.so;" .. (parent_dir and parent_dir .. "/?.so;" or "") .. package.cpath
assert(love.filesystem.load("main_base.lua"))()

-- The upstream item-location screen draws every populated pickup slot. On
-- Keep the reader data intact but limit that screen to the room occupied.
-- by the first active player (the local player's game-world slot).
local function current_item_room_id()
	for i = 1, 4 do
		if Players[i] and Players[i].inGame and Players[i].roomID and Players[i].roomID > 0 then
			return Players[i].roomID
		end
	end
	return 0
end

local function item_is_in_current_room(item)
	local room_id = current_item_room_id()
	return item and room_id > 0 and item.roomid == room_id
end

local draw_item_set = ItemCard2.draw
function ItemCard2:draw(x, y)
	if not item_is_in_current_room(Items2[self.id]) then
		return
	end
	draw_item_set(self, x, y)
end

local draw_item_location = ItemCard3.draw
function ItemCard3:draw(x, y)
	if not item_is_in_current_room(Items2[self.id]) then
		return
	end
	draw_item_location(self, x, y)
end

-- PINE memory reads are much more expensive than ordinary local Lua work.
-- Keep the main update loop live, but cache only the bulky secondary views.
local tracker
for i = 1, math.huge do
	local name, value = debug.getupvalue(love.update, i)
	if not name then break end
	if name == "tracker" then
		tracker = value
		break
	end
end

if tracker then
	local get_item = tracker.getItem
	local get_item2 = tracker.getItem2
	local get_room_master = tracker.getRoomMaster
	local item_cache, item2_cache, room_master_cache = {}, {}, {}
	local item_time, item2_time, room_master_time = 0, {}, {}

	tracker.getItem = function(id)
		local now = love.timer.getTime()
		if not item_cache[id] or now - item_time >= 0.08 then
			item_cache[id] = get_item(id)
			item_time = now
		end
		return item_cache[id]
	end

	tracker.getItem2 = function(id)
		local now = love.timer.getTime()
		if not item2_cache[id] or now - (item2_time[id] or 0) >= 0.15 then
			item2_cache[id] = get_item2(id)
			item2_time[id] = now
		end
		return item2_cache[id]
	end

	tracker.getRoomMaster = function(id)
		local now = love.timer.getTime()
		if not room_master_cache[id] or now - (room_master_time[id] or 0) >= 0.25 then
			room_master_cache[id] = get_room_master(id)
			room_master_time[id] = now
		end
		return room_master_cache[id]
	end
end
