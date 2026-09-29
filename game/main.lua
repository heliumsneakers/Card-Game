local App = require("src.app")
local app

function love.load()
    app = App.new()
    app:load()
end

function love.update(dt)
    app:update(dt)
end

function love.draw()
    app:draw()
end

function love.keypressed(key)
    app:keypressed(key)
end

function love.mousepressed(x, y, button)
    app:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    app:mousereleased(x, y, button)
end

function love.touchpressed(_, x, y)
    app:touchpressed(x, y)
end

function love.touchreleased(_, x, y)
    app:touchreleased(x, y)
end
