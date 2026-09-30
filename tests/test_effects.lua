package.path = "game/?.lua;game/?/init.lua;" .. package.path

local Resolver = require("src.domain.effects.resolver")
local Descriptions = require("src.presentation.descriptions")
local Combat = require("src.domain.combat")
local Game = require("src.game")
local Content = require("src.content")
-- Build an expression leaf for the synthetic effect definitions below.
local function literal(value) return { kind = "literal", value = value } end
-- Build a live scalar query expression for ordering tests.
local function context(path) return { kind = "context", path = path } end

-- The resolver runs without a Game object; later effects see earlier mutations.
local mana, count, calls = 0, 0, {}
local query = {
    -- Reject unexpected reads while exposing the latest synthetic mana value.
    value = function(path) assert(path == "mana"); return mana end,
    -- Verify current-card ID resolution and return the updated synthetic count.
    counter = function(id) assert(id == "card.test"); return count end,
}
local actions = {
    -- Simulate capped mana mutation so later expressions must see the result.
    mana = function(amount, cap) mana = math.min(cap, mana + amount) end,
    -- Verify the resolved counter ID before recording the increment.
    incrementCounter = function(id, amount) assert(id == "card.test"); count = count + amount end,
    -- Record ordered damage calls without requiring a combat instance.
    damage = function(target, amount) calls[#calls + 1] = { target, amount } end,
}
Resolver.resolve({ effects = {
    { op = "mana", amount = literal(2), cap = 3 },
    { op = "incrementCounter", id = "$thisCard", amount = 1 },
    { op = "setLocal", name = "power", value = { kind = "binary", operator = "add",
        left = context("mana"), right = { kind = "counter", id = "$thisCard" } } },
    { op = "if", condition = { kind = "compare", operator = "eq", left = context("thisCardId"), right = literal("card.test") },
        ["then"] = { { op = "damage", target = "selectedEnemy", amount = { kind = "local", name = "power" }, scalable = true } },
        ["else"] = { { op = "unknown" } } },
    { op = "if", condition = { kind = "compare", operator = "lt", left = context("mana"), right = literal(0) },
        ["then"] = { { op = "unknown" } },
        ["else"] = { { op = "damage", target = "allEnemies", amount = literal(1.9) } } },
} }, "card.test", query, actions, 2)
assert(#calls == 2 and calls[1][1] == "selectedEnemy" and calls[1][2] == 6)
assert(calls[2][1] == "allEnemies" and calls[2][2] == 1)
local ok = pcall(Resolver.resolve, { effects = {
    { op = "damage", target = "selectedEnemy", amount = { kind = "local", name = "power" } },
} }, "card.test", query, actions, 2)
assert(not ok, "locals must not leak between resolutions")

-- Exercise the concrete operation adapter, including caps and target lifecycle.
local catalog = assert(Content.load("content/content.json"))
local definition = catalog.cards["card.fireball"]
definition.effects = {
    { op = "damage", target = "allEnemies", amount = literal(1), scalable = true },
    { op = "freeze", target = "allEnemies" },
    { op = "armor", amount = context("livingEnemies") },
    { op = "heal", amount = literal(10) },
    { op = "mana", amount = literal(10) },
    { op = "draw", amount = literal(10) },
    { op = "addStatus", id = "status.spell_power", stacks = literal(1) },
    { op = "addStatus", id = "status.mirror", stacks = literal(1) },
    { op = "incrementCounter", id = "card.firebolt", amount = 2 },
    { op = "damage", target = "selectedEnemy", amount = literal(1), scalable = true },
}
local game = Game.new(30, 100, { catalog = catalog })
game:keepHand()
game.run.hp, game.combat.mana = 29, 0
for _, card in ipairs(game.deck.hand) do game.deck.draw[#game.deck.draw + 1] = card end
game.deck.hand = {}
game.combat.statuses["status.spell_power"] = 1
game.combat.enemies = {
    { tough = 2, alive = true, frozen = false },
    { tough = 10, alive = true, frozen = false },
    { tough = 0, alive = false, frozen = false },
}
game:resolveCard(game.cards:make("card.fireball"), 2)
assert(not game.combat.enemies[1].alive and not game.combat.enemies[1].frozen)
assert(game.combat.enemies[2].tough == 6 and game.combat.enemies[2].frozen, "multiplier is captured before status mutations")
assert(not game.combat.enemies[3].frozen)
assert(game.run.armor == 1 and game.run.hp == 30 and game.combat.mana == game.combat.maxMana)
assert(#game.deck.hand == 7 and #game.deck.draw == 2)
assert(game.combat.statuses["status.spell_power"] == 0 and game.combat.surge == nil)
assert(game.combat.statuses["status.mirror"] == 1 and game.combat.mirror == nil)
assert(game.combat.turnCounters["card.firebolt"] == 2 and game.combat.fb == nil)

-- Rejected actions leave cards/resources untouched; targeted effects ignore dead targets.
local hand, manaBefore = game.deck.hand, game.combat.mana
game.combat.phase = "enemy"
assert(not game:play(1, 2) and game.deck.hand == hand and game.combat.mana == manaBefore)
game.combat.phase = "player"
definition.effects = { { op = "damage", target = "selectedEnemy", amount = literal(20) } }
game:resolveCard(game.cards:make("card.fireball"), 1)
assert(game.combat.enemies[1].tough == 0 and game.combat.enemies[2].tough == 6)

-- Multi-target selectors exclude the primary target, while debuff stacks can scale.
definition.effects = {
    { op = "damage", target = "selectedEnemy", amount = literal(2) },
    { op = "damage", target = "otherEnemies", amount = literal(1) },
    { op = "debuff", id = "debuff.freeze", target = "selectedEnemy", stacks = literal(1), scalable = true },
}
game.combat.enemies = {
    { name = "Target", pow = 3, tough = 20, maxTough = 20, alive = true, frozen = false, debuffs = {} },
    { name = "Other A", pow = 3, tough = 20, maxTough = 20, alive = true, frozen = false, debuffs = {} },
    { name = "Other B", pow = 3, tough = 20, maxTough = 20, alive = true, frozen = false, debuffs = {} },
}
game.combat.statuses["status.spell_power"] = 1
game:resolveCard(game.cards:make("card.fireball"), 1)
assert(game.combat.enemies[1].tough == 18, "primary target should receive only primary damage")
assert(game.combat.enemies[2].tough == 19 and game.combat.enemies[3].tough == 19,
    "otherEnemies should reach every living enemy except the primary target")
assert(game.combat.enemies[1].debuffs["debuff.freeze"] == 2 and game.combat.enemies[1].frozen,
    "spell power should scale freeze stacks")

game.run.hp, game.run.armor, game.run.state, game.combat.phase = 30, 0, "combat", "player"
game.combat.enemies = { game.combat.enemies[1] }
for remaining = 1, 0, -1 do
    game:endTurn()
    game:update(0.4)
    assert(game.run.hp == 30, "each freeze stack should skip one enemy action")
    assert(game.combat.enemies[1].debuffs["debuff.freeze"] == remaining)
    game:update(0.7)
end
game:endTurn()
game:update(0.4)
assert(game.run.hp == 27, "enemy should attack after all freeze stacks expire")
-- Restore the scalar state expected by the independent description assertions below.
game.run.armor = 1
game.combat.turnCounters["card.firebolt"] = 2

-- Descriptions only receive scalar queries; no action adapter is available.
local description = {
    description = "Deal {dmg=2} damage. Gain {armor=1+2} Armor.",
    effects = {
        { op = "setLocal", name = "damage", value = { kind = "counter", id = "card.firebolt" } },
        { op = "damage", amount = { kind = "local", name = "damage" }, scalable = true },
        { op = "armor", amount = literal(3) },
    },
}
assert(Descriptions.describe(description, Combat.queries(game.combat, game.run), "card.fireball", 2)
    == "Deal 4* damage. Gain 3* Armor.")
assert(game.run.armor == 1 and game.combat.fb == nil)
assert(Descriptions.describe(description) == "Deal 2 damage. Gain 3* Armor.")
assert(Descriptions.describe({ effects = { { op = "heal", amount = literal(5) } } }) == "Heal 5 HP.")
print("effect ordering, combat operations, and description tests passed")
