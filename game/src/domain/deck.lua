-- Pile operations use the supplied state and RNG; no content or global RNG access.
local Deck = {}

-- Copy a list of card IDs so run edits do not mutate the catalog's starter list.
function Deck.clone(source)
    local result = {}
    for i, value in ipairs(source) do result[i] = value end
    return result
end

-- Shuffle a list in place with Fisher-Yates and the supplied RNG.
function Deck.shuffle(list, random)
    for i = #list, 2, -1 do
        -- Choose from the remaining prefix; the injected RNG makes the order reproducible.
        local j = random(i)
        list[i], list[j] = list[j], list[i]
    end
end

-- Build fresh card instances and shuffled room piles from permanent deck IDs.
function Deck.new(masterDeck, cards, random)
    local state = {}
    state.draw, state.discard, state.hand = {}, {}, {}
    for _, id in ipairs(masterDeck) do state.draw[#state.draw + 1] = cards:make(id) end
    Deck.shuffle(state.draw, random)
    return state
end

-- Draw one card, recycling discard if necessary; return false when drawing is blocked.
function Deck.draw(state, random)
    -- Check the hand cap before recycling or consuming randomness.
    if #state.hand >= 7 then return false end
    if #state.draw == 0 then
        if #state.discard == 0 then return false end
        -- Transfer ownership of the old discard list, then create a fresh discard pile.
        state.draw, state.discard = state.discard, {}
        Deck.shuffle(state.draw, random)
    end
    -- The array tail acts as the top of the draw pile.
    state.hand[#state.hand + 1] = table.remove(state.draw)
    return true
end

-- Return the opening hand to the draw pile, shuffle, and deal up to seven cards.
function Deck.redraw(state, random)
    for _, card in ipairs(state.hand) do state.draw[#state.draw + 1] = card end
    state.hand = {}
    Deck.shuffle(state.draw, random)
    for _ = 1, 7 do Deck.draw(state, random) end
end

-- Keep ordinary cards for recycling while temporary copies vanish.
function Deck.discardPlayed(state, card)
    if not card.isCopy then state.discard[#state.discard + 1] = card end
end

-- Add discounted temporary copies until the count or hand limit is reached.
function Deck.addCopies(state, cards, card, count)
    -- Copies occupy hand slots but do not enter the permanent deck.
    for _ = 1, count do
        if #state.hand >= 7 then break end
        state.hand[#state.hand + 1] = cards:make(card.id, math.max(0, card.cost - 1), true)
    end
end

-- Count occurrences of a definition ID in the permanent deck.
function Deck.count(masterDeck, id)
    local count = 0
    for _, value in ipairs(masterDeck) do if value == id then count = count + 1 end end
    return count
end

-- Group permanent IDs into named, sorted rows for display.
function Deck.counts(masterDeck, cards)
    local counts = {}
    for _, id in ipairs(masterDeck) do counts[id] = (counts[id] or 0) + 1 end
    local rows = {}
    for id, count in pairs(counts) do rows[#rows + 1] = { id = id, name = cards:definition(id).name, count = count } end
    -- Sort display rows by name without reordering the permanent deck.
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

return Deck
