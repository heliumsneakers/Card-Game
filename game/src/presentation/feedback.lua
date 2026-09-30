-- Transient visual state is owned and updated by the application.
local Feedback = {}
Feedback.__index = Feedback

-- Create independent visual feedback state for an app instance.
function Feedback.new()
    local self = setmetatable({}, Feedback)
    self:reset()
    return self
end

-- Clear messages and timers, allowing obsolete enemies to be garbage-collected.
function Feedback:reset()
    self.message, self.messageTime, self.shake = nil, 0, 0
    -- Weak keys prevent visual feedback from keeping obsolete enemy instances alive.
    self.flashes = setmetatable({}, { __mode = "k" })
end

-- Replace the current banner and set its visible duration.
function Feedback:notice(text, duration)
    self.message, self.messageTime = text, duration or 1.2
end

-- Start a brief flash keyed by the damaged enemy instance.
function Feedback:enemyDamaged(enemy)
    self.flashes[enemy] = 0.18
end

-- Start the player-hit shake timer.
function Feedback:playerDamaged()
    self.shake = 0.22
end

-- Read an enemy's remaining flash time without creating an entry.
function Feedback:flash(enemy)
    return self.flashes[enemy] or 0
end

-- Expire visual timers independently of combat progression.
function Feedback:update(dt)
    self.messageTime = math.max(0, self.messageTime - dt)
    self.shake = math.max(0, self.shake - dt)
    for enemy, time in pairs(self.flashes) do
        self.flashes[enemy] = time > dt and time - dt or nil
    end
end

return Feedback
