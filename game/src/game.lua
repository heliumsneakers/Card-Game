local Cards = require("src.cards")
local Effects = require("src.effects")
local Encounters = require("src.encounters")

local Game = {}
Game.__index = Game

local bossGuards = { { "enemy.skeleton", 4, 15 }, { "enemy.skeleton", 4, 15 } }

local function cloneList(source)
    local result = {}
    for i, value in ipairs(source) do result[i] = value end
    return result
end

local function shuffle(list, random)
    for i = #list, 2, -1 do
        local j = random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function makeEnemy(spec, boss, random, scale)
    local reference = spec.id or spec[1]
    local definition = spec.damage and spec or assert(Cards.catalog.enemies[reference], "unknown enemy: " .. tostring(reference))
    scale = scale or 1
    local power = spec[2] or random(definition.damage.min, definition.damage.max)
    local toughness = spec[3] or random(definition.hp.min, definition.hp.max)
    power = math.max(0, math.floor(power * scale + 0.5))
    toughness = math.max(1, math.floor(toughness * scale + 0.5))
    return {
        id = definition.id, name = definition.name, pow = power, tough = toughness, maxTough = toughness,
        frozen = false, alive = true, isBoss = boss or false, flash = 0,
    }
end

local function newSeed()
    local fraction = love and love.timer and love.timer.getTime and math.floor(love.timer.getTime() * 1000) or 0
    return os.time() + fraction
end

function Game.new(startingHp, seed)
    local self = setmetatable({}, Game)
    self.startingHp = startingHp or 30
    self.fixedSeed = seed
    self:restart()
    return self
end

function Game:restart()
    self.runSeed = self.fixedSeed or newSeed()
    self.random = Encounters.newRng(self.runSeed)
    self.maxHp = self.startingHp
    self.hp = self.maxHp
    self.armor = 0
    self.masterDeck = cloneList(Cards.startingDeck)
    self.room = 1
    self.endless = false
    self.endlessRoom = 0
    self.message = nil
    self.messageTime = 0
    self:startRoom()
end

function Game:notice(text, duration)
    self.message = text
    self.messageTime = duration or 1.2
end

function Game:startRoom()
    self.state = "combat"
    self.phase = "mulligan"
    self.wave = 1
    self.turn = 1
    self.maxMana = 1
    self.mana = 1
    self.statuses = {}
    self.turnCounters = {}
    self.previousCardId = nil
    self.surge, self.mirror, self.fb = 0, 0, 0
    self.selected = nil
    self.deck = {}
    self.discard = {}
    self.hand = {}
    for _, name in ipairs(self.masterDeck) do self.deck[#self.deck + 1] = Cards.make(name) end
    shuffle(self.deck, self.random)

    if self.room == 5 and not self.endless then
        self.encounterTargetPower = 7
        self.encounterPower = Encounters.encounterPower({ Cards.catalog.enemies["enemy.skeleton"], Cards.catalog.enemies["enemy.skeleton"] })
        self.encounterSeed = self.runSeed + 5005
        self:spawnEnemies(bossGuards, false, Encounters.newRng(self.encounterSeed))
        self:notice("BONE LORD'S GUARD", 1.5)
    else
        local config
        if self.endless then
            local endless = Cards.catalog.document.endless or Encounters.defaultEndless
            config = {}
            for key, value in pairs(endless) do config[key] = value end
            config.power = endless.startingPower + (self.endlessRoom - 1) * endless.powerPerRoom
        else
            config = assert(Encounters.roomConfig(Cards.catalog.document, self.room), "missing generation settings for room " .. self.room)
        end
        self.encounterSeed = self.runSeed + self.room * 1009 + self.endlessRoom * 7919
        local encounterRandom = Encounters.newRng(self.encounterSeed)
        local candidate, warning = Encounters.generate(Cards.catalog, config, self.room, encounterRandom, self.endless)
        assert(candidate, "could not generate room " .. self.room .. ": " .. tostring(warning))
        local scale = self.endless and Encounters.scaleForPower(candidate.enemies, config.power) or 1
        self.encounterTargetPower = config.power
        self.encounterPower = candidate.power
        self.encounterScale = scale
        self.encounterWarning = warning
        self:spawnEnemies(candidate.enemies, false, encounterRandom, scale)
        local banner = self.endless and ("ENDLESS " .. self.endlessRoom .. "  •  POWER " .. config.power)
            or ("ROOM " .. self.room .. "  •  POWER " .. config.power)
        self:notice(banner, 1.5)
    end
    for _ = 1, 7 do self:draw() end
end

function Game:spawnEnemies(specs, boss, random, scale)
    random = random or self.random
    self.enemies = {}
    for _, spec in ipairs(specs) do self.enemies[#self.enemies + 1] = makeEnemy(spec, boss, random, scale) end
end

function Game:draw()
    if #self.hand >= 7 then return false end
    if #self.deck == 0 then
        if #self.discard == 0 then return false end
        self.deck = self.discard
        self.discard = {}
        shuffle(self.deck, self.random)
    end
    self.hand[#self.hand + 1] = table.remove(self.deck)
    return true
end

function Game:keepHand()
    if self.phase == "mulligan" then self.phase = "player" end
end

function Game:redrawHand()
    if self.phase ~= "mulligan" then return end
    for _, card in ipairs(self.hand) do self.deck[#self.deck + 1] = card end
    self.hand = {}
    shuffle(self.deck, self.random)
    for _ = 1, 7 do self:draw() end
    self.phase = "player"
end

function Game:surgeMultiplier()
    local surge = self.statuses["status.spell_power"] or 0
    return surge > 0 and surge * 2 or 1
end

function Game:canPlay(index, targetIndex)
    if self.state ~= "combat" or self.phase ~= "player" then return false end
    local card = self.hand[index]
    if not card or card.cost > self.mana then return false end
    local definition = Cards.definition(card)
    if definition.target == "enemy" then
        local enemy = self.enemies[targetIndex or 0]
        return enemy ~= nil and enemy.alive
    end
    return true
end

function Game:damageEnemy(enemy, amount)
    if not enemy or not enemy.alive then return end
    enemy.tough = math.max(0, enemy.tough - amount)
    enemy.flash = 0.18
    if enemy.tough == 0 then enemy.alive = false end
end

function Game:resolveCard(card, targetIndex)
    local definition = Cards.definition(card)
    Effects.resolve(self, card, definition, targetIndex)
    local retainsSpellPower = false
    for _, id in ipairs(definition.retainsStatuses or {}) do
        if id == "status.spell_power" then retainsSpellPower = true end
    end
    if not retainsSpellPower then
        self.statuses["status.spell_power"] = 0
        self.surge = 0
    end
end

function Game:play(index, targetIndex)
    if not self:canPlay(index, targetIndex) then return false end

    local card = table.remove(self.hand, index)
    self.selected = nil
    self.mana = self.mana - card.cost

    -- Existing mirror stacks trigger on this spell. Clearing them before the
    -- effect lets a played Mirror Image establish a fresh future trigger.
    local mirrorCopies = self.statuses["status.mirror"] or 0
    self.statuses["status.mirror"] = 0
    self.mirror = 0
    self:resolveCard(card, targetIndex)
    self.previousCardId = card.id

    if not card.isCopy then self.discard[#self.discard + 1] = card end
    for _ = 1, mirrorCopies do
        if #self.hand >= 7 then break end
        self.hand[#self.hand + 1] = Cards.make(card.id, math.max(0, card.cost - 1), true)
    end

    self:checkEncounterClear()
    return true
end

function Game:livingEnemies()
    local count = 0
    for _, enemy in ipairs(self.enemies) do if enemy.alive then count = count + 1 end end
    return count
end

function Game:checkEncounterClear()
    if self:livingEnemies() > 0 then return end
    if self.room == 5 and self.wave == 1 then
        self.wave = 2
        self:spawnEnemies({ { "enemy.bone_lord", 6, 28 } }, true)
        self.turn = self.turn + 1
        self.maxMana = math.min(3, self.maxMana + 1)
        self.mana = self.maxMana
        self.turnCounters = {}
        self.fb = 0
        self:draw()
        self:notice("BONE LORD AWAKENS", 1.8)
    elseif self.room == 5 and not self.endless then
        self.endless = true
        self.endlessRoom = 1
        self.room = 6
        self.hp = self.maxHp
        self.armor = 0
        self:startRoom()
        self:notice("BONE LORD DEFEATED  •  ENDLESS BEGINS", 2.2)
    elseif self.endless then
        self.endlessRoom = self.endlessRoom + 1
        self.room = self.room + 1
        self:startRoom()
    else
        self:openReward()
    end
end

function Game:endTurn()
    if self.state ~= "combat" or self.phase ~= "player" then return end
    self.selected = nil
    self.phase = "enemy"
    self.enemyIndex = 1
    self.enemyTimer = 0.35
end

function Game:damagePlayer(amount)
    local absorbed = math.min(self.armor, amount)
    self.armor = self.armor - absorbed
    self.hp = math.max(0, self.hp - (amount - absorbed))
    self.shake = 0.22
    if self.hp == 0 then
        self.state = "gameover"
        self.phase = nil
    end
end

function Game:finishEnemyPhase()
    self.turn = self.turn + 1
    self.maxMana = math.min(3, self.maxMana + 1)
    self.mana = self.maxMana
    self.turnCounters = {}
    self.fb = 0
    self:draw()
    self.phase = "player"
end

function Game:update(dt)
    self.messageTime = math.max(0, self.messageTime - dt)
    self.shake = math.max(0, (self.shake or 0) - dt)
    for _, enemy in ipairs(self.enemies or {}) do enemy.flash = math.max(0, enemy.flash - dt) end

    if self.state ~= "combat" or self.phase ~= "enemy" then return end
    self.enemyTimer = self.enemyTimer - dt
    if self.enemyTimer > 0 then return end

    while self.enemyIndex <= #self.enemies and not self.enemies[self.enemyIndex].alive do
        self.enemyIndex = self.enemyIndex + 1
    end
    local enemy = self.enemies[self.enemyIndex]
    if not enemy then
        self:finishEnemyPhase()
        return
    end

    if enemy.frozen then
        enemy.frozen = false
        self:notice(enemy.name .. " IS FROZEN", 0.65)
    else
        self:damagePlayer(enemy.pow)
        self:notice(enemy.name .. " HITS FOR " .. enemy.pow, 0.65)
    end
    self.enemyIndex = self.enemyIndex + 1
    self.enemyTimer = 0.65
end

function Game:deckCount(name)
    local id = Cards.definition(name).id
    local count = 0
    for _, value in ipairs(self.masterDeck) do if value == id then count = count + 1 end end
    return count
end

function Game:openReward()
    self.state = "reward"
    self.phase = nil
    self.shopPicks = {}
    self.shopChoices = {}
    self.showDeck = false
    local eligible = {}
    for _, name in ipairs(Cards.shopPool) do
        if self:deckCount(name) < 3 then eligible[#eligible + 1] = name end
    end
    shuffle(eligible, self.random)
    local preview = Cards.catalog.document.preview
    local featured = preview and preview.featuredCardId or nil
    if featured then
        for index, id in ipairs(eligible) do
            if id == featured then
                self.shopChoices[#self.shopChoices + 1] = id
                table.remove(eligible, index)
                break
            end
        end
    end
    for i = 1, math.min(6 - #self.shopChoices, #eligible) do
        self.shopChoices[#self.shopChoices + 1] = eligible[i]
    end
end

function Game:pickReward(name)
    if self.state ~= "reward" or #self.shopPicks >= 3 then return false end
    local pending = 0
    for _, picked in ipairs(self.shopPicks) do if picked == name then pending = pending + 1 end end
    if self:deckCount(name) + pending >= 3 then
        self:notice("MAX 3 COPIES", 0.8)
        return false
    end
    self.shopPicks[#self.shopPicks + 1] = Cards.definition(name).id
    return true
end

function Game:resetPicks()
    if self.state == "reward" then self.shopPicks = {} end
end

function Game:descend()
    if self.state ~= "reward" or #self.shopPicks ~= 3 then return false end
    for _, name in ipairs(self.shopPicks) do self.masterDeck[#self.masterDeck + 1] = name end
    self.room = self.room + 1
    self:startRoom()
    return true
end

function Game:masterCounts()
    local counts = {}
    for _, name in ipairs(self.masterDeck) do counts[name] = (counts[name] or 0) + 1 end
    local rows = {}
    for id, count in pairs(counts) do rows[#rows + 1] = { id = id, name = Cards.definition(id).name, count = count } end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

return Game
