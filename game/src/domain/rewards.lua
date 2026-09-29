local Deck = require("src.domain.deck")
local Rewards = {}

function Rewards.new(masterDeck, cards, random)
    local choices = {}
    local eligible = {}
    for _, name in ipairs(cards.shopPool) do
        if Deck.count(masterDeck, cards:definition(name).id) < 3 then eligible[#eligible + 1] = name end
    end
    Deck.shuffle(eligible, random)
    local preview = cards.catalog.document.preview
    local featured = preview and preview.featuredCardId or nil
    if featured then
        for index, id in ipairs(eligible) do
            if id == featured then
                choices[#choices + 1] = id
                table.remove(eligible, index)
                break
            end
        end
    end
    for i = 1, math.min(6 - #choices, #eligible) do
        choices[#choices + 1] = eligible[i]
    end
    return { choices = choices, picks = {} }
end

function Rewards.pick(state, masterDeck, cards, name)
    local picks = state.picks
    if #picks >= 3 then return false end
    local pending = 0
    for _, picked in ipairs(picks) do if picked == name then pending = pending + 1 end end
    if Deck.count(masterDeck, cards:definition(name).id) + pending >= 3 then
        return false, "MAX 3 COPIES"
    end
    picks[#picks + 1] = cards:definition(name).id
    return true
end

function Rewards.apply(state, masterDeck)
    for _, id in ipairs(state.picks) do masterDeck[#masterDeck + 1] = id end
end

function Rewards.reset(state)
    state.picks = {}
end

function Rewards.complete(state)
    return #state.picks == 3
end

return Rewards
