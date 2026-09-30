local Viewport = { width = 1920, height = 1080 }

-- Compute aspect-preserving scale and centering offsets in virtual coordinates.
function Viewport.transform()
    local ww, wh = love.graphics.getDimensions()
    -- Use the smaller ratio to fit both dimensions without stretching the game.
    local scale = math.min(ww / Viewport.width, wh / Viewport.height)
    return scale, (ww / scale - Viewport.width) / 2, (wh / scale - Viewport.height) / 2
end

-- Convert window pointer coordinates into the game's fixed drawing space.
function Viewport.toVirtual(x, y)
    local scale, ox, oy = Viewport.transform()
    return x / scale - ox, y / scale - oy
end

-- Save graphics state and apply the virtual-resolution transform.
function Viewport.beginDraw()
    local scale, ox, oy = Viewport.transform()
    love.graphics.push()
    love.graphics.scale(scale, scale)
    love.graphics.translate(ox, oy)
end

-- Restore the graphics transform after drawing the game.
function Viewport.endDraw()
    love.graphics.pop()
end

return Viewport
