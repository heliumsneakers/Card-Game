local Cards = require("src.cards")
local Game = require("src.game")

-- All UI is authored against a 1920x1080 canvas, then letterboxed and scaled
-- uniformly by screenTransform(). This keeps layout, rendering, and hitboxes in
-- the same coordinate system at every browser/window resolution.
local VW, VH = 1920, 1080
local CARD_W, CARD_H = 220, 292
local game
local zones = {}
local pointer = { down = false, held = 0, zone = nil, inspected = false }
local inspectCard = nil
local fonts = {}

local palette = {
    ink = { 0.08, 0.09, 0.12 }, paper = { 0.90, 0.86, 0.72 },
    gold = { 0.91, 0.70, 0.25 }, blue = { 0.20, 0.42, 0.58 },
    red = { 0.68, 0.19, 0.18 }, green = { 0.23, 0.58, 0.31 },
    muted = { 0.48, 0.51, 0.53 }, white = { 0.96, 0.96, 0.91 },
}

local function color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], alpha or value[4] or 1)
end

local function rect(x, y, w, h, fill, outline, radius)
    radius = radius or 12
    color(fill)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    if outline then
        color(outline)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, radius, radius)
    end
end

local function getFont(style)
    return fonts[style or "body"] or love.graphics.getFont()
end

local function label(text, x, y, w, align, tint, style)
    color(tint or palette.white)
    love.graphics.setFont(getFont(style))
    love.graphics.printf(tostring(text), x, y, w, align or "left")
end

local function addZone(id, x, y, w, h, payload)
    zones[#zones + 1] = { id = id, x = x, y = y, w = w, h = h, payload = payload }
end

local function hitZone(x, y)
    for i = #zones, 1, -1 do
        local z = zones[i]
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then return z end
    end
end

local function button(id, text, x, y, w, h, enabled, tint, style)
    local fill = enabled == false and { 0.18, 0.19, 0.21 } or tint or palette.blue
    rect(x, y, w, h, fill, enabled == false and palette.muted or palette.paper)
    local fontStyle = style or "label"
    local textY = y + math.floor((h - getFont(fontStyle):getHeight()) / 2)
    label(text, x, textY, w, "center", enabled == false and palette.muted or palette.white, fontStyle)
    if enabled ~= false then addZone(id, x, y, w, h) end
end

local function effectiveText(card)
    return Cards.describe(card, game)
end

local function drawCard(card, x, y, w, h, selected, disabled, zoneId, payload)
    local definition = Cards.definition(card)
    local compact = w < 300
    local edge = selected and palette.gold or palette.paper
    rect(x, y, w, h, Cards.color(definition), edge, 16)
    if selected then
        color(palette.gold)
        love.graphics.setLineWidth(5)
        love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, 18, 18)
        love.graphics.setLineWidth(2)
    end
    if disabled then
        color(palette.ink, 0.56)
        love.graphics.rectangle("fill", x, y, w, h, 16, 16)
    end

    local manaRadius = compact and 24 or 32
    color(palette.ink)
    love.graphics.circle("fill", x + manaRadius + 10, y + manaRadius + 10, manaRadius)
    label(card.cost, x, y + (compact and 19 or 22), (manaRadius + 10) * 2, "center", palette.white,
        compact and "label" or "heading")
    local elementLabel = definition.element and (definition.element:upper() .. " • ") or ""
    label(elementLabel .. definition.type:upper(), x + 72, y + 19, w - 88, "right", palette.paper, compact and "tiny" or "small")
    label(card.name:upper(), x + 16, y + (compact and 74 or 88), w - 32, "center", palette.white,
        compact and "small" or "heading")

    local dividerY = y + (compact and 124 or 150)
    color(palette.paper, 0.42)
    love.graphics.line(x + 18, dividerY, x + w - 18, dividerY)
    label(effectiveText(card), x + 18, dividerY + 18, w - 36, "center", palette.paper,
        compact and "tiny" or "body")
    if card.isCopy then
        label("COPY", x + 18, y + h - 34, w - 36, "right", palette.gold, "tiny")
    end
    if zoneId then addZone(zoneId, x, y, w, h, payload or card) end
end

local function drawHud()
    rect(24, 24, 520, 122, { 0.12, 0.15, 0.19 }, palette.paper)
    label("HEALTH", 48, 43, 190, "left", palette.muted, "tiny")
    label(game.hp .. " / " .. game.maxHp, 48, 73, 190, "left",
        game.hp <= 10 and palette.red or palette.white, "heading")
    label("ARMOR", 280, 43, 180, "left", palette.muted, "tiny")
    label(game.armor, 280, 73, 180, "left", palette.white, "heading")
    label(game.endless and ("ENDLESS " .. game.endlessRoom) or ("ROOM " .. game.room .. " / 5"),
        374, 48, 146, "right", palette.gold, "small")
    label("TURN " .. game.turn, 400, 88, 120, "right", palette.muted, "tiny")

    rect(1424, 24, 472, 122, { 0.12, 0.15, 0.19 }, palette.paper)
    label("MANA", 1452, 43, 130, "left", palette.muted, "tiny")
    label(game.mana .. " / " .. game.maxMana, 1452, 73, 160, "left", palette.gold, "heading")
    label("DRAW", 1640, 43, 92, "center", palette.muted, "tiny")
    label(#game.deck, 1640, 76, 92, "center", palette.white, "label")
    label("DISCARD", 1768, 43, 104, "center", palette.muted, "tiny")
    label(#game.discard, 1768, 76, 104, "center", palette.white, "label")

    local surge = game.statuses["status.spell_power"] or 0
    local mirror = game.statuses["status.mirror"] or 0
    if surge > 0 or mirror > 0 then
        local buffs = {}
        if surge > 0 then buffs[#buffs + 1] = "SURGE x" .. surge end
        if mirror > 0 then buffs[#buffs + 1] = "MIRROR x" .. mirror end
        label(table.concat(buffs, "     "), 590, 42, 740, "center", palette.gold, "small")
    end
    if game.encounterTargetPower then
        local scaleText = game.endless and string.format("  •  SCALE %.2fx", game.encounterScale or 1) or ""
        label(string.format("BUDGET %.1f  •  BASE %.1f%s  •  SEED %d",
            game.encounterTargetPower, game.encounterPower or 0, scaleText, game.encounterSeed or 0),
            590, 132, 740, "center", palette.muted, "tiny")
    end
    local preview = Cards.catalog.document.preview
    if preview and preview.featuredCardId and Cards.definition(preview.featuredCardId) then
        label("EDITOR PREVIEW  •  " .. Cards.definition(preview.featuredCardId).name:upper(),
            590, 91, 740, "center", palette.muted, "tiny")
    end
end

local function enemyPosition(index, count)
    return VW / 2 + (index - (count + 1) / 2) * 390, 320
end

local function drawEnemies()
    for i, enemy in ipairs(game.enemies) do
        if enemy.alive then
            local x, y = enemyPosition(i, #game.enemies)
            local fill = enemy.isBoss and { 0.36, 0.13, 0.23 } or { 0.24, 0.28, 0.28 }
            if enemy.flash > 0 then fill = { 0.85, 0.85, 0.78 } end
            rect(x - 150, y - 88, 300, 190, fill, enemy.frozen and { 0.35, 0.85, 1 } or palette.paper)
            label(enemy.name:upper(), x - 132, y - 62, 264, "center",
                enemy.flash > 0 and palette.ink or palette.white, "heading")
            color(palette.paper, 0.35)
            love.graphics.line(x - 122, y - 12, x + 122, y - 12)
            label("HEALTH", x - 126, y + 12, 116, "center", palette.muted, "tiny")
            label(enemy.tough .. " / " .. enemy.maxTough, x - 126, y + 42, 116, "center", palette.white, "label")
            label("ATTACK", x + 10, y + 12, 116, "center", palette.muted, "tiny")
            label(enemy.pow, x + 10, y + 42, 116, "center", palette.gold, "label")
            if enemy.frozen then
                local stacks = enemy.debuffs and enemy.debuffs["debuff.freeze"] or 1
                label("FROZEN x" .. stacks, x - 132, y + 112, 264, "center", { 0.35, 0.85, 1 }, "small")
            end
            addZone("enemy", x - 154, y - 92, 308, 200, i)
        end
    end
end

local function drawWizard()
    local x, y, w, h = 870, 500, 180, 190
    rect(x, y, w, h, { 0.16, 0.26, 0.48 }, palette.gold)
    color({ 0.43, 0.25, 0.62 })
    love.graphics.polygon("fill", x + 18, y + 42, x + w / 2, y - 56, x + w - 18, y + 42)
    label("YOU", x, y + 116, w, "center", palette.white, "heading")
    addZone("wizard", x - 8, y - 58, w + 16, h + 66)
end

local function drawHand()
    local count = #game.hand
    if count == 0 then return end
    local gap = 18
    local total = count * CARD_W + (count - 1) * gap
    local startX = math.floor((VW - total) / 2)
    for i, card in ipairs(game.hand) do
        local x = startX + (i - 1) * (CARD_W + gap)
        local selected = game.selected == i
        drawCard(card, x, 760 - (selected and 22 or 0), CARD_W, CARD_H,
            selected, card.cost > game.mana, "card", i)
    end
end

local function drawMulligan()
    color(palette.ink, 0.82)
    love.graphics.rectangle("fill", 0, 0, VW, 720)
    rect(560, 230, 800, 370, { 0.12, 0.15, 0.19 }, palette.gold)
    label("OPENING HAND", 600, 280, 720, "center", palette.gold, "title")
    label("Keep these seven cards or redraw the hand once.", 600, 372, 720, "center", palette.white, "body")
    button("keep", "KEEP HAND", 640, 480, 280, 72, true, palette.green)
    button("redraw", "REDRAW", 1000, 480, 280, 72, true, palette.red)
end

local function drawCombat()
    drawHud()
    drawEnemies()
    drawWizard()
    drawHand()
    button("endturn", game.phase == "enemy" and "ENEMIES..." or "END TURN",
        1632, 624, 264, 76, game.phase == "player", palette.red)
    if game.phase == "player" then
        label(game.selected and "Choose a target or select the card again" or "Select a card  •  Hold to inspect",
            530, 705, 860, "center", palette.muted, "small")
    end
    if game.phase == "mulligan" then drawMulligan() end
end

local function shopPickCount(name)
    local count = 0
    for _, picked in ipairs(game.shopPicks) do if picked == name then count = count + 1 end end
    return count
end

local function drawReward()
    label("CARD SHOP", 0, 28, VW, "center", palette.gold, "title")
    label("Choose exactly 3 cards  •  " .. #game.shopPicks .. " / 3 selected",
        0, 96, VW, "center", palette.white, "body")
    local shopW, shopH = 280, 320
    local gapX, gapY = 48, 34
    local startX, startY = 492, 150
    for i, name in ipairs(game.shopChoices) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local x, y = startX + col * (shopW + gapX), startY + row * (shopH + gapY)
        drawCard(Cards.make(name), x, y, shopW, shopH, false, false, "shop", name)
        local picked = shopPickCount(name)
        if picked > 0 then
            rect(x + shopW - 70, y - 12, 82, 48, palette.gold, palette.ink)
            label("x" .. picked, x + shopW - 70, y - 4, 82, "center", palette.ink, "label")
        end
    end
    button("reset", "RESET PICKS", 492, 900, 280, 72, #game.shopPicks > 0, palette.red)
    button("deck", "VIEW DECK", 820, 900, 280, 72, true, palette.blue)
    button("descend", "DESCEND", 1148, 900, 280, 72, #game.shopPicks == 3, palette.green)
end

local function drawDeckViewer()
    color(palette.ink, 0.90)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
    rect(400, 92, 1120, 884, { 0.12, 0.15, 0.19 }, palette.gold)
    label("MASTER DECK  •  " .. #game.masterDeck .. " CARDS", 440, 130, 1040, "center", palette.gold, "title")
    label("Hold a row to inspect the card", 440, 196, 1040, "center", palette.muted, "tiny")
    for i, row in ipairs(game:masterCounts()) do
        local y = 246 + (i - 1) * 56
        if y < 860 then
            color(Cards.color(row.name), 0.55)
            love.graphics.rectangle("fill", 470, y, 980, 46, 8, 8)
            label(row.name, 494, y + 8, 720, "left", palette.white, "small")
            label("x" .. row.count, 1250, y + 8, 170, "right", palette.gold, "small")
            addZone("deckcard", 470, y, 980, 46, Cards.make(row.name))
        end
    end
    button("closedeck", "CLOSE", 820, 886, 280, 62, true, palette.red)
end

local function drawEndScreen(victory)
    label(victory and "DUNGEON CLEARED!" or "YOU DIED", 0, 330, VW, "center",
        victory and palette.gold or palette.red, "display")
    local defeat = game.endless and ("FELL IN ENDLESS ROOM " .. game.endlessRoom)
        or ("FELL IN ROOM " .. game.room .. " / 5")
    label(victory and "The Bone Lord has fallen." or defeat,
        0, 440, VW, "center", palette.white, "heading")
    button("restart", victory and "PLAY AGAIN" or "RESTART", 790, 540, 340, 82, true, palette.green, "heading")
end

local function drawInspection()
    if not inspectCard then return end
    color(palette.ink, 0.88)
    love.graphics.rectangle("fill", 0, 0, VW, VH)
    local card = type(inspectCard) == "string" and Cards.make(inspectCard) or inspectCard
    drawCard(card, 710, 110, 500, 760, false, false)
    local definition = Cards.definition(card)
    label((definition.element and (definition.element:upper() .. "  •  ") or "") .. definition.type:upper() .. "  •  TARGET: " .. definition.target:upper(),
        710, 890, 500, "center", palette.gold, "small")
    label("Release to close", 0, 970, VW, "center", palette.muted, "body")
end

local function screenTransform()
    local ww, wh = love.graphics.getDimensions()
    local scale = math.min(ww / VW, wh / VH)
    local logicalWidth, logicalHeight = ww / scale, wh / scale
    return scale, (logicalWidth - VW) / 2, (logicalHeight - VH) / 2
end

local function toVirtual(x, y)
    local scale, ox, oy = screenTransform()
    return x / scale - ox, y / scale - oy
end

function love.load()
    love.graphics.setDefaultFilter("linear", "linear")
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(2)
    fonts = {
        tiny = love.graphics.newFont(18),
        small = love.graphics.newFont(20),
        body = love.graphics.newFont(26),
        label = love.graphics.newFont(30),
        heading = love.graphics.newFont(38),
        title = love.graphics.newFont(54),
        display = love.graphics.newFont(72),
    }
    game = Game.new(30)
end

function love.update(dt)
    game:update(dt)
    if pointer.down and pointer.zone and not pointer.inspected then
        pointer.held = pointer.held + dt
        if pointer.held >= 0.38 then
            local z = pointer.zone
            if z.id == "card" then inspectCard = game.hand[z.payload]
            elseif z.id == "shop" then inspectCard = Cards.make(z.payload)
            elseif z.id == "deckcard" then inspectCard = z.payload end
            if inspectCard then pointer.inspected = true end
        end
    end
end

function love.draw()
    zones = {}
    love.graphics.clear(0.045, 0.065, 0.085)
    local scale, ox, oy = screenTransform()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    love.graphics.translate(ox, oy)
    if game.state == "combat" then drawCombat()
    elseif game.state == "reward" then
        drawReward()
        if game.showDeck then
            zones = {}
            drawDeckViewer()
        end
    elseif game.state == "victory" then drawEndScreen(true)
    elseif game.state == "gameover" then drawEndScreen(false) end
    if game.messageTime > 0 and not inspectCard then
        rect(610, 166, 700, 74, { 0.08, 0.09, 0.12 }, palette.gold)
        label(game.message, 630, 187, 660, "center", palette.gold, "small")
    end
    drawInspection()
    love.graphics.pop()
end

local function activate(zone)
    if not zone then
        if game.state == "combat" then game.selected = nil end
        return
    end
    if zone.id == "keep" then game:keepHand()
    elseif zone.id == "redraw" then game:redrawHand()
    elseif zone.id == "endturn" then game:endTurn()
    elseif zone.id == "card" then
        if game.phase ~= "player" then return end
        local index, card = zone.payload, game.hand[zone.payload]
        if not card then return end
        local definition = Cards.definition(card)
        local requiresEnemyTarget = definition.target == "enemy" or definition.target == "multi"
        if game.selected == index then
            if not requiresEnemyTarget then game:play(index) else game.selected = nil end
        else game.selected = index end
    elseif zone.id == "enemy" then
        if game.selected then game:play(game.selected, zone.payload) end
    elseif zone.id == "wizard" then
        if game.selected then
            local card = game.hand[game.selected]
            if card then
                local target = Cards.definition(card).target
                if target ~= "enemy" and target ~= "multi" then game:play(game.selected) end
            end
        end
    elseif zone.id == "shop" then game:pickReward(zone.payload)
    elseif zone.id == "reset" then game:resetPicks()
    elseif zone.id == "descend" then game:descend()
    elseif zone.id == "deck" then game.showDeck = true
    elseif zone.id == "closedeck" then game.showDeck = false
    elseif zone.id == "restart" then game:restart() end
end

local function pointerPressed(x, y)
    local vx, vy = toVirtual(x, y)
    pointer.down, pointer.held, pointer.inspected = true, 0, false
    pointer.zone = hitZone(vx, vy)
end

local function pointerReleased(x, y)
    local vx, vy = toVirtual(x, y)
    local released = hitZone(vx, vy)
    if pointer.inspected then inspectCard = nil
    elseif pointer.zone and released and pointer.zone.id == released.id and pointer.zone.payload == released.payload then activate(released)
    elseif not pointer.zone then activate(nil) end
    pointer.down, pointer.zone = false, nil
end

function love.mousepressed(x, y, button) if button == 1 then pointerPressed(x, y) end end
function love.mousereleased(x, y, button) if button == 1 then pointerReleased(x, y) end end
function love.touchpressed(_, x, y)
    pointerPressed(x, y)
end
function love.touchreleased(_, x, y)
    pointerReleased(x, y)
end
function love.keypressed(key)
    if key == "escape" then
        if inspectCard then inspectCard = nil elseif game.showDeck then game.showDeck = false else game.selected = nil end
    elseif key == "space" and game.state == "combat" then game:endTurn()
    elseif key == "f11" or (key == "return" and (love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt"))) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    end
end
