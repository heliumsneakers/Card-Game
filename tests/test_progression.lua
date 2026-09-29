package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Content = require("src.content")
local Game = require("src.game")
local Controller = require("src.presentation.combat_controller")
local Feedback = require("src.presentation.feedback")
local catalog = assert(Content.load("content/content.json"))
local function newGame() return Game.new(30, 321, { catalog = catalog, feedback = Feedback.new() }) end
local game = newGame()
local other = newGame()
assert(game.run ~= other.run and game.combat ~= other.combat and game.deck ~= other.deck)
assert(game.combat.statuses ~= other.combat.statuses and game.deck.hand ~= other.deck.hand)
assert(game.hp == nil and game.hand == nil and game.statuses == nil)
local oldRun, oldCombat, oldDeck = game.run, game.combat, game.deck
game:restart()
assert(game.run ~= oldRun and game.combat ~= oldCombat and game.deck ~= oldDeck)
assert(#other.deck.hand == 7 and other.run.room == 1)

-- Enemy turns preserve pacing, skip dead enemies, thaw freeze, then initialize once.
game:keepHand()
game.deck.hand = {}
game.combat.turnCounters["card.firebolt"] = 4
game.combat.statuses["status.mirror"] = 1
game.combat.enemies = {
    { alive = false, pow = 100 },
    { alive = true, frozen = true, pow = 100, name = "Frozen" },
    { alive = true, frozen = false, pow = 3, name = "Attacker" },
}
game:endTurn()
game:update(0.1)
assert(game.run.hp == 30 and game.combat.enemyIndex == 1)
game:update(0.3)
assert(game.run.hp == 30 and not game.combat.enemies[2].frozen)
game:update(0.7)
assert(game.run.hp == 27)
game:update(0.7)
assert(game.combat.phase == "player" and game.combat.turn == 2)
assert(game.combat.mana == 2 and #game.deck.hand == 1)
assert(next(game.combat.turnCounters) == nil and game.combat.statuses["status.mirror"] == 1)
game:update(10)
assert(game.combat.turn == 2 and #game.deck.hand == 1)

-- Lethal damage stops subsequent enemies and cannot initialize another turn.
game.run.hp = 1
game:endTurn()
game:update(0.4)
assert(game.run.state == "gameover" and game.combat.phase == nil)
local enemyIndex, handCount = game.combat.enemyIndex, #game.deck.hand
game:update(100)
assert(game.combat.enemyIndex == enemyIndex and #game.deck.hand == handCount)
assert(not game:play(1, 1) and not game:descend())

-- Boss wave uses the same turn reset, but keeps piles and existing statuses.
game = newGame()
game.run.room = 5
game:startRoom()
game:keepHand()
game.deck.hand = {}
game.combat.turnCounters["card.firebolt"] = 7
game.combat.statuses["status.mirror"] = 1
local combat, deck, run = game.combat, game.deck, game.run
for _, enemy in ipairs(game.combat.enemies) do enemy.alive = false end
game:checkEncounterClear()
assert(game.combat == combat and game.deck == deck and game.run == run)
assert(game.combat.wave == 2 and game.combat.enemies[1].id == "enemy.bone_lord")
assert(game.combat.turn == 2 and game.combat.mana == 2 and #game.deck.hand == 1)
assert(next(game.combat.turnCounters) == nil and game.combat.statuses["status.mirror"] == 1)
assert(game.feedback.message == "BONE LORD AWAKENS")
game.run.hp, game.run.armor = 2, 4
game.combat.enemies[1].alive = false
game:checkEncounterClear()
assert(game.run == run and game.combat ~= combat and game.deck ~= deck)
assert(game.run.endless and game.run.room == 6 and game.run.hp == 30 and game.run.armor == 0)
assert(game.combat.phase == "mulligan" and next(game.combat.statuses) == nil)
assert(game.feedback.message == "BONE LORD DEFEATED  •  ENDLESS BEGINS" and game.feedback.messageTime == 2.2)

-- Rewards initialize independent selections; failed completion leaves the run intact.
local a, b = newGame(), newGame()
a:openReward(); b:openReward()
assert(a.rewards ~= b.rewards and a.rewards.picks ~= b.rewards.picks)
assert(not a:descend() and a.run.room == 1)
assert(a:pickReward(a.rewards.choices[1]))
assert(#b.rewards.picks == 0)
a:resetPicks()
assert(#a.rewards.picks == 0)

-- Selection belongs solely to the controller; no graphics or App are required.
game = newGame()
local controller = Controller.new(game)
controller:activate({ id = "keep" })
game.deck.hand = { game.cards:make("Fireball"), game.cards:make("Mend") }
game.combat.mana = 3
controller:activate({ id = "card", payload = 1 })
assert(controller.selected == 1)
controller:activate({ id = "card", payload = 1 })
assert(controller.selected == nil and #game.deck.hand == 2)
controller:activate({ id = "card", payload = 2 })
controller:activate({ id = "wizard" })
assert(controller.selected == nil and #game.deck.hand == 1)
controller:activate({ id = "card", payload = 1 })
controller:activate(nil)
assert(controller.selected == nil)
print("state ownership, progression, transitions, and controller tests passed")
