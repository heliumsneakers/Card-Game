local CardPresentation = require("src.presentation.cards")
local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local DeckView = {}
local VW, VH = 1920, 1080

-- Render permanent-deck counts and inspectable rows over a modal backdrop.
function DeckView.draw(game)
    UI.color(palette.ink, 0.90)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
    UI.rect(400, 92, 1120, 884, { 0.12, 0.15, 0.19 }, palette.gold)
    UI.label("MASTER DECK  •  " .. #game.run.masterDeck .. " CARDS", 440, 130, 1040, "center", palette.gold, "title")
    UI.label("Hold a row to inspect the card", 440, 196, 1040, "center", palette.muted, "tiny")
    for i, row in ipairs(game:masterCounts()) do
        local y = 246 + (i - 1) * 56
        if y < 860 then
            UI.color(CardPresentation.color(game.cards, row.name), 0.55)
            love.graphics.rectangle("fill", 470, y, 980, 46, 8, 8)
            UI.label(row.name, 494, y + 8, 720, "left", palette.white, "small")
            UI.label("x" .. row.count, 1250, y + 8, 170, "right", palette.gold, "small")
            UI.addZone("deckcard", 470, y, 980, 46, game.cards:make(row.name))
        end
    end
    UI.button("closedeck", "CLOSE", 820, 886, 280, 62, true, palette.red)
end

return DeckView
