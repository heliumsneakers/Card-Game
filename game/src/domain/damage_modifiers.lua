local Modifiers = {}

-- Resolve card-relative filters when the bonus is created, not when it is spent.
function Modifiers.add(state, card, effect, amount)
    local element, category = effect.element, effect.category
    local resolvedElement = element == "this" and card.element or element
    local resolvedCategory = category == "this" and card.type or category
    assert(resolvedElement or resolvedCategory, "damage bonus requires an element or category")
    local lifetime = effect.scope == "combat" and state.combatDamageBonuses or state.turnDamageBonuses
    local key = (resolvedElement or "*") .. "|" .. (resolvedCategory or "*")
    local bonus = lifetime[key]
    if not bonus then
        bonus = { element = resolvedElement, category = resolvedCategory, amount = 0 }
        lifetime[key] = bonus
    end
    -- Replaying a matching bonus adds to its existing value for that duration.
    bonus.amount = bonus.amount + amount
end

-- Sum active bonuses whose filters match the card dealing this damage.
function Modifiers.amount(state, card)
    local total = 0
    for _, lifetime in ipairs({ state.turnDamageBonuses, state.combatDamageBonuses }) do
        for _, bonus in pairs(lifetime) do
            local matchesElement = not bonus.element or bonus.element == card.element
            local matchesCategory = not bonus.category or bonus.category == card.type
            if matchesElement and matchesCategory then total = total + bonus.amount end
        end
    end
    return total
end

-- Discard turn bonuses at the same boundary as turn counters.
function Modifiers.advanceTurn(state)
    state.turnDamageBonuses = {}
end

return Modifiers
