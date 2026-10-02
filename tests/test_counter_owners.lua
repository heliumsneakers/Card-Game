package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Json = require("src.json")
local Counters = require("src.domain.effects.counters")
local Validation = require("src.domain.effects.validation")
local Content = require("src.content")
local Game = require("src.game")
local Combat = require("src.domain.combat")
local Descriptions = require("src.presentation.descriptions")
local file = assert(io.open("tests/fixtures/counter_owners.json", "r"))
local fixtures = Json.decode(file:read("*a"))
file:close()
local ids = { ["card.firebolt"] = true, ["card.fireball"] = true }

-- Copy a reference into a write or read without mutating the shared fixture.
local function withFields(reference, fields)
    for key, value in pairs(reference) do fields[key] = value end
    return fields
end

for _, fixture in ipairs(fixtures.valid) do
    local context = { cardId = fixture.card.id, element = fixture.card.element, category = fixture.card.type, instanceId = fixture.instanceId }
    assert(Counters.key(fixture.reference, context) == fixture.expected, fixture.name)
    assert(Counters.key(Counters.normalize(fixture.reference), context) == fixture.expected, fixture.name .. " migration")
    local errors = {}
    Validation.effects({ withFields(fixture.reference, { op = "incrementCounter", amount = 1 }) }, "effects", errors, 0, "enemy", ids)
    assert(#errors == 0, fixture.name)
end
for _, reference in ipairs(fixtures.invalid) do
    -- Both formula reads and mutations must reject the same malformed identities.
    for _, effect in ipairs({ withFields(reference, { op = "incrementCounter", amount = 1 }), { op = "damage", target = "selectedEnemy", amount = withFields(reference, { kind = "counter" }) } }) do
        local errors = {}
        Validation.effects({ effect }, "effects", errors, 0, "enemy", ids)
        assert(#errors > 0, "invalid ownership was accepted")
    end
end

-- Build ordered effects that make shared increments observable as damage.
local function effects(reference)
    return {
        withFields(reference, { op = "incrementCounter", amount = 1 }),
        { op = "damage", target = "selectedEnemy", amount = withFields(reference, { kind = "counter" }) },
    }
end

local catalog = assert(Content.load("content/content.json"))
local element = { owner = { kind = "element", element = "this" }, name = "power" }
local category = { owner = { kind = "category", category = "this" }, name = "power", scope = "combat" }
catalog.cards["card.firebolt"].effects = effects(element)
catalog.cards["card.fireball"].effects = effects(element)
catalog.cards["card.frostbite"].effects = effects(element)
local game = Game.new(30, 100, { catalog = catalog })
game:keepHand()
game.combat.enemies = { { name = "Dummy", tough = 100, pow = 0, alive = true, debuffs = {} } }
local enemy = game.combat.enemies[1]
game:resolveCard(game.cards:make("card.firebolt"), 1)
game:resolveCard(game.cards:make("card.fireball"), 1)
assert(enemy.tough == 97, "fire cards must share the increment")
game:resolveCard(game.cards:make("card.frostbite"), 1)
assert(enemy.tough == 96, "ice must have its own counter")
catalog.cards["card.fireball"].effects = effects({ owner = { kind = "element", element = "fire" }, name = "casts" })
game:resolveCard(game.cards:make("card.fireball"), 1)
assert(enemy.tough == 95, "different names must be isolated")
catalog.cards["card.firebolt"].effects = effects(category)
catalog.cards["card.frostbite"].effects = effects(category)
game:resolveCard(game.cards:make("card.firebolt"), 1)
game:resolveCard(game.cards:make("card.frostbite"), 1)
assert(enemy.tough == 92, "DMG category must share across elements")
catalog.cards["card.arcane_ward"].effects = effects(category)
game:resolveCard(game.cards:make("card.arcane_ward"), 1)
assert(enemy.tough == 91, "DEF category must be independent")
Combat.advanceTurn(game.combat, game.deck, game.random)
assert(next(game.combat.turnCounters) == nil)
assert(game.combat.combatCounters["@named:13:@category:DMG:power"] == 2)
game:resolveCard(game.cards:make("card.firebolt"), 1)
assert(enemy.tough == 88, "combat counters must survive the turn")

-- Ordered description previews carry group metadata but cannot mutate real counters.
local definition = catalog.cards["card.firebolt"]
definition.description = "Deal {dmg=0} damage."
assert(Descriptions.describe(definition, Combat.queries(game.combat, game.run, game.deck), definition.id, 1, 99) == "Deal 4* damage.")
assert(game.combat.combatCounters["@named:13:@category:DMG:power"] == 3)
assert(enemy.tough == 88)
-- Every counter mutation resolves the same explicit owner as formula reads.
definition.effects = {
    withFields(element, { op = "setCounter", amount = 5 }),
    withFields(element, { op = "subtractCounter", amount = 2 }),
    { op = "damage", target = "selectedEnemy", amount = withFields(element, { kind = "counter" }) },
    withFields(element, { op = "resetCounter" }),
}
game:resolveCard(game.cards:make("card.firebolt"), 1)
assert(enemy.tough == 85)
assert(game.combat.turnCounters["@named:13:@element:fire:power"] == 0)
local fresh = Combat.new()
assert(next(fresh.turnCounters) == nil and next(fresh.combatCounters) == nil)
print("counter ownership compatibility, shared groups, lifetimes, validation, and descriptions passed")
