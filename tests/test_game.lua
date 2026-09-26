package.path = "game/?.lua;game/?/init.lua;" .. package.path

love = {
    math = {
        random = function(limit) return math.random(limit) end,
    },
}

math.randomseed(12345)

local Cards = require("src.cards")
local Game = require("src.game")

local function equal(actual, expected, message)
    assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local game = Game.new(30, 12345)
equal(game.state, "combat", "new run state")
equal(game.phase, "mulligan", "new room phase")
equal(#game.hand, 7, "opening hand size")
equal(#game.masterDeck, 9, "starter deck size")
equal(game.encounterTargetPower, 1, "room one power budget")
equal(#game.enemies, 1, "room one generated enemy count")
equal(game.enemies[1].id, "enemy.goblin", "room one generated enemy")

game:redrawHand()
equal(game.phase, "player", "redraw completes mulligan")
equal(#game.hand, 7, "redraw preserves opening hand size")

game.enemies = { { name = "Dummy", pow = 2, tough = 100, maxTough = 100, alive = true, frozen = false, flash = 0 } }
game.hand = { Cards.make("Power Surge"), Cards.make("Fireball") }
game.mana = 3
assert(game:play(1))
equal(game.surge, 1, "Power Surge stacks")
assert(game:play(1, 1))
equal(game.enemies[1].tough, 88, "surged Fireball damage")
equal(game.surge, 0, "surge consumption")

game.hand = { Cards.make("Mirror Image"), Cards.make("Firebolt") }
game.mana = 3
assert(game:play(1))
equal(game.mirror, 1, "Mirror Image stack")
assert(game:play(1, 1))
equal(game.mirror, 0, "mirror consumption")
equal(#game.hand, 1, "mirror creates one copy")
equal(game.hand[1].name, "Firebolt", "copied card name")
equal(game.hand[1].cost, 0, "copied card discount")
assert(game.hand[1].isCopy)
local discardBefore = #game.discard
assert(game:play(1, 1))
equal(#game.discard, discardBefore, "copy vanishes instead of discarding")

game.hp, game.armor = 30, 3
game:damagePlayer(5)
equal(game.armor, 0, "armor absorbs first")
equal(game.hp, 28, "overflow reaches HP")

game.state, game.phase = "combat", "player"
game.hp, game.armor = 28, 0
game.enemies = { { name = "Frozen Dummy", pow = 9, tough = 10, maxTough = 10, alive = true, frozen = true, flash = 0 } }
game:endTurn()
game:update(0.4)
equal(game.hp, 28, "frozen enemy skips damage")
equal(game.enemies[1].frozen, false, "frozen enemy thaws")
game:update(0.7)
equal(game.phase, "player", "enemy phase completes")

game.room, game.wave = 5, 1
game.state, game.phase = "combat", "player"
game.turn, game.maxMana, game.mana = 3, 3, 0
game.enemies = { { name = "Skeleton", pow = 4, tough = 0, maxTough = 15, alive = false, frozen = false, flash = 0 } }
game:checkEncounterClear()
equal(game.wave, 2, "boss wave begins")
equal(game.enemies[1].name, "Bone Lord", "boss spawned")
equal(game.turn, 4, "boss wave advances turn")
equal(game.mana, 3, "boss wave refills mana")

game.enemies[1].alive = false
game.enemies[1].tough = 0
local completedDeckSize = #game.masterDeck
game.hp = 3
game:checkEncounterClear()
equal(game.state, "combat", "boss death starts endless combat")
equal(game.endless, true, "endless mode enabled")
equal(game.endlessRoom, 1, "first endless room")
equal(game.room, 6, "run continues after boss room")
equal(game.hp, game.maxHp, "endless benchmark begins healed")
equal(#game.masterDeck, completedDeckSize, "endless preserves completed deck")
local endlessSettings = Cards.catalog.document.endless
equal(game.encounterTargetPower, endlessSettings.startingPower, "first endless power budget")
assert(#game.enemies >= 1 and #game.enemies <= 4, "endless room should generate a valid group")

for _, enemy in ipairs(game.enemies) do enemy.alive, enemy.tough = false, 0 end
game:checkEncounterClear()
equal(game.state, "combat", "endless clear skips shop")
equal(game.endlessRoom, 2, "endless room advances")
equal(game.encounterTargetPower, endlessSettings.startingPower + endlessSettings.powerPerRoom, "endless power scales each room")

print("gameplay rules tests passed")
