-- Loader.lua - prepare first, then compile/fetch, then load SolarHub.
-- The loader intentionally does NOT initialize SolarHub immediately after execution.
-- It first waits for the Roblox client/game environment and required game objects
-- to become available, then fetches/compiles all modules, and only after that
-- initializes Shared/UI/Joiner/Macro/Webhook.

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
local CACHE_BUST = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))

-------------------------------------------------
-- ALLOWED GAMES
-------------------------------------------------

local ALLOWED_GAMES = {
    {
        Name = "Anime Expeditions",
        GameId = 7613921865,
        PlaceIds = {
            [84515722934860] = true,
        },
    },
}

-------------------------------------------------
-- GAME CHECK
-------------------------------------------------

local function getAllowedGame()
    local currentGameId = game.GameId
    local currentPlaceId = game.PlaceId

    for _, entry in ipairs(ALLOWED_GAMES) do
        if currentGameId == entry.GameId
            or (entry.PlaceIds and entry.PlaceIds[currentPlaceId] == true) then

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

-------------------------------------------------
-- PREPARATION
-------------------------------------------------

local PREP_MIN_SECONDS = 4
local PREP_TIMEOUT_SECONDS = 25
local prepStartedAt = os.clock()

print("[Loader] Preparing SolarHub...")
print("[Loader] Game: " .. allowedGame.Name)

-- Do not begin module loading immediately. Give Roblox a short preparation
-- window first, while also waiting for the important game-side objects.
local function getRemoteEvents()
    return game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
end

local function getReplicaClientModule()
    local sharedFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
    local module = sharedFolder and sharedFolder:FindFirstChild("ReplicaClient")
    if module and module:IsA("ModuleScript") then
        return module
    end
    return nil
end

local function isPrepared()
    local loaded = true
    pcall(function()
        loaded = game:IsLoaded()
    end)

    local player = game:GetService("Players").LocalPlayer
    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
    local remoteEvents = getRemoteEvents()
    local replicaClient = getReplicaClientModule()

    return loaded
        and player ~= nil
        and playerGui ~= nil
        and remoteEvents ~= nil
        and replicaClient ~= nil
end

while os.clock() - prepStartedAt < PREP_TIMEOUT_SECONDS do
    local elapsed = os.clock() - prepStartedAt
    local remaining = math.max(0, PREP_MIN_SECONDS - elapsed)

    if elapsed >= PREP_MIN_SECONDS and isPrepared() then
        break
    end

    task.wait(math.min(0.25, math.max(0.05, remaining)))
end

print("[Loader] Preparation complete. Collecting modules...")

-------------------------------------------------
-- COLLECT
-------------------------------------------------

local function fetchSource(fileName)
    local ok, result = pcall(function()
        local url = BASE_URL .. fileName .. "?solarhub_version=" .. CACHE_BUST
        return game:HttpGet(url)
    end)

    if not ok then
        error("[Loader] FAILED to fetch " .. fileName .. ": " .. tostring(result))
    end

    if type(result) ~= "string" or result == "" then
        error("[Loader] FAILED to fetch " .. fileName .. ": empty response")
    end

    return result
end

local moduleSources = {}

for _, fileName in ipairs({
    "Shared.lua",
    "UI.lua",
    "Joiner.lua",
    "Macro.lua",
    "Webhook.lua",
}) do
    print("[Loader] Collecting " .. fileName .. "...")
    moduleSources[fileName] = fetchSource(fileName)
end

-------------------------------------------------
-- COMPILE / PREPARE
-------------------------------------------------

local function compile(fileName)
    local source = moduleSources[fileName]
    if not source then
        error("[Loader] Missing collected source: " .. fileName)
    end

    local ok, chunk = pcall(loadstring, source)
    if not ok or type(chunk) ~= "function" then
        error("[Loader] COMPILE ERROR in " .. fileName .. ": " .. tostring(chunk))
    end

    return chunk
end

print("[Loader] Compiling modules...")

local compiled = {
    Shared = compile("Shared.lua"),
    UI = compile("UI.lua"),
    Joiner = compile("Joiner.lua"),
    Macro = compile("Macro.lua"),
    Webhook = compile("Webhook.lua"),
}

moduleSources = nil

-------------------------------------------------
-- LOAD / INIT
-------------------------------------------------

local function runModule(label, fn)
    local ok, result = xpcall(fn, function(err)
        local msg = "[Loader] " .. label .. " ERROR: " .. tostring(err)
        warn(msg)
        return debug.traceback(tostring(err), 2)
    end)

    if not ok then
        warn("[Loader] " .. label .. " failed; continuing where possible.")
        return nil
    end

    return result
end

print("[Loader] Loading Shared...")
local Shared = runModule("Shared", function()
    return compiled.Shared()
end)
if not Shared then return end

print("[Loader] Loading UI...")
local UI = runModule("UI.Init", function()
    local UIModule = compiled.UI()
    return UIModule.Init(Shared)
end)
if not UI then return end

print("[Loader] Loading Joiner...")
runModule("Joiner.Init", function()
    local JoinerModule = compiled.Joiner()
    return JoinerModule.Init(Shared, UI)
end)

-- Joiner gets a clean startup window before Macro is initialized.
-- Macro's recording hook is still lazy and is only installed when recording starts.
task.delay(5, function()
    print("[Loader] Loading Macro...")
    runModule("Macro.Init", function()
        local MacroModule = compiled.Macro()
        return MacroModule.Init(Shared, UI)
    end)
end)

print("[Loader] Loading Webhook...")
runModule("Webhook.Init", function()
    local WebhookModule = compiled.Webhook()
    return WebhookModule.Init(Shared, UI)
end)

print("☀️ Solar Hub loaded successfully (prepared modular edition)!")
