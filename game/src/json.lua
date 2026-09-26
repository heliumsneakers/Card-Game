local Json = {}

local function decodeError(source, index, message)
    error(string.format("JSON error at byte %d: %s", index, message), 0)
end

function Json.decode(source)
    assert(type(source) == "string", "JSON source must be a string")
    local index, length = 1, #source

    local function skipWhitespace()
        while index <= length and source:sub(index, index):match("%s") do index = index + 1 end
    end

    local parseValue

    local function parseString()
        index = index + 1
        local result = {}
        while index <= length do
            local char = source:sub(index, index)
            if char == '"' then
                index = index + 1
                return table.concat(result)
            elseif char == "\\" then
                local escape = source:sub(index + 1, index + 1)
                local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if simple[escape] then
                    result[#result + 1] = simple[escape]
                    index = index + 2
                elseif escape == "u" then
                    local hex = source:sub(index + 2, index + 5)
                    if not hex:match("^%x%x%x%x$") then decodeError(source, index, "invalid unicode escape") end
                    local value = tonumber(hex, 16)
                    if value < 128 then
                        result[#result + 1] = string.char(value)
                    elseif value < 2048 then
                        result[#result + 1] = string.char(192 + math.floor(value / 64), 128 + value % 64)
                    else
                        result[#result + 1] = string.char(224 + math.floor(value / 4096), 128 + math.floor(value / 64) % 64, 128 + value % 64)
                    end
                    index = index + 6
                else
                    decodeError(source, index, "invalid escape")
                end
            else
                if char:byte() < 32 then decodeError(source, index, "control character in string") end
                result[#result + 1] = char
                index = index + 1
            end
        end
        decodeError(source, index, "unterminated string")
    end

    local function parseNumber()
        local start = index
        if source:sub(index, index) == "-" then index = index + 1 end
        if source:sub(index, index) == "0" then
            index = index + 1
        else
            if not source:sub(index, index):match("%d") then decodeError(source, index, "invalid number") end
            while source:sub(index, index):match("%d") do index = index + 1 end
        end
        if source:sub(index, index) == "." then
            index = index + 1
            if not source:sub(index, index):match("%d") then decodeError(source, index, "invalid fraction") end
            while source:sub(index, index):match("%d") do index = index + 1 end
        end
        local exponent = source:sub(index, index)
        if exponent == "e" or exponent == "E" then
            index = index + 1
            local sign = source:sub(index, index)
            if sign == "+" or sign == "-" then index = index + 1 end
            if not source:sub(index, index):match("%d") then decodeError(source, index, "invalid exponent") end
            while source:sub(index, index):match("%d") do index = index + 1 end
        end
        return tonumber(source:sub(start, index - 1))
    end

    local function parseArray()
        index = index + 1
        skipWhitespace()
        local result = {}
        if source:sub(index, index) == "]" then index = index + 1; return result end
        while true do
            result[#result + 1] = parseValue()
            skipWhitespace()
            local char = source:sub(index, index)
            if char == "]" then index = index + 1; return result end
            if char ~= "," then decodeError(source, index, "expected ',' or ']'") end
            index = index + 1
            skipWhitespace()
        end
    end

    local function parseObject()
        index = index + 1
        skipWhitespace()
        local result = {}
        if source:sub(index, index) == "}" then index = index + 1; return result end
        while true do
            if source:sub(index, index) ~= '"' then decodeError(source, index, "expected string key") end
            local key = parseString()
            skipWhitespace()
            if source:sub(index, index) ~= ":" then decodeError(source, index, "expected ':'") end
            index = index + 1
            skipWhitespace()
            result[key] = parseValue()
            skipWhitespace()
            local char = source:sub(index, index)
            if char == "}" then index = index + 1; return result end
            if char ~= "," then decodeError(source, index, "expected ',' or '}'") end
            index = index + 1
            skipWhitespace()
        end
    end

    parseValue = function()
        skipWhitespace()
        local char = source:sub(index, index)
        if char == '"' then return parseString()
        elseif char == "{" then return parseObject()
        elseif char == "[" then return parseArray()
        elseif char == "-" or char:match("%d") then return parseNumber()
        elseif source:sub(index, index + 3) == "true" then index = index + 4; return true
        elseif source:sub(index, index + 4) == "false" then index = index + 5; return false
        elseif source:sub(index, index + 3) == "null" then index = index + 4; return nil
        end
        decodeError(source, index, "unexpected token")
    end

    local value = parseValue()
    skipWhitespace()
    if index <= length then decodeError(source, index, "trailing content") end
    return value
end

return Json
