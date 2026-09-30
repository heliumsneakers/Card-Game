local Deck = require("src.domain.deck")
local Rewards = {}

-- Remove one entry using its designer-authored relative shop weight.
local function takeWeighted(list, cards, random)
    local total = 0
    for _, id in ipairs(list) do
        total = total + math.max(0, (cards:definition(id).availability or {}).shopChance or 50)
    end
    if total <= 0 then return nil end
    local roll = random() * total
    for index, id in ipairs(list) do
        roll = roll - math.max(0, (cards:definition(id).availability or {}).shopChance or 50)
        if roll <= 0 then return table.remove(list, index) end
    end
    return table.remove(list)
end

-- Build up to six eligible offers and an empty set of pending picks.
function Rewards.new(masterDeck, cards, random)
    local choices = {}
    local eligible = {}
    for _, name in ipairs(cards.shopPool) do
        local availability = cards:definition(name).availability or {}
        local chance = availability.shopChance == nil and 50 or availability.shopChance
        if chance > 0 and Deck.count(masterDeck, cards:definition(name).id) < (availability.copyLimit or 3) then
            eligible[#eligible + 1] = name
        end
    end
    local preview = cards.catalog.document.preview
    local featured = preview and preview.featuredCardId or nil
    -- The preview card moves to the first slot only if it is eligible.
    if featured then
        for index, id in ipairs(eligible) do
            if id == featured then
                choices[#choices + 1] = id
                table.remove(eligible, index)
                break
            end
        end
    end
    -- Fill the remaining slots without repeating offers, honoring relative rarity.
    while #choices < 6 and #eligible > 0 do
        local picked = takeWeighted(eligible, cards, random)
        if not picked then break end
        choices[#choices + 1] = picked
    end
    return { choices = choices, picks = {} }
end

-- Append a pick if total selections and permanent-plus-pending copies allow it.
function Rewards.pick(state, masterDeck, cards, name)
    local picks = state.picks
    if #picks >= 3 then return false end
    -- Include earlier picks when checking the limit, before anything is committed.
    local pending = 0
    for _, picked in ipairs(picks) do if picked == name then pending = pending + 1 end end
    local copyLimit = (cards:definition(name).availability or {}).copyLimit or 3
    if Deck.count(masterDeck, cards:definition(name).id) + pending >= copyLimit then
        return false, "MAX " .. copyLimit .. " COPIES"
    end
    picks[#picks + 1] = cards:definition(name).id
    return true
end

-- Commit pending card IDs into the supplied permanent deck.
function Rewards.apply(state, masterDeck)
    for _, id in ipairs(state.picks) do masterDeck[#masterDeck + 1] = id end
end

-- Replace the pending selection without regenerating offers.
function Rewards.reset(state)
    state.picks = {}
end

-- Report whether exactly three rewards have been selected.
function Rewards.complete(state)
    return #state.picks == 3
end

return Rewards
