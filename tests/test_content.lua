package.path = "game/?.lua;game/?/init.lua;" .. package.path

love = { math = { random = function(a) return a end } }

local Content = require("src.content")
local Cards = require("src.cards")
local Game = require("src.game")
local Encounters = require("src.encounters")

local catalog, errors = Content.load("content/content.json")
assert(catalog, errors and errors[1] and errors[1].message)
assert(catalog.cards["card.firebolt"])
assert(catalog.enemies["enemy.goblin"])
assert(Cards.definition("Fireball").id == "card.fireball")
assert(Cards.definition("Mend").element == "nature")
assert(Cards.color("Arcane Ward") == Cards.elementColors.earth)
assert(math.abs(Encounters.enemyPower({
    damage = { min = 2, max = 3 }, hp = { min = 8, max = 9 }, generation = {},
}) - 1) < 0.001)

local roomThree = Encounters.roomConfig(catalog.document, 3)
local generated = assert(Encounters.generate(catalog, roomThree, 3, Encounters.newRng(99), false))
assert(#generated.enemies >= roomThree.minimumEnemies and #generated.enemies <= roomThree.maximumEnemies)
assert(generated.power <= roomThree.power * roomThree.maximumBudgetRatio)
for _, enemy in ipairs(generated.enemies) do assert(enemy.id ~= "enemy.bone_lord") end

local invalid = {
    schemaVersion = 1,
    cards = { { id = "bad id", name = "", cost = -1, type = "NOPE", target = "nowhere", effects = {} } },
    enemies = {},
}
assert(#Content.validate(invalid) >= 5)

local game = Game.new(30, 24680)
game:keepHand()
game.enemies = { { name = "Dummy", pow = 0, tough = 20, maxTough = 20, alive = true, frozen = false, flash = 0 } }
game.hand = { Cards.make("Firebolt"), Cards.make("Firebolt") }
game.mana = 3
assert(game:play(1, 1))
assert(game.enemies[1].tough == 18)
assert(game:play(1, 1))
assert(game.enemies[1].tough == 15)
assert(game.previousCardId == "card.firebolt")
assert(Cards.describe(Cards.make("Firebolt"), game):find("Deal 4* damage", 1, true))

local Effects = require("src.effects")
local formulaDescription = Effects.describe({
    description = "Deal {dmg=2+1} damage.",
    effects = { { op = "damage", target = "selectedEnemy", amount = { kind = "literal", value = 3 } } },
}, game, { id = "card.formula_test" })
assert(formulaDescription == "Deal 3* damage.")

Cards.catalog.document.preview = { featuredCardId = "card.fireball" }
game:openReward()
assert(game.shopChoices[1] == "card.fireball", "previewed card should be pinned to the first shop slot")
local eligibleCount = 0
for _, id in ipairs(Cards.shopPool) do
    local availability = Cards.definition(id).availability
    if (availability.shopChance or 50) > 0 and game:deckCount(id) < availability.copyLimit then eligibleCount = eligibleCount + 1 end
end
assert(#game.shopChoices == math.min(6, eligibleCount), "shop should fill all six slots when the pool allows")

local excludedId
for _, id in ipairs(Cards.shopPool) do if id ~= "card.fireball" then excludedId = id; break end end
local excludedDefinition = Cards.definition(excludedId)
local originalChance = excludedDefinition.availability.shopChance
excludedDefinition.availability.shopChance = 0
game:openReward()
for _, id in ipairs(game.shopChoices) do assert(id ~= excludedId, "zero-percent cards should not enter the shop") end
excludedDefinition.availability.shopChance = originalChance

print("content schema and interpreter tests passed")
