local Expressions = require("src.domain.effects.expressions")
local Handlers = require("src.domain.effects.handlers")
local Resolver = {}

-- Walk effects in order and recursively execute only the selected conditional branch.
local function executeList(effects, context)
    for _, effect in ipairs(effects) do
        -- Resolve branches synchronously; subsequent effects see mutations from the chosen branch.
        if effect.op == "if" then
            local branch = Expressions.evaluate(effect.condition, context) and effect["then"] or effect["else"]
            executeList(branch or {}, context)
        else
            -- Read-only observers capture computed values before the action mutates state.
            if context.observe then context.observe(effect, context) end
            assert(Handlers[effect.op], "unknown effect: " .. tostring(effect.op))(effect, context)
        end
    end
end

-- Queries stay live as effects execute; spell power is captured once per card.
function Resolver.resolve(definition, cardId, query, actions, multiplier, instanceId, observe)
    executeList(definition.effects, {
        cardId = cardId, instanceId = instanceId, query = query, actions = actions,
        multiplier = multiplier, locals = {}, observe = observe,
    })
end

return Resolver
