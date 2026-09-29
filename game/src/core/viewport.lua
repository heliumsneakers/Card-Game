local Viewport = { width = 1920, height = 1080 }

function Viewport.transform()
    local ww, wh = love.graphics.getDimensions()
    local scale = math.min(ww / Viewport.width, wh / Viewport.height)
    return scale, (ww / scale - Viewport.width) / 2, (wh / scale - Viewport.height) / 2
end

function Viewport.toVirtual(x, y)
    local scale, ox, oy = Viewport.transform()
    return x / scale - ox, y / scale - oy
end

function Viewport.beginDraw()
    local scale, ox, oy = Viewport.transform()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    love.graphics.translate(ox, oy)
end

function Viewport.endDraw()
    love.graphics.pop()
end

return Viewport
