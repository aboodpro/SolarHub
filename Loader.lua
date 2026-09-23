-- Loader.lua - game-gated modular loader.
-- Only approved games/places are allowed to load SolarHub modules.

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
-- Unique query per loader execution so GitHub/raw CDN and executor HTTP caches
-- cannot reuse an older SolarHub module after a GitHub update.
local CACHE_BUST = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))

-------------------------------------------------
-- ALLOWED GAMES
--
-- Add another game later by adding another entry.
-- GameId = UniverseId.
-- PlaceIds limits the loader to specific places inside that universe.
--
-- Example:
-- {
--     Name = "Another Game",
--     GameId = 123456789,
--     PlaceIds = {
--         [987654321] = true,
--     },
-- },
-------------------------------------------------

local ALLOWED_GAMES = {
    {
        Name = "Anime Expeditions",
        GameId = 7613921865,
        PlaceIds = {
            [84515722934860] = true,
        },
    },

    -- Add future allowed games here:
    --
    -- {
    --     Name = "Another Game",
    --     GameId = 123456789,
    --     PlaceIds = {
    --         [987654321] = true,
    --     },
    -- },
}

-------------------------------------------------
-- GAME CHECK
-------------------------------------------------

local function getAllowedGame()
    local currentGameId = game.GameId
    local currentPlaceId = game.PlaceId

    for _, entry in ipairs(ALLOWED_GAMES) do
        if currentGameId == entry.GameId or (entry.PlaceIds and entry.PlaceIds[currentPlaceId] == true) then

            -- If PlaceIds is omitted, the whole universe is allowed.
            if entry.PlaceIds == nil then
                return entry
            end

            if entry.PlaceIds[currentPlaceId] == true then
                return entry
            end

            return nil
        end
    end

    return nil
end

local allowedGame = getAllowedGame()

if not allowedGame then
    warn("[Loader] SolarHub is not supported in this game/place.")
    warn("[Loader] GameId: " .. tostring(game.GameId))
    warn("[Loader] PlaceId: " .. tostring(game.PlaceId))
    return
end

print("[Loader] Approved game: " .. allowedGame.Name)
print("[Loader] GameId: " .. tostring(game.GameId))
print("[Loader] PlaceId: " .. tostring(game.PlaceId))

-------------------------------------------------
-- MODULE FETCH
-------------------------------------------------

local function fetch(fileName)
    local ok, result = pcall(function()
        local url = BASE_URL .. fileName .. "?solarhub_version=" .. CACHE_BUST
        return loadstring(game:HttpGet(url))()
    end)

    if not ok then
        warn("[Loader] FAILED to load " .. fileName .. ": " .. tostring(result))
        error("[Loader] Stopping - " .. fileName .. " could not be loaded.")
    end

    return result
end

-------------------------------------------------
-- LOAD SOLARHUB
-------------------------------------------------

print("[Loader] Fetching Shared.lua...")
local Shared = fetch("Shared.lua")

local function runModule(label, fn)
    local ok, result = xpcall(fn, function(err)
        local msg = "[Loader] " .. label .. " ERROR: " .. tostring(err)
        warn(msg)
        return msg
    end)
    if not ok then
        warn("[Loader] " .. label .. " failed; continuing where possible.")
        return nil
    end
    return result
end

print("[Loader] Fetching UI.lua...")
local UIModule = fetch("UI.lua")
local UI = runModule("UI.Init", function() return UIModule.Init(Shared) end)
if not UI then return end

print("[Loader] Fetching Joiner.lua...")
local JoinerModule = fetch("Joiner.lua")
runModule("Joiner.Init", function() return JoinerModule.Init(Shared, UI) end)

print("[Loader] Fetching Macro.lua...")
local MacroModule = fetch("Macro.lua")

-- Macro initialization is deliberately delayed so the Joiner can finish its
-- lobby/Select Stage -> StartGame flow first. Macro itself does not need to
-- initialize before the player opens the Macro tab.
task.delay(5, function()
    local ok, result = xpcall(function()
        return MacroModule.Init(Shared, UI)
    end, function(err)
        return debug.traceback(tostring(err), 2)
    end)

    if not ok then
        warn("[Loader] Macro.Init ERROR:\n" .. tostring(result))
        if UI.setTabError then
            UI.setTabError("Macro", "Macro failed to initialize:\n" .. tostring(result))
        end
    elseif UI.clearTabError then
        UI.clearTabError("Macro")
    end
end)

print("[Loader] Fetching Webhook.lua...")
local WebhookModule = fetch("Webhook.lua")
runModule("Webhook.Init", function() return WebhookModule.Init(Shared, UI) end)

print("☀️ Solar Hub loaded successfully (modular edition)!")
