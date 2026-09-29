package.path = "game/?.lua;game/?/init.lua;" .. package.path
local Json = require("src.json")
local Content = require("src.content")
local Encounters = require("src.encounters")
local Descriptions = require("src.presentation.descriptions")
local file = assert(io.open("tests/fixtures/content_contract.json", "rb"))
local fixture = Json.decode(file:read("*a"))
file:close()
for _, item in ipairs(fixture.descriptions) do
    assert(Descriptions.describe(item) == item.expected)
end
for _, item in ipairs(fixture.enemies) do
    assert(math.abs(Encounters.enemyPower(item) - item.expectedPower) < 0.000001)
end
for _, edit in ipairs(fixture.invalidEdits) do
    local catalog = assert(Content.load("content/content.json"))
    catalog.document[edit.collection][1][edit.field] = edit.value
    assert(#Content.validate(catalog.document) > 0)
end
print("shared Lua content contract passed")
