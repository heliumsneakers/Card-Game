local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local CardView = require("src.ui.card_view")
local Reward = {}
local VW = 1920

local function shopPickCount(game, name)
    local count = 0
    for _, picked in ipairs(game.rewards.picks) do if picked == name then count = count + 1 end end
    return count
end

function Reward.draw(game)
    UI.label("CARD SHOP", 0, 28, VW, "center", palette.gold, "title")
    UI.label("Choose exactly 3 cards  •  " .. #game.rewards.picks .. " / 3 selected",
        0, 96, VW, "center", palette.white, "body")
    local shopW, shopH = 280, 320
    local gapX, gapY = 48, 34
    local startX, startY = 492, 150
    for i, name in ipairs(game.rewards.choices) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local x, y = startX + col * (shopW + gapX), startY + row * (shopH + gapY)
        CardView.draw(game.cards:make(name), game, x, y, shopW, shopH, false, false, "shop", name)
        local picked = shopPickCount(game, name)
        if picked > 0 then
            UI.rect(x + shopW - 70, y - 12, 82, 48, palette.gold, palette.ink)
            UI.label("x" .. picked, x + shopW - 70, y - 4, 82, "center", palette.ink, "label")
        end
    end
    UI.button("reset", "RESET PICKS", 492, 900, 280, 72, #game.rewards.picks > 0, palette.red)
    UI.button("deck", "VIEW DECK", 820, 900, 280, 72, true, palette.blue)
    UI.button("descend", "DESCEND", 1148, 900, 280, 72, #game.rewards.picks == 3, palette.green)
end

function Reward.activate(game, zone, app)
    if not zone then return end
    if zone.id == "shop" then game:pickReward(zone.payload)
    elseif zone.id == "reset" then game:resetPicks()
    elseif zone.id == "descend" then game:descend()
    elseif zone.id == "deck" then app:showDeck() end
end

return Reward
