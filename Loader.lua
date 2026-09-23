--!strict
-- Loader.lua - game-gated modular loader.
-- Only approved games/places are allowed to load SolarHub modules.

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
local CACHE_BUST = tostring(os.clock())

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
        if currentGameId == entry.GameId then

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
        return loadstring(game:HttpGet(BASE_URL .. fileName .. "?v=" .. CACHE_BUST))()
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

print("[Loader] Fetching UI.lua...")
local UIModule = fetch("UI.lua")
local UI = UIModule.Init(Shared)

print("[Loader] Fetching Joiner.lua...")
local JoinerModule = fetch("Joiner.lua")
JoinerModule.Init(Shared, UI)

print("[Loader] Fetching Macro.lua...")
local MacroModule = fetch("Macro.lua")
MacroModule.Init(Shared, UI)

print("[Loader] Fetching Webhook.lua...")
local WebhookModule = fetch("Webhook.lua")
WebhookModule.Init(Shared, UI)

print("☀️ Solar Hub loaded successfully (modular edition)!")
