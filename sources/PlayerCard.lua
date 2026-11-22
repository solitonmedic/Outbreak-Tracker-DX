-- Purpose: shared player cards, inventory, health/death effects and clear effect badges.
-- Runtime/location: sources/PlayerCard.lua; LOVE 11.5/LuaJIT or Decky drawing bridge.
-- Inputs: existing player/room-master state, packaged atlas and UI elapsed time.
-- Outputs: full cards or reusable portrait crops; no file, PINE or game writes.
-- Run: main tracker/map cards. Check: tracker-tests/maps/check-presentation.lua.
local Effects = require("PlayerEffects")
PlayerCard = {}
PlayerCard.__index = PlayerCard

local IconPositions = {
    --[[ x  | y  ]]
    --
    { 8, 42 },
    { 56, 42 },
    { 8, 92 },
    { 56, 92 },
    { 117, 92 },
    { 105, 42 },
    { 154, 42 },
    { 105, 92 },
    { 154, 92 },
}

function PlayerCard:new(id)
    local o = {}
    o.id = id or 1
    o.icons = {}
    for i = 1, 9 do
        o.icons[i] = ItemIcon:new(unpack(IconPositions[i]))
    end

    o.nameLabel = Label:new(10, 4, "placeholder", SmallFont)
    o.nameLabelShadow = Label:new(12, 5, "placeholder", SmallFont, nil, nil, nil, nil, { 0, 0, 0, 1 })
    o.roomLabel = Label:new(110, 0, "placeholder", SmallFont, "center", "center", 190, 40)
    o.roomLabelShadow = Label:new(111, 1, "placeholder", SmallFont, "center", "center", 190, 40, { 0, 0, 0, 1 })
    --o.roomLabel_j		= Label:new(280, 2, "placeholder", SmallFont, "center", "up", 15, 145)
    --o.roomLabelShadow_j = Label:new(281, 3, "placeholder", SmallFont, "center", "up", 15, 145, {0, 0, 0, 1})
    o.healthLabel = Label:new(8, 20, "placeholder", VerySmallFont, "center", "up", 70, 10)

    return setmetatable(o, self)
end

-- UNLOCK bar over Alyssa's pick-tool icon.
-- Called from a pick-hint spot (File 1 and File 2), so it only runs while
-- Alyssa stands in that lock's hint range. isContainer: true for cabinets,
-- lockers and drawers, false for doors, nil when the hint does not say.
-- Each pick attempt sets the counter to 200 and lowers it; the lock opens at
-- <= 0. The bar shows the current attempt's progress and is hidden before an
-- attempt starts, once the lock opens, and whenever the reader has no matching
-- record (another player, or a release without a table).
function PlayerCard:drawUnlockBar(spotX, spotY, isContainer)
    if ReadLockCounter == nil then
        return
    end
    local counter = ReadLockCounter(self.id, spotX, spotY, isContainer)
    if counter == nil or counter <= 0 or counter > 200 then
        return
    end
    local progress = (200 - counter) / 200
    local r, g, b, a = love.graphics.getColor()
    local font = love.graphics.getFont()
    local x, y, w = 117, 118, 46
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", x, y, w, 20)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(MiniFont)
    love.graphics.printf("UNLOCK", x, y, w, "center")
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.rectangle("fill", x + 3, y + 13, w - 6, 5)
    love.graphics.setColor(1, 0.8, 0.1, 1)
    love.graphics.rectangle("fill", x + 3, y + 13, (w - 6) * progress, 5)
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, a)
end

-- portraitOnly reuses the bust, effect timers, virus and room-master crown for
-- compact map cards. Inventory is drawn in its own complete region there.
function PlayerCard:draw(x, y, portraitOnly)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(x, y)

    local player = Players[self.id]
    Effects.background(player, 0, 0, 300, 145, TrackerPresentationTime or 0)
    local sb = love.graphics.newSpriteBatch(UIAtlas.tex)
    local bustname = "bust" .. Players[self.id].type
    local _, _, bw, bh = UIAtlas.quads[bustname]:getViewport()
    local scale = 140 / bh

    if Effects.health(player) == "dead" then
        sb:setColor(1, 0.08, 0.08, 1)
    elseif Players[self.id].inGame == false then
        sb:setColor(1, 1, 1, 0.5)
    else
        sb:setColor(1, 1, 1, 1)
    end
    UIAtlas:addSB(sb, bustname, 300 - bw * scale, 145 - bh * scale, 0, scale, scale)
    if portraitOnly then
        love.graphics.draw(sb)
    else
        sb:setColor(1, 1, 1, 1)
        if
            not (
                Players[self.id].status == "Dead"
                or Players[self.id].status == "Down"
                or Players[self.id].status == "Zombie"
            )
        then
            sb:setColor(unpack(GetConditionColor(GetConditionName(Players[self.id].HP, Players[self.id].maxHP))))
        else
            sb:setColor(unpack(GetConditionColor(GetConditionName(0, 2))))
        end
        UIAtlas:addSB(sb, "healthmask", 8, 5)
        sb:setColor(1, 1, 1, 1)
        UIAtlas:addSB(sb, "statusbar", 0, 2)
        UIAtlas:addSB(sb, GetVirusState(Players[self.id].virus), 86, 18)
        if
            not (
                Players[self.id].type == "Yoko"
                or Players[self.id].type == "David"
                or Players[self.id].type == "Cindy"
            ) and not (Players[self.id].status == "Dead" or Players[self.id].status == "Zombie")
        then
            sb:setColor(20 / 255, 48 / 255, 85 / 255, 0.8)
            UIAtlas:addSB(sb, "inventorymask", 8, 42)
            UIAtlas:addSB(sb, "ispecialmask", 118, 92)
            sb:setColor(1, 1, 1, 1)
            UIAtlas:addSB(sb, "invSingle", 0, 37)
            UIAtlas:addSB(sb, "invSpecial", 110, 89)
        else
            sb:setColor(20 / 255, 48 / 255, 85 / 255, 0.8)
            UIAtlas:addSB(sb, "inventorymask", 8, 42)
            if not (Players[self.id].status == "Dead" or Players[self.id].status == "Zombie") then
                sb:setColor(50 / 255, 120 / 255, 70 / 255, 0.8)
            end
            UIAtlas:addSB(sb, "inventorymask", 106, 42)
            sb:setColor(1, 1, 1, 1)
            UIAtlas:addSB(sb, "invDouble", 0, 37)
        end
        if Players[self.id].type == "Alyssa" and not (Players[self.id].status == "Dead") then
            love.graphics.setFont(VerySmallFont)
            love.graphics.printf("I", 118, 92, 12, "center")
            love.graphics.printf("S", 130, 92, 12, "center")
            love.graphics.printf("W", 118, 104, 12, "center")
            love.graphics.printf("P", 130, 104, 12, "center")
        end

        love.graphics.draw(sb)

        for i = 1, 4 do
            if not (Players[self.id].inventory[i].id == -1) then
                self.icons[i].type = Players[self.id].inventory[i].type
                self.icons[i].count = Players[self.id].inventory[i].count
                local equip = Players[self.id].equipped
                if equip == 0 then
                    self.icons[i].equipped = false
                else
                    self.icons[i].equipped = (equip == Players[self.id].inventory[i].id)
                end
                self.icons[i]:draw()
            end
        end
        if
            not (
                Players[self.id].type == "Yoko"
                or Players[self.id].type == "David"
                or Players[self.id].type == "Cindy"
            )
            and not (Players[self.id].specialItem.id == -1)
            and not (Players[self.id].status == "Dead" or Players[self.id].status == "Zombie")
        then
            self.icons[5].type = Players[self.id].specialItem.type
            self.icons[5].count = Players[self.id].specialItem.count
            local equip = Players[self.id].equipped
            if equip <= 0 then
                self.icons[5].equipped = false
            else
                self.icons[5].equipped = (equip == Players[self.id].specialItem.id)
            end
            if Players[self.id].specialItem.type == 403 then
                self.icons[5]:draw(false)
            else
                self.icons[5]:draw(true)
            end
        else
            for i = 6, 9 do
                if not (Players[self.id].specialInventory[i - 5].id == -1) then
                    self.icons[i].type = Players[self.id].specialInventory[i - 5].type
                    self.icons[i].count = Players[self.id].specialInventory[i - 5].count
                    local equip = Players[self.id].equipped
                    if equip <= 0 then
                        self.icons[i].equipped = false
                    else
                        self.icons[i].equipped = (equip == Players[self.id].specialInventory[i - 5].id)
                    end
                    self.icons[i]:draw()
                end
            end
        end

        love.graphics.setFont(VerySmallFont)
        love.graphics.setColor(0, 1, 0, 1)
        if Players[self.id].type == "Alyssa" and not (Players[self.id].status == "Dead") then
            if GameInfo.scenario == "outbreak" then
                if Players[self.id].roomID == 1 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 922211 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 922211 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1261926 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1261926 + 25000
                    then
                        self:drawUnlockBar(9222.11, 12619.26, false) -- J's Bar
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --J's Bar
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 5 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 867210 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 867210 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1301926 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1301926 + 25000
                    then
                        self:drawUnlockBar(8672.10, 13019.26, false) -- Staff Room
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --Staff Room
                        else
                            love.graphics.printf("P", 130, 104, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 7 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 915857 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 915857 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1245250 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1245250 + 25000
                    then
                        self:drawUnlockBar(9158.57, 12452.50, true) -- Drawing Room (Cabinet)
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Drawing Room (Cabinet)
                        else
                            love.graphics.printf("S", 130, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 14 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 787211 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 787211 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1301926 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1301926 + 25000
                    then
                        self:drawUnlockBar(7872.11, 13019.26, false) -- Rooftop
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("P", 130, 104, 12, "center") --Rooftop
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "below freezing point" then
                if Players[self.id].roomID == 15 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 560641 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 560641 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 425127 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 425127 + 25000
                    then
                        self:drawUnlockBar(5606.41, 4251.27, true) -- Break Room (Locker)
                        if GameInfo.difficulty == "hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --Break Room (Locker)
                        else
                            love.graphics.printf("S", 130, 92, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "the hive" then
                if Players[self.id].roomID == 14 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 645873 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 645873 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 322941 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 322941 + 25000
                    then
                        self:drawUnlockBar(6458.73, 3229.41, true) -- Locker Room (Locker)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --Locker Room (Locker)
                        else
                            love.graphics.printf("P", 130, 104, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 5 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 661941 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 661941 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 193027 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 193027 + 25000
                    then
                        self:drawUnlockBar(6619.41, 1930.27, true) -- Office (Drawer)
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --Office (Drawer)
                        else
                            love.graphics.printf("W", 118, 104, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "hellfire" then
                if Players[self.id].roomID == 29 or Players[self.id].roomID == 34 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 967660 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 967660 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 977602 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 977602 + 25000
                    then
                        self:drawUnlockBar(9676.60, 9776.02, false) -- 1F Corridor→ Lounge Stairs
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --1F Corridor→ Lounge Stairs
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 36 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 1014602 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 1014602 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1042339 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1042339 + 25000
                    then
                        self:drawUnlockBar(10146.02, 10423.39, false) -- Room 102
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Room 102
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 40 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 769602 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 769602 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1022339 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1022339 + 25000
                    then
                        self:drawUnlockBar(7696.02, 10223.39, false) -- Room 201
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Room 201
                        elseif GameInfo.difficulty == "easy" or GameInfo.difficulty == "normal" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 44 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 1014602 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 1014602 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 1042339 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 1042339 + 25000
                    then
                        self:drawUnlockBar(10146.02, 10423.39, false) -- Room 202
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --Room 202
                        else
                            love.graphics.printf("W", 118, 104, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 42 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 861258 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 861258 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 970073 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 970073 + 25000
                    then
                        self:drawUnlockBar(8612.58, 9700.73, true) -- Store Room (Locker)
                        if GameInfo.difficulty == "hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Store Room (Locker)
                        elseif GameInfo.difficulty == "easy" or GameInfo.difficulty == "normal" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "decisions,decisions" then
                if Players[self.id].roomID == 78 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 340476 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 340476 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 828902 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 828902 + 25000
                    then
                        self:drawUnlockBar(3404.76, 8289.02, true) -- 1F Elevator Passway (Locker)
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --1F Elevator Passway (Locker)
                        else
                            love.graphics.printf("S", 130, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 55 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 302041 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 302041 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 424727 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 424727 + 25000
                    then
                        self:drawUnlockBar(3020.41, 4247.27, true) -- B4F Control Room (Locker)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --B4F Control Room (Locker)
                        else
                            love.graphics.printf("P", 130, 104, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 54 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 337211 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 337211 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 386927 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 386927 + 25000
                    then
                        self:drawUnlockBar(3372.11, 3869.27, false) -- T-shaped Corridor
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --T-shaped Corridor
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        else
                            love.graphics.printf("P", 130, 104, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 58 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 272927 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 272927 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 352789 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 352789 + 25000
                    then
                        self:drawUnlockBar(2729.27, 3527.89, false) -- Store Room
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Store Room
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "wild things" then
                if
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1303073 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1303073 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 1337211 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 1337211 + 25000
                then
                    self:drawUnlockBar(13030.73, 13372.11, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("W", 118, 104, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    else
                        love.graphics.printf("P", 130, 104, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1473000 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1473000 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 1431471 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 1431471 + 25000
                then
                    self:drawUnlockBar(14730.00, 14314.71, false) -- wild things door (counter at +0x64 seen in a recorded pick)
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("I", 118, 92, 12, "center")
                    else
                        love.graphics.printf("W", 118, 104, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1442788 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1442788 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 1454573 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 1454573 + 25000
                then
                    self:drawUnlockBar(14427.88, 14545.73, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    else
                        love.graphics.printf("I", 118, 92, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1418758 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1418758 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 1528529 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 1528529 + 25000
                then
                    self:drawUnlockBar(14187.58, 15285.29, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                        love.graphics.printf("W", 118, 104, 12, "center")
                    else
                        love.graphics.printf("S", 130, 92, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1067211 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1067211 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 896926 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 896926 + 25000
                then
                    self:drawUnlockBar(10672.11, 8969.26, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("I", 118, 92, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 986926 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 986926 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 677789 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 677789 + 25000
                then
                    self:drawUnlockBar(9869.26, 6777.89, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("I", 118, 92, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("W", 118, 104, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 632211 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 632211 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 876926 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 876926 + 25000
                then
                    self:drawUnlockBar(6322.11, 8769.26, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 714458 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 714458 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 781273 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 781273 + 25000
                then
                    self:drawUnlockBar(7144.58, 7812.73, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    else
                        love.graphics.printf("P", 130, 104, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 986926 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 986926 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 462789 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 462789 + 25000
                then
                    self:drawUnlockBar(9869.26, 4627.89, nil) -- wild things, lock type not labelled
                    if GameInfo.difficulty == "normal" or GameInfo.difficulty == "very hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    else
                        love.graphics.printf("I", 118, 92, 12, "center")
                    end
                end
            elseif GameInfo.scenario == "underbelly" then
                if Players[self.id].roomID == 18 or Players[self.id].roomID == 7 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 812397 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 812397 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 292661 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 292661 + 25000
                    then
                        self:drawUnlockBar(8123.97, 2926.61, false) -- East Concourse
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("P", 130, 104, 12, "center") --East Concourse
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --East Concourse
                        end
                    end
                end
                if Players[self.id].roomID == 3 or Players[self.id].roomID == 7 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 467602 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 467602 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 287339 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 287339 + 25000
                    then
                        self:drawUnlockBar(4676.02, 2873.39, false) -- West Concourse
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --West Concourse
                        end
                    end
                end
                if Players[self.id].roomID == 7 or Players[self.id].roomID == 11 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 692339 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 692339 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 287398 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 287398 + 25000
                    then
                        self:drawUnlockBar(6923.39, 2873.98, false) -- Break Room (Front)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --Break Room (Front)
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("W", 118, 104, 12, "center") --Break Room (Front)
                        end
                    end
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 697660 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 697660 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 162602 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 162602 + 25000
                    then
                        self:drawUnlockBar(6976.60, 1626.02, false) -- Break Room (Back)
                        if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                            love.graphics.printf("I", 118, 92, 12, "center") --Break Room (Back)
                        end
                    end
                end
                if Players[self.id].roomID == 9 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 573127 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 573127 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 242559 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 242559 + 25000
                    then
                        self:drawUnlockBar(5731.27, 2425.59, true) -- Control room (Drawer)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --Control room (Drawer)
                        else
                            love.graphics.printf("P", 130, 104, 12, "center") --Control room (Drawer)
                        end
                    end
                end
            elseif GameInfo.scenario == "desperate times" then
                if Players[self.id].roomID == 1 or Players[self.id].roomID == 4 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 431927 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 431927 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 947788 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 947788 + 25000
                    then
                        self:drawUnlockBar(4319.27, 9477.88, false) -- 1F Lobby→ Main Hall
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --1F Lobby→ Main Hall
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 4 or Players[self.id].roomID == 20 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 564839 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 564839 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 847397 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 847397 + 25000
                    then
                        self:drawUnlockBar(5648.39, 8473.97, false) -- 1F Lobby→ Hallway
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --1F Lobby→ Hallway
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 2 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 211841 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 211841 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 890226 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 890226 + 25000
                    then
                        self:drawUnlockBar(2118.41, 8902.26, true) -- Reception Desk (Drawer)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --Reception Desk (Drawer)
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 9 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 585841 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 585841 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 723327 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 723327 + 25000
                    then
                        self:drawUnlockBar(5858.41, 7233.27, true) -- 1F East Passage (Cabinet)
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --1F East Passage (Cabinet)
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 11 or Players[self.id].roomID == 12 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 567660 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 567660 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 842602 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 842602 + 25000
                    then
                        self:drawUnlockBar(5676.60, 8426.02, false) -- B1F East Hall
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center") --B1F East Hall
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 14 or Players[self.id].roomID == 15 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 137339 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 137339 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 862397 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 862397 + 25000
                    then
                        self:drawUnlockBar(1373.39, 8623.97, nil) -- desperate times, lock type not labelled
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
                if Players[self.id].roomID == 9 or Players[self.id].roomID == 5 then
                    if
                        math.floor(Players[self.id].positionX * 100 + 0.5) > 592660 - 25000
                        and math.floor(Players[self.id].positionX * 100 + 0.5) < 592660 + 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) > 852602 - 25000
                        and math.floor(Players[self.id].positionY * 100 + 0.5) < 852602 + 25000
                    then
                        self:drawUnlockBar(5926.60, 8526.02, nil) -- desperate times, lock type not labelled
                        if GameInfo.difficulty == "very hard" then
                            love.graphics.printf("S", 130, 92, 12, "center")
                        elseif GameInfo.difficulty == "hard" then
                            love.graphics.printf("P", 130, 104, 12, "center")
                        else
                            love.graphics.printf("I", 118, 92, 12, "center")
                        end
                    end
                end
            elseif GameInfo.scenario == "flashback" then
                if
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 854792 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 854792 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 667988 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 667988 + 25000
                then
                    self:drawUnlockBar(8547.92, 6679.88, nil) -- flashback, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    else
                        love.graphics.printf("I", 118, 92, 12, "center")
                    end
                elseif
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 1067339 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 1067339 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 637398 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 637398 + 25000
                then
                    self:drawUnlockBar(10673.39, 6373.98, nil) -- flashback, lock type not labelled
                    if GameInfo.difficulty == "very hard" then
                        love.graphics.printf("S", 130, 92, 12, "center")
                    elseif GameInfo.difficulty == "hard" then
                        love.graphics.printf("P", 130, 104, 12, "center")
                    end
                end
            elseif GameInfo.scenario == "end of the road" then
                if
                    math.floor(Players[self.id].positionX * 100 + 0.5) > 481741 - 25000
                    and math.floor(Players[self.id].positionX * 100 + 0.5) < 481741 + 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) > 332327 - 25000
                    and math.floor(Players[self.id].positionY * 100 + 0.5) < 332327 + 25000
                then
                    self:drawUnlockBar(4817.41, 3323.27, nil) -- end of the road, lock type not labelled
                    if GameInfo.difficulty == "hard" or GameInfo.difficulty == "very hard" then
                        love.graphics.printf("I", 118, 92, 12, "center")
                    else
                        love.graphics.printf("S", 130, 92, 12, "center")
                    end
                end
            end
        end

        love.graphics.setColor(1, 1, 1, 1)

        self.nameLabel.text = Players[self.id].name:upper()
        self.nameLabelShadow.text = Players[self.id].name:upper()
        self.nameLabelShadow:draw()
        self.nameLabel:draw()

        self.healthLabel.color = GetStatusColor(self.id)
        self.healthLabel.text = GetPlayerHealthString(self.id)
        self.healthLabel:draw()

        self.roomLabel.text = GetRoomName(GameInfo.scenario, Players[self.id].roomID)
        self.roomLabelShadow.text = GetRoomName(GameInfo.scenario, Players[self.id].roomID)
        self.roomLabelShadow:draw()
        self.roomLabel:draw()
    end

    local a = Players[self.id].antivirustime
    local b = Players[self.id].antivirusgtime
    local c = Players[self.id].herbtime
    local d = Players[self.id].bleedtime
    local e = Players[self.id].status

    if GameInfo.currentFile == 1 then
        if b > 0 then
            ItemIcons:draw("1/317", 250, 64, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string5(b) }, 241, 73, 60, "right")
            love.graphics.printf({ { 1, 1, 1, 1 }, Time2string5(b) }, 240, 72, 60, "right")
        end
    end
    if a > c then
        if a > 0 then
            ItemIcons:draw("1/316", 250, 82, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string5(a) }, 241, 91, 60, "right")
            love.graphics.printf({ { 1, 1, 1, 1 }, Time2string5(a) }, 240, 90, 60, "right")
        end
    else
        if c > 0 then
            ItemIcons:draw("1/316", 250, 82, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string5(c) }, 241, 91, 60, "right")
            love.graphics.printf({ { 1, 1, 1, 1 }, Time2string5(c) }, 240, 90, 60, "right")
        end
    end

    if d > 0 and (e == "Bleed" or e == "Poison+Bleed" or e == "Gas+Bleed") then
        if b > 0 and GameInfo.currentFile == 1 then
            ItemIcons:draw("1/311", 250, 46, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string4(d) }, 241, 55, 60, "right")
            love.graphics.printf({ { 1, 0, 0, 1 }, Time2string4(d) }, 240, 54, 60, "right")
        end
        if a > 0 or c > 0 then
            ItemIcons:draw("1/311", 250, 64, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string4(d) }, 241, 73, 60, "right")
            love.graphics.printf({ { 1, 0, 0, 1 }, Time2string4(d) }, 240, 72, 60, "right")
        else
            ItemIcons:draw("1/311", 250, 82, 0, 0.65)
            love.graphics.printf({ { 0, 0, 0, 1 }, Time2string4(d) }, 241, 91, 60, "right")
            love.graphics.printf({ { 1, 0, 0, 1 }, Time2string4(d) }, 240, 90, 60, "right")
        end
    end

    --self.roomLabel_j.text = GetRoomName_j(GameInfo.scenario, Players[self.id].roomID)
    --self.roomLabelShadow_j.text = GetRoomName_j(GameInfo.scenario, Players[self.id].roomID)
    --self.roomLabelShadow_j:draw()
    --self.roomLabel_j:draw()

    love.graphics.setFont(VirusFont)
    if Players[self.id].specialItem.type == 403 then
        love.graphics.printf(
            { { 25 / 255, 255 / 255, 25 / 255, 1 }, tostring(Players[self.id].critBonus) .. "%" },
            118,
            125,
            46,
            "right"
        )
    end
    -- Here goes some weird magic 150, 120
    local tx, ty = 192, 125
    love.graphics.push()
    love.graphics.translate(186, 122)
    love.graphics.scale(1.45, 1.45)
    love.graphics.printf(string.format("%.2f%%", player.virus), 0, 0, 76, "right")
    love.graphics.pop()
    -- weird magic ends here

    --local siz = math.floor(math.floor((Players[self.id].size)*100))
    --love.graphics.printf(string.format("%d", siz) .. "%", tx+46, ty+3.5-60, 60, "right", 0, 1.0, 1.0)

    local pow = math.floor(math.floor(Players[self.id].power * 100 + 0.5))
    if pow ~= 100 or (player.basePower or 1) > 1 then
        love.graphics.printf(
            { { 25 / 255, 255 / 255, 255 / 255, 1 }, string.format("%d", pow) .. "%" },
            tx + 46,
            ty + 3.5 - 20,
            60,
            "right",
            0,
            1.0,
            1.0
        )
    end

    local roomMaster = RoomMasters[player.roomID]
    local master = player.inGame
        and player.roomID > 0
        and roomMaster
        and roomMaster.enabled
        and roomMaster.roommaster == self.id
    if master then
        UIAtlas:draw("room master crown", 267, Effects.timers(player) and 28 or 88.5)
    end
    love.graphics.setFont(MiniFont or VerySmallFont)
    love.graphics.setColor(
        unpack(Effects.markerColor(player, Effects.slotColors[self.id], TrackerPresentationTime or 0))
    )
    local badgeX, badgeY = 276, Effects.badgeY(player, master)
    -- The compact bust crops off the name row; keep a lifted badge inside the
    -- portrait, beside the lifted crown when both effect timers and crown show.
    if portraitOnly and badgeY < 26 then
        badgeX = 180
        badgeY = 28
    end
    love.graphics.printf("P" .. self.id, badgeX, badgeY, 22, "right")
    love.graphics.setColor(1, 1, 1, 1)

    --local spd = math.floor(math.floor(Players[self.id].speed*100+0.5))
    --love.graphics.printf(string.format("%d", spd) .. "%", tx+46, ty+3.5-40, 60, "right", 0, 1.0, 1.0)

    --local px = math.floor(math.floor(Players[self.id].positionX*100+0.5))
    --local py = math.floor(math.floor(Players[self.id].positionY*100+0.5))
    --love.graphics.setFont(VerySmallFont)
    --love.graphics.printf({{25/255, 255/255, 255/255, 1},string.format("%d", px)}, tx+46, ty+3.5-60, 60, "right", 0, 1.0, 1.0)
    --love.graphics.printf({{25/255, 255/255, 255/255, 1},string.format("%d", py)}, tx+46, ty+3.5-40, 60, "right", 0, 1.0, 1.0)
    love.graphics.pop()
    --love.graphics.printf("I",118, 92,12, "center")
    --love.graphics.printf("S",130, 92,12, "center")
    --love.graphics.printf("W",118, 104,12, "center")
    --love.graphics.printf("P",130, 104,12, "center")
end
