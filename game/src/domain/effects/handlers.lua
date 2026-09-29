-- Handlers receive only expression queries and explicit combat operations.
local Expressions = require("src.domain.effects.expressions")
local amount = Expressions.amount
local Handlers = {}

function Handlers.damage(effect, context)
    context.actions.damage(effect.target, amount(effect, context))
end

function Handlers.freeze(effect, context)
    context.actions.freeze(effect.target)
end

function Handlers.armor(effect, context)
    context.actions.armor(amount(effect, context))
end

function Handlers.heal(effect, context)
    context.actions.heal(amount(effect, context))
end

function Handlers.draw(effect, context)
    context.actions.draw(amount(effect, context))
end

function Handlers.mana(effect, context)
    context.actions.mana(amount(effect, context), effect.cap)
end

function Handlers.addStatus(effect, context)
    context.actions.addStatus(effect.id, amount(effect, context, "stacks"))
end

function Handlers.incrementCounter(effect, context)
    local id = effect.id == "$thisCard" and context.cardId or effect.id
    context.actions.incrementCounter(id, effect.amount or 1)
end

function Handlers.setLocal(effect, context)
    context.locals[effect.name] = Expressions.evaluate(effect.value, context)
end

return Handlers
