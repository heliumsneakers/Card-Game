local Cards = require("src.cards")
local Combat = require("src.domain.combat")
local Deck = require("src.domain.deck")
local Rewards = require("src.domain.rewards")
local Run = require("src.domain.run")
local Encounters = require("src.encounters")

-- Coordinates domain modules; mutable data lives in run/combat/deck/rewards.
local Game = {}
Game.__index = Game

function Game.new(startingHp, seed, dependencies)
    dependencies = dependencies or {}
    local self = setmetatable({}, Game)
    self.cards = Cards.new(assert(dependencies.catalog, "catalog is required"))
    self.seedSource = dependencies.seedSource or os.time
    self.feedback = dependencies.feedback
    self.startingHp, self.fixedSeed = startingHp or 30, seed
    self:restart()
    return self
end

function Game:restart()
    self.run = Run.new(self.startingHp, self.fixedSeed or self.seedSource(), self.cards.startingDeck)
    self.random = Encounters.newRng(self.run.runSeed)
    self.rewards = nil
    if self.feedback then self.feedback:reset() end
    self:startRoom()
end

function Game:notice(text, duration)
    if self.feedback then self.feedback:notice(text, duration) end
end

function Game:startRoom()
    Run.setState(self.run, "combat")
    self.combat = Combat.new()
    self.deck = Deck.new(self.run.masterDeck, self.cards, self.random)
    local plan = Run.encounter(self.run, self.cards.catalog)
    self.combat.encounterTargetPower, self.combat.encounterPower = plan.targetPower, plan.power
    self.combat.encounterSeed = plan.seed
    self.combat.encounterScale, self.combat.encounterWarning = plan.scale, plan.warning
    self:spawnEnemies(plan.enemies, false, plan.random, plan.scale)
    self:notice(plan.banner, 1.5)
    for _ = 1, 7 do self:draw() end
end

function Game:spawnEnemies(specs, boss, random, scale)
    Combat.spawnEnemies(self.combat, self.cards.catalog, specs, boss, random or self.random, scale)
end

function Game:draw()
    return Deck.draw(self.deck, self.random)
end

function Game:keepHand()
    return Combat.keepHand(self.combat)
end

function Game:redrawHand()
    return Combat.redrawHand(self.combat, self.deck, self.random)
end

function Game:surgeMultiplier()
    return Combat.surgeMultiplier(self.combat)
end

function Game:canPlay(index, targetIndex)
    return self.run.state == "combat" and Combat.canPlay(self.combat, self.deck, self.cards, index, targetIndex)
end

function Game:damageEnemy(enemy, amount)
    return Combat.damageEnemy(self.combat, enemy, amount, self.feedback)
end

function Game:resolveCard(card, targetIndex)
    return Combat.resolveCard(self.combat, self.deck, self.run, self.cards, self.random, self.feedback, card, targetIndex)
end

function Game:play(index, targetIndex)
    if self.run.state ~= "combat" then return false end
    local played = Combat.play(self.combat, self.deck, self.run, self.cards, self.random, self.feedback, index, targetIndex)
    if played then self:checkEncounterClear() end
    return played
end

function Game:livingEnemies()
    return Combat.livingEnemies(self.combat)
end

function Game:checkEncounterClear()
    if self:livingEnemies() > 0 then return end
    local nextStep, banner = Run.afterClear(self.run, self.combat.wave)
    if nextStep == "boss" then
        local plan = Run.bossWave()
        self.combat.wave = 2
        self:spawnEnemies(plan.enemies, true)
        Combat.advanceTurn(self.combat, self.deck, self.random)
        self:notice(plan.banner, 1.8)
    elseif nextStep == "room" then
        self:startRoom()
        if banner then self:notice(banner, 2.2) end
    else
        self:openReward()
    end
end

function Game:endTurn()
    if self.run.state == "combat" then Combat.endTurn(self.combat) end
end

function Game:damagePlayer(amount)
    if Combat.damagePlayer(self.combat, self.run, amount, self.feedback) then Run.setState(self.run, "gameover") end
end

function Game:finishEnemyPhase()
    return Combat.finishEnemyPhase(self.combat, self.deck, self.random)
end

function Game:update(dt)
    if self.run.state ~= "combat" then return end
    if Combat.update(self.combat, self.deck, self.run, dt, self.random, self.feedback) then
        Run.setState(self.run, "gameover")
    end
end

function Game:deckCount(name)
    return Deck.count(self.run.masterDeck, self.cards:definition(name).id)
end

function Game:openReward()
    Run.setState(self.run, "reward")
    Combat.setPhase(self.combat, nil)
    self.rewards = Rewards.new(self.run.masterDeck, self.cards, self.random)
end

function Game:pickReward(name)
    if self.run.state ~= "reward" then return false end
    local picked, message = Rewards.pick(self.rewards, self.run.masterDeck, self.cards, name)
    if message then self:notice(message, 0.8) end
    return picked
end

function Game:resetPicks()
    if self.run.state == "reward" then Rewards.reset(self.rewards) end
end

function Game:descend()
    if self.run.state ~= "reward" or not Rewards.complete(self.rewards) then return false end
    Rewards.apply(self.rewards, self.run.masterDeck)
    Run.advanceRoom(self.run)
    self:startRoom()
    return true
end

function Game:masterCounts()
    return Deck.counts(self.run.masterDeck, self.cards)
end

return Game
