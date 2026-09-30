local Json = require("src.json")

local Content = { schemaVersion = 1 }

local function readFile(path)
    if love and love.filesystem and love.filesystem.getInfo(path) then
        return love.filesystem.read(path)
    end
    local file = io.open("game/" .. path, "rb") or io.open(path, "rb")
    if not file then return nil, "could not open " .. path end
    local data = file:read("*a")
    file:close()
    return data
end

local function integer(value, minimum)
    return type(value) == "number" and value == math.floor(value) and value >= (minimum or 0)
end

local validTargets = { enemy = true, multi = true, all = true, self = true }
local validEffectTargets = { selectedEnemy = true, otherEnemies = true, allEnemies = true }
local validDebuffs = { ["debuff.freeze"] = true }
local validTypes = { DMG = true, DEF = true, HEAL = true, UTIL = true }
local validElements = { fire = true, ice = true, nature = true, earth = true, arcane = true }
local validOps = {
    damage = true, debuff = true, freeze = true, armor = true, heal = true, draw = true,
    mana = true, addStatus = true, incrementCounter = true, setLocal = true, ["if"] = true,
}

local function contentId(kind, name)
    local slug = type(name) == "string" and name:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "") or ""
    if slug == "" then slug = "untitled" end
    return kind .. "." .. slug
end

local function add(errors, path, message)
    errors[#errors + 1] = { path = path, message = message }
end

local function numberInRange(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and (maximum == nil or value <= maximum)
end

local function validateEncounterSettings(settings, path, errors, needsPower)
    if type(settings) ~= "table" then add(errors, path, "encounter settings are required"); return end
    if needsPower and not numberInRange(settings.power, 0.01) then add(errors, path .. ".power", "power must be greater than zero") end
    if not integer(settings.minimumEnemies, 1) or settings.minimumEnemies > 4 then add(errors, path .. ".minimumEnemies", "must be an integer from 1-4") end
    if not integer(settings.maximumEnemies, 1) or settings.maximumEnemies > 4 or (integer(settings.minimumEnemies, 1) and settings.maximumEnemies < settings.minimumEnemies) then add(errors, path .. ".maximumEnemies", "must be at least minimumEnemies and no greater than 4") end
    if not numberInRange(settings.minimumBudgetRatio, 0.01) then add(errors, path .. ".minimumBudgetRatio", "must be greater than zero") end
    local minimumRatio = type(settings.minimumBudgetRatio) == "number" and settings.minimumBudgetRatio or 0.01
    if not numberInRange(settings.maximumBudgetRatio, minimumRatio) then add(errors, path .. ".maximumBudgetRatio", "must be at least minimumBudgetRatio") end
end

local function validDescriptionFormula(source)
    local compact = source:gsub("%s+", "")
    return compact ~= ""
        and compact:match("^%d") ~= nil
        and compact:match("%d$") ~= nil
        and compact:find("[^%d+%-%*]") == nil
        and compact:find("[+%-%*][+%-%*]") == nil
end

local function validateDescription(description, path, errors)
    if type(description) ~= "string" or description == "" or #description > 500 then
        add(errors, path, "description must contain 1-500 characters")
        return
    end
    local remainder = description:gsub("{([a-z][a-z0-9_]*)%s*=%s*([^{}]+)}", function(_, formula)
        if not validDescriptionFormula(formula) then add(errors, path, "value formulas support whole numbers with +, - or *") end
        return ""
    end)
    if remainder:find("[{}]") then add(errors, path, "value blocks must look like {dmg=2}") end
end

local function validateExpression(expression, path, errors, depth)
    depth = depth or 0
    if depth > 12 then add(errors, path, "expression nesting exceeds 12"); return end
    if type(expression) ~= "table" then add(errors, path, "must be an expression object"); return end
    local kind = expression.kind
    if kind == "literal" then
        if not integer(expression.value, 0) then add(errors, path .. ".value", "must be a non-negative integer") end
    elseif kind == "counter" then
        if type(expression.id) ~= "string" or expression.id == "" then add(errors, path .. ".id", "counter id is required") end
    elseif kind == "local" then
        if type(expression.name) ~= "string" or expression.name == "" then add(errors, path .. ".name", "local name is required") end
    elseif kind == "context" then
        local allowed = { previousCardId = true, thisCardId = true, mana = true, hp = true, turn = true, livingEnemies = true }
        if not allowed[expression.path] then add(errors, path .. ".path", "unsupported context value") end
    elseif kind == "binary" then
        local allowed = { add = true, subtract = true, multiply = true, min = true, max = true }
        if not allowed[expression.operator] then add(errors, path .. ".operator", "unsupported arithmetic operator") end
        validateExpression(expression.left, path .. ".left", errors, depth + 1)
        validateExpression(expression.right, path .. ".right", errors, depth + 1)
    elseif kind == "compare" then
        local allowed = { eq = true, ne = true, lt = true, lte = true, gt = true, gte = true }
        if not allowed[expression.operator] then add(errors, path .. ".operator", "unsupported comparison operator") end
        validateExpression(expression.left, path .. ".left", errors, depth + 1)
        validateExpression(expression.right, path .. ".right", errors, depth + 1)
    else
        add(errors, path .. ".kind", "unsupported expression kind")
    end
end

local function validateEffectTarget(effect, path, errors, cardTarget)
    if not validEffectTargets[effect.target] then add(errors, path .. ".target", "unsupported enemy target"); return end
    if effect.target == "selectedEnemy" and cardTarget ~= "enemy" and cardTarget ~= "multi" then add(errors, path .. ".target", "selected enemy requires enemy or multi card target") end
    if effect.target == "otherEnemies" and cardTarget ~= "multi" then add(errors, path .. ".target", "other enemies requires multi card target") end
    if effect.target == "allEnemies" and cardTarget ~= "all" and cardTarget ~= "multi" then add(errors, path .. ".target", "all enemies requires all or multi card target") end
end

local function validateEffects(effects, path, errors, depth, cardTarget)
    depth = depth or 0
    if type(effects) ~= "table" then add(errors, path, "must be an array"); return end
    if #effects > 64 then add(errors, path, "cannot contain more than 64 effects") end
    if depth > 3 then add(errors, path, "conditional nesting exceeds 3"); return end
    for index, effect in ipairs(effects) do
        local effectPath = string.format("%s[%d]", path, index)
        if type(effect) ~= "table" or not validOps[effect.op] then
            add(errors, effectPath .. ".op", "unsupported effect operation")
        elseif effect.op == "damage" then
            validateExpression(effect.amount, effectPath .. ".amount", errors)
            validateEffectTarget(effect, effectPath, errors, cardTarget)
        elseif effect.op == "debuff" then
            if not validDebuffs[effect.id] then add(errors, effectPath .. ".id", "unsupported debuff") end
            validateExpression(effect.stacks, effectPath .. ".stacks", errors)
            validateEffectTarget(effect, effectPath, errors, cardTarget)
        elseif effect.op == "freeze" then
            validateEffectTarget(effect, effectPath, errors, cardTarget)
        elseif effect.op == "armor" or effect.op == "heal" or effect.op == "draw" or effect.op == "mana" then
            validateExpression(effect.amount, effectPath .. ".amount", errors)
        elseif effect.op == "addStatus" then
            if type(effect.id) ~= "string" then add(errors, effectPath .. ".id", "status id is required") end
            validateExpression(effect.stacks, effectPath .. ".stacks", errors)
        elseif effect.op == "incrementCounter" then
            if type(effect.id) ~= "string" then add(errors, effectPath .. ".id", "counter id is required") end
        elseif effect.op == "setLocal" then
            if type(effect.name) ~= "string" then add(errors, effectPath .. ".name", "local name is required") end
            validateExpression(effect.value, effectPath .. ".value", errors)
        elseif effect.op == "if" then
            validateExpression(effect.condition, effectPath .. ".condition", errors)
            validateEffects(effect["then"] or {}, effectPath .. ".then", errors, depth + 1, cardTarget)
            validateEffects(effect["else"] or {}, effectPath .. ".else", errors, depth + 1, cardTarget)
        end
    end
end

function Content.validate(document)
    local errors = {}
    if type(document) ~= "table" then return { { path = "$", message = "content must be an object" } } end
    if document.schemaVersion ~= Content.schemaVersion then add(errors, "schemaVersion", "only schema version 1 is supported") end
    if type(document.cards) ~= "table" then add(errors, "cards", "must be an array") end
    if type(document.enemies) ~= "table" then add(errors, "enemies", "must be an array") end
    local ids = {}
    for index, card in ipairs(document.cards or {}) do
        local path = string.format("cards[%d]", index)
        if type(card.id) ~= "string" or not card.id:match("^card%.[a-z0-9_]+$") then add(errors, path .. ".id", "invalid card id")
        elseif ids[card.id] then add(errors, path .. ".id", "duplicate content id") else ids[card.id] = true end
        if type(card.name) ~= "string" or card.name == "" or #card.name > 48 then add(errors, path .. ".name", "name must contain 1-48 characters") end
        if type(card.name) == "string" and card.id ~= contentId("card", card.name) then add(errors, path .. ".id", "card id must match its name") end
        if not integer(card.cost, 0) or card.cost > 99 then add(errors, path .. ".cost", "cost must be an integer from 0-99") end
        if not validTypes[card.type] then add(errors, path .. ".type", "unsupported card type") end
        if card.element ~= nil and not validElements[card.element] then add(errors, path .. ".element", "unsupported card element") end
        if not validTargets[card.target] then add(errors, path .. ".target", "unsupported card target") end
        -- Description was added within schema v1. Older v1 documents remain
        -- loadable and fall back to generated text until the editor migrates them.
        if card.description ~= nil then validateDescription(card.description, path .. ".description", errors) end
        local availability = card.availability
        if type(availability) ~= "table" then add(errors, path .. ".availability", "availability is required")
        else
            if availability.shopChance ~= nil and not numberInRange(availability.shopChance, 0, 100) then add(errors, path .. ".availability.shopChance", "must be from 0-100") end
            if not integer(availability.copyLimit, 1) then add(errors, path .. ".availability.copyLimit", "must be a positive integer") end
        end
        validateEffects(card.effects, path .. ".effects", errors, nil, card.target)
    end
    for index, enemy in ipairs(document.enemies or {}) do
        local path = string.format("enemies[%d]", index)
        if type(enemy.id) ~= "string" or not enemy.id:match("^enemy%.[a-z0-9_]+$") then add(errors, path .. ".id", "invalid enemy id")
        elseif ids[enemy.id] then add(errors, path .. ".id", "duplicate content id") else ids[enemy.id] = true end
        if type(enemy.name) ~= "string" or enemy.name == "" or #enemy.name > 48 then add(errors, path .. ".name", "name must contain 1-48 characters") end
        if type(enemy.name) == "string" and enemy.id ~= contentId("enemy", enemy.name) then add(errors, path .. ".id", "enemy id must match its name") end
        for _, field in ipairs({ "damage", "hp" }) do
            local range = enemy[field]
            local minimum = field == "hp" and 1 or 0
            if type(range) ~= "table" or not integer(range.min, minimum) or not integer(range.max, minimum) then
                add(errors, path .. "." .. field, "range values must be whole numbers")
            elseif range.min > range.max then add(errors, path .. "." .. field, "minimum cannot exceed maximum") end
        end
        if enemy.generation ~= nil then
            local generation = enemy.generation
            if type(generation) ~= "table" then add(errors, path .. ".generation", "must be an object")
            else
                if not numberInRange(generation.spawnWeight, 0.01) then add(errors, path .. ".generation.spawnWeight", "must be greater than zero") end
                if not integer(generation.minimumRoom, 1) then add(errors, path .. ".generation.minimumRoom", "must be a positive integer") end
                local minimumRoom = type(generation.minimumRoom) == "number" and generation.minimumRoom or 1
                if generation.maximumRoom ~= nil and (not integer(generation.maximumRoom, minimumRoom)) then add(errors, path .. ".generation.maximumRoom", "must be at least minimumRoom") end
                if not integer(generation.maximumCopies, 1) or generation.maximumCopies > 4 then add(errors, path .. ".generation.maximumCopies", "must be an integer from 1-4") end
                if generation.powerOverride ~= nil and not numberInRange(generation.powerOverride, 0.01) then add(errors, path .. ".generation.powerOverride", "must be greater than zero") end
                if type(generation.tags) ~= "table" then add(errors, path .. ".generation.tags", "must be an array")
                else for tagIndex, tag in ipairs(generation.tags) do
                    if type(tag) ~= "string" or not tag:match("^[a-z0-9_]+$") then add(errors, path .. ".generation.tags[" .. tagIndex .. "]", "invalid tag") end
                end end
            end
        end
    end
    if document.roomCurve ~= nil then
        if type(document.roomCurve) ~= "table" then add(errors, "roomCurve", "must be an array")
        else
            local rooms = {}
            for index, room in ipairs(document.roomCurve) do
                local path = string.format("roomCurve[%d]", index)
                if not integer(room.room, 1) or room.room > 4 then add(errors, path .. ".room", "must be an integer from 1-4")
                elseif rooms[room.room] then add(errors, path .. ".room", "duplicate room") else rooms[room.room] = true end
                validateEncounterSettings(room, path, errors, true)
            end
            for room = 1, 4 do if not rooms[room] then add(errors, "roomCurve", "missing room " .. room) end end
        end
    end
    if document.endless ~= nil then
        validateEncounterSettings(document.endless, "endless", errors, false)
        if type(document.endless) == "table" then
            if not numberInRange(document.endless.startingPower, 0.01) then add(errors, "endless.startingPower", "must be greater than zero") end
            if not numberInRange(document.endless.powerPerRoom, 0.01) then add(errors, "endless.powerPerRoom", "must be greater than zero") end
        end
    end
    return errors
end

function Content.compile(document)
    local errors = Content.validate(document)
    if #errors > 0 then return nil, errors end
    local catalog = { document = document, cards = {}, enemies = {}, cardNames = {} }
    for _, card in ipairs(document.cards) do
        catalog.cards[card.id] = card
        catalog.cardNames[card.name] = card.id
    end
    for _, enemy in ipairs(document.enemies) do catalog.enemies[enemy.id] = enemy end
    return catalog
end

function Content.load(path)
    local source, readError = readFile(path or "content/content.json")
    if not source then return nil, { { path = "$", message = readError } } end
    local ok, document = pcall(Json.decode, source)
    if not ok then return nil, { { path = "$", message = document } } end
    return Content.compile(document)
end

return Content
