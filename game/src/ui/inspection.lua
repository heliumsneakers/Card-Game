local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local CardView = require("src.ui.card_view")
local Inspection = {}
local VW, VH = 1920, 1080

function Inspection.draw(game, inspectCard)
    if not inspectCard then return end
    UI.color(palette.ink, 0.88)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
    local card = type(inspectCard) == "string" and game.cards:make(inspectCard) or inspectCard
    CardView.draw(card, game, 710, 110, 500, 760, false, false)
    local definition = game.cards:definition(card)
    UI.label((definition.element and (definition.element:upper() .. "  •  ") or "") .. definition.type:upper() .. "  •  TARGET: " .. definition.target:upper(),
        710, 890, 500, "center", palette.gold, "small")
    UI.label("Release to close", 0, 970, VW, "center", palette.muted, "body")
end

return Inspection
