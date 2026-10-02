local Catalog = require("src.domain.debuffs.definitions")
local Behaviors = require("src.domain.debuffs.behaviors")
local Registry = { definitions = Catalog.definitions, byId = {}, byToken = {}, defaultId = Catalog.defaultId, legacyOperations = Catalog.legacyOperations }

-- Resolve a supported ID and fail explicitly when content bypasses validation.
function Registry.get(id)
    return assert(Registry.byId[id], "unknown debuff: " .. tostring(id))
end

-- Read authoritative stacks, with a fallback for old frozen-only enemy fixtures.
function Registry.stacks(enemy, id)
    local definition = Registry.get(id)
    local value = enemy.debuffs and enemy.debuffs[id]
    -- An explicit zero overrides the legacy flag after the debuff expires.
    if value ~= nil then return value end
    return definition.legacyFlag and enemy[definition.legacyFlag] and 1 or 0
end

-- Read the captured bonus separately from the debuff's remaining duration.
function Registry.bonusDamage(enemy, id)
    return enemy.debuffDamage and enemy.debuffDamage[id] or 0
end

-- Replace one stack count and synchronize any legacy presentation flag.
function Registry.setStacks(enemy, id, stacks)
    local definition = Registry.get(id)
    enemy.debuffs = enemy.debuffs or {}
    enemy.debuffs[id] = math.max(0, stacks)
    if definition.legacyFlag then enemy[definition.legacyFlag] = enemy.debuffs[id] > 0 end
    -- Expiration clears potency so a later application starts fresh.
    if enemy.debuffs[id] == 0 and enemy.debuffDamage then enemy.debuffDamage[id] = nil end
end

-- Stack a registered debuff; target filtering remains the combat adapter's job.
function Registry.apply(enemy, id, stacks, bonusDamage)
    local before = Registry.stacks(enemy, id)
    if stacks <= 0 then return end
    local previousBonus = before > 0 and Registry.bonusDamage(enemy, id) or 0
    Registry.setStacks(enemy, id, before + stacks)
    -- Duration accumulates, but potency retains the strongest active application.
    enemy.debuffDamage = enemy.debuffDamage or {}
    enemy.debuffDamage[id] = math.max(previousBonus, bonusDamage or 0)
end

-- Return active metadata and amounts in stable registry order for enemy badges.
function Registry.active(enemy)
    local result = {}
    for _, definition in ipairs(Registry.definitions) do
        local stacks = Registry.stacks(enemy, definition.id)
        if stacks > 0 then result[#result + 1] = { definition = definition, stacks = stacks, bonusDamage = Registry.bonusDamage(enemy, definition.id) } end
    end
    return result
end

-- Apply recurring bonuses at the turn boundary independently of enemy actions.
function Registry.tickTurn(enemy, context)
    for _, entry in ipairs(Registry.active(enemy)) do
        -- Stop once a bonus kills the target; dead enemies receive no further ticks.
        if not enemy.alive then break end
        if entry.bonusDamage > 0 then context.damage(entry.bonusDamage) end
    end
end

-- Run each active behavior once before an enemy attack, without short-circuiting skips.
function Registry.beforeAction(enemy, context)
    local skip = false
    for _, entry in ipairs(Registry.active(enemy)) do
        -- A previous hook may kill the enemy; later hooks must not revive its action.
        if not enemy.alive then break end
        local definition = entry.definition
        local skipped = Behaviors[definition.behavior](definition, entry.stacks, {
            name = enemy.name,
            notice = context.notice,
            damage = context.damage,
            -- Keep direct state mutation inside the registry, not in behavior modules.
            setStacks = function(stacks) Registry.setStacks(enemy, definition.id, stacks) end,
        })
        skip = skipped or skip
    end
    return skip
end

-- Build indexes once, and reject missing mechanics immediately instead of silently doing nothing.
for _, definition in ipairs(Registry.definitions) do
    assert(not Registry.byId[definition.id], "duplicate debuff id")
    assert(not Registry.byToken[definition.token], "duplicate debuff token")
    assert(Behaviors[definition.behavior], "unsupported debuff behavior: " .. definition.behavior)
    Registry.byId[definition.id] = definition
    Registry.byToken[definition.token] = definition
end
Registry.get(Registry.defaultId)
return Registry
