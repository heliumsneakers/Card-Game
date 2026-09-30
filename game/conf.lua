-- Configure the save identity and resizable LÖVE window before the app loads.
function love.conf(t)
    t.identity = "pixel-card-game"
    t.version = "11.5"
    t.window.title = "Pixel Card Game"
    t.window.width = 1920
    t.window.height = 1080
    t.window.resizable = true
    t.window.minwidth = 960
    t.window.minheight = 540
    t.window.highdpi = true
    t.window.usedpiscale = true
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
end
