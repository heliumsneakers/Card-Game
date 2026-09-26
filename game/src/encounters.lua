local Encounters = {}

local DEFAULT_ROOMS = {
    { room = 1, power = 1, minimumEnemies = 1, maximumEnemies = 2, minimumBudgetRatio = 0.90, maximumBudgetRatio = 1.05 },
    { room = 2, power = 3, minimumEnemies = 1, maximumEnemies = 3, minimumBudgetRatio = 0.90, maximumBudgetRatio = 1.05 },
    { room = 3, power = 5, minimumEnemies = 1, maximumEnemies = 4, minimumBudgetRatio = 0.90, maximumBudgetRatio = 1.05 },
    { room = 4, power = 7, minimumEnemies = 1, maximumEnemies = 4, minimumBudgetRatio = 0.90, maximumBudgetRatio = 1.05 },
}

Encounters.defaultEndless = {
    startingPower = 9,
    powerPerRoom = 2,
    minimumEnemies = 1,
    maximumEnemies = 4,
    minimumBudgetRatio = 0.90,
    maximumBudgetRatio = 1.05,
}

function Encounters.newRng(seed)
    local state = math.floor(math.abs(seed or 1)) % 2147483647
    if state == 0 then state = 1 end
    return function(minimum, maximum)
        state = (state * 48271) % 2147483647
        local unit = state / 2147483647
        if minimum == nil then return unit end
        if maximum == nil then maximum, minimum = minimum, 1 end
        return minimum + math.floor(unit * (maximum - minimum + 1))
    end
end

function Encounters.enemyPower(enemy)
    local generation = enemy.generation or {}
    if generation.powerOverride then return generation.powerOverride end
    local averageHp = (enemy.hp.min + enemy.hp.max) / 2
    local averageDamage = (enemy.damage.min + enemy.damage.max) / 2
    return (averageHp / 8.5) * (0.4 + 0.6 * (averageDamage / 2.5))
end

function Encounters.groupMultiplier(count)
    if count <= 1 then return 1 end
    if count == 2 then return 1.5 end
    if count == 3 then return 1.8 end
    return 2
end

function Encounters.encounterPower(enemies)
    local total = 0
    for _, enemy in ipairs(enemies) do total = total + Encounters.enemyPower(enemy) end
    return total * Encounters.groupMultiplier(#enemies)
end

function Encounters.roomConfig(document, roomNumber)
    for _, room in ipairs(document.roomCurve or DEFAULT_ROOMS) do
        if room.room == roomNumber then return room end
    end
    return DEFAULT_ROOMS[roomNumber]
end

local function hasTag(enemy, sought)
    for _, tag in ipairs((enemy.generation or {}).tags or enemy.tags or {}) do
        if tag == sought then return true end
    end
    return false
end

local function allowed(enemy, roomNumber, endless)
    local generation = enemy.generation or {}
    if enemy.enabled == false or generation.spawnEnabled == false or generation.bossOnly then return false end
    if not endless then
        if roomNumber < (generation.minimumRoom or 1) then return false end
        if generation.maximumRoom and roomNumber > generation.maximumRoom then return false end
    end
    return true
end

local function candidateMatchesTags(enemies, config)
    for _, tag in ipairs(config.excludedTags or {}) do
        for _, enemy in ipairs(enemies) do if hasTag(enemy, tag) then return false end end
    end
    for _, tag in ipairs(config.requiredTags or {}) do
        local found = false
        for _, enemy in ipairs(enemies) do if hasTag(enemy, tag) then found = true; break end end
        if not found then return false end
    end
    return true
end

local function allCandidates(catalog, config, roomNumber, endless)
    local pool = {}
    for _, enemy in ipairs(catalog.document.enemies) do
        if allowed(enemy, roomNumber, endless) then pool[#pool + 1] = enemy end
    end
    table.sort(pool, function(a, b) return a.id < b.id end)

    local candidates, current, counts = {}, {}, {}
    local minimum = config.minimumEnemies or 1
    local maximum = math.min(4, config.maximumEnemies or 4)

    local function visit(startIndex, targetCount)
        if #current == targetCount then
            if candidateMatchesTags(current, config) then
                local enemies, weight = {}, 1
                for _, enemy in ipairs(current) do
                    enemies[#enemies + 1] = enemy
                    weight = weight * ((enemy.generation or {}).spawnWeight or 1)
                end
                candidates[#candidates + 1] = {
                    enemies = enemies,
                    power = Encounters.encounterPower(enemies),
                    weight = weight,
                }
            end
            return
        end
        for index = startIndex, #pool do
            local enemy = pool[index]
            local maximumCopies = math.min(4, (enemy.generation or {}).maximumCopies or 4)
            local count = counts[enemy.id] or 0
            if count < maximumCopies then
                current[#current + 1] = enemy
                counts[enemy.id] = count + 1
                visit(index, targetCount)
                counts[enemy.id] = count
                current[#current] = nil
            end
        end
    end

    for count = minimum, maximum do visit(1, count) end
    return candidates
end

local function weightedChoice(candidates, random)
    local total = 0
    for _, candidate in ipairs(candidates) do total = total + candidate.weight end
    local roll = random() * total
    for _, candidate in ipairs(candidates) do
        roll = roll - candidate.weight
        if roll <= 0 then return candidate end
    end
    return candidates[#candidates]
end

function Encounters.generate(catalog, config, roomNumber, random, endless)
    local candidates = allCandidates(catalog, config, roomNumber, endless)
    if #candidates == 0 then return nil, "no eligible enemy combinations" end

    local target = config.power
    local minimum = target * (config.minimumBudgetRatio or 0.90)
    local maximum = target * (config.maximumBudgetRatio or 1.05)
    local matches = {}
    for _, candidate in ipairs(candidates) do
        if candidate.power >= minimum and candidate.power <= maximum then matches[#matches + 1] = candidate end
    end
    if #matches > 0 then return weightedChoice(matches, random) end

    local bestUnder
    for _, candidate in ipairs(candidates) do
        if candidate.power <= target and (not bestUnder or candidate.power > bestUnder.power) then bestUnder = candidate end
    end
    if bestUnder then return bestUnder, "used closest encounter below budget" end

    table.sort(candidates, function(a, b) return a.power < b.power end)
    return candidates[1], "used weakest eligible encounter"
end

-- Finds a uniform HP/damage multiplier whose midpoint power approximately
-- reaches the endless target while keeping the selected composition intact.
function Encounters.scaleForPower(enemies, targetPower)
    local multiplier = Encounters.groupMultiplier(#enemies)
    local linear, quadratic = 0, 0
    for _, enemy in ipairs(enemies) do
        local hp = (enemy.hp.min + enemy.hp.max) / 2
        local damage = (enemy.damage.min + enemy.damage.max) / 2
        linear = linear + (hp / 8.5) * 0.4
        quadratic = quadratic + (hp / 8.5) * 0.6 * (damage / 2.5)
    end
    linear, quadratic = linear * multiplier, quadratic * multiplier
    if quadratic == 0 then return math.max(1, targetPower / math.max(linear, 0.001)) end
    return math.max(1, (-linear + math.sqrt(linear * linear + 4 * quadratic * targetPower)) / (2 * quadratic))
end

return Encounters
