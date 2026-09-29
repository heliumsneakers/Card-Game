local Descriptions = require("src.presentation.descriptions")
local Combat = require("src.domain.combat")
local CardPresentation = {}

CardPresentation.elementColors = {
    fire = { 0.72, 0.22, 0.18 },
    ice = { 0.18, 0.42, 0.62 },
    nature = { 0.18, 0.55, 0.30 },
    earth = { 0.48, 0.52, 0.58 },
    arcane = { 0.48, 0.28, 0.65 },
}

local defaultElements = { DMG = "fire", DEF = "earth", HEAL = "nature", UTIL = "arcane" }

function CardPresentation.color(cards, cardOrReference)
    local definition = cards:definition(cardOrReference)
    return CardPresentation.elementColors[definition.element or defaultElements[definition.type]]
end

function CardPresentation.describe(cards, cardOrReference, game)
    local card = type(cardOrReference) == "table" and cardOrReference or cards:make(cardOrReference)
    return Descriptions.describe(cards:definition(card), game and Combat.queries(game.combat, game.run),
        card.id, game and Combat.surgeMultiplier(game.combat))
end

return CardPresentation
