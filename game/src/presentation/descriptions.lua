local Counters = require("src.domain.effects.counters")
local Debuffs = require("src.domain.debuffs.registry")
local Expressions = require("src.domain.effects.expressions")
local amount = Expressions.amount
local clampAmount = Expressions.clampAmount
local Descriptions = {}

-- Prefer a live expression value, falling back to symbolic text when unavailable.
local function describeExpression(expression, context)
    if context then
        -- Preview contexts may lack locals; keep readable fallback text instead of failing.
        local ok, value = pcall(Expressions.evaluate, expression, context)
        if ok then return tostring(value) end
    end
    if expression.kind == "card" then return expression.id end
    if expression.kind == "literal" then return tostring(expression.value) end
    if expression.kind == "counter" then return Counters.label(expression) .. " counter" end
    if expression.kind == "local" then return expression.name end
    if expression.kind == "context" then return expression.path end
    local symbols = { add = "+", subtract = "−", multiply = "×", min = "min", max = "max" }
    return string.format("%s %s %s", describeExpression(expression.left), symbols[expression.operator] or expression.operator, describeExpression(expression.right))
end

-- Build fallback prose from supported effect blocks when no authored text exists.
local function describeGenerated(definition, query, cardId, multiplier, instanceId)
    local phrases = {}
    local context = query and { query = query, cardId = cardId, instanceId = instanceId, element = definition.element, category = definition.type, multiplier = multiplier, locals = {} } or nil
    for _, effect in ipairs(definition.effects) do
        if effect.op == "setLocal" and context then
            context.locals[effect.name] = Expressions.evaluate(effect.value, context)
        elseif effect.op == "damage" then
            local value = describeExpression(effect.amount, context)
            if effect.scalable and context then value = tostring(tonumber(value) * context.multiplier) end
            local target = effect.target == "allEnemies" and " to all enemies"
                or effect.target == "otherEnemies" and " to all other enemies" or " to the target"
            phrases[#phrases + 1] = "Deal " .. value .. " damage" .. target .. "."
        elseif effect.op == "debuff" then
            local value = context and amount(effect, context, "stacks") or describeExpression(effect.stacks)
            local target = effect.target == "allEnemies" and "all enemies"
                or effect.target == "otherEnemies" and "all other enemies" or "the target"
            phrases[#phrases + 1] = "Apply " .. value .. " " .. Debuffs.get(effect.id).label .. " to " .. target .. "."
            if effect.bonusDamage then
                local bonus = context and Expressions.debuffDamage(effect, context) or describeExpression(effect.bonusDamage)
                phrases[#phrases + 1] = "With " .. tostring(bonus) .. " bonus damage per turn."
            end
        elseif effect.op == "freeze" then phrases[#phrases + 1] = effect.target == "allEnemies" and "Freeze them." or "Freeze the target."
        elseif effect.op == "armor" then phrases[#phrases + 1] = "Gain " .. tostring(context and amount(effect, context) or describeExpression(effect.amount)) .. " Armor."
        elseif effect.op == "heal" then phrases[#phrases + 1] = "Heal " .. tostring(context and amount(effect, context) or describeExpression(effect.amount)) .. " HP."
        elseif effect.op == "draw" then phrases[#phrases + 1] = "Draw " .. tostring(context and amount(effect, context) or describeExpression(effect.amount)) .. " cards."
        elseif effect.op == "mana" then phrases[#phrases + 1] = "Gain " .. tostring(context and amount(effect, context) or describeExpression(effect.amount)) .. " mana this turn."
        elseif effect.op == "addStatus" and effect.id == "status.spell_power" then phrases[#phrases + 1] = "Spell power ×2. Stacks."
        elseif effect.op == "addStatus" and effect.id == "status.mirror" then phrases[#phrases + 1] = "Copy your next spell. Its copy costs 1 less."
        end
    end
    return table.concat(phrases, " ")
end

-- Parse whole-number display arithmetic without executing Lua source.
local function evaluateDisplayFormula(source)
    local compact = source:gsub("%s+", "")
    local length, position = #compact, 1

    -- Consume the next unsigned integer from the compact display formula.
    local function parseNumber()
        local start = position
        while position <= length and compact:sub(position, position):match("%d") do position = position + 1 end
        if start == position then return nil end
        return tonumber(compact:sub(start, position - 1))
    end

    -- Resolve multiplication before the outer addition/subtraction pass.
    local function parseTerm()
        local value = parseNumber()
        if value == nil then return nil end
        while compact:sub(position, position) == "*" do
            position = position + 1
            local right = parseNumber()
            if right == nil then return nil end
            value = value * right
        end
        return value
    end

    local value = parseTerm()
    if value == nil then return nil end
    while position <= length do
        local operator = compact:sub(position, position)
        if operator ~= "+" and operator ~= "-" then return nil end
        position = position + 1
        local right = parseTerm()
        if right == nil then return nil end
        value = operator == "+" and value + right or value - right
    end
    return clampAmount(value), compact:find("[+%-%*]") ~= nil
end

local tokenOps = {
    dmg = "damage", armor = "armor", heal = "heal", draw = "draw",
    mana = "mana", stacks = "addStatus",
}

-- Index value-bearing effects in traversal order for description placeholders.
local function collectValueEffects(effects, values)
    for _, effect in ipairs(effects) do
        if tokenOps.dmg == effect.op or tokenOps.armor == effect.op or tokenOps.heal == effect.op
            or tokenOps.draw == effect.op or tokenOps.mana == effect.op or tokenOps.stacks == effect.op
            or effect.op == "debuff" then
            -- Namespace debuff tokens so they cannot collide with ordinary effect names.
            local key = effect.op == "debuff" and ("debuff:" .. Debuffs.get(effect.id).token) or effect.op
            values[key] = values[key] or {}
            values[key][#values[key] + 1] = effect
            if effect.op == "debuff" and effect.bonusDamage then
                local damageKey = "debuffDamage:" .. Debuffs.get(effect.id).token
                values[damageKey] = values[damageKey] or {}
                values[damageKey][#values[damageKey] + 1] = effect
            end
        elseif effect.op == "if" then
            -- Index both branches for stable token numbering; this does not execute either branch.
            collectValueEffects(effect["then"] or {}, values)
            collectValueEffects(effect["else"] or {}, values)
        end
    end
end

-- Evaluate top-level local declarations for previews without executing actions.
local function primeDescriptionLocals(effects, context)
    for _, effect in ipairs(effects) do
        if effect.op == "setLocal" then
            local ok, value = pcall(Expressions.evaluate, effect.value, context)
            if ok then context.locals[effect.name] = value end
        end
    end
end

-- Replace authored value tokens with live amounts or their baseline formulas.
local function renderDescription(definition, query, cardId, multiplier, instanceId)
    local context = query and { query = query, cardId = cardId, instanceId = instanceId, element = definition.element, category = definition.type, multiplier = multiplier, locals = {} } or nil
    if context then primeDescriptionLocals(definition.effects, context) end

    -- The combat adapter can simulate ordered effects without touching real state.
    local resolvedValues, resolvedBonuses
    if query and query.previewValues then
        local ok, values, bonuses = pcall(query.previewValues, definition, cardId, instanceId, multiplier)
        if ok then resolvedValues, resolvedBonuses = values, bonuses end
    end
    local values, occurrences = {}, {}
    collectValueEffects(definition.effects, values)
    -- Resolve each token independently; authored baseline values remain the fallback.
    local rendered = definition.description:gsub("{([a-z][a-z0-9_]*)%s*=%s*([^{}]+)}", function(name, formula)
        local baseline, usesFormula = evaluateDisplayFormula(formula)
        if baseline == nil then return "?" end
        local baseName = name:gsub("%d+$", "")
        local damageToken = baseName:match("^(.-)_damage$")
        local isDamage = damageToken and Debuffs.byToken[damageToken]
        local op = isDamage and ("debuffDamage:" .. damageToken) or Debuffs.byToken[baseName] and ("debuff:" .. baseName) or tokenOps[baseName]
        occurrences[baseName] = (occurrences[baseName] or 0) + 1
        -- A suffix such as dmg2 selects an effect explicitly; otherwise use occurrence order.
        local explicitIndex = tonumber(name:match("(%d+)$"))
        local effect = op and values[op] and values[op][explicitIndex or occurrences[baseName]]
        local resolved = baseline
        if effect and resolvedValues then
            local selected = isDamage and (resolvedBonuses or {}) or resolvedValues
            resolved = selected[effect] or baseline
        elseif effect and context then
            local usesStacks = effect.op == "addStatus" or effect.op == "debuff"
            local ok, value
            if isDamage then ok, value = pcall(Expressions.debuffDamage, effect, context)
            else ok, value = pcall(amount, effect, context, usesStacks and "stacks" or "amount") end
            if ok then resolved = value end
        end
        -- The asterisk marks arithmetic baselines or amounts changed by live evaluation.
        local modified = usesFormula or resolved ~= baseline
        return tostring(resolved) .. (modified and "*" or "")
    end)
    return rendered
end

-- Use authored text when present, otherwise generate supported effect prose.
function Descriptions.describe(definition, query, cardId, multiplier, instanceId)
    if type(definition.description) == "string" and definition.description ~= "" then
        return renderDescription(definition, query, cardId, multiplier, instanceId)
    end
    return describeGenerated(definition, query, cardId, multiplier, instanceId)
end

return Descriptions
