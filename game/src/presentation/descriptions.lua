local Expressions = require("src.domain.effects.expressions")
local amount = Expressions.amount
local clampAmount = Expressions.clampAmount
local Descriptions = {}

local function describeExpression(expression, context)
    if context then
        local ok, value = pcall(Expressions.evaluate, expression, context)
        if ok then return tostring(value) end
    end
    if expression.kind == "literal" then return tostring(expression.value) end
    if expression.kind == "counter" then return "that card's count" end
    if expression.kind == "local" then return expression.name end
    if expression.kind == "context" then return expression.path end
    local symbols = { add = "+", subtract = "−", multiply = "×", min = "min", max = "max" }
    return string.format("%s %s %s", describeExpression(expression.left), symbols[expression.operator] or expression.operator, describeExpression(expression.right))
end

local function describeGenerated(definition, query, cardId, multiplier)
    local phrases = {}
    local context = query and { query = query, cardId = cardId, multiplier = multiplier, locals = {} } or nil
    for _, effect in ipairs(definition.effects) do
        if effect.op == "setLocal" and context then
            context.locals[effect.name] = Expressions.evaluate(effect.value, context)
        elseif effect.op == "damage" then
            local value = describeExpression(effect.amount, context)
            if effect.scalable and context then value = tostring(tonumber(value) * context.multiplier) end
            phrases[#phrases + 1] = effect.target == "allEnemies" and ("Deal " .. value .. " damage to all enemies.") or ("Deal " .. value .. " damage.")
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

local function evaluateDisplayFormula(source)
    local compact = source:gsub("%s+", "")
    local length, position = #compact, 1

    local function parseNumber()
        local start = position
        while position <= length and compact:sub(position, position):match("%d") do position = position + 1 end
        if start == position then return nil end
        return tonumber(compact:sub(start, position - 1))
    end

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

local function collectValueEffects(effects, values)
    for _, effect in ipairs(effects) do
        if tokenOps.dmg == effect.op or tokenOps.armor == effect.op or tokenOps.heal == effect.op
            or tokenOps.draw == effect.op or tokenOps.mana == effect.op or tokenOps.stacks == effect.op then
            values[effect.op] = values[effect.op] or {}
            values[effect.op][#values[effect.op] + 1] = effect
        elseif effect.op == "if" then
            collectValueEffects(effect["then"] or {}, values)
            collectValueEffects(effect["else"] or {}, values)
        end
    end
end

local function primeDescriptionLocals(effects, context)
    for _, effect in ipairs(effects) do
        if effect.op == "setLocal" then
            local ok, value = pcall(Expressions.evaluate, effect.value, context)
            if ok then context.locals[effect.name] = value end
        end
    end
end

local function renderDescription(definition, query, cardId, multiplier)
    local context = query and { query = query, cardId = cardId, multiplier = multiplier, locals = {} } or nil
    if context then primeDescriptionLocals(definition.effects, context) end

    local values, occurrences = {}, {}
    collectValueEffects(definition.effects, values)
    local rendered = definition.description:gsub("{([a-z][a-z0-9_]*)%s*=%s*([^{}]+)}", function(name, formula)
        local baseline, usesFormula = evaluateDisplayFormula(formula)
        if baseline == nil then return "?" end
        local baseName = name:gsub("%d+$", "")
        local op = tokenOps[baseName]
        occurrences[baseName] = (occurrences[baseName] or 0) + 1
        local explicitIndex = tonumber(name:match("(%d+)$"))
        local effect = op and values[op] and values[op][explicitIndex or occurrences[baseName]]
        local resolved = baseline
        if effect and context then
            local ok, value = pcall(amount, effect, context, effect.op == "addStatus" and "stacks" or "amount")
            if ok then resolved = value end
        end
        local modified = usesFormula or resolved ~= baseline
        return tostring(resolved) .. (modified and "*" or "")
    end)
    return rendered
end

function Descriptions.describe(definition, query, cardId, multiplier)
    if type(definition.description) == "string" and definition.description ~= "" then
        return renderDescription(definition, query, cardId, multiplier)
    end
    return describeGenerated(definition, query, cardId, multiplier)
end

return Descriptions
