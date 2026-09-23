--!strict

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
local CACHE_BUST = tostring(os.clock()) .. "_" .. tostring(math.random(100000, 999999))

local function addLog(...)
    print(...)
end

print("========================================")
print("☀️ SOLARHUB DEBUG STARTED")
print("GameId:", game.GameId)
print("PlaceId:", game.PlaceId)
print("========================================")

local ALLOWED_GAMES = {
    {
        Name = "Anime Expeditions",
        GameId = 7613921865,
        PlaceIds = {
            [84515722934860] = true,
        },
    },
}

local function getAllowedGame()
    local currentGameId = game.GameId
    local currentPlaceId = game.PlaceId

    for _, entry in ipairs(ALLOWED_GAMES) do
        if currentGameId == entry.GameId then
            if entry.PlaceIds == nil then
                return entry
            end

            if entry.PlaceIds[currentPlaceId] == true then
                return entry
            end
        end
    end

    return nil
end

local allowedGame = getAllowedGame()

if not allowedGame then
    addLog("[BLOCKED] Game/Place not supported.")
    addLog("[BLOCKED] GameId:", game.GameId)
    addLog("[BLOCKED] PlaceId:", game.PlaceId)
    return
end

addLog("[OK] Game approved:", allowedGame.Name)

local function fetch(fileName)
    local ok, result = pcall(function()
        local url = BASE_URL .. fileName .. "?debug=" .. CACHE_BUST

        addLog("========================================")
        addLog("[FETCH]", fileName)
        addLog("[URL]", url)

        local source = game:HttpGet(url)

        if type(source) ~= "string" then
            error("[SOURCE ERROR] " .. fileName .. " returned invalid source type: " .. tostring(typeof(source)))
        end

        addLog("[SOURCE LENGTH]", fileName, #source)

        local chunk, compileError = loadstring(source, "@SolarHub/" .. fileName)

        if not chunk then
            error("[COMPILE ERROR] " .. fileName .. ": " .. tostring(compileError))
        end

        addLog("[COMPILE OK]", fileName)

        local runtimeOk, runtimeResult = xpcall(
            chunk,
            function(err)
                return debug.traceback("[RUNTIME ERROR] " .. fileName .. ": " .. tostring(err), 2)
            end
        )

        if not runtimeOk then
            error(tostring(runtimeResult))
        end

        addLog("[RUNTIME OK]", fileName)
        return runtimeResult
    end)

    if not ok then
        addLog("========================================")
        addLog("[FETCH ERROR]", fileName)
        addLog(tostring(result))
        addLog("========================================")
        error(result)
    end

    return result
end

local function initModule(label, callback)
    local ok, result = xpcall(
        callback,
        function(err)
            return debug.traceback("[INIT ERROR] " .. label .. ": " .. tostring(err), 2)
        end
    )

    if not ok then
        addLog("========================================")
        addLog("[INIT ERROR]", label)
        addLog(tostring(result))
        addLog("========================================")
        return nil
    end

    addLog("[INIT OK]", label)
    return result
end

addLog("[LOAD] Shared.lua")
local Shared = fetch("Shared.lua")
if not Shared then
    addLog("[FATAL] Shared.lua returned nil.")
    return
end
addLog("[OK] Shared.lua loaded")

addLog("[LOAD] UI.lua")
local UIModule = fetch("UI.lua")
if not UIModule then
    addLog("[FATAL] UI.lua returned nil.")
    return
end
addLog("[OK] UI.lua fetched")

local UI = initModule("UI.Init", function()
    return UIModule.Init(Shared)
end)

if not UI then
    addLog("[FATAL] UI initialization failed.")
    return
end
addLog("[OK] UI initialized")

addLog("[LOAD] Joiner.lua")
local JoinerModule = fetch("Joiner.lua")
if not JoinerModule then
    addLog("[FATAL] Joiner.lua returned nil.")
    return
end
addLog("[OK] Joiner.lua fetched")

initModule("Joiner.Init", function()
    return JoinerModule.Init(Shared, UI)
end)

addLog("[LOAD] Macro.lua")
local MacroModule = fetch("Macro.lua")

if not MacroModule then
    addLog("[FATAL] Macro.lua returned nil.")
else
    addLog("[OK] Macro.lua fetched")

    local macroResult = initModule("Macro.Init", function()
        return MacroModule.Init(Shared, UI)
    end)

    if macroResult ~= nil then
        addLog("[OK] Macro initialized")
    else
        addLog("[ERROR] Macro initialization returned nil")
    end
end

addLog("[LOAD] Webhook.lua")
local WebhookModule = fetch("Webhook.lua")

if not WebhookModule then
    addLog("[ERROR] Webhook.lua returned nil")
else
    addLog("[OK] Webhook.lua fetched")

    initModule("Webhook.Init", function()
        return WebhookModule.Init(Shared, UI)
    end)
end

print("========================================")
print("☀️ SOLARHUB DEBUG FINISHED")
print("========================================")
