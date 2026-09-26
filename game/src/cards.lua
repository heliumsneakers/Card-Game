local Content = require("src.content")
local Effects = require("src.effects")

local Cards = {}

local catalog, errors = Content.load("content/content.json")
if not catalog then
    local messages = {}
    for _, item in ipairs(errors) do messages[#messages + 1] = item.path .. ": " .. item.message end
    error("content validation failed: " .. table.concat(messages, "; "))
end

Cards.catalog = catalog
Cards.definitions = catalog.cards

Cards.elementColors = {
    fire = { 0.72, 0.22, 0.18 },
    ice = { 0.18, 0.42, 0.62 },
    nature = { 0.18, 0.55, 0.30 },
    earth = { 0.48, 0.52, 0.58 },
    arcane = { 0.48, 0.28, 0.65 },
}

local defaultElements = { DMG = "fire", DEF = "earth", HEAL = "nature", UTIL = "arcane" }

function Cards.color(cardOrReference)
    local definition = Cards.definition(cardOrReference)
    return Cards.elementColors[definition.element or defaultElements[definition.type]]
end

function Cards.make(name, cost, isCopy)
    local id = type(name) == "table" and name.id or (catalog.cards[name] and name or catalog.cardNames[name])
    local definition = assert(catalog.cards[id], "unknown card: " .. tostring(name))
    return {
        id = id,
        name = definition.name,
        cost = cost == nil and definition.cost or cost,
        isCopy = isCopy or false,
    }
end

function Cards.definition(cardOrName)
    local reference = type(cardOrName) == "table" and cardOrName.id or cardOrName
    local id = catalog.cards[reference] and reference or catalog.cardNames[reference]
    return catalog.cards[id]
end

Cards.startingDeck = {}
Cards.shopPool = {}
for _, definition in ipairs(catalog.document.cards) do
    local availability = definition.availability or {}
    for _ = 1, availability.startingDeck or 0 do Cards.startingDeck[#Cards.startingDeck + 1] = definition.id end
    if availability.shop then Cards.shopPool[#Cards.shopPool + 1] = definition.id end
end

function Cards.describe(cardOrReference, game)
    local card = type(cardOrReference) == "table" and cardOrReference or Cards.make(cardOrReference)
    return Effects.describe(Cards.definition(card), game, card)
end

function Cards.setCatalog(nextCatalog)
    catalog = nextCatalog
    Cards.catalog = nextCatalog
    Cards.definitions = nextCatalog.cards
end

return Cards
