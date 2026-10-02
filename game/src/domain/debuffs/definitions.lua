-- Generated from game/content/debuffs.json; do not edit this copy.
-- Regenerate with: npm run debuffs:generate
return {
    ["defaultId"] = "debuff.freeze",
    ["legacyOperations"] = {
        ["freeze"] = "debuff.freeze"
    },
    ["definitions"] = {
        {
            ["id"] = "debuff.freeze",
            ["label"] = "Freeze",
            ["token"] = "freeze",
            ["stackLabel"] = "Turns frozen",
            ["defaultStacks"] = 1,
            ["scalable"] = false,
            ["behavior"] = "skipAction",
            ["actionText"] = "IS FROZEN",
            ["badge"] = "FROZEN",
            ["color"] = {
                0.35,
                0.85,
                1
            },
            ["legacyFlag"] = "frozen"
        },
        {
            ["id"] = "debuff.burn",
            ["label"] = "Burn",
            ["token"] = "burn",
            ["stackLabel"] = "Turns burned",
            ["defaultStacks"] = 1,
            ["scalable"] = false,
            ["behavior"] = "burn",
            ["actionText"] = "IS BURNING!",
            ["badge"] = "BURNING",
            ["color"] = {
                0.35,
                0.85,
                1
            }
        }
    }
}
