local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local CardView = require("src.ui.card_view")
local Hud = require("src.ui.hud")
local Combat = {}
local VW = 1920
local CARD_W, CARD_H = 220, 292

-- Center the enemy row with fixed spacing for the current group size.
local function enemyPosition(index, count)
    return VW / 2 + (index - (count + 1) / 2) * 390, 320
end

-- Draw living enemies, their feedback/status appearance, and target zones.
local function drawEnemies(game, app)
    for i, enemy in ipairs(game.combat.enemies) do
        if enemy.alive then
            local x, y = enemyPosition(i, #game.combat.enemies)
            local fill = enemy.isBoss and { 0.36, 0.13, 0.23 } or { 0.24, 0.28, 0.28 }
            if app.feedback:flash(enemy) > 0 then fill = { 0.85, 0.85, 0.78 } end
            UI.rect(x - 150, y - 88, 300, 190, fill, enemy.frozen and { 0.35, 0.85, 1 } or palette.paper)
            UI.label(enemy.name:upper(), x - 132, y - 62, 264, "center",
                app.feedback:flash(enemy) > 0 and palette.ink or palette.white, "heading")
            UI.color(palette.paper, 0.35)
            love.graphics.line(x - 122, y - 12, x + 122, y - 12)
            UI.label("HEALTH", x - 126, y + 12, 116, "center", palette.muted, "tiny")
            UI.label(enemy.tough .. " / " .. enemy.maxTough, x - 126, y + 42, 116, "center", palette.white, "label")
            UI.label("ATTACK", x + 10, y + 12, 116, "center", palette.muted, "tiny")
            UI.label(enemy.pow, x + 10, y + 42, 116, "center", palette.gold, "label")
            if enemy.frozen then
                UI.label("FROZEN", x - 132, y + 112, 264, "center", { 0.35, 0.85, 1 }, "small")
            end
            UI.addZone("enemy", x - 154, y - 92, 308, 200, i)
        end
    end
end

-- Draw the player avatar and the zone used for self-targeted cards.
local function drawWizard(game)
    local x, y, w, h = 870, 500, 180, 190
    UI.rect(x, y, w, h, { 0.16, 0.26, 0.48 }, palette.gold)
    UI.color({ 0.43, 0.25, 0.62 })
    love.graphics.polygon("fill", x + 18, y + 42, x + w / 2, y - 56, x + w - 18, y + 42)
    UI.label("YOU", x, y + 116, w, "center", palette.white, "heading")
    UI.addZone("wizard", x - 8, y - 58, w + 16, h + 66)
end

-- Center the current hand and lift the controller's selected card.
local function drawHand(game, app)
    local count = #game.deck.hand
    if count == 0 then return end
    local gap = 18
    local total = count * CARD_W + (count - 1) * gap
    local startX = math.floor((VW - total) / 2)
    for i, card in ipairs(game.deck.hand) do
        local x = startX + (i - 1) * (CARD_W + gap)
        -- Selection changes layout only; the controller owns the interaction state.
        local selected = app.combatController.selected == i
        CardView.draw(card, game, x, 760 - (selected and 22 or 0), CARD_W, CARD_H,
            selected, card.cost > game.combat.mana, "card", i)
    end
end

-- Cover combat controls with the opening-hand decision panel.
local function drawMulligan(game)
    UI.color(palette.ink, 0.82)
    love.graphics.rectangle("fill", 0, 0, VW, 720)
    UI.rect(560, 230, 800, 370, { 0.12, 0.15, 0.19 }, palette.gold)
    UI.label("OPENING HAND", 600, 280, 720, "center", palette.gold, "title")
    UI.label("Keep these seven cards or redraw the hand once.", 600, 372, 720, "center", palette.white, "body")
    UI.button("keep", "KEEP HAND", 640, 480, 280, 72, true, palette.green)
    UI.button("redraw", "REDRAW", 1000, 480, 280, 72, true, palette.red)
end

-- Compose combat visuals and phase-appropriate buttons from current state.
function Combat.draw(game, app)
    Hud.draw(game)
    drawEnemies(game, app)
    drawWizard(game)
    drawHand(game, app)
    UI.button("endturn", game.combat.phase == "enemy" and "ENEMIES..." or "END TURN",
        1632, 624, 264, 76, game.combat.phase == "player", palette.red)
    if game.combat.phase == "player" then
        UI.label(app.combatController.selected and "Choose a target or select the card again" or "Select a card  •  Hold to inspect",
            530, 705, 860, "center", palette.muted, "small")
    end
    if game.combat.phase == "mulligan" then drawMulligan(game) end
end

-- Forward screen actions to the controller that owns combat interaction.
function Combat.activate(game, zone, app)
    app.combatController:activate(zone)
end

return Combat
