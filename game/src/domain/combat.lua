local Deck = require("src.domain.deck")
local Resolver = require("src.domain.effects.resolver")
local Combat = {}

function Combat.setPhase(state, phase)
    state.phase = phase
end

local function makeEnemy(catalog, spec, boss, random, scale)
    local reference = spec.id or spec[1]
    local definition = spec.damage and spec or assert(catalog.enemies[reference], "unknown enemy: " .. tostring(reference))
    scale = scale or 1
    local power = spec[2] or random(definition.damage.min, definition.damage.max)
    local toughness = spec[3] or random(definition.hp.min, definition.hp.max)
    power = math.max(0, math.floor(power * scale + 0.5))
    toughness = math.max(1, math.floor(toughness * scale + 0.5))
    return {
        id = definition.id, name = definition.name, pow = power, tough = toughness, maxTough = toughness,
        frozen = false, alive = true, isBoss = boss or false,
    }
end

function Combat.new()
    local state = {}
    Combat.setPhase(state, "mulligan")
    state.wave, state.turn = 1, 1
    state.maxMana, state.mana = 1, 1
    state.statuses, state.turnCounters = {}, {}
    state.previousCardId = nil
    return state
end

function Combat.spawnEnemies(state, catalog, specs, boss, random, scale)
    state.enemies = {}
    for _, spec in ipairs(specs) do state.enemies[#state.enemies + 1] = makeEnemy(catalog, spec, boss, random, scale) end
end

-- Scalar queries expose no mutable game tables to effects or descriptions.
function Combat.queries(state, player)
    return {
        counter = function(id) return state.turnCounters[id] or 0 end,
        value = function(path)
            if path == "livingEnemies" then return Combat.livingEnemies(state) end
            if path == "hp" then return player.hp end
            if path == "previousCardId" or path == "mana" or path == "turn" then
                return state[path]
            end
        end,
    }
end

local function eachTarget(state, target, targetIndex, callback)
    if target == "allEnemies" then
        for _, enemy in ipairs(state.enemies) do
            if enemy.alive then callback(enemy) end
        end
    elseif target == "selectedEnemy" then
        local enemy = state.enemies[targetIndex or 0]
        if enemy and enemy.alive then callback(enemy) end
    end
end

-- Closures bind the chosen target and dependencies. Handlers cannot reach state.
local function effectActions(state, piles, player, random, feedback, targetIndex)
    return {
        damage = function(target, amount)
            eachTarget(state, target, targetIndex, function(enemy) Combat.damageEnemy(state, enemy, amount, feedback) end)
        end,
        freeze = function(target)
            eachTarget(state, target, targetIndex, function(enemy) enemy.frozen = true end)
        end,
        armor = function(amount) player.armor = player.armor + amount end,
        heal = function(amount) player.hp = math.min(player.maxHp, player.hp + amount) end,
        draw = function(amount) for _ = 1, amount do Deck.draw(piles, random) end end,
        mana = function(amount, cap) state.mana = math.min(cap or state.maxMana, state.mana + amount) end,
        addStatus = function(id, stacks)
            state.statuses[id] = (state.statuses[id] or 0) + stacks
        end,
        incrementCounter = function(id, amount)
            state.turnCounters[id] = (state.turnCounters[id] or 0) + amount
        end,
    }
end

function Combat.keepHand(state)
    if state.phase == "mulligan" then Combat.setPhase(state, "player") end
end

function Combat.redrawHand(state, piles, random)
    if state.phase ~= "mulligan" then return end
    Deck.redraw(piles, random)
    Combat.setPhase(state, "player")
end

function Combat.surgeMultiplier(state)
    local surge = state.statuses["status.spell_power"] or 0
    return surge > 0 and surge * 2 or 1
end

function Combat.canPlay(state, piles, cards, index, targetIndex)
    if state.phase ~= "player" then return false end
    local card = piles.hand[index]
    if not card or card.cost > state.mana then return false end
    local definition = cards:definition(card)
    if definition.target == "enemy" then
        local enemy = state.enemies[targetIndex or 0]
        return enemy ~= nil and enemy.alive
    end
    return true
end

function Combat.damageEnemy(state, enemy, amount, feedback)
    if not enemy or not enemy.alive then return end
    enemy.tough = math.max(0, enemy.tough - amount)
    if feedback then feedback:enemyDamaged(enemy) end
    if enemy.tough == 0 then enemy.alive = false end
end

function Combat.resolveCard(state, piles, player, cards, random, feedback, card, targetIndex)
    local definition = cards:definition(card)
    Resolver.resolve(definition, card.id, Combat.queries(state, player),
        effectActions(state, piles, player, random, feedback, targetIndex), Combat.surgeMultiplier(state))
    local retainsSpellPower = false
    for _, id in ipairs(definition.retainsStatuses or {}) do
        if id == "status.spell_power" then retainsSpellPower = true end
    end
    if not retainsSpellPower then
        state.statuses["status.spell_power"] = 0
    end
end

function Combat.play(state, piles, player, cards, random, feedback, index, targetIndex)
    if not Combat.canPlay(state, piles, cards, index, targetIndex) then return false end

    local card = table.remove(piles.hand, index)
    state.mana = state.mana - card.cost

    -- Existing mirror stacks trigger on this spell. Clearing them before the
    -- effect lets a played Mirror Image establish a fresh future trigger.
    local mirrorCopies = state.statuses["status.mirror"] or 0
    state.statuses["status.mirror"] = 0
    Combat.resolveCard(state, piles, player, cards, random, feedback, card, targetIndex)
    state.previousCardId = card.id

    Deck.discardPlayed(piles, card)
    Deck.addCopies(piles, cards, card, mirrorCopies)

    return true
end

function Combat.livingEnemies(state)
    local count = 0
    for _, enemy in ipairs(state.enemies) do if enemy.alive then count = count + 1 end end
    return count
end

function Combat.endTurn(state)
    if state.phase ~= "player" then return end
    Combat.setPhase(state, "enemy")
    state.enemyIndex = 1
    state.enemyTimer = 0.35
end

function Combat.damagePlayer(state, player, amount, feedback)
    local absorbed = math.min(player.armor, amount)
    player.armor = player.armor - absorbed
    player.hp = math.max(0, player.hp - (amount - absorbed))
    if feedback then feedback:playerDamaged() end
    if player.hp == 0 then
        Combat.setPhase(state, nil)
    end
    return player.hp == 0
end

function Combat.advanceTurn(state, piles, random)
    state.turn = state.turn + 1
    state.maxMana = math.min(3, state.maxMana + 1)
    state.mana = state.maxMana
    state.turnCounters = {}
    Deck.draw(piles, random)
end

function Combat.finishEnemyPhase(state, piles, random)
    Combat.advanceTurn(state, piles, random)
    Combat.setPhase(state, "player")
end

function Combat.update(state, piles, player, dt, random, feedback)
    if state.phase ~= "enemy" then return end
    state.enemyTimer = state.enemyTimer - dt
    if state.enemyTimer > 0 then return end

    while state.enemyIndex <= #state.enemies and not state.enemies[state.enemyIndex].alive do
        state.enemyIndex = state.enemyIndex + 1
    end
    local enemy = state.enemies[state.enemyIndex]
    if not enemy then
        Combat.finishEnemyPhase(state, piles, random)
        return
    end

    if enemy.frozen then
        enemy.frozen = false
        if feedback then feedback:notice(enemy.name .. " IS FROZEN", 0.65) end
    else
        Combat.damagePlayer(state, player, enemy.pow, feedback)
        if feedback then feedback:notice(enemy.name .. " HITS FOR " .. enemy.pow, 0.65) end
    end
    state.enemyIndex = state.enemyIndex + 1
    state.enemyTimer = 0.65
    return player.hp == 0
end

return Combat
