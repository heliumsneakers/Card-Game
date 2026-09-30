local Deck = require("src.domain.deck")
local Encounters = require("src.encounters")
local Run = {}

-- Set the run's active mode; combat phases are managed separately.
function Run.setState(run, state)
    run.state = state
end

-- Create persistent run data with a private copy of the starting deck.
function Run.new(startingHp, seed, startingDeck)
    return { runSeed = seed, maxHp = startingHp, hp = startingHp, armor = 0,
        masterDeck = Deck.clone(startingDeck), room = 1, endless = false, endlessRoom = 0 }
end

-- A room plan contains only the existing scenario data and generation results.
function Run.encounter(run, catalog)
    -- The guard room uses fixed composition and stats rather than random generation.
    if run.room == 5 and not run.endless then
        local seed = run.runSeed + 5005
        return {
            enemies = { { "enemy.skeleton", 4, 15 }, { "enemy.skeleton", 4, 15 } },
            targetPower = 7,
            power = Encounters.encounterPower({ catalog.enemies["enemy.skeleton"], catalog.enemies["enemy.skeleton"] }),
            seed = seed, random = Encounters.newRng(seed), banner = "BONE LORD'S GUARD",
        }
    end
    local config
    if run.endless then
        local endless = catalog.document.endless or Encounters.defaultEndless
        config = {}
        for key, value in pairs(endless) do config[key] = value end
        -- Endless rooms increase the budget while reusing the authored generation limits.
        config.power = endless.startingPower + (run.endlessRoom - 1) * endless.powerPerRoom
    else
        config = assert(Encounters.roomConfig(catalog.document, run.room), "missing generation settings for room " .. run.room)
    end
    -- Derive a repeatable room stream separately from draws and reward shuffles.
    local seed = run.runSeed + run.room * 1009 + run.endlessRoom * 7919
    local random = Encounters.newRng(seed)
    local candidate, warning = Encounters.generate(catalog, config, run.room, random, run.endless)
    assert(candidate, "could not generate room " .. run.room .. ": " .. tostring(warning))
    return {
        enemies = candidate.enemies, targetPower = config.power, power = candidate.power,
        seed = seed, random = random, warning = warning,
        scale = run.endless and Encounters.scaleForPower(candidate.enemies, config.power) or 1,
        banner = run.endless and ("ENDLESS " .. run.endlessRoom .. "  •  POWER " .. config.power)
            or ("ROOM " .. run.room .. "  •  POWER " .. config.power),
    }
end

-- Return the existing fixed boss wave without spawning combat entities.
function Run.bossWave()
    return { enemies = { { "enemy.bone_lord", 6, 28 } }, banner = "BONE LORD AWAKENS" }
end

-- Advance the room number without initializing combat.
function Run.advanceRoom(run)
    run.room = run.room + 1
end

-- Decide progression after combat reports a clear. Combat never chooses rooms.
function Run.afterClear(run, wave)
    if run.room == 5 and wave == 1 then return "boss" end
    if run.room == 5 and not run.endless then
        run.endless, run.endlessRoom, run.room = true, 1, 6
        -- The boss-to-endless transition restores health and removes carried armor.
        run.hp, run.armor = run.maxHp, 0
        return "room", "BONE LORD DEFEATED  •  ENDLESS BEGINS"
    end
    if run.endless then
        run.endlessRoom = run.endlessRoom + 1
        Run.advanceRoom(run)
        return "room"
    end
    return "reward"
end

return Run
