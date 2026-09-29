-- Per-game card catalog. Loading and validation belong to the caller.
local Cards = {}
Cards.__index = Cards

function Cards.new(catalog)
    local self = setmetatable({ catalog = assert(catalog, "catalog is required"),
        definitions = catalog.cards, startingDeck = {}, shopPool = {} }, Cards)
    for _, definition in ipairs(catalog.document.cards) do
        local availability = definition.availability or {}
        for _ = 1, availability.startingDeck or 0 do
            self.startingDeck[#self.startingDeck + 1] = definition.id
        end
        if availability.shop then self.shopPool[#self.shopPool + 1] = definition.id end
    end
    return self
end

function Cards:make(name, cost, isCopy)
    local catalog = self.catalog
    local id = type(name) == "table" and name.id or (catalog.cards[name] and name or catalog.cardNames[name])
    local definition = assert(catalog.cards[id], "unknown card: " .. tostring(name))
    return {
        id = id,
        name = definition.name,
        cost = cost == nil and definition.cost or cost,
        isCopy = isCopy or false,
    }
end

function Cards:definition(cardOrName)
    local reference = type(cardOrName) == "table" and cardOrName.id or cardOrName
    local catalog = self.catalog
    local id = catalog.cards[reference] and reference or catalog.cardNames[reference]
    return catalog.cards[id]
end

return Cards
