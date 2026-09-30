local Input = {}
Input.__index = Input

-- Create gesture state with injected coordinate, hit-test, and action callbacks.
function Input.new(viewport, ui, activate, inspect, closeInspection)
    return setmetatable({
        viewport = viewport, ui = ui, activate = activate,
        inspect = inspect, closeInspection = closeInspection,
        down = false, held = 0, zone = nil, inspected = false,
    }, Input)
end

-- Capture the virtual hit zone at the start of a press.
function Input:press(x, y)
    local vx, vy = self.viewport.toVirtual(x, y)
    self.down, self.held, self.inspected = true, 0, false
    -- Keep the original semantic target even though drawing rebuilds zones each frame.
    self.zone = self.ui.hitZone(vx, vy)
end

-- Open inspection after a held press crosses the hold threshold.
function Input:update(dt)
    if self.down and self.zone and not self.inspected then
        self.held = self.held + dt
        if self.held >= 0.38 then self.inspected = self.inspect(self.zone) or false end
    end
end

-- Close inspection or activate the matching press/release target, then reset the gesture.
function Input:release(x, y)
    local vx, vy = self.viewport.toVirtual(x, y)
    local released = self.ui.hitZone(vx, vy)
    -- A hold-to-inspect gesture must not also count as a card activation.
    if self.inspected then
        self.closeInspection()
    -- Match ID and payload, not table identity, because hit zones are recreated per draw.
    elseif self.zone and released and self.zone.id == released.id and self.zone.payload == released.payload then
        self.activate(released)
    elseif not self.zone then
        self.activate(nil)
    end
    self.down, self.zone = false, nil
end

return Input
