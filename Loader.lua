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
-- PROFESSIONAL LOADING SCREEN
-------------------------------------------------

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local loadingGui
local loadingStatus
local loadingSpinner

local function createLoadingScreen()
    local player = Players.LocalPlayer
    if not player then
        return
    end

    -- PlayerGui is the reliable client-side parent for a local loading screen.
    local parent = player:WaitForChild("PlayerGui")

    pcall(function()
        local old = parent:FindFirstChild("SolarHubLoading")
        if old then
            old:Destroy()
        end
    end)

    loadingGui = Instance.new("ScreenGui")
    loadingGui.Name = "SolarHubLoading"
    loadingGui.IgnoreGuiInset = true
    loadingGui.ResetOnSpawn = false
    loadingGui.DisplayOrder = 2147483647
    loadingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    loadingGui.Parent = parent

    local background = Instance.new("Frame")
    background.Size = UDim2.fromScale(1, 1)
    background.BackgroundColor3 = Color3.fromRGB(7, 8, 12)
    background.BorderSizePixel = 0
    background.Parent = loadingGui

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.BackgroundColor3 = Color3.fromRGB(11, 12, 18)
    overlay.BackgroundTransparency = 0.18
    overlay.BorderSizePixel = 0
    overlay.Parent = background

    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(430, 245)
    card.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
    card.BorderSizePixel = 0
    card.Parent = overlay

    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 190, 65)
    stroke.Transparency = 0.72
    stroke.Thickness = 1.2
    stroke.Parent = card

    local glow = Instance.new("UIGradient")
    glow.Rotation = 25
    glow.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 27, 38)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(19, 21, 31)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 14, 21)),
    })
    glow.Parent = card

    local icon = Instance.new("TextLabel")
    icon.AnchorPoint = Vector2.new(0.5, 0)
    icon.Position = UDim2.new(0.5, 0, 0, 25)
    icon.Size = UDim2.fromOffset(64, 48)
    icon.BackgroundTransparency = 1
    icon.Font = Enum.Font.GothamBlack
    icon.Text = "☀"
    icon.TextColor3 = Color3.fromRGB(255, 194, 70)
    icon.TextSize = 38
    icon.Parent = card

    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 74)
    title.Size = UDim2.fromOffset(360, 36)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "Loading Solar..."
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.TextSize = 24
    title.Parent = card

    loadingStatus = Instance.new("TextLabel")
    loadingStatus.AnchorPoint = Vector2.new(0.5, 0)
    loadingStatus.Position = UDim2.new(0.5, 0, 0, 112)
    loadingStatus.Size = UDim2.fromOffset(370, 24)
    loadingStatus.BackgroundTransparency = 1
    loadingStatus.Font = Enum.Font.Gotham
    loadingStatus.Text = "Preparing environment"
    loadingStatus.TextColor3 = Color3.fromRGB(145, 150, 165)
    loadingStatus.TextSize = 12
    loadingStatus.Parent = card

    loadingSpinner = Instance.new("TextLabel")
    loadingSpinner.AnchorPoint = Vector2.new(1, 0.5)
    loadingSpinner.Position = UDim2.new(1, -26, 0, 29)
    loadingSpinner.Size = UDim2.fromOffset(28, 28)
    loadingSpinner.BackgroundTransparency = 1
    loadingSpinner.Font = Enum.Font.GothamBold
    loadingSpinner.Text = "◌"
    loadingSpinner.TextColor3 = Color3.fromRGB(255, 196, 70)
    loadingSpinner.TextSize = 22
    loadingSpinner.Parent = card

    task.spawn(function()
        while loadingGui and loadingGui.Parent and loadingSpinner do
            local tween = TweenService:Create(
                loadingSpinner,
                TweenInfo.new(0.8, Enum.EasingStyle.Linear),
                {Rotation = loadingSpinner.Rotation + 360}
            )
            tween:Play()
            tween.Completed:Wait()
        end
    end)
end

local function setLoadingStatus(status)
    if loadingGui and loadingGui.Parent and loadingStatus then
        loadingStatus.Text = status or "Loading..."
    end
end

local function finishLoadingScreen()
    if not loadingGui or not loadingGui.Parent then
        return
    end

    setLoadingStatus("SolarHub ready")
    task.wait(0.35)

    local background = loadingGui:FindFirstChildWhichIsA("Frame")
    if background then
        local tween = TweenService:Create(
            background,
            TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
        tween:Play()
        tween.Completed:Wait()
    end

    loadingGui:Destroy()
    loadingGui = nil
end

createLoadingScreen()

task.spawn(function()
    -------------------------------------------------
    -- PREPARATION
    -------------------------------------------------
    
    local PREP_MIN_SECONDS = 4
    local PREP_TIMEOUT_SECONDS = 25
    local prepStartedAt = os.clock()
    
    print("[Loader] Preparing SolarHub...")
    print("[Loader] Game: " .. allowedGame.Name)
    setLoadingStatus("Preparing environment...")
    
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
    
    setLoadingStatus("Preparing Solar modules...")
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
        setLoadingStatus("Loading " .. fileName .. "...")
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
    
    setLoadingStatus("Compiling Solar modules...")
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
    
    setLoadingStatus("Starting SolarHub...")
    print("[Loader] Loading Shared...")
    local Shared = runModule("Shared", function()
        return compiled.Shared()
    end)
    if not Shared then return end
    
    setLoadingStatus("Building interface...")
    print("[Loader] Loading UI...")
    local UI = runModule("UI.Init", function()
        local UIModule = compiled.UI()
        return UIModule.Init(Shared)
    end)
    if not UI then return end
    
    setLoadingStatus("Connecting game systems...")
    print("[Loader] Loading Joiner...")
    runModule("Joiner.Init", function()
        local JoinerModule = compiled.Joiner()
        return JoinerModule.Init(Shared, UI)
    end)
    
    -- Joiner gets a clean startup window before Macro is initialized.
    -- Macro's recording hook is still lazy and is only installed when recording starts.
    task.delay(5, function()
        setLoadingStatus("Loading Macro engine...")
        print("[Loader] Loading Macro...")
        runModule("Macro.Init", function()
            local MacroModule = compiled.Macro()
            return MacroModule.Init(Shared, UI)
        end)
    
        setLoadingStatus("SolarHub ready")
        task.spawn(finishLoadingScreen)
    end)
    
    setLoadingStatus("Finalizing SolarHub...")
    print("[Loader] Loading Webhook...")
    runModule("Webhook.Init", function()
        local WebhookModule = compiled.Webhook()
        return WebhookModule.Init(Shared, UI)
    end)
    
    print("☀️ Solar Hub loaded successfully (prepared modular edition)!")
    -- The visual loader is closed by the Macro initialization callback.
    
end)
