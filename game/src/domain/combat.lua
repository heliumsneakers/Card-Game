local Debuffs = require("src.domain.debuffs.registry")
local DamageModifiers = require("src.domain.damage_modifiers")
local Deck = require("src.domain.deck")
local Resolver = require("src.domain.effects.resolver")
local Combat = {}
local effectActions
local Expressions = require("src.domain.effects.expressions")

-- Copy mutable preview state without sharing nested tables with combat.
local function copyState(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copyState(child) end
    return result
end

-- Centralize combat-phase assignment, including clearing the phase on defeat.
function Combat.setPhase(state, phase)
    state.phase = phase
end

-- Roll or use fixed enemy stats, apply scaling, and create mutable combat data.
local function makeEnemy(catalog, spec, boss, random, scale)
    local reference = spec.id or spec[1]
    local definition = spec.damage and spec or assert(catalog.enemies[reference], "unknown enemy: " .. tostring(reference))
    scale = scale or 1
    -- Fixed wave specs supply positional stats; generated definitions roll from ranges.
    local power = spec[2] or random(definition.damage.min, definition.damage.max)
    local toughness = spec[3] or random(definition.hp.min, definition.hp.max)
    -- Round scaled stats once and keep HP positive even at very small scales.
    power = math.max(0, math.floor(power * scale + 0.5))
    toughness = math.max(1, math.floor(toughness * scale + 0.5))
    return {
        id = definition.id, name = definition.name, pow = power, tough = toughness, maxTough = toughness,
        frozen = false, debuffs = {}, alive = true, isBoss = boss or false,
    }
end

-- Initialize room-local mana, phase, statuses, and counters.
function Combat.new()
    local state = {}
    Combat.setPhase(state, "mulligan")
    state.wave, state.turn = 1, 1
    state.maxMana, state.mana = 1, 1
    state.statuses, state.turnCounters, state.combatCounters = {}, {}, {}
    -- Damage bonuses have independent turn and encounter lifetimes.
    state.turnDamageBonuses, state.combatDamageBonuses = {}, {}
    state.previousCardId = nil
    return state
end

-- Replace the active enemy group with new instances from the supplied specs.
function Combat.spawnEnemies(state, catalog, specs, boss, random, scale)
    state.enemies = {}
    for _, spec in ipairs(specs) do state.enemies[#state.enemies + 1] = makeEnemy(catalog, spec, boss, random, scale) end
end

-- Scalar queries expose no mutable game tables to effects or descriptions.
function Combat.queries(state, player, piles, targetIndex, previewCost)
    return {
        -- Resolve descriptions against isolated state using the real action adapter.
        previewValues = function(definition, cardId, instanceId, multiplier)
            local shadow, person = copyState(state), copyState(player)
            local deck = copyState(piles or { hand = {}, draw = {}, discard = {} })
            local values, bonusValues = {}, {}
            -- The inspected card pays its cost and leaves hand before its effects.
            shadow.mana = shadow.mana - (previewCost or definition.cost or 0)
            for index, card in ipairs(deck.hand) do
                if card.instanceId == instanceId then table.remove(deck.hand, index); break end
            end
            Resolver.resolve(definition, cardId, Combat.queries(shadow, person),
                effectActions(shadow, deck, person, function(limit) return limit end, nil, targetIndex or 1, definition), multiplier, instanceId,
                function(effect, context)
                    -- Bind values to blocks so both branch numbering and ordering remain stable.
                    if effect.op == "debuff" and effect.bonusDamage then bonusValues[effect] = Expressions.debuffDamage(effect, context) end
                    if effect.op == "debuff" or effect.op == "addStatus" then values[effect] = Expressions.amount(effect, context, "stacks")
                    elseif effect.op == "damageBonus" then values[effect] = Expressions.amount(effect, context)
                    elseif effect.op == "damage" then values[effect] = Expressions.amount(effect, context) + DamageModifiers.amount(shadow, definition)
                    elseif effect.op == "armor" or effect.op == "heal" or effect.op == "draw" or effect.op == "mana" then values[effect] = Expressions.amount(effect, context) end
                end)
            return values, bonusValues
        end,
        -- Counters are read on demand so earlier effects can influence later expressions.
        counter = function(id, scope)
            local counters = scope == "combat" and state.combatCounters or state.turnCounters
            return counters[id] or 0
        end,
        -- Expose only the supported scalar fields, not arbitrary combat or run data.
        value = function(path)
            if path == "livingEnemies" then return Combat.livingEnemies(state) end
            if path == "hp" then return player.hp end
            if path == "previousCardId" or path == "mana" or path == "turn" then
                return state[path]
            end
        end,
    }
end

-- Visit living targets for either the selected slot or the entire enemy group.
local function eachTarget(state, target, targetIndex, callback)
    if target == "allEnemies" then
        for _, enemy in ipairs(state.enemies) do
            if enemy.alive then callback(enemy) end
        end
    elseif target == "selectedEnemy" then
        -- Recheck aliveness per effect because an earlier block may have killed the target.
        local enemy = state.enemies[targetIndex or 0]
        if enemy and enemy.alive then callback(enemy) end
    elseif target == "otherEnemies" then
        for index, enemy in ipairs(state.enemies) do
            if index ~= targetIndex and enemy.alive then callback(enemy) end
        end
    end
end

-- Closures bind the chosen target and dependencies. Handlers cannot reach state.
effectActions = function(state, piles, player, random, feedback, targetIndex, sourceCard)
    return {
        -- Bind target resolution and damage feedback behind one mutation operation.
        damage = function(target, amount)
            -- Add matching passive bonuses once, then use the same total per target.
            local modifiedAmount = amount + DamageModifiers.amount(state, sourceCard)
            eachTarget(state, target, targetIndex, function(enemy) Combat.damageEnemy(state, enemy, modifiedAmount, feedback) end)
        end,
        -- Store additive damage bonuses outside card-specific damage formulas.
        damageBonus = function(effect, amount) DamageModifiers.add(state, sourceCard, effect, amount) end,
        -- Debuffs share target selection and retain their authoritative stack count.
        debuff = function(target, id, stacks, bonusDamage)
            eachTarget(state, target, targetIndex, function(enemy)
                Debuffs.apply(enemy, id, stacks, bonusDamage)
            end)
        end,
        -- Armor persists with the player across room-local combat resets.
        armor = function(amount) player.armor = player.armor + amount end,
        -- Healing cannot increase HP beyond the run maximum.
        heal = function(amount) player.hp = math.min(player.maxHp, player.hp + amount) end,
        -- Each requested card goes through the normal hand-limit and recycling rules.
        draw = function(amount) for _ = 1, amount do Deck.draw(piles, random) end end,
        -- An explicit effect cap overrides the current turn maximum.
        mana = function(amount, cap) state.mana = math.min(cap or state.maxMana, state.mana + amount) end,
        -- Accumulate stacks in the authoritative status table.
        addStatus = function(id, stacks)
            state.statuses[id] = (state.statuses[id] or 0) + stacks
        end,
        -- Accumulate a counter until the shared turn initialization clears it.
        incrementCounter = function(id, amount, scope)
            local counters = scope == "combat" and state.combatCounters or state.turnCounters
            counters[id] = math.max(0, (counters[id] or 0) + amount)
        end,
        -- Set/reset reuse the same lifetime selection without changing other counters.
        setCounter = function(id, amount, scope)
            local counters = scope == "combat" and state.combatCounters or state.turnCounters
            counters[id] = math.max(0, amount)
        end,
    }
end

-- Leave mulligan with the original hand; later requests have no effect.
function Combat.keepHand(state)
    if state.phase == "mulligan" then Combat.setPhase(state, "player") end
end

-- Replace the opening hand once, then enter the player phase.
function Combat.redrawHand(state, piles, random)
    if state.phase ~= "mulligan" then return end
    Deck.redraw(piles, random)
    Combat.setPhase(state, "player")
end

-- Convert spell-power stacks to the current linear damage multiplier.
function Combat.surgeMultiplier(state)
    local surge = state.statuses["status.spell_power"] or 0
    return surge > 0 and surge * 2 or 1
end

-- Check phase, card cost, and any required living enemy target without mutation.
function Combat.canPlay(state, piles, cards, index, targetIndex)
    if state.phase ~= "player" then return false end
    local card = piles.hand[index]
    if not card or card.cost > state.mana then return false end
    local definition = cards:definition(card)
    if definition.target == "enemy" or definition.target == "multi" then
        local enemy = state.enemies[targetIndex or 0]
        return enemy ~= nil and enemy.alive
    end
    return true
end

-- Reduce living enemy HP, trigger feedback, and mark lethal hits dead.
function Combat.damageEnemy(state, enemy, amount, feedback)
    if not enemy or not enemy.alive then return end
    enemy.tough = math.max(0, enemy.tough - amount)
    if feedback then feedback:enemyDamaged(enemy) end
    if enemy.tough == 0 then enemy.alive = false end
end

-- Execute effects with captured spell power, then apply its consumption rule.
function Combat.resolveCard(state, piles, player, cards, random, feedback, card, targetIndex)
    local definition = cards:definition(card)
    -- Capture the multiplier now, while scalar queries remain live during execution.
    Resolver.resolve(definition, card.id, Combat.queries(state, player),
        effectActions(state, piles, player, random, feedback, targetIndex, definition), Combat.surgeMultiplier(state), card.instanceId)
    -- Only definitions that explicitly retain spell power leave its stacks available.
    local retainsSpellPower = false
    for _, id in ipairs(definition.retainsStatuses or {}) do
        if id == "status.spell_power" then retainsSpellPower = true end
    end
    if not retainsSpellPower then
        state.statuses["status.spell_power"] = 0
    end
end

-- Spend resources and resolve the card, including discard and mirror-copy handling.
function Combat.play(state, piles, player, cards, random, feedback, index, targetIndex)
    if not Combat.canPlay(state, piles, cards, index, targetIndex) then return false end

    -- Remove and pay before effects so draws see the freed hand slot and updated mana.
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

-- Count alive flags rather than relying on enemy array length.
function Combat.livingEnemies(state)
    local count = 0
    for _, enemy in ipairs(state.enemies) do if enemy.alive then count = count + 1 end end
    return count
end

-- Begin the paced enemy sequence from its first slot.
function Combat.endTurn(state)
    if state.phase ~= "player" then return end
    Combat.setPhase(state, "enemy")
    state.enemyIndex = 1
    -- Queue one global tick before the paced enemy actions begin.
    state.debuffTurnPending = true
    state.enemyTimer = 0.35
end

-- Absorb damage with armor before HP; return whether the player died.
function Combat.damagePlayer(state, player, amount, feedback)
    -- Armor absorbs first; only the remainder is subtracted from HP.
    local absorbed = math.min(player.armor, amount)
    player.armor = player.armor - absorbed
    player.hp = math.max(0, player.hp - (amount - absorbed))
    if feedback then feedback:playerDamaged() end
    if player.hp == 0 then
        Combat.setPhase(state, nil)
    end
    return player.hp == 0
end

-- Share mana refill, counter reset, and one draw across turn and boss transitions.
function Combat.advanceTurn(state, piles, random)
    state.turn = state.turn + 1
    state.maxMana = math.min(3, state.maxMana + 1)
    state.mana = state.maxMana
    state.turnCounters = {}
    -- Turn bonuses expire with counters; combat bonuses survive this transition.
    DamageModifiers.advanceTurn(state)
    Deck.draw(piles, random)
end

-- Initialize a new turn, then allow player actions again.
function Combat.finishEnemyPhase(state, piles, random)
    Combat.advanceTurn(state, piles, random)
    Combat.setPhase(state, "player")
end

-- Tick turn bonuses once, then resolve at most one paced enemy action.
function Combat.update(state, piles, player, dt, random, feedback)
    if state.phase ~= "enemy" then return end
    if state.debuffTurnPending then
        -- Clear first so later updates or repeated actions cannot tick twice.
        state.debuffTurnPending = false
        for _, enemy in ipairs(state.enemies) do
            if enemy.alive then
                Debuffs.tickTurn(enemy, {
                    damage = function(amount) Combat.damageEnemy(state, enemy, amount, feedback) end,
                })
            end
        end
        -- Let the game handle rewards or boss transitions without advancing the turn.
        if Combat.livingEnemies(state) == 0 then return end
    end
    state.enemyTimer = state.enemyTimer - dt
    if state.enemyTimer > 0 then return end

    -- Dead slots stay in the array for stable targeting, but never take an action.
    while state.enemyIndex <= #state.enemies and not state.enemies[state.enemyIndex].alive do
        state.enemyIndex = state.enemyIndex + 1
    end
    local enemy = state.enemies[state.enemyIndex]
    if not enemy then
        Combat.finishEnemyPhase(state, piles, random)
        return
    end

    -- Registered debuffs run before the attack and own their expiration rules.
    local skip = Debuffs.beforeAction(enemy, {
        damage = function(amount) Combat.damageEnemy(state, enemy, amount, feedback) end,
        notice = feedback and function(message) feedback:notice(message, 0.65) end or nil,
    })
    if enemy.alive and not skip then
        Combat.damagePlayer(state, player, enemy.pow, feedback)
        if feedback then feedback:notice(enemy.name .. " HITS FOR " .. enemy.pow, 0.65) end
    end
    state.enemyIndex = state.enemyIndex + 1
    -- Schedule the next action instead of resolving multiple attacks in one update.
    state.enemyTimer = 0.65
    return player.hp == 0
end

return Combat
