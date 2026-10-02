local Counters = require("src.domain.effects.counters")
local Expressions = {}

-- Coerce a value to a non-negative whole-number effect amount.
function Expressions.clampAmount(value)
    value = tonumber(value) or 0
    return math.max(0, math.floor(value))
end

-- Recursively evaluate an expression using card-local values and live queries.
function Expressions.evaluate(expression, context)
    local kind = expression.kind
    if kind == "literal" then return expression.value end
    if kind == "card" then return expression.id end
    if kind == "local" then
        -- False is a valid calculated condition; only nil means unassigned.
        local value = context.locals[expression.name]
        assert(value ~= nil, "unknown local: " .. tostring(expression.name))
        return value
    end
    if kind == "counter" then
        -- Resolve the shorthand against the card being evaluated, including temporary copies.
        return context.query.counter(Counters.key(expression, context), Counters.scope(expression))
    end
    if kind == "context" then
        if expression.path == "thisCardId" then return context.cardId end
        return context.query.value(expression.path)
    end
    -- Nested operands use the same local scope and live query interface.
    local left = Expressions.evaluate(expression.left, context)
    local right = Expressions.evaluate(expression.right, context)
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

-- Evaluate an amount or stacks field, then apply scaling when requested.
function Expressions.amount(effect, context, field)
    local value = Expressions.clampAmount(Expressions.evaluate(effect[field or "amount"], context))
    -- Apply spell power after clamping the base amount, matching execution and descriptions.
    if effect.scalable then value = value * context.multiplier end
    return value
end

-- Capture optional recurring damage with its own spell-power setting.
function Expressions.debuffDamage(effect, context)
    if not effect.bonusDamage then return 0 end
    -- Reuse amount clamping without inheriting the duration's scaling flag.
    return Expressions.amount({ amount = effect.bonusDamage, scalable = effect.damageScalable }, context)
end

return Expressions
