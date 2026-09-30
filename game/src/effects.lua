local Effects = {}

local function clampAmount(value)
    value = tonumber(value) or 0
    return math.max(0, math.floor(value))
end

function Effects.evaluate(expression, context)
    local kind = expression.kind
    if kind == "literal" then return expression.value end
    if kind == "local" then return assert(context.locals[expression.name], "unknown local: " .. tostring(expression.name)) end
    if kind == "counter" then
        local id = expression.id == "$thisCard" and context.card.id or expression.id
        return context.game.turnCounters[id] or 0
    end
    if kind == "context" then
        local values = {
            previousCardId = context.game.previousCardId,
            thisCardId = context.card.id,
            mana = context.game.mana,
            hp = context.game.hp,
            turn = context.game.turn,
            livingEnemies = context.game:livingEnemies(),
        }
        return values[expression.path]
    end
    local left = Effects.evaluate(expression.left, context)
    local right = Effects.evaluate(expression.right, context)
    if kind == "binary" then
        if expression.operator == "add" then return left + right end
        if expression.operator == "subtract" then return left - right end
        if expression.operator == "multiply" then return left * right end
        if expression.operator == "min" then return math.min(left, right) end
        if expression.operator == "max" then return math.max(left, right) end
    elseif kind == "compare" then
        if expression.operator == "eq" then return left == right end
        if expression.operator == "ne" then return left ~= right end
        if expression.operator == "lt" then return left < right end
        if expression.operator == "lte" then return left <= right end
        if expression.operator == "gt" then return left > right end
        if expression.operator == "gte" then return left >= right end
    end
    error("unsupported expression: " .. tostring(kind) .. "/" .. tostring(expression.operator))
end

local function amount(effect, context, field)
    local value = clampAmount(Effects.evaluate(effect[field or "amount"], context))
    if effect.scalable then value = value * context.multiplier end
    return value
end

local function eachTarget(effect, context, callback)
    if effect.target == "allEnemies" then
        for _, enemy in ipairs(context.game.enemies) do
            if enemy.alive then callback(enemy) end
        end
    elseif effect.target == "selectedEnemy" then
        local enemy = context.game.enemies[context.targetIndex or 0]
        if enemy and enemy.alive then callback(enemy) end
    elseif effect.target == "otherEnemies" then
        for index, enemy in ipairs(context.game.enemies) do
            if index ~= context.targetIndex and enemy.alive then callback(enemy) end
        end
    end
end

local handlers = {}

handlers.damage = function(effect, context)
    local value = amount(effect, context)
    eachTarget(effect, context, function(enemy) context.game:damageEnemy(enemy, value) end)
end

local function addDebuff(enemy, id, stacks)
    enemy.debuffs = enemy.debuffs or {}
    enemy.debuffs[id] = (enemy.debuffs[id] or 0) + stacks
    if id == "debuff.freeze" then enemy.frozen = enemy.debuffs[id] > 0 end
end

handlers.debuff = function(effect, context)
    local stacks = amount(effect, context, "stacks")
    eachTarget(effect, context, function(enemy) addDebuff(enemy, effect.id, stacks) end)
end

handlers.freeze = function(effect, context)
    eachTarget(effect, context, function(enemy) addDebuff(enemy, "debuff.freeze", 1) end)
end

handlers.armor = function(effect, context)
    context.game.armor = context.game.armor + amount(effect, context)
end

handlers.heal = function(effect, context)
    context.game.hp = math.min(context.game.maxHp, context.game.hp + amount(effect, context))
end

handlers.draw = function(effect, context)
    for _ = 1, amount(effect, context) do context.game:draw() end
end

handlers.mana = function(effect, context)
    local cap = effect.cap or context.game.maxMana
    context.game.mana = math.min(cap, context.game.mana + amount(effect, context))
end

handlers.addStatus = function(effect, context)
    local stacks = amount(effect, context, "stacks")
    context.game.statuses[effect.id] = (context.game.statuses[effect.id] or 0) + stacks
    if effect.id == "status.spell_power" then context.game.surge = context.game.statuses[effect.id] end
    if effect.id == "status.mirror" then context.game.mirror = context.game.statuses[effect.id] end
end

handlers.incrementCounter = function(effect, context)
    local id = effect.id == "$thisCard" and context.card.id or effect.id
    context.game.turnCounters[id] = (context.game.turnCounters[id] or 0) + (effect.amount or 1)
    if id == "card.firebolt" then context.game.fb = context.game.turnCounters[id] end
end

handlers.setLocal = function(effect, context)
    context.locals[effect.name] = Effects.evaluate(effect.value, context)
end

local function executeList(effects, context)
    for _, effect in ipairs(effects) do
        if effect.op == "if" then
            local branch = Effects.evaluate(effect.condition, context) and effect["then"] or effect["else"]
            executeList(branch or {}, context)
        else
            assert(handlers[effect.op], "unknown effect: " .. tostring(effect.op))(effect, context)
        end
    end
end

function Effects.resolve(game, card, definition, targetIndex)
    local context = {
        game = game, card = card, definition = definition, targetIndex = targetIndex,
        multiplier = game:surgeMultiplier(), locals = {},
    }
    executeList(definition.effects, context)
end

local function describeExpression(expression, context)
    if context then
        local ok, value = pcall(Effects.evaluate, expression, context)
        if ok then return tostring(value) end
    end
    if expression.kind == "literal" then return tostring(expression.value) end
    if expression.kind == "counter" then return "that card's count" end
    if expression.kind == "local" then return expression.name end
    if expression.kind == "context" then return expression.path end
    local symbols = { add = "+", subtract = "−", multiply = "×", min = "min", max = "max" }
    return string.format("%s %s %s", describeExpression(expression.left), symbols[expression.operator] or expression.operator, describeExpression(expression.right))
end

local function describeGenerated(definition, game, card)
    local phrases = {}
    local context = game and { game = game, card = card, definition = definition, multiplier = game:surgeMultiplier(), locals = {} } or nil
    for _, effect in ipairs(definition.effects) do
        if effect.op == "setLocal" and context then
            context.locals[effect.name] = Effects.evaluate(effect.value, context)
        elseif effect.op == "damage" then
            local value = describeExpression(effect.amount, context)
            if effect.scalable and context then value = tostring(tonumber(value) * context.multiplier) end
            local target = effect.target == "allEnemies" and " to all enemies" or effect.target == "otherEnemies" and " to all other enemies" or " to the target"
            phrases[#phrases + 1] = "Deal " .. value .. " damage" .. target .. "."
        elseif effect.op == "debuff" then
            local value = context and amount(effect, context, "stacks") or describeExpression(effect.stacks)
            local target = effect.target == "allEnemies" and "all enemies" or effect.target == "otherEnemies" and "all other enemies" or "the target"
            phrases[#phrases + 1] = "Apply " .. value .. " Freeze to " .. target .. "."
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
    mana = "mana", stacks = "addStatus", freeze = "debuff",
}

local function collectValueEffects(effects, values)
    for _, effect in ipairs(effects) do
        if tokenOps.dmg == effect.op or tokenOps.armor == effect.op or tokenOps.heal == effect.op
            or tokenOps.draw == effect.op or tokenOps.mana == effect.op or tokenOps.stacks == effect.op
            or tokenOps.freeze == effect.op then
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
            local ok, value = pcall(Effects.evaluate, effect.value, context)
            if ok then context.locals[effect.name] = value end
        end
    end
end

local function renderDescription(definition, game, card)
    local context = game and {
        game = game, card = card, definition = definition,
        multiplier = game:surgeMultiplier(), locals = {},
    } or nil
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
            local usesStacks = effect.op == "addStatus" or effect.op == "debuff"
            local ok, value = pcall(amount, effect, context, usesStacks and "stacks" or "amount")
            if ok then resolved = value end
        end
        local modified = usesFormula or resolved ~= baseline
        return tostring(resolved) .. (modified and "*" or "")
    end)
    return rendered
end

function Effects.describe(definition, game, card)
    if type(definition.description) == "string" and definition.description ~= "" then
        return renderDescription(definition, game, card)
    end
    return describeGenerated(definition, game, card)
end

return Effects
