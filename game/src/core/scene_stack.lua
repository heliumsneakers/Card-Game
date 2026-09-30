local SceneStack = {}
SceneStack.__index = SceneStack

-- Create an empty base-screen and overlay stack.
function SceneStack.new()
    return setmetatable({ base = nil, overlays = {} }, SceneStack)
end

-- Replace the base screen and drop overlays when the base changes.
function SceneStack:setBase(screen)
    if self.base ~= screen then
        self.base = screen
        self.overlays = {}
    end
end

-- Place an overlay above the current screen and existing overlays.
function SceneStack:push(overlay)
    self.overlays[#self.overlays + 1] = overlay
end

-- Remove and return the topmost overlay.
function SceneStack:pop()
    return table.remove(self.overlays)
end

-- Return the overlay that receives actions, or the base screen if none exists.
function SceneStack:top()
    return self.overlays[#self.overlays] or self.base
end

-- Check whether a particular overlay object is already on the stack.
function SceneStack:hasOverlay(overlay)
    for _, item in ipairs(self.overlays) do
        if item == overlay then return true end
    end
    return false
end

return SceneStack
