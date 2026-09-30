local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local Hud = {}

-- Display run health, combat resources, active buffs, and encounter metadata.
function Hud.draw(game)
    UI.rect(24, 24, 520, 122, { 0.12, 0.15, 0.19 }, palette.paper)
    UI.label("HEALTH", 48, 43, 190, "left", palette.muted, "tiny")
    UI.label(game.run.hp .. " / " .. game.run.maxHp, 48, 73, 190, "left",
        game.run.hp <= 10 and palette.red or palette.white, "heading")
    UI.label("ARMOR", 280, 43, 180, "left", palette.muted, "tiny")
    UI.label(game.run.armor, 280, 73, 180, "left", palette.white, "heading")
    UI.label(game.run.endless and ("ENDLESS " .. game.run.endlessRoom) or ("ROOM " .. game.run.room .. " / 5"),
        374, 48, 146, "right", palette.gold, "small")
    UI.label("TURN " .. game.combat.turn, 400, 88, 120, "right", palette.muted, "tiny")

    UI.rect(1424, 24, 472, 122, { 0.12, 0.15, 0.19 }, palette.paper)
    UI.label("MANA", 1452, 43, 130, "left", palette.muted, "tiny")
    UI.label(game.combat.mana .. " / " .. game.combat.maxMana, 1452, 73, 160, "left", palette.gold, "heading")
    UI.label("DRAW", 1640, 43, 92, "center", palette.muted, "tiny")
    UI.label(#game.deck.draw, 1640, 76, 92, "center", palette.white, "label")
    UI.label("DISCARD", 1768, 43, 104, "center", palette.muted, "tiny")
    UI.label(#game.deck.discard, 1768, 76, 104, "center", palette.white, "label")

    local surge = game.combat.statuses["status.spell_power"] or 0
    local mirror = game.combat.statuses["status.mirror"] or 0
    if surge > 0 or mirror > 0 then
        local buffs = {}
        if surge > 0 then buffs[#buffs + 1] = "SURGE x" .. surge end
        if mirror > 0 then buffs[#buffs + 1] = "MIRROR x" .. mirror end
        UI.label(table.concat(buffs, "     "), 590, 42, 740, "center", palette.gold, "small")
    end
    if game.combat.encounterTargetPower then
        local scaleText = game.run.endless and string.format("  •  SCALE %.2fx", game.combat.encounterScale or 1) or ""
        UI.label(string.format("BUDGET %.1f  •  BASE %.1f%s  •  SEED %d",
            game.combat.encounterTargetPower, game.combat.encounterPower or 0, scaleText, game.combat.encounterSeed or 0),
            590, 132, 740, "center", palette.muted, "tiny")
    end
    local preview = game.cards.catalog.document.preview
    if preview and preview.featuredCardId and game.cards:definition(preview.featuredCardId) then
        UI.label("EDITOR PREVIEW  •  " .. game.cards:definition(preview.featuredCardId).name:upper(),
            590, 91, 740, "center", palette.muted, "tiny")
    end
end

return Hud
