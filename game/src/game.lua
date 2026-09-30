local Cards = require("src.cards")
local Combat = require("src.domain.combat")
local Deck = require("src.domain.deck")
local Rewards = require("src.domain.rewards")
local Run = require("src.domain.run")
local Encounters = require("src.encounters")

-- Coordinates domain modules; mutable data lives in run/combat/deck/rewards.
local Game = {}
Game.__index = Game

-- Build a game with an explicit catalog, seed policy, and optional visual feedback.
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

-- Replace run state and reset the seeded random stream before opening room one.
function Game:restart()
    -- A fixed seed repeats on restart; otherwise ask the injected source for a new seed.
    self.run = Run.new(self.startingHp, self.fixedSeed or self.seedSource(), self.cards.startingDeck)
    self.random = Encounters.newRng(self.run.runSeed)
    self.rewards = nil
    if self.feedback then self.feedback:reset() end
    self:startRoom()
end

-- Forward a banner to presentation when a feedback sink is installed.
function Game:notice(text, duration)
    if self.feedback then self.feedback:notice(text, duration) end
end

-- Create fresh combat and piles, then apply the run module's encounter plan.
function Game:startRoom()
    Run.setState(self.run, "combat")
    -- Replace room-local objects while preserving run health and the permanent deck.
    self.combat = Combat.new()
    self.deck = Deck.new(self.run.masterDeck, self.cards, self.random)
    -- Encounter generation uses its own stream so stat rolls do not consume deck randomness.
    local plan = Run.encounter(self.run, self.cards.catalog)
    self.combat.encounterTargetPower, self.combat.encounterPower = plan.targetPower, plan.power
    self.combat.encounterSeed = plan.seed
    self.combat.encounterScale, self.combat.encounterWarning = plan.scale, plan.warning
    self:spawnEnemies(plan.enemies, false, plan.random, plan.scale)
    self:notice(plan.banner, 1.5)
    for _ = 1, 7 do self:draw() end
end

-- Create enemies from definitions using an encounter RNG or the run RNG.
function Game:spawnEnemies(specs, boss, random, scale)
    Combat.spawnEnemies(self.combat, self.cards.catalog, specs, boss, random or self.random, scale)
end

-- Draw into this game's hand using its private random stream.
function Game:draw()
    return Deck.draw(self.deck, self.random)
end

-- Accept the opening hand through the combat phase rules.
function Game:keepHand()
    return Combat.keepHand(self.combat)
end

-- Request the one mulligan allowed before the player phase.
function Game:redrawHand()
    return Combat.redrawHand(self.combat, self.deck, self.random)
end

-- Expose the current spell-power multiplier for rules and display callers.
function Game:surgeMultiplier()
    return Combat.surgeMultiplier(self.combat)
end

-- Check run state before asking combat to validate cost, phase, and target.
function Game:canPlay(index, targetIndex)
    return self.run.state == "combat" and Combat.canPlay(self.combat, self.deck, self.cards, index, targetIndex)
end

-- Apply enemy damage and its optional visual feedback.
function Game:damageEnemy(enemy, amount)
    return Combat.damageEnemy(self.combat, enemy, amount, self.feedback)
end

-- Resolve a card's effects without spending mana or moving the card between piles.
function Game:resolveCard(card, targetIndex)
    return Combat.resolveCard(self.combat, self.deck, self.run, self.cards, self.random, self.feedback, card, targetIndex)
end

-- Resolve a legal play, then advance progression only after all card work finishes.
function Game:play(index, targetIndex)
    if self.run.state ~= "combat" then return false end
    local played = Combat.play(self.combat, self.deck, self.run, self.cards, self.random, self.feedback, index, targetIndex)
    -- Progression runs after effects, discarding, and mirror copies have completed.
    if played then self:checkEncounterClear() end
    return played
end

-- Count enemies that still participate in the encounter.
function Game:livingEnemies()
    return Combat.livingEnemies(self.combat)
end

-- Ask progression what follows a clear and coordinate the chosen transition.
function Game:checkEncounterClear()
    if self:livingEnemies() > 0 then return end
    -- The run module chooses the next scenario; this coordinator initializes its systems.
    local nextStep, banner = Run.afterClear(self.run, self.combat.wave)
    if nextStep == "boss" then
        local plan = Run.bossWave()
        self.combat.wave = 2
        self:spawnEnemies(plan.enemies, true)
        -- Boss-wave advancement refreshes turn resources without replacing piles or statuses.
        Combat.advanceTurn(self.combat, self.deck, self.random)
        self:notice(plan.banner, 1.8)
    elseif nextStep == "room" then
        self:startRoom()
        if banner then self:notice(banner, 2.2) end
    else
        self:openReward()
    end
end

-- Start enemy actions only while the run is in combat.
function Game:endTurn()
    if self.run.state == "combat" then Combat.endTurn(self.combat) end
end

-- Apply armor/HP damage and promote lethal damage to a run-level defeat.
function Game:damagePlayer(amount)
    if Combat.damagePlayer(self.combat, self.run, amount, self.feedback) then Run.setState(self.run, "gameover") end
end

-- Initialize the next player turn through the shared combat helper.
function Game:finishEnemyPhase()
    return Combat.finishEnemyPhase(self.combat, self.deck, self.random)
end

-- Advance enemy pacing and propagate defeat to the run state.
function Game:update(dt)
    if self.run.state ~= "combat" then return end
    if Combat.update(self.combat, self.deck, self.run, dt, self.random, self.feedback) then
        Run.setState(self.run, "gameover")
    end
end

-- Count permanent copies after resolving a card name or ID.
function Game:deckCount(name)
    return Deck.count(self.run.masterDeck, self.cards:definition(name).id)
end

-- Leave the combat phase and create a fresh reward selection.
function Game:openReward()
    Run.setState(self.run, "reward")
    Combat.setPhase(self.combat, nil)
    self.rewards = Rewards.new(self.run.masterDeck, self.cards, self.random)
end

-- Validate a reward pick and display any copy-limit rejection.
function Game:pickReward(name)
    if self.run.state ~= "reward" then return false end
    local picked, message = Rewards.pick(self.rewards, self.run.masterDeck, self.cards, name)
    if message then self:notice(message, 0.8) end
    return picked
end

-- Clear pending rewards without changing the permanent deck.
function Game:resetPicks()
    if self.run.state == "reward" then Rewards.reset(self.rewards) end
end

-- Commit a complete reward selection before advancing to the next room.
function Game:descend()
    if self.run.state ~= "reward" or not Rewards.complete(self.rewards) then return false end
    -- Commit before rebuilding room piles so the new cards join the next shuffle.
    Rewards.apply(self.rewards, self.run.masterDeck)
    Run.advanceRoom(self.run)
    self:startRoom()
    return true
end

-- Return alphabetically sorted permanent-deck rows for the deck overlay.
function Game:masterCounts()
    return Deck.counts(self.run.masterDeck, self.cards)
end

return Game
