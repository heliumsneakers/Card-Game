package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Json = require("src.json")
local Debuffs = require("src.domain.debuffs.registry")
local Behaviors = require("src.domain.debuffs.behaviors")
local Content = require("src.content")
local Descriptions = require("src.presentation.descriptions")
local Game = require("src.game")
local file = assert(io.open("tests/fixtures/debuff_registry.json", "r"))
local fixture = Json.decode(file:read("*a"))
file:close()

-- Register a test-only second entry without changing editor or combat switches.
local definition = fixture.definition
Debuffs.definitions[#Debuffs.definitions + 1] = definition
Debuffs.byId[definition.id], Debuffs.byToken[definition.token] = definition, definition
local catalog = assert(Content.load("content/content.json"))
local card = catalog.cards["card.firebolt"]
card.effects, card.description = fixture.effects, fixture.description
assert(#Content.validate(catalog.document) == 0)
local game = Game.new(30, 100, { catalog = catalog })
game:keepHand()
game.combat.enemies = {
    { name = "Target", alive = true, tough = 20, maxTough = 20, pow = 3, debuffs = {}, frozen = false },
    { name = "Dead", alive = false, tough = 0, maxTough = 20, pow = 3, debuffs = {}, frozen = false },
}
game:resolveCard(game.cards:make("card.firebolt"), 1)
local enemy = game.combat.enemies[1]
assert(Debuffs.stacks(enemy, "debuff.freeze") == 3 and Debuffs.stacks(enemy, definition.id) == 3)
assert(#Debuffs.active(enemy) == 2 and next(game.combat.enemies[2].debuffs) == nil)
assert(Descriptions.describe(card, { counter = function() return 0 end, value = function() return 0 end }, card.id, 1) == fixture.expectedDescription)

-- Every active skip behavior ages once per action; their order cannot hide expiration.
local hp = game.run.hp
for remaining = 2, 0, -1 do
    game:endTurn()
    game:update(0.4)
    assert(game.run.hp == hp)
    assert(Debuffs.stacks(enemy, "debuff.freeze") == remaining and Debuffs.stacks(enemy, definition.id) == remaining)
    game:update(0.7)
end
game:endTurn()
game:update(0.4)
assert(game.run.hp == hp - 3 and not enemy.frozen)

-- Compatibility flags apply only when no authoritative stack value exists.
local legacy = { alive = true, name = "Old", frozen = true }
assert(Debuffs.stacks(legacy, "debuff.freeze") == 1)
assert(Debuffs.beforeAction(legacy, {}) and not legacy.frozen)
assert(not Debuffs.beforeAction(legacy, {}))
assert(not pcall(Debuffs.apply, enemy, "debuff.missing", 1))

-- A future damage hook can kill a target without allowing a posthumous attack.
Behaviors.testDamage = function(_, stacks, actions)
    actions.damage(stacks)
    actions.setStacks(0)
    return false
end
definition.behavior = "testDamage"
game = Game.new(30, 100, { catalog = catalog })
game:keepHand()
game.combat.enemies = { { name = "Doomed", alive = true, tough = 1, maxTough = 1, pow = 99, debuffs = { [definition.id] = 1 } } }
game:endTurn()
game:update(0.4)
assert(game.run.hp == 30 and not game.combat.enemies[1].alive)
assert(game.run.state == "reward", "debuff kills must complete the encounter")
print("debuff registry, mixed stacks, descriptions, lifecycle, and compatibility tests passed")

-- A last-guard debuff kill starts the boss wave in the player phase exactly once.
game = Game.new(30, 100, { catalog = catalog })
game:keepHand()
game.run.room, game.combat.wave = 5, 1
game.combat.enemies = { { name = "Guard", alive = true, tough = 1, maxTough = 1, pow = 99, debuffs = { [definition.id] = 1 } } }
local turn = game.combat.turn
game:endTurn()
game:update(0.4)
assert(game.combat.wave == 2 and game.combat.phase == "player")
assert(game.combat.enemies[1].id == "enemy.bone_lord" and game.combat.turn == turn + 1)
game:update(0.7)
assert(game.combat.turn == turn + 1, "transition must not advance another turn")
print("debuff boss-transition test passed")
