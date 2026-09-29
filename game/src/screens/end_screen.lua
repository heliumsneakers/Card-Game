local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local EndScreen = {}
local VW = 1920

function EndScreen.draw(game, app)
    local victory = app.state == "victory"
    UI.label(victory and "DUNGEON CLEARED!" or "YOU DIED", 0, 330, VW, "center",
        victory and palette.gold or palette.red, "display")
    local defeat = game.run.endless and ("FELL IN ENDLESS ROOM " .. game.run.endlessRoom)
        or ("FELL IN ROOM " .. game.run.room .. " / 5")
    UI.label(victory and "The Bone Lord has fallen." or defeat,
        0, 440, VW, "center", palette.white, "heading")
    UI.button("restart", victory and "PLAY AGAIN" or "RESTART", 790, 540, 340, 82, true, palette.green, "heading")
end

function EndScreen.activate(game, zone)
    if zone and zone.id == "restart" then game:restart() end
end

return EndScreen
