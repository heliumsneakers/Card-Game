local Counters = {}

-- Convert legacy shorthand without treating arbitrary dotted names as card groups.
function Counters.normalize(reference)
    if reference.owner then return reference end
    local id = reference.id
    local owner, name = { kind = "shared" }, id
    if id == "$thisCard" then owner, name = { kind = "this" }, "default"
    elseif id == "$thisInstance" then owner, name = { kind = "instance" }, "default"
    elseif id:match("^card%.") then owner, name = { kind = "card", cardId = id }, "default" end
    return { owner = owner, name = name, scope = reference.scope }
end

-- Resolve explicit ownership to one shared slot, independently of its lifetime.
function Counters.key(reference, context)
    local normalized = Counters.normalize(reference)
    local owner, name = normalized.owner, normalized.name
    local base
    if owner.kind == "shared" then return name
    elseif owner.kind == "this" then base = context.cardId
    elseif owner.kind == "card" then base = owner.cardId
    elseif owner.kind == "instance" then
        base = "@instance:" .. tostring(assert(context.instanceId, "instance counter requires a card instance"))
    elseif owner.kind == "element" then
        local element = owner.element
        if element == "this" then element = context.element end
        base = "@element:" .. assert(element, "current card element is required")
    elseif owner.kind == "category" then
        local category = owner.category
        if category == "this" then category = context.category end
        base = "@category:" .. assert(category, "current card category is required")
    else error("unknown counter owner") end
    -- Default slots preserve old keys. Byte lengths isolate names containing delimiters.
    if name == "default" then return base end
    return "@named:" .. #base .. ":" .. base .. ":" .. name
end

-- Describe group ownership when no live query is available for rules text.
function Counters.label(reference)
    local normalized = Counters.normalize(reference)
    local owner, name = normalized.owner, normalized.name
    local label
    if owner.kind == "shared" then return name
    elseif owner.kind == "this" then label = "This card"
    elseif owner.kind == "instance" then label = "This copy"
    elseif owner.kind == "card" then label = owner.cardId
    elseif owner.kind == "element" then label = owner.element == "this" and "This card's element" or owner.element
    elseif owner.kind == "category" then label = owner.category == "this" and "This card's category" or owner.category end
    return label .. " / " .. name
end

-- Choose a counter lifetime, retaining schema-v1 turn behavior by default.
function Counters.scope(reference)
    return reference.scope or "turn"
end

return Counters
