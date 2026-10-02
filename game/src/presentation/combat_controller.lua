-- Owns combat selection and translates UI gestures into existing game methods.
local Controller = {}
Controller.__index = Controller

-- Bind combat interaction state to one game instance.
function Controller.new(game)
    return setmetatable({ game = game }, Controller)
end

-- Cancel a pending card selection without changing gameplay.
function Controller:clearSelection()
    self.selected = nil
    self.targetIndices = {}
end

-- Submit a play and clear selection only if the game accepts it.
function Controller:play(index, targetIndex, targetIndices)
    local played = self.game:play(index, targetIndex, targetIndices)
    -- Keep selection on rejection so the player can choose a valid target.
    if played then self:clearSelection() end
    return played
end

-- Confirm only after the required number of distinct enemies is selected.
function Controller:confirmTargets()
    local required = self.selected and self.game:targetRequirement(self.selected)
    if not required or #self.targetIndices ~= required then return false end
    local targets = {}
    for index, enemyIndex in ipairs(self.targetIndices) do targets[index] = enemyIndex end
    return self:play(self.selected, targets[1], targets)
end

-- Clear selection for a valid end-turn request and delegate the rules.
function Controller:endTurn()
    if self.game.run.state == "combat" and self.game.combat.phase == "player" then
        self:clearSelection()
    end
    self.game:endTurn()
end

-- Translate zone clicks into selection, targeting, mulligan, or turn actions.
function Controller:activate(zone)
    local game = self.game
    if not zone then self:clearSelection(); return end
    if zone.id == "keep" then game:keepHand()
    elseif zone.id == "redraw" then game:redrawHand()
    elseif zone.id == "endturn" then self:endTurn()
    elseif zone.id == "confirmTargets" then self:confirmTargets()
    elseif zone.id == "card" then
        if game.combat.phase ~= "player" then return end
        local index, card = zone.payload, game.deck.hand[zone.payload]
        if not card then return end
        local definition = game.cards:definition(card)
        local requiresEnemyTarget = definition.target == "enemy" or definition.target == "multi"
        -- A second click plays self/all-target cards but cancels enemy-target selection.
        if self.selected == index then
            if not requiresEnemyTarget then self:play(index) else self:clearSelection() end
        else
            self.selected = index
            self.targetIndices = {}
        end
    elseif zone.id == "enemy" then
        if self.selected then
            local required = game:targetRequirement(self.selected)
            if required then
                -- Clicking a chosen enemy toggles it off; new picks stop at the limit.
                for index, enemyIndex in ipairs(self.targetIndices) do
                    if enemyIndex == zone.payload then table.remove(self.targetIndices, index); return end
                end
                if #self.targetIndices < required then self.targetIndices[#self.targetIndices + 1] = zone.payload end
            else self:play(self.selected, zone.payload) end
        end
    elseif zone.id == "wizard" then
        if self.selected then
            local card = game.deck.hand[self.selected]
            if card then
                local target = game.cards:definition(card).target
                if target ~= "enemy" and target ~= "multi" then self:play(self.selected) end
            end
        end
    end
end

-- Map the combat keyboard shortcut to the same end-turn path as the button.
function Controller:keypressed(key)
    if key == "space" then self:endTurn() end
end

return Controller
