ItemCard = {}
ItemCard.__index = ItemCard
local cellWidth, cellHeight = 46, 48 -- one icon cell of the inventory grid
local IconPositions = {
    --[[ x  | y  ]]
    --
    { 0 * cellWidth, 1 * cellHeight - cellHeight }, --1
    { 1 * cellWidth, 1 * cellHeight - cellHeight }, --2
    { 2 * cellWidth, 1 * cellHeight - cellHeight }, --3
    { 3 * cellWidth, 1 * cellHeight - cellHeight }, --4
    { 4 * cellWidth, 1 * cellHeight - cellHeight }, --5
    { 5 * cellWidth, 1 * cellHeight - cellHeight }, --6
    { 6 * cellWidth, 1 * cellHeight - cellHeight }, --7
    { 7 * cellWidth, 1 * cellHeight - cellHeight }, --8
    { 0 * cellWidth, 2 * cellHeight - cellHeight }, --9
    { 1 * cellWidth, 2 * cellHeight - cellHeight }, --10
    { 2 * cellWidth, 2 * cellHeight - cellHeight }, --11
    { 3 * cellWidth, 2 * cellHeight - cellHeight }, --12
    { 4 * cellWidth, 2 * cellHeight - cellHeight }, --13
    { 5 * cellWidth, 2 * cellHeight - cellHeight }, --14
    { 6 * cellWidth, 2 * cellHeight - cellHeight }, --15
    { 7 * cellWidth, 2 * cellHeight - cellHeight }, --16
    { 0 * cellWidth, 1 * cellHeight - cellHeight }, --1
    { 1 * cellWidth, 1 * cellHeight - cellHeight }, --2
    { 2 * cellWidth, 1 * cellHeight - cellHeight }, --3
    { 3 * cellWidth, 1 * cellHeight - cellHeight }, --4
    { 4 * cellWidth, 1 * cellHeight - cellHeight }, --5
    { 5 * cellWidth, 1 * cellHeight - cellHeight }, --6
    { 6 * cellWidth, 1 * cellHeight - cellHeight }, --7
    { 7 * cellWidth, 1 * cellHeight - cellHeight }, --8
    { 0 * cellWidth, 2 * cellHeight - cellHeight }, --9
    { 1 * cellWidth, 2 * cellHeight - cellHeight }, --10
    { 2 * cellWidth, 2 * cellHeight - cellHeight }, --11
    { 3 * cellWidth, 2 * cellHeight - cellHeight }, --12
    { 4 * cellWidth, 2 * cellHeight - cellHeight }, --13
    { 5 * cellWidth, 2 * cellHeight - cellHeight }, --14
    { 6 * cellWidth, 2 * cellHeight - cellHeight }, --15
    { 7 * cellWidth, 2 * cellHeight - cellHeight }, --16
}

function ItemCard:new(id)
    local o = {}
    o.id = id or 1
    o.icons = {}
    for i = 1, 32 do
        o.icons[i] = ItemIcon:new(unpack(IconPositions[i]))
    end

    return setmetatable(o, self)
end

function ItemCard:draw(x, y)
    love.graphics.push()
    love.graphics.scale(0.6, 0.6)
    love.graphics.translate(x, y)

    local p = GameInfo.playernum

    if p == 1 then
        for i = 1, 32 do
            --if(Items[self.id].roomitem[i].pick < 5) and (Items[self.id].roomitem[i].type > 0) and(Items[self.id].roomitem[i].count > 0) then
            if not (Items[self.id].roomitem[i].id == -1) then
                if
                    not (
                        Items[self.id].roomitem[i].mix == 0x20
                        or (Items[self.id].roomitem[i].pick > 0) and (Items[self.id].roomitem[i].present == 0)
                    )
                then
                    self.icons[i].type = Items[self.id].roomitem[i].type
                    self.icons[i].count = Items[self.id].roomitem[i].count
                    love.graphics.setColor(1, 1, 1, 1)
                    self.icons[i]:draw()
                end
            end
        end
    else
        for i = 1, 32 do
            --if(Items[self.id].roomitem[i].pick < 5) and (Items[self.id].roomitem[i].type > 0) and(Items[self.id].roomitem[i].count > 0) then
            if not (Items[self.id].roomitem[i].id == -1) then
                if
                    Items[self.id].roomitem[i].mix == 0x20
                    or (Items[self.id].roomitem[i].pick > 0) and (Items[self.id].roomitem[i].present == 0)
                then
                    self.icons[i].type = Items[self.id].roomitem[i].type
                    self.icons[i].count = Items[self.id].roomitem[i].count
                    self.icons[i].pick = Items[self.id].roomitem[i].pick
                    love.graphics.setColor(1, 1, 1, 0.25)
                    self.icons[i]:draw()
                else
                    self.icons[i].type = Items[self.id].roomitem[i].type
                    self.icons[i].count = Items[self.id].roomitem[i].count
                    self.icons[i].pick = Items[self.id].roomitem[i].pick
                    love.graphics.setColor(1, 1, 1, 1)
                    self.icons[i]:draw()
                end
            end
        end
    end

    love.graphics.pop()
end
ItemCard2 = {}
ItemCard2.__index = ItemCard2

function ItemCard2:new(id)
    local o = {}
    o.id = id or 1
    o.icons = {}
    for i = 1, 1 do
        o.icons[i] = ItemIcon:new(i)
    end

    return setmetatable(o, self)
end

function ItemCard2:draw(x, y)
    love.graphics.push()
    love.graphics.scale(0.65, 0.65)
    love.graphics.translate(x, y)

    for i = 1, 1 do
        --if(Items2[self.id].pick < 5) and (Items2[self.id].type > 0) and(Items2[self.id].count > 0) then
        if Items2[self.id].number > 0 then
            if
                Items2[self.id].id == -1
                or Items2[self.id].count == 0xffff
                or Items2[self.id].mix == 0x20
                or (Items2[self.id].pick > 0) and (Items2[self.id].present == 0)
            then
                self.icons[i].type = Items2[self.id].type
                self.icons[i].count = Items2[self.id].count
                self.icons[i].pick = Items2[self.id].pick
                love.graphics.setColor(1, 1, 1, 0.25)
                self.icons[i]:draw()
            else
                self.icons[i].type = Items2[self.id].type
                self.icons[i].count = Items2[self.id].count
                self.icons[i]:draw()
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    love.graphics.pop()
end

ItemCard3 = {}
ItemCard3.__index = ItemCard3

function ItemCard3:new(id)
    local o = {}
    o.id = id or 1
    o.icons = {}
    for i = 1, 1 do
        o.icons[i] = ItemIcon2:new(i)
    end

    return setmetatable(o, self)
end

function ItemCard3:draw(x, y)
    love.graphics.push()
    love.graphics.scale(0.65, 0.65)
    love.graphics.translate(x, y)

    for i = 1, 1 do
        --if(Items2[self.id].pick < 5) and (Items2[self.id].type > 0) and(Items2[self.id].count > 0) then
        if Items2[self.id].number > 0 then
            if
                Items2[self.id].id == -1
                or Items2[self.id].count == 0xffff
                or Items2[self.id].mix == 0x20
                or (Items2[self.id].pick > 0) and (Items2[self.id].present == 0)
            then
                self.icons[i].type = Items2[self.id].type
                self.icons[i].roomid = Items2[self.id].roomid
                --self.icons[i].pick = Items2[self.id].pick
                love.graphics.setColor(1, 1, 1, 0.25)
                self.icons[i]:draw()
            else
                self.icons[i].type = Items2[self.id].type
                self.icons[i].roomid = Items2[self.id].roomid
                self.icons[i]:draw()
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    love.graphics.pop()
end
