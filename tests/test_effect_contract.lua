package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Json = require("src.json")
local Validation = require("src.domain.effects.validation")
local Resolver = require("src.domain.effects.resolver")
local Combat = require("src.domain.combat")
local Content = require("src.content")
local Game = require("src.game")
local Deck = require("src.domain.deck")
local file = assert(io.open("tests/effect-contract.json", "r"))
local contract = Json.decode(file:read("*a"))
file:close()
local ids = { ["card.test"] = true, ["card.partner"] = true }

-- Compare both directions so unexpected counter writes cannot go unnoticed.
local function sameCounters(actual, expected)
    for key, value in pairs(expected) do assert(actual[key] == value, key) end
    for key, value in pairs(actual) do assert(expected[key] == value, key) end
end

for _, fixture in ipairs(contract.valid) do
    local errors = {}
    Validation.effects(fixture.effects, "effects", errors, 0, "multi", ids)
    assert(#errors == 0, fixture.name)
    local hp, counters = 30, {}
    local query = {
        -- Counters remain live between operations and repeated resolutions.
        counter = function(id, scope) return counters[(scope or "turn") .. ":" .. id] or 0 end,
        value = function(path) if path == "mana" then return 2 end end,
    }
    local actions = {
        -- Synthetic damage makes the expected result independent of enemy generation.
        damage = function(_, amount) hp = math.max(0, hp - amount) end,
        incrementCounter = function(id, amount, scope)
            local key = scope .. ":" .. id
            counters[key] = math.max(0, (counters[key] or 0) + amount)
        end,
        setCounter = function(id, amount, scope) counters[scope .. ":" .. id] = amount end,
    }
    for _ = 1, fixture.repetitions or 1 do
        Resolver.resolve({ effects = fixture.effects }, "card.test", query, actions, (fixture.spellPower or 0) > 0 and fixture.spellPower * 2 or 1, fixture.instanceId or "1")
    end
    assert(hp == fixture.expectedHp, fixture.name)
    sameCounters(counters, fixture.expectedCounters)
end
for _, fixture in ipairs(contract.invalid) do
    local errors = {}
    Validation.effects(fixture.effects, "effects", errors, 0, "multi", ids)
    assert(#errors > 0, fixture.name)
end

-- Exercise real card identities, mirror copies, and combat lifetime transitions.
local catalog = assert(Content.load("content/content.json"))
local game = Game.new(30, 100, { catalog = catalog })
local first = game.cards:make("card.firebolt")
local second = game.cards:make("card.firebolt")
assert(first.instanceId ~= second.instanceId)
catalog.cards["card.firebolt"].effects = {
    { op = "incrementCounter", id = "$thisInstance", scope = "combat", amount = { kind = "literal", value = 1 } },
    { op = "incrementCounter", id = "$thisCard", amount = 1 },
}
game:resolveCard(first, 1)
game:resolveCard(second, 1)
assert(game.combat.turnCounters["card.firebolt"] == 2)
assert(game.combat.combatCounters["@instance:" .. first.instanceId] == 1)
Combat.advanceTurn(game.combat, game.deck, game.random)
assert(next(game.combat.turnCounters) == nil)
assert(game.combat.combatCounters["@instance:" .. second.instanceId] == 1)
game.deck.hand = {}
Deck.addCopies(game.deck, game.cards, first, 1)
assert(game.deck.hand[1].instanceId ~= first.instanceId)
assert(next(Combat.new().combatCounters) == nil)
print("shared effect contract, lifetime, and copy tests passed")

-- Live descriptions simulate ordered actions without mutating counters or piles.
local Descriptions = require("src.presentation.descriptions")
local CardPresentation = require("src.presentation.cards")
local definition = catalog.cards["card.firebolt"]
definition.description = "Deal {dmg=2} damage."
definition.effects = {
    { op = "incrementCounter", id = "$thisCard", amount = 1 },
    { op = "damage", target = "selectedEnemy", amount = { kind = "counter", id = "$thisCard" } },
}
game.combat.turnCounters["card.firebolt"] = 2
local hpBefore = game.combat.enemies[1].tough
assert(Descriptions.describe(definition, Combat.queries(game.combat, game.run, game.deck), first.id, 1, first.instanceId) == "Deal 3* damage.")
assert(game.combat.turnCounters["card.firebolt"] == 2 and game.combat.enemies[1].tough == hpBefore)
-- Discounted instances preview mana after their actual cost, not the definition cost.
definition.effects = { { op = "damage", target = "selectedEnemy", amount = { kind = "context", path = "mana" } } }
game.combat.mana = 3
local discounted = game.cards:make("card.firebolt", 0, true)
assert(CardPresentation.describe(game.cards, discounted, game) == "Deal 3* damage.")
assert(game.combat.mana == 3)
print("ordered description and discounted-copy preview tests passed")
