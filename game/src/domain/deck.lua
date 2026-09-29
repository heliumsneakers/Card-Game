-- Pile operations use the supplied state and RNG; no content or global RNG access.
local Deck = {}

function Deck.clone(source)
    local result = {}
    for i, value in ipairs(source) do result[i] = value end
    return result
end

function Deck.shuffle(list, random)
    for i = #list, 2, -1 do
        local j = random(i)
        list[i], list[j] = list[j], list[i]
    end
end

function Deck.new(masterDeck, cards, random)
    local state = {}
    state.draw, state.discard, state.hand = {}, {}, {}
    for _, id in ipairs(masterDeck) do state.draw[#state.draw + 1] = cards:make(id) end
    Deck.shuffle(state.draw, random)
    return state
end

function Deck.draw(state, random)
    if #state.hand >= 7 then return false end
    if #state.draw == 0 then
        if #state.discard == 0 then return false end
        state.draw, state.discard = state.discard, {}
        Deck.shuffle(state.draw, random)
    end
    state.hand[#state.hand + 1] = table.remove(state.draw)
    return true
end

function Deck.redraw(state, random)
    for _, card in ipairs(state.hand) do state.draw[#state.draw + 1] = card end
    state.hand = {}
    Deck.shuffle(state.draw, random)
    for _ = 1, 7 do Deck.draw(state, random) end
end

function Deck.discardPlayed(state, card)
    if not card.isCopy then state.discard[#state.discard + 1] = card end
end

function Deck.addCopies(state, cards, card, count)
    for _ = 1, count do
        if #state.hand >= 7 then break end
        state.hand[#state.hand + 1] = cards:make(card.id, math.max(0, card.cost - 1), true)
    end
end

function Deck.count(masterDeck, id)
    local count = 0
    for _, value in ipairs(masterDeck) do if value == id then count = count + 1 end end
    return count
end

function Deck.counts(masterDeck, cards)
    local counts = {}
    for _, id in ipairs(masterDeck) do counts[id] = (counts[id] or 0) + 1 end
    local rows = {}
    for id, count in pairs(counts) do rows[#rows + 1] = { id = id, name = cards:definition(id).name, count = count } end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

return Deck
