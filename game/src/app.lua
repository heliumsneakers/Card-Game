local Game = require("src.game")
local Content = require("src.content")
local Feedback = require("src.presentation.feedback")
local CombatController = require("src.presentation.combat_controller")
local Viewport = require("src.core.viewport")
local Input = require("src.core.input")
local SceneStack = require("src.core.scene_stack")
local UI = require("src.ui.ui")
local palette = require("src.ui.theme")
local Combat = require("src.screens.combat_screen")
local Reward = require("src.screens.reward_screen")
local EndScreen = require("src.screens.end_screen")
local DeckView = require("src.ui.deck_view")
local Inspection = require("src.ui.inspection")

local App = {}
App.__index = App

local screens = {
    combat = Combat,
    reward = Reward,
    victory = EndScreen,
    gameover = EndScreen,
}

function App.new()
    local self = setmetatable({ scenes = SceneStack.new() }, App)
    self.input = Input.new(Viewport, UI,
        function(zone) self:activate(zone) end,
        function(zone) return self:inspect(zone) end,
        function() self:closeInspection() end)
    return self
end

function App:load()
    love.graphics.setDefaultFilter("linear", "linear")
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(2)
    UI.setFonts({
        tiny = love.graphics.newFont(18),
        small = love.graphics.newFont(20),
        body = love.graphics.newFont(26),
        label = love.graphics.newFont(30),
        heading = love.graphics.newFont(38),
        title = love.graphics.newFont(54),
        display = love.graphics.newFont(72),
    })
    local catalog, errors = Content.load("content/content.json")
    if not catalog then
        local messages = {}
        for _, item in ipairs(errors) do messages[#messages + 1] = item.path .. ": " .. item.message end
        error("content validation failed: " .. table.concat(messages, "; "))
    end
    self.feedback = Feedback.new()
    self.game = Game.new(30, nil, {
        catalog = catalog,
        seedSource = function() return os.time() + math.floor(love.timer.getTime() * 1000) end,
        feedback = self.feedback,
    })
    self.combatController = CombatController.new(self.game)
    self:syncScene()
end

function App:syncScene()
    if self.state ~= self.game.run.state then
        self.combatController:clearSelection()
        self.state = self.game.run.state
        self.scenes:setBase(assert(screens[self.state], "unknown game state: " .. tostring(self.state)))
        self.scenes.overlays = {}
        self.inspection = nil
    end
end

function App:showDeck()
    if self.game.run.state == "reward" then self.scenes:push(DeckView) end
end

function App:closeInspection()
    if self.scenes:top() == self.inspection then self.scenes:pop() end
    self.inspection = nil
end

function App:inspect(zone)
    local card
    if zone.id == "card" then card = self.game.deck.hand[zone.payload]
    elseif zone.id == "shop" then card = self.game.cards:make(zone.payload)
    elseif zone.id == "deckcard" then card = zone.payload end
    if not card then return false end
    self.inspection = { draw = Inspection.draw, card = card }
    self.scenes:push(self.inspection)
    return true
end

function App:update(dt)
    self.feedback:update(dt)
    self.game:update(dt)
    self.input:update(dt)
    self:syncScene()
end

function App:draw()
    UI.beginFrame()
    love.graphics.clear(0.045, 0.065, 0.085)
    Viewport.beginDraw()
    self.scenes.base.draw(self.game, self)
    for _, overlay in ipairs(self.scenes.overlays) do
        if overlay == DeckView then UI.clearZones() end
        if overlay == DeckView then overlay.draw(self.game) end
    end
    if self.feedback.messageTime > 0 and not self.inspection then
        UI.rect(610, 166, 700, 74, { 0.08, 0.09, 0.12 }, palette.gold)
        UI.label(self.feedback.message, 630, 187, 660, "center", palette.gold, "small")
    end
    if self.inspection then
        self.inspection.draw(self.game, self.inspection.card)
    end
    Viewport.endDraw()
end

function App:activate(zone)
    self:syncScene()
    local top = self.scenes:top()
    if top == DeckView then
        if zone and zone.id == "closedeck" then self.scenes:pop() end
    elseif top == self.inspection then
        return
    else
        top.activate(self.game, zone, self)
    end
    self:syncScene()
end

function App:keypressed(key)
    if key == "escape" then
        if self.inspection then self:closeInspection()
        elseif self.scenes:hasOverlay(DeckView) then self.scenes:pop()
        else self.combatController:clearSelection() end
    elseif key == "f11" or (key == "return" and (love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt"))) then
        love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    else
        self:syncScene()
        if key == "space" and self.game.run.state == "combat" then self.combatController:keypressed(key) end
    end
end

function App:mousepressed(x, y, button)
    if button == 1 then self.input:press(x, y) end
end

function App:mousereleased(x, y, button)
    if button == 1 then self.input:release(x, y) end
end

function App:touchpressed(x, y)
    self.input:press(x, y)
end

function App:touchreleased(x, y)
    self.input:release(x, y)
end

return App
