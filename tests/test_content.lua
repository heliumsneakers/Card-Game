package.path = "game/?.lua;game/?/init.lua;" .. package.path

love = { math = { random = function(a) return a end } }

local Content = require("src.content")
local CardCatalog = require("src.cards")
local CardPresentation = require("src.presentation.cards")
local Game = require("src.game")
local Encounters = require("src.encounters")

local catalog, errors = Content.load("content/content.json")
assert(catalog, errors and errors[1] and errors[1].message)
local Cards = CardCatalog.new(catalog)
assert(catalog.cards["card.firebolt"])
assert(catalog.enemies["enemy.goblin"])
assert(Cards:definition("Fireball").id == "card.fireball")
assert(Cards:definition("Mend").element == "nature")
assert(CardPresentation.color(Cards, "Arcane Ward") == CardPresentation.elementColors.earth)
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

local game = Game.new(30, 24680, { catalog = catalog })
game:keepHand()
game.combat.enemies = { { name = "Dummy", pow = 0, tough = 20, maxTough = 20, alive = true, frozen = false, flash = 0 } }
game.deck.hand = { Cards:make("Firebolt"), Cards:make("Firebolt") }
game.combat.mana = 3
assert(game:play(1, 1))
assert(game.combat.enemies[1].tough == 18)
assert(game:play(1, 1))
assert(game.combat.enemies[1].tough == 15)
assert(game.combat.previousCardId == "card.firebolt")
assert(CardPresentation.describe(Cards, Cards:make("Firebolt"), game):find("Deal 4* damage", 1, true))

local Descriptions = require("src.presentation.descriptions")
local Combat = require("src.domain.combat")
local formulaDescription = Descriptions.describe({
    description = "Deal {dmg=2+1} damage.",
    effects = { { op = "damage", target = "selectedEnemy", amount = { kind = "literal", value = 3 } } },
}, Combat.queries(game.combat, game.run), "card.formula_test", Combat.surgeMultiplier(game.combat))
assert(formulaDescription == "Deal 3* damage.")

Cards.catalog.document.preview = { featuredCardId = "card.fireball" }
game:openReward()
assert(game.rewards.choices[1] == "card.fireball", "previewed card should be pinned to the first shop slot")

print("content schema and interpreter tests passed")
