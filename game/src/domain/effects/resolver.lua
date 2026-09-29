local Expressions = require("src.domain.effects.expressions")
local Handlers = require("src.domain.effects.handlers")
local Resolver = {}

local function executeList(effects, context)
    for _, effect in ipairs(effects) do
        if effect.op == "if" then
            local branch = Expressions.evaluate(effect.condition, context) and effect["then"] or effect["else"]
            executeList(branch or {}, context)
        else
            assert(Handlers[effect.op], "unknown effect: " .. tostring(effect.op))(effect, context)
        end
    end
end

-- Queries stay live as effects execute; spell power is captured once per card.
function Resolver.resolve(definition, cardId, query, actions, multiplier)
    executeList(definition.effects, {
        cardId = cardId, query = query, actions = actions,
        multiplier = multiplier, locals = {},
    })
end

return Resolver
