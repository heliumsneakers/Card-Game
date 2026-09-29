-- Owns combat selection and translates UI gestures into existing game methods.
local Controller = {}
Controller.__index = Controller

function Controller.new(game)
    return setmetatable({ game = game }, Controller)
end

function Controller:clearSelection()
    self.selected = nil
end

function Controller:play(index, targetIndex)
    local played = self.game:play(index, targetIndex)
    if played then self:clearSelection() end
    return played
end

function Controller:endTurn()
    if self.game.run.state == "combat" and self.game.combat.phase == "player" then
        self:clearSelection()
    end
    self.game:endTurn()
end

function Controller:activate(zone)
    local game = self.game
    if not zone then self.selected = nil; return end
    if zone.id == "keep" then game:keepHand()
    elseif zone.id == "redraw" then game:redrawHand()
    elseif zone.id == "endturn" then self:endTurn()
    elseif zone.id == "card" then
        if game.combat.phase ~= "player" then return end
        local index, card = zone.payload, game.deck.hand[zone.payload]
        if not card then return end
        local definition = game.cards:definition(card)
        if self.selected == index then
            if definition.target ~= "enemy" then self:play(index) else self.selected = nil end
        else self.selected = index end
    elseif zone.id == "enemy" then
        if self.selected then self:play(self.selected, zone.payload) end
    elseif zone.id == "wizard" then
        if self.selected then
            local card = game.deck.hand[self.selected]
            if card and game.cards:definition(card).target ~= "enemy" then self:play(self.selected) end
        end
    end
end

function Controller:keypressed(key)
    if key == "space" then self:endTurn() end
end

return Controller
