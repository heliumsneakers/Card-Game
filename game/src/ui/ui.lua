local palette = require("src.ui.theme")
local UI = { fonts = {}, zones = {} }

function UI.beginFrame()
    UI.zones = {}
end

function UI.clearZones()
    UI.zones = {}
end

function UI.setFonts(fonts)
    UI.fonts = fonts
end

function UI.color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], alpha or value[4] or 1)
end

function UI.rect(x, y, w, h, fill, outline, radius)
    radius = radius or 12
    UI.color(fill)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    if outline then
        UI.color(outline)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, radius, radius)
    end
end

function UI.getFont(style)
    return UI.fonts[style or "body"] or love.graphics.getFont()
end

function UI.label(text, x, y, w, align, tint, style)
    UI.color(tint or palette.white)
    love.graphics.setFont(UI.getFont(style))
    love.graphics.printf(tostring(text), x, y, w, align or "left")
end

function UI.addZone(id, x, y, w, h, payload)
    UI.zones[#UI.zones + 1] = { id = id, x = x, y = y, w = w, h = h, payload = payload }
end

function UI.hitZone(x, y)
    for i = #UI.zones, 1, -1 do
        local z = UI.zones[i]
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then return z end
    end
end

function UI.button(id, text, x, y, w, h, enabled, tint, style)
    local fill = enabled == false and { 0.18, 0.19, 0.21 } or tint or palette.blue
    UI.rect(x, y, w, h, fill, enabled == false and palette.muted or palette.paper)
    local fontStyle = style or "label"
    local textY = y + math.floor((h - UI.getFont(fontStyle):getHeight()) / 2)
    UI.label(text, x, textY, w, "center", enabled == false and palette.muted or palette.white, fontStyle)
    if enabled ~= false then UI.addZone(id, x, y, w, h) end
end

return UI
