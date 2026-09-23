--!strict

local MODULE_REF = "f1fc7ee358033f8f4947ffbf170f05e0b4790bc4"
local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/" .. MODULE_REF .. "/"
local debugGui
local debugBox
local debugText = ""

local function createDebugWindow()
    if debugGui then return end

    local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    debugGui = Instance.new("ScreenGui")
    debugGui.Name = "SolarHubDebugV2"
    debugGui.ResetOnSpawn = false
    debugGui.IgnoreGuiInset = true
    debugGui.DisplayOrder = 999999
    debugGui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromScale(0.82, 0.72)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    frame.BorderSizePixel = 1
    frame.Parent = debugGui

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 34)
    title.Position = UDim2.fromOffset(10, 8)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 210, 70)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "☀️ SolarHub Debug V2"
    title.Parent = frame

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -20, 0, 28)
    hint.Position = UDim2.fromOffset(10, 42)
    hint.BackgroundTransparency = 1
    hint.TextColor3 = Color3.fromRGB(170, 170, 170)
    hint.Font = Enum.Font.SourceSans
    hint.TextSize = 15
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Text = "داخل المربع: Ctrl+A ثم Ctrl+C"
    hint.Parent = frame

    debugBox = Instance.new("TextBox")
    debugBox.Size = UDim2.new(1, -20, 1, -84)
    debugBox.Position = UDim2.fromOffset(10, 76)
    debugBox.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
    debugBox.BorderSizePixel = 1
    debugBox.BorderColor3 = Color3.fromRGB(65, 65, 65)
    debugBox.TextColor3 = Color3.fromRGB(235, 235, 235)
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

    Instance.new("UICorner", debugBox).CornerRadius = UDim.new(0, 5)
end

local function addLog(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local message = table.concat(parts, " ")
    print(message)

    pcall(function()
        createDebugWindow()
        debugText = debugText .. message .. "\n"
        debugBox.Text = debugText
    end)
end

local function fetch(fileName)
    local ok, result = pcall(function()
        local url = BASE_URL .. fileName
        addLog("[FETCH]", fileName, "REF=" .. MODULE_REF)

        local source = game:HttpGet(url)
        if type(source) ~= "string" then
            error("[SOURCE ERROR] " .. fileName)
        end

        addLog("[SOURCE LENGTH]", fileName, #source)

        local chunk, compileError = loadstring(source, "@SolarHub/" .. fileName)
        if not chunk then
            error("[COMPILE ERROR] " .. fileName .. ": " .. tostring(compileError))
        end

        addLog("[COMPILE OK]", fileName)

        local runOk, runResult = xpcall(
            chunk,
            function(err)
                return debug.traceback(
                    "[RUNTIME ERROR] " .. fileName .. ": " .. tostring(err),
                    2
                )
            end
        )

        if not runOk then
            error(tostring(runResult))
        end

        addLog("[RUNTIME OK]", fileName)
        return runResult
    end)

    if not ok then
        addLog("[FETCH ERROR]", fileName)
        addLog(tostring(result))
        return nil
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
        addLog(tostring(result))
        return nil
    end

    addLog("[INIT OK]", label)
    return result
end

createDebugWindow()
addLog("========================================")
addLog("☀️ SOLARHUB DEBUG V2")
addLog("Pinned commit:", MODULE_REF)
addLog("GameId:", game.GameId)
addLog("PlaceId:", game.PlaceId)
addLog("========================================")

if game.GameId ~= 7613921865 or game.PlaceId ~= 84515722934860 then
    addLog("[BLOCKED] Wrong game/place.")
    return
end

addLog("[LOAD] Shared.lua")
local Shared = fetch("Shared.lua")
if not Shared then return end

addLog("[LOAD] UI.lua")
local UIModule = fetch("UI.lua")
if not UIModule then return end

local UI = initModule("UI.Init", function()
    return UIModule.Init(Shared)
end)
if not UI then return end

addLog("[LOAD] Joiner.lua")
local JoinerModule = fetch("Joiner.lua")
if not JoinerModule then return end

initModule("Joiner.Init", function()
    return JoinerModule.Init(Shared, UI)
end)

addLog("[LOAD] Macro.lua")
local MacroModule = fetch("Macro.lua")

if MacroModule then
    local macroResult = initModule("Macro.Init", function()
        return MacroModule.Init(Shared, UI)
    end)

    if macroResult ~= nil then
        addLog("[OK] Macro initialized")
    else
        addLog("[INFO] Macro.Init returned nil")
    end
end

addLog("[LOAD] Webhook.lua")
local WebhookModule = fetch("Webhook.lua")
if WebhookModule then
    initModule("Webhook.Init", function()
        return WebhookModule.Init(Shared, UI)
    end)
end

addLog("========================================")
addLog("☀️ DEBUG V2 FINISHED")
addLog("========================================")
