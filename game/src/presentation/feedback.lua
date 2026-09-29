-- Transient visual state is owned and updated by the application.
local Feedback = {}
Feedback.__index = Feedback

function Feedback.new()
    local self = setmetatable({}, Feedback)
    self:reset()
    return self
end

function Feedback:reset()
    self.message, self.messageTime, self.shake = nil, 0, 0
    self.flashes = setmetatable({}, { __mode = "k" })
end

function Feedback:notice(text, duration)
    self.message, self.messageTime = text, duration or 1.2
end

function Feedback:enemyDamaged(enemy)
    self.flashes[enemy] = 0.18
end

function Feedback:playerDamaged()
    self.shake = 0.22
end

function Feedback:flash(enemy)
    return self.flashes[enemy] or 0
end

function Feedback:update(dt)
    self.messageTime = math.max(0, self.messageTime - dt)
    self.shake = math.max(0, self.shake - dt)
    for enemy, time in pairs(self.flashes) do
        self.flashes[enemy] = time > dt and time - dt or nil
    end
end

return Feedback
