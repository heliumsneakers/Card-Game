package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Json = require("src.json")
local Content = require("src.content")
local Game = require("src.game")
local Combat = require("src.domain.combat")
local Debuffs = require("src.domain.debuffs.registry")
local Descriptions = require("src.presentation.descriptions")
local Validation = require("src.domain.effects.validation")
local file = assert(io.open("tests/fixtures/debuff_damage.json", "r"))
local fixtures = Json.decode(file:read("*a"))
file:close()

-- Start an isolated combat with deterministic HP and enough mana for formula reads.
local function scenario(effect, spellPower)
    local catalog = assert(Content.load("content/content.json"))
    catalog.cards["card.firebolt"].effects = { effect }
    local game = Game.new(30, 100, { catalog = catalog })
    game:keepHand()
    game.combat.mana = 2
    game.combat.statuses["status.spell_power"] = spellPower or 0
    game.combat.enemies = { { name = "Dummy", tough = 20, maxTough = 20, pow = 3, alive = true, frozen = false, debuffs = {} } }
    game:resolveCard(game.cards:make("card.firebolt"), 1)
    return game
end

for _, fixture in ipairs(fixtures) do
    local errors = {}
    Validation.effects({ fixture.effect }, "effects", errors, 0, "enemy", {})
    assert(#errors == 0, fixture.name)
    local game = scenario(fixture.effect, fixture.spellPower)
    local enemy, id = game.combat.enemies[1], fixture.effect.id
    assert(enemy.tough == 20, "application must not deal immediate damage")
    assert(Debuffs.stacks(enemy, id) == fixture.expectedStacks)
    assert(Debuffs.bonusDamage(enemy, id) == fixture.expectedBonus)
    for tick, hp in ipairs(fixture.enemyHp) do
        -- Potency stays captured after spell power is consumed by the original card.
        game:endTurn()
        game:update(0.4)
        assert(enemy.tough == hp and game.run.hp == fixture.playerHp[tick], fixture.name)
        game:update(0.7)
    end
    assert(Debuffs.stacks(enemy, id) == 0 and Debuffs.bonusDamage(enemy, id) == 0)
    game:endTurn()
    game:update(0.4)
    assert(enemy.tough == fixture.enemyHp[#fixture.enemyHp], "expired bonuses must not tick")
end

-- Reapplication retains potency, while expiration resets it for a weaker application.
local enemy = { alive = true, name = "Stacks", debuffs = {} }
Debuffs.apply(enemy, "debuff.freeze", 2, 4)
Debuffs.apply(enemy, "debuff.freeze", 1, 1)
Debuffs.apply(enemy, "debuff.freeze", 1)
Debuffs.apply(enemy, "debuff.freeze", 0, 99)
assert(Debuffs.stacks(enemy, "debuff.freeze") == 4 and Debuffs.bonusDamage(enemy, "debuff.freeze") == 4)
Debuffs.setStacks(enemy, "debuff.freeze", 0)
Debuffs.apply(enemy, "debuff.freeze", 1, 1)
assert(Debuffs.bonusDamage(enemy, "debuff.freeze") == 1)

-- Central bonus application also works for a future debuff reusing an existing hook.
local custom = { id = "debuff.test_bonus", token = "test_bonus", label = "Test", behavior = "skipAction", actionText = "SKIPS", color = {1, 1, 1} }
Debuffs.definitions[#Debuffs.definitions + 1] = custom
Debuffs.byId[custom.id], Debuffs.byToken[custom.token] = custom, custom
local future = { alive = true, name = "Future", debuffs = {} }
Debuffs.apply(future, custom.id, 1, 5)
local damage = 0
Debuffs.tickTurn(future, { damage = function(value) damage = damage + value end })
assert(Debuffs.beforeAction(future, {}))
assert(damage == 5 and Debuffs.bonusDamage(future, custom.id) == 0)

-- All enemies tick at the turn boundary, even before their action timers elapse.
local timed = scenario({ op = "armor", amount = { kind = "literal", value = 0 } })
local first = timed.combat.enemies[1]
local second = { name = "Second", tough = 20, pow = 3, alive = true, debuffs = {} }
timed.combat.enemies[2] = second
Debuffs.apply(first, "debuff.freeze", 3, 2)
Debuffs.apply(second, "debuff.freeze", 3, 4)
timed:endTurn()
timed:update(0)
assert(first.tough == 18 and second.tough == 16, "all bonuses tick before any action")
timed:endTurn()
timed:update(0)
assert(first.tough == 18 and second.tough == 16, "repeated updates and end-turn calls must not tick again")
-- Multiple actions consume normal behavior stacks without repeating bonus damage.
Debuffs.beforeAction(first, {})
Debuffs.beforeAction(first, {})
assert(first.tough == 18, "extra actions must not repeat the turn bonus")
timed:update(0.4)
timed:update(0.7)
timed:update(0.7)
timed:endTurn()
timed:update(0)
assert(first.tough == 18 and second.tough == 12, "next turn ticks only still-active debuffs")

-- Lethal bonus damage skips the base Burn hook and completes the encounter.
local lethal = { op = "debuff", id = "debuff.burn", target = "selectedEnemy", stacks = { kind = "literal", value = 1 }, bonusDamage = { kind = "literal", value = 20 } }
local game = scenario(lethal)
game:endTurn()
game:update(0.4)
assert(game.run.hp == 30 and game.run.state == "reward")

-- Description tokens evaluate damage scaling separately and never change real state.
local effect = { op = "debuff", id = "debuff.freeze", target = "selectedEnemy", stacks = { kind = "literal", value = 2 }, bonusDamage = { kind = "literal", value = 3 }, damageScalable = true }
local definition = { description = "Freeze {freeze=0} with {freeze_damage=0} damage.", effects = { effect } }
game = scenario({ op = "armor", amount = { kind = "literal", value = 0 } })
assert(Descriptions.describe(definition, Combat.queries(game.combat, game.run), "card.test", 2, 99) == "Freeze 2* with 6* damage.")
assert(next(game.combat.enemies[1].debuffs) == nil)
for _, invalid in ipairs({ { kind = "literal", value = -1 }, { kind = "context", path = "thisCardId" } }) do
    effect.bonusDamage = invalid
    local errors = {}
    Validation.effects({ effect }, "effects", errors, 0, "enemy", {})
    assert(#errors > 0)
end
print("debuff bonus damage, captured scaling, expiration, future hooks, and description tests passed")
