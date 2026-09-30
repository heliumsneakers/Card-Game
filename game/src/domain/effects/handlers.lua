-- Handlers receive only expression queries and explicit combat operations.
local Expressions = require("src.domain.effects.expressions")
local amount = Expressions.amount
local Handlers = {}

-- Evaluate damage and send the target selector to the combat adapter.
function Handlers.damage(effect, context)
    context.actions.damage(effect.target, amount(effect, context))
end

-- Ask combat to freeze the living targets selected by the effect.
function Handlers.freeze(effect, context)
    context.actions.freeze(effect.target)
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

-- Resolve the current-card shorthand before incrementing a counter.
function Handlers.incrementCounter(effect, context)
    local id = effect.id == "$thisCard" and context.cardId or effect.id
    context.actions.incrementCounter(id, effect.amount or 1)
end

-- Store a computed value for later effects within this resolution only.
function Handlers.setLocal(effect, context)
    context.locals[effect.name] = Expressions.evaluate(effect.value, context)
end

return Handlers
