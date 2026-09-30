local App = require("src.app")
local app

-- Where everything begins.
function love.load()
	-- create a new instance of the app on startup
	app = App.new()

	--load function gets everything ready. follow the code
	app:load()
end

-- Advance the app once per frame using elapsed seconds.
function love.update(dt)
	app:update(dt)
end

-- Render the current app screen and overlays.
function love.draw()
	app:draw()
end

-- Forward keyboard shortcuts and combat keys to the app.
function love.keypressed(key)
	app:keypressed(key)
end

-- Forward the mouse press so input can begin a click or hold.
function love.mousepressed(x, y, button)
	app:mousepressed(x, y, button)
end

-- Forward release so input can activate or dismiss inspection.
function love.mousereleased(x, y, button)
	app:mousereleased(x, y, button)
end

-- Ignore the touch ID and use the shared pointer gesture path.
function love.touchpressed(_, x, y)
	app:touchpressed(x, y)
end

-- Finish the shared gesture with the released touch position.
function love.touchreleased(_, x, y)
	app:touchreleased(x, y)
end
