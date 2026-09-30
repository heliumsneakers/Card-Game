package.path = "game/?.lua;game/?/init.lua;" .. package.path

love = {
    math = {
        -- Supply only the LÖVE random shim expected by this headless setup.
        random = function(limit) return math.random(limit) end,
    },
}

math.randomseed(12345)

local Game = require("src.game")

-- Report the scenario and both values when a gameplay expectation fails.
local function equal(actual, expected, message)
    assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local catalog = assert(require("src.content").load("content/content.json"))
local game = Game.new(30, 12345, { catalog = catalog })
local Cards = game.cards
equal(game.run.state, "combat", "new run state")
equal(game.combat.phase, "mulligan", "new room phase")
equal(#game.deck.hand, 7, "opening hand size")
equal(#game.run.masterDeck, 9, "starter deck size")
equal(game.combat.encounterTargetPower, 1, "room one power budget")
equal(#game.combat.enemies, 1, "room one generated enemy count")
equal(game.combat.enemies[1].id, "enemy.goblin", "room one generated enemy")

game:redrawHand()
equal(game.combat.phase, "player", "redraw completes mulligan")
equal(#game.deck.hand, 7, "redraw preserves opening hand size")

game.combat.enemies = { { name = "Dummy", pow = 2, tough = 100, maxTough = 100, alive = true, frozen = false, flash = 0 } }
game.deck.hand = { Cards:make("Power Surge"), Cards:make("Fireball") }
game.combat.mana = 3
assert(game:play(1))
equal(game.combat.statuses["status.spell_power"], 1, "Power Surge stacks")
assert(game:play(1, 1))
equal(game.combat.enemies[1].tough, 88, "surged Fireball damage")
equal(game.combat.statuses["status.spell_power"], 0, "surge consumption")

game.deck.hand = { Cards:make("Mirror Image"), Cards:make("Firebolt") }
game.combat.mana = 3
assert(game:play(1))
equal(game.combat.statuses["status.mirror"], 1, "Mirror Image stack")
assert(game:play(1, 1))
equal(game.combat.statuses["status.mirror"], 0, "mirror consumption")
equal(#game.deck.hand, 1, "mirror creates one copy")
equal(game.deck.hand[1].name, "Firebolt", "copied card name")
equal(game.deck.hand[1].cost, 0, "copied card discount")
assert(game.deck.hand[1].isCopy)
local discardBefore = #game.deck.discard
assert(game:play(1, 1))
equal(#game.deck.discard, discardBefore, "copy vanishes instead of discarding")

game.run.hp, game.run.armor = 30, 3
game:damagePlayer(5)
equal(game.run.armor, 0, "armor absorbs first")
equal(game.run.hp, 28, "overflow reaches HP")

game.run.state, game.combat.phase = "combat", "player"
game.run.hp, game.run.armor = 28, 0
game.combat.enemies = { { name = "Frozen Dummy", pow = 9, tough = 10, maxTough = 10, alive = true, frozen = true, flash = 0 } }
game:endTurn()
game:update(0.4)
equal(game.run.hp, 28, "frozen enemy skips damage")
equal(game.combat.enemies[1].frozen, false, "frozen enemy thaws")
game:update(0.7)
equal(game.combat.phase, "player", "enemy phase completes")

game.run.room, game.combat.wave = 5, 1
game.run.state, game.combat.phase = "combat", "player"
game.combat.turn, game.combat.maxMana, game.combat.mana = 3, 3, 0
game.combat.enemies = { { name = "Skeleton", pow = 4, tough = 0, maxTough = 15, alive = false, frozen = false, flash = 0 } }
game:checkEncounterClear()
equal(game.combat.wave, 2, "boss wave begins")
equal(game.combat.enemies[1].name, "Bone Lord", "boss spawned")
equal(game.combat.turn, 4, "boss wave advances turn")
equal(game.combat.mana, 3, "boss wave refills mana")

game.combat.enemies[1].alive = false
game.combat.enemies[1].tough = 0
local completedDeckSize = #game.run.masterDeck
game.run.hp = 3
game:checkEncounterClear()
equal(game.run.state, "combat", "boss death starts endless combat")
equal(game.run.endless, true, "endless mode enabled")
equal(game.run.endlessRoom, 1, "first endless room")
equal(game.run.room, 6, "run continues after boss room")
equal(game.run.hp, game.run.maxHp, "endless benchmark begins healed")
equal(#game.run.masterDeck, completedDeckSize, "endless preserves completed deck")
local endlessSettings = Cards.catalog.document.endless
equal(game.combat.encounterTargetPower, endlessSettings.startingPower, "first endless power budget")
assert(#game.combat.enemies >= 1 and #game.combat.enemies <= 4, "endless room should generate a valid group")

for _, enemy in ipairs(game.combat.enemies) do enemy.alive, enemy.tough = false, 0 end
game:checkEncounterClear()
equal(game.run.state, "combat", "endless clear skips shop")
equal(game.run.endlessRoom, 2, "endless room advances")
equal(game.combat.encounterTargetPower, endlessSettings.startingPower + endlessSettings.powerPerRoom, "endless power scales each room")

print("gameplay rules tests passed")
