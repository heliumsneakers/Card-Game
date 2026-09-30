local CardPresentation = require("src.presentation.cards")
local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local CardView = {}

-- Render a card's cost, identity, description, and optional interaction zone.
function CardView.draw(card, game, x, y, w, h, selected, disabled, zoneId, payload)
    -- Use immutable definition text and visuals alongside the instance-specific cost.
    local definition = game.cards:definition(card)
    local compact = w < 300
    local edge = selected and palette.gold or palette.paper
    UI.rect(x, y, w, h, CardPresentation.color(game.cards, definition), edge, 16)
    if selected then
        UI.color(palette.gold)
        love.graphics.setLineWidth(5)
        love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, 18, 18)
        love.graphics.setLineWidth(2)
    end
    if disabled then
        UI.color(palette.ink, 0.56)
        love.graphics.rectangle("fill", x, y, w, h, 16, 16)
    end

    local manaRadius = compact and 24 or 32
    UI.color(palette.ink)
    love.graphics.circle("fill", x + manaRadius + 10, y + manaRadius + 10, manaRadius)
    UI.label(card.cost, x, y + (compact and 19 or 22), (manaRadius + 10) * 2, "center", palette.white,
        compact and "label" or "heading")
    local elementLabel = definition.element and (definition.element:upper() .. " • ") or ""
    UI.label(elementLabel .. definition.type:upper(), x + 72, y + 19, w - 88, "right", palette.paper, compact and "tiny" or "small")
    UI.label(card.name:upper(), x + 16, y + (compact and 74 or 88), w - 32, "center", palette.white,
        compact and "small" or "heading")

    local dividerY = y + (compact and 124 or 150)
    UI.color(palette.paper, 0.42)
    love.graphics.line(x + 18, dividerY, x + w - 18, dividerY)
    UI.label(CardPresentation.describe(game.cards, card, game), x + 18, dividerY + 18, w - 36, "center", palette.paper,
        compact and "tiny" or "body")
    if card.isCopy then
        UI.label("COPY", x + 18, y + h - 34, w - 36, "right", palette.gold, "tiny")
    end
    if zoneId then UI.addZone(zoneId, x, y, w, h, payload or card) end
end

return CardView
