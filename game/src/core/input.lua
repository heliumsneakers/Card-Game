local Input = {}
Input.__index = Input

function Input.new(viewport, ui, activate, inspect, closeInspection)
    return setmetatable({
        viewport = viewport, ui = ui, activate = activate,
        inspect = inspect, closeInspection = closeInspection,
        down = false, held = 0, zone = nil, inspected = false,
    }, Input)
end

function Input:press(x, y)
    local vx, vy = self.viewport.toVirtual(x, y)
    self.down, self.held, self.inspected = true, 0, false
    self.zone = self.ui.hitZone(vx, vy)
end

function Input:update(dt)
    if self.down and self.zone and not self.inspected then
        self.held = self.held + dt
        if self.held >= 0.38 then self.inspected = self.inspect(self.zone) or false end
    end
end

function Input:release(x, y)
    local vx, vy = self.viewport.toVirtual(x, y)
    local released = self.ui.hitZone(vx, vy)
    if self.inspected then
        self.closeInspection()
    elseif self.zone and released and self.zone.id == released.id and self.zone.payload == released.payload then
        self.activate(released)
    elseif not self.zone then
        self.activate(nil)
    end
    self.down, self.zone = false, nil
end

return Input
