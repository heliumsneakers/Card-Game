local Counters = {}

-- Resolve authoring shorthand into a definition or individual-copy key.
function Counters.key(reference, context)
    if reference.id == "$thisCard" then return context.cardId end
    -- Reserve the instance namespace so named counters cannot collide with copies.
    if reference.id == "$thisInstance" then return "@instance:" .. tostring(assert(context.instanceId, "instance counter requires a card instance")) end
    return reference.id
end

-- Choose a counter lifetime, retaining schema-v1 turn behavior by default.
function Counters.scope(reference)
    return reference.scope or "turn"
end

return Counters
