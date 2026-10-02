local Debuffs = require("src.domain.debuffs.registry")
-- Handlers receive only expression queries and explicit combat operations.
local Expressions = require("src.domain.effects.expressions")
local Counters = require("src.domain.effects.counters")
local amount = Expressions.amount
local Handlers = {}

-- Evaluate damage and send the target selector to the combat adapter.
function Handlers.damage(effect, context)
    context.actions.damage(effect.target, amount(effect, context))
end

-- Ask combat to freeze the living targets selected by the effect.
function Handlers.freeze(effect, context)
    context.actions.debuff(effect.target, Debuffs.legacyOperations.freeze, 1)
end

-- Evaluate stack count and apply a named debuff to the selected living targets.
function Handlers.debuff(effect, context)
    context.actions.debuff(effect.target, effect.id, amount(effect, context, "stacks"), Expressions.debuffDamage(effect, context))
end

-- Evaluate armor gain and delegate its mutation to combat.
function Handlers.armor(effect, context)
    context.actions.armor(amount(effect, context))
end

-- Evaluate healing; the combat operation enforces maximum HP.
function Handlers.heal(effect, context)
    context.actions.heal(amount(effect, context))
end

-- Evaluate draw count; pile rules enforce availability and hand size.
function Handlers.draw(effect, context)
    context.actions.draw(amount(effect, context))
end

-- Evaluate mana gain and pass the optional cap to combat.
function Handlers.mana(effect, context)
    context.actions.mana(amount(effect, context), effect.cap)
end

-- Evaluate stacks and add them through the status operation.
function Handlers.addStatus(effect, context)
    context.actions.addStatus(effect.id, amount(effect, context, "stacks"))
end

-- Accept legacy numbers and evaluate new formulas before mutating counters.
local function counterAmount(effect, context)
    local value = effect.amount
    if value == nil and effect.op == "incrementCounter" then value = 1 end
    if type(value) == "table" then value = Expressions.evaluate(value, context) end
    return Expressions.clampAmount(value)
end

-- Add an unscaled amount to the chosen counter and lifetime.
function Handlers.incrementCounter(effect, context)
    context.actions.incrementCounter(Counters.key(effect, context), counterAmount(effect, context), Counters.scope(effect))
end

-- Subtract an unscaled amount; the combat adapter prevents negative state.
function Handlers.subtractCounter(effect, context)
    context.actions.incrementCounter(Counters.key(effect, context), -counterAmount(effect, context), Counters.scope(effect))
end

-- Replace a counter with the evaluated amount.
function Handlers.setCounter(effect, context)
    context.actions.setCounter(Counters.key(effect, context), counterAmount(effect, context), Counters.scope(effect))
end

-- Clear only the selected counter, leaving other owners and lifetimes intact.
function Handlers.resetCounter(effect, context)
    context.actions.setCounter(Counters.key(effect, context), 0, Counters.scope(effect))
end

-- Store a computed value for later effects within this resolution only.
function Handlers.setLocal(effect, context)
    context.locals[effect.name] = Expressions.evaluate(effect.value, context)
end

return Handlers
