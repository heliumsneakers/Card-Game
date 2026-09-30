package.path = "game/?.lua;game/?/init.lua;" .. package.path

-- The rules can load and run without LÖVE or module-time content reads.
love = nil
local Content = require("src.content")
local loadContent = Content.load
-- Fail if requiring rules unexpectedly reads content at module load time.
Content.load = function() error("rules must not load content") end
local Game = require("src.game")
Content.load = loadContent
local Deck = require("src.domain.deck")
local Feedback = require("src.presentation.feedback")
local catalog = assert(Content.load("content/content.json"))
local otherCatalog = assert(Content.load("content/content.json"))
otherCatalog.cards["card.fireball"].cost = 0
for _, card in ipairs(otherCatalog.document.cards) do
    card.availability.startingDeck = card.id == "card.fireball" and 9 or 0
    card.availability.shop = card.id == "card.fireball"
end
local first = Game.new(30, 100, { catalog = catalog })
local second = Game.new(30, 100, { catalog = otherCatalog })
assert(first.cards:make("Fireball").cost ~= second.cards:make("Fireball").cost)
assert(#second.cards.shopPool == 1 and #first.cards.shopPool > 1)
for _, card in ipairs(second.deck.hand) do assert(card.id == "card.fireball") end
assert(first:deckCount("Fireball") ~= second:deckCount("Fireball"))
second.run.masterDeck[1] = "card.firebolt"
second:restart()
assert(second:deckCount("Fireball") == 9)

-- Use a predictable seed source to distinguish fresh runs from fixed-seed restarts.
local seed = 400
local seeded = Game.new(30, nil, { catalog = catalog, seedSource = function() seed = seed + 1; return seed end })
assert(seeded.run.runSeed == 401)
seeded:restart()
assert(seeded.run.runSeed == 402)
first:restart()
assert(first.run.runSeed == 100)

local a, b = first.cards:make("Fireball"), first.cards:make("Mend")
local piles = { hand = {}, draw = {}, discard = { a, b } }
assert(Deck.draw(piles, function(limit) return limit end))
assert(piles.hand[1] == b and piles.draw[1] == a and #piles.discard == 0)
piles.hand = { a, a, a, a, a, a, a }
assert(not Deck.draw(piles, function() error("full hand must not shuffle") end))
assert(#piles.draw == 1)

first.run.masterDeck = { "card.fireball", "card.fireball" }
first:openReward()
assert(not first:descend())
assert(first:pickReward("card.fireball"))
assert(not first:pickReward("card.fireball"))
assert(#first.rewards.picks == 1)
first:resetPicks()
assert(#first.rewards.picks == 0)
assert(first:pickReward("card.mend"))
assert(first:pickReward("card.mend"))
assert(first:pickReward("card.mend"))
assert(not first:pickReward("card.firebolt"))
assert(first:descend())
assert(first.run.room == 2 and first.combat.phase == "mulligan" and first:deckCount("Mend") == 3)

local feedback = Feedback.new()
local visible = Game.new(30, 100, { catalog = catalog, feedback = feedback })
assert(visible.messageTime == nil and visible.selected == nil)
local enemy = visible.combat.enemies[1]
visible:damageEnemy(enemy, 1)
assert(enemy.flash == nil and feedback:flash(enemy) == 0.18)
visible:damagePlayer(1)
assert(visible.shake == nil and feedback.shake == 0.22)
feedback:update(0.3)
assert(feedback:flash(enemy) == 0 and feedback.shake == 0)
visible:restart()
assert(feedback:flash(enemy) == 0 and feedback.messageTime == 1.5)

-- Exercise screen/controller wiring with graphics calls stubbed, not gameplay.
-- Replace graphics side effects while exercising real app and screen routing.
local noop = function() end
love = {
    timer = { getTime = function() return 0 end },
    graphics = {
        -- Supply only the font metric used by button layout.
        newFont = function() return { getHeight = function() return 20 end } end,
        -- Use the virtual resolution so layout tests need no scaling assumptions.
        getDimensions = function() return 1920, 1080 end,
    },
}
for _, name in ipairs({ "setDefaultFilter", "setLineStyle", "setLineWidth", "setColor", "rectangle",
    "setFont", "printf", "circle", "line", "polygon", "clear", "push", "pop", "translate", "scale" }) do
    love.graphics[name] = noop
end
local App = require("src.app")
local app = App.new()
app:load()
app:draw()
app:activate({ id = "keep" })
app.game.deck.hand = { app.game.cards:make("Fireball") }
app.game.combat.mana = 0
app:activate({ id = "card", payload = 1 })
assert(app.combatController.selected == 1 and app.game.selected == nil)
app:activate({ id = "enemy", payload = 1 })
assert(app.combatController.selected == 1, "rejected play preserves selection")
app.game.combat.mana = 3
app.game.combat.enemies[1].tough = 100
app:activate({ id = "enemy", payload = 1 })
assert(app.combatController.selected == nil and #app.game.deck.hand == 0)
app:draw()
app.combatController.selected = 1
app:keypressed("space")
assert(app.combatController.selected == nil and app.game.combat.phase == "enemy")
app:update(0.4)
app:draw()
app.game:openReward()
app:syncScene()
app:draw()
app:showDeck()
app:draw()
app:activate({ id = "closedeck" })
assert(app:inspect({ id = "shop", payload = app.game.rewards.choices[1] }))
app:draw()
app:closeInspection()
app.game:damagePlayer(1000)
app:syncScene()
app:draw()
app:activate({ id = "restart" })
assert(app.game.combat.phase == "mulligan" and app.combatController.selected == nil)
app:draw()
print("structure and presentation integration tests passed")
