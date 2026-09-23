--!strict

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
local CACHE_BUST = tostring(os.clock()) .. "_" .. tostring(math.random(100000, 999999))

-------------------------------------------------
-- ON-SCREEN DEBUG OUTPUT
-------------------------------------------------

local debugGui
local debugBox
local debugText = ""

local function createDebugWindow()
    if debugGui then
        return
    end

    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    debugGui = Instance.new("ScreenGui")
    debugGui.Name = "SolarHubDebug"
    debugGui.ResetOnSpawn = false
    debugGui.IgnoreGuiInset = true
    debugGui.DisplayOrder = 999999
    debugGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.Name = "Window"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0.82, 0, 0.72, 0)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.BorderSizePixel = 1
    frame.Parent = debugGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 34)
    title.Position = UDim2.new(0, 10, 0, 8)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 210, 70)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "☀️ SolarHub Debug"
    title.Parent = frame

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 28)
    hint.Position = UDim2.new(0, 10, 0, 42)
    hint.BackgroundTransparency = 1
    hint.TextColor3 = Color3.fromRGB(170, 170, 170)
    hint.Font = Enum.Font.SourceSans
    hint.TextSize = 15
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Text = "اضغط داخل المربع ثم Ctrl+A وبعدها Ctrl+C لنسخ اللوج"
    hint.Parent = frame

    debugBox = Instance.new("TextBox")
    debugBox.Name = "Log"
    debugBox.Size = UDim2.new(1, -20, 1, -84)
    debugBox.Position = UDim2.new(0, 10, 0, 76)
    debugBox.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    debugBox.BorderSizePixel = 1
    debugBox.BorderColor3 = Color3.fromRGB(65, 65, 65)
    debugBox.TextColor3 = Color3.fromRGB(235, 235, 235)
    debugBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
    debugBox.Font = Enum.Font.Code
    debugBox.TextSize = 14
    debugBox.TextXAlignment = Enum.TextXAlignment.Left
    debugBox.TextYAlignment = Enum.TextYAlignment.Top
    debugBox.TextWrapped = false
    debugBox.MultiLine = true
    debugBox.ClearTextOnFocus = false
    debugBox.TextEditable = true
    debugBox.Text = ""
    debugBox.Parent = frame

    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = UDim.new(0, 5)
    boxCorner.Parent = debugBox
end

local function showDebug(message)
    pcall(function()
        createDebugWindow()
        debugText = debugText .. tostring(message) .. "\n"
        debugBox.Text = debugText
        debugBox.CursorPosition = #debugBox.Text + 1
    end)
end

local function addLog(...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end

    local message = table.concat(parts, " ")

    print(message)
    showDebug(message)
end

-------------------------------------------------
-- START
-------------------------------------------------

createDebugWindow()

addLog("========================================")
addLog("☀️ SOLARHUB DEBUG STARTED")
addLog("GameId:", game.GameId)
addLog("PlaceId:", game.PlaceId)
addLog("========================================")

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

-------------------------------------------------
-- MODULE FETCH
-------------------------------------------------

local function fetch(fileName)
    local ok, result = pcall(function()
        local url = BASE_URL .. fileName .. "?debug=" .. CACHE_BUST

        addLog("========================================")
        addLog("[FETCH]", fileName)

        local source = game:HttpGet(url)

        if type(source) ~= "string" then
            error("[SOURCE ERROR] " .. fileName .. " returned invalid source type: " .. tostring(typeof(source)))
        end

        addLog("[SOURCE LENGTH]", fileName, #source)

        local chunk, compileError = loadstring(
            source,
            "@SolarHub/" .. fileName
        )

        if not chunk then
            error("[COMPILE ERROR] " .. fileName .. ": " .. tostring(compileError))
        end

        addLog("[COMPILE OK]", fileName)

        local runtimeOk, runtimeResult = xpcall(
            chunk,
            function(err)
                return debug.traceback(
                    "[RUNTIME ERROR] " .. fileName .. ": " .. tostring(err),
                    2
                )
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

-------------------------------------------------
-- SAFE INIT
-------------------------------------------------

local function initModule(label, callback)
    local ok, result = xpcall(
        callback,
        function(err)
            return debug.traceback(
                "[INIT ERROR] " .. label .. ": " .. tostring(err),
                2
            )
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

-------------------------------------------------
-- LOAD MODULES
-------------------------------------------------

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

addLog("========================================")
addLog("☀️ SOLARHUB DEBUG FINISHED")
addLog("========================================")
