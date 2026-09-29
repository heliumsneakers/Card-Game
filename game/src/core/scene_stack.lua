local SceneStack = {}
SceneStack.__index = SceneStack

function SceneStack.new()
    return setmetatable({ base = nil, overlays = {} }, SceneStack)
end

function SceneStack:setBase(screen)
    if self.base ~= screen then
        self.base = screen
        self.overlays = {}
    end
end

function SceneStack:push(overlay)
    self.overlays[#self.overlays + 1] = overlay
end

function SceneStack:pop()
    return table.remove(self.overlays)
end

function SceneStack:top()
    return self.overlays[#self.overlays] or self.base
end

function SceneStack:hasOverlay(overlay)
    for _, item in ipairs(self.overlays) do
        if item == overlay then return true end
    end
    return false
end

return SceneStack
