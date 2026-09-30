local palette = require("src.ui.theme")
local UI = { fonts = {}, zones = {} }

-- Discard last frame's hit zones before screens register current geometry.
function UI.beginFrame()
    UI.zones = {}
end

-- Remove underlying hit zones when an overlay takes over interaction.
function UI.clearZones()
    UI.zones = {}
end

-- Install the app-created font set used by named text styles.
function UI.setFonts(fonts)
    UI.fonts = fonts
end

-- Apply a palette color with an optional alpha override.
function UI.color(value, alpha)
    love.graphics.setColor(value[1], value[2], value[3], alpha or value[4] or 1)
end

-- Draw a rounded fill and optional inset outline.
function UI.rect(x, y, w, h, fill, outline, radius)
    radius = radius or 12
    UI.color(fill)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    if outline then
        UI.color(outline)
        love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, radius, radius)
    end
end

-- Resolve a named style with a fallback to LÖVE's current font.
function UI.getFont(style)
    return UI.fonts[style or "body"] or love.graphics.getFont()
end

-- Draw aligned text within a fixed-width region using a named font style.
function UI.label(text, x, y, w, align, tint, style)
    UI.color(tint or palette.white)
    love.graphics.setFont(UI.getFont(style))
    love.graphics.printf(tostring(text), x, y, w, align or "left")
end

-- Register an interactive rectangle and its semantic action payload.
function UI.addZone(id, x, y, w, h, payload)
    UI.zones[#UI.zones + 1] = { id = id, x = x, y = y, w = w, h = h, payload = payload }
end

-- Find the last-registered rectangle containing the virtual pointer position.
function UI.hitZone(x, y)
    -- Later-drawn controls win overlaps, matching their visual stacking order.
    for i = #UI.zones, 1, -1 do
        local z = UI.zones[i]
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then return z end
    end
end

-- Draw a button and register a hit zone only when it is enabled.
function UI.button(id, text, x, y, w, h, enabled, tint, style)
    local fill = enabled == false and { 0.18, 0.19, 0.21 } or tint or palette.blue
    UI.rect(x, y, w, h, fill, enabled == false and palette.muted or palette.paper)
    local fontStyle = style or "label"
    local textY = y + math.floor((h - UI.getFont(fontStyle):getHeight()) / 2)
    UI.label(text, x, textY, w, "center", enabled == false and palette.muted or palette.white, fontStyle)
    -- Disabled buttons remain visible but cannot be activated by hit testing.
    if enabled ~= false then UI.addZone(id, x, y, w, h) end
end

return UI
