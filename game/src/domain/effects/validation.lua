local Debuffs = require("src.domain.debuffs.registry")
local Validation = {}
local ops = { damage = true, damageBonus = true, debuff = true, freeze = true, armor = true, heal = true, draw = true,
    mana = true, addStatus = true, incrementCounter = true, subtractCounter = true, setCounter = true,
    resetCounter = true, setLocal = true, ["if"] = true }

-- Match the editor's finite, safe, non-negative integer domain.
local function integer(value)
    return type(value) == "number" and value >= 0 and value <= 9007199254740991 and value == math.floor(value)
end

-- Copy definite local assignments before checking a conditional branch.
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end

-- Validate expression types, counter ownership, and ordered local visibility.
function Validation.effects(effects, path, errors, depth, cardTarget, cardIds, locals)
    depth, locals = depth or 0, locals or {}
    -- Keep diagnostics path-specific so imports fail before reaching the resolver.
    local function add(at, message) errors[#errors + 1] = { path = at, message = message } end
    if type(effects) ~= "table" then add(path, "effects must be an array"); return locals end
    if depth > 3 then add(path, "conditional nesting exceeds 3"); return locals end
    if #effects > 64 then add(path, "cannot contain more than 64 effects"); return locals end

    -- Validate both reference formats without reinterpreting legacy dotted names.
    local function counter(value, at)
        if value.scope ~= nil and value.scope ~= "turn" and value.scope ~= "combat" then
            add(at .. ".scope", "choose turn or combat lifetime")
        end
        if value.owner == nil then
            local id = value.id
            if type(id) ~= "string" or not id:match("%S") or id:sub(1, 1) == "@"
                or (id:sub(1, 1) == "$" and id ~= "$thisCard" and id ~= "$thisInstance") then
                add(at .. ".id", "invalid counter owner or shared name")
            elseif id:match("^card%.") and cardIds and not cardIds[id] then
                add(at .. ".id", "referenced card does not exist")
            end
            if value.name ~= nil then add(at, "named counters require an explicit owner") end
            return
        end
        -- Mixed identities are rejected so editor and game never choose different keys.
        if value.id ~= nil then add(at, "use an owner or a legacy ID, not both") end
        if type(value.name) ~= "string" or not value.name:match("%S") then add(at, "counter name must not be empty") end
        local owner = value.owner
        if type(owner) ~= "table" then add(at, "invalid counter owner"); return end
        if owner.kind == "this" or owner.kind == "instance" then return
        elseif owner.kind == "card" then
            if type(owner.cardId) ~= "string" or (cardIds and not cardIds[owner.cardId]) then add(at, "referenced card does not exist") end
        elseif owner.kind == "element" then
            local allowed = { this = true, fire = true, ice = true, nature = true, earth = true, arcane = true }
            if not allowed[owner.element] then add(at, "invalid element") end
        elseif owner.kind == "category" then
            local allowed = { this = true, DMG = true, DEF = true, HEAL = true, UTIL = true }
            if not allowed[owner.category] then add(at, "invalid category") end
        elseif owner.kind == "shared" then
            -- Shared names must not impersonate card IDs or internal storage keys.
            if type(value.name) == "string" and (value.name:match("^[@$]") or value.name:match("^card%.")) then
                add(at, "shared name uses a reserved prefix")
            end
        else add(at, "invalid counter owner") end
    end

    -- Infer each node's result and reject mixed arithmetic or unsafe lookups.
    local function expression(value, at, nesting)
        nesting = nesting or 0
        if nesting > 12 then add(at, "expression nesting exceeds 12"); return "invalid" end
        if type(value) ~= "table" then add(at, "expected an expression"); return "invalid" end
        local kind = value.kind
        if kind == "literal" then
            if not integer(value.value) then add(at, "use a non-negative safe whole number") end
            return "number"
        elseif kind == "counter" then counter(value, at); return "number"
        elseif kind == "card" then
            if type(value.id) ~= "string" or (cardIds and not cardIds[value.id]) then add(at, "referenced card does not exist") end
            return "card"
        elseif kind == "context" then
            if value.path == "thisCardId" or value.path == "previousCardId" then return "card" end
            if value.path == "mana" or value.path == "hp" or value.path == "turn" or value.path == "livingEnemies" then return "number" end
            add(at, "unsupported game value"); return "invalid"
        elseif kind == "local" then
            local result = type(value.name) == "string" and locals[value.name]
            if not result then add(at, "calculated value must be set earlier on every path") end
            return result or "invalid"
        elseif kind ~= "binary" and kind ~= "compare" then add(at, "unsupported expression kind"); return "invalid" end
        local left = expression(value.left, at .. ".left", nesting + 1)
        local right = expression(value.right, at .. ".right", nesting + 1)
        if kind == "binary" then
            local allowed = { add = true, subtract = true, multiply = true, min = true, max = true }
            if not allowed[value.operator] then add(at, "unsupported arithmetic operator") end
            if left ~= "number" or right ~= "number" then add(at, "arithmetic requires two numbers") end
            return "number"
        end
        local allowed = { eq = true, ne = true, lt = true, lte = true, gt = true, gte = true }
        if not allowed[value.operator] then add(at, "unsupported comparison operator") end
        if left ~= right or left == "invalid" then add(at, "compare values of the same type") end
        if value.operator ~= "eq" and value.operator ~= "ne" and left ~= "number" then add(at, "ordered comparisons require numbers") end
        return "boolean"
    end

    -- Require the type expected by each effect input.
    local function expect(value, at, expected)
        if expression(value, at) ~= expected then add(at, "expected a " .. expected .. " value") end
    end

    for index, effect in ipairs(effects) do
        local at = string.format("%s[%d]", path, index)
        if type(effect) ~= "table" or not ops[effect.op] then add(at, "unsupported effect operation")
        else
            if effect.scalable ~= nil and type(effect.scalable) ~= "boolean" then add(at, "scalable must be a boolean") end
            local op = effect.op
            if op == "if" then
                expect(effect.condition, at .. ".condition", "boolean")
                local yes = Validation.effects(effect["then"], at .. ".then", errors, depth + 1, cardTarget, cardIds, copy(locals))
                local no = Validation.effects(effect["else"] or {}, at .. ".else", errors, depth + 1, cardTarget, cardIds, copy(locals))
                -- Retain only assignments with the same type on both outcomes.
                locals = {}
                for name, kind in pairs(yes) do if no[name] == kind then locals[name] = kind end end
            elseif op == "setLocal" then
                local kind = expression(effect.value, at .. ".value")
                if type(effect.name) ~= "string" or not effect.name:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then add(at, "invalid calculated-value name")
                else locals[effect.name] = kind end
            elseif op == "damageBonus" then
                expect(effect.amount, at .. ".amount", "number")
                if effect.scope ~= "turn" and effect.scope ~= "combat" then add(at .. ".scope", "choose turn or combat duration") end
                local elements = { this = true, fire = true, ice = true, nature = true, earth = true, arcane = true }
                local categories = { this = true, DMG = true, DEF = true, HEAL = true, UTIL = true }
                if effect.element ~= nil and not elements[effect.element] then add(at .. ".element", "choose a valid element") end
                if effect.category ~= nil and not categories[effect.category] then add(at .. ".category", "choose a valid category") end
                if effect.element == nil and effect.category == nil then add(at, "choose an element or category to receive the bonus") end
            elseif op == "incrementCounter" or op == "subtractCounter" or op == "setCounter" or op == "resetCounter" then
                counter(effect, at)
                if op ~= "resetCounter" then
                    local value = effect.amount
                    if value == nil and op == "incrementCounter" then value = 1 end
                    if type(value) == "number" then value = { kind = "literal", value = value } end
                    expect(value, at .. ".amount", "number")
                end
            else
                if op ~= "freeze" then expect((op == "debuff" or op == "addStatus") and effect.stacks or effect.amount, at .. ".amount", "number") end
                -- Optional damage formulas are independent from stack scaling.
                if op == "debuff" and effect.bonusDamage ~= nil then expect(effect.bonusDamage, at .. ".bonusDamage", "number") end
                if op == "debuff" and effect.damageScalable ~= nil and type(effect.damageScalable) ~= "boolean" then add(at, "bonus damage scaling must be a boolean") end
                if op == "debuff" and not Debuffs.byId[effect.id] then add(at, "unsupported debuff") end
                if op == "addStatus" and effect.id ~= "status.spell_power" and effect.id ~= "status.mirror" then add(at, "unsupported status") end
                if op == "mana" and effect.cap ~= nil and not integer(effect.cap) then add(at, "invalid mana cap") end
                if op == "damage" or op == "debuff" or op == "freeze" then
                    local target = effect.target
                    if target ~= "selectedEnemy" and target ~= "otherEnemies" and target ~= "allEnemies" then add(at, "unsupported enemy target") end
                    if target == "selectedEnemy" and cardTarget ~= "enemy" and cardTarget ~= "multi" then add(at, "selected enemy requires enemy or multi card target") end
                    if target == "otherEnemies" and cardTarget ~= "multi" then add(at, "other enemies requires multi card target") end
                    if target == "allEnemies" and cardTarget ~= "all" and cardTarget ~= "multi" then add(at, "all enemies requires all or multi card target") end
                end
            end
        end
    end
    return locals
end

return Validation
