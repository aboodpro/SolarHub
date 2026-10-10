-- Loader.lua - prepare first, then compile/fetch, then load SolarHub.
-- The loader intentionally does NOT initialize SolarHub immediately after execution.
-- It first waits for the Roblox client/game environment and required game objects
-- to become available, then fetches/compiles all modules, and only after that
-- initializes Shared/UI/Joiner/Macro/Webhook.

local BASE_URL = "https://raw.githubusercontent.com/aboodpro/SolarHub/main/"
local ARCANE_SOURCE_REF = "1cb59d650477c488521d59b64c8526379ae7b4f9"
local CACHE_BUST = tostring(os.clock()):gsub("%.", "") .. "_" .. tostring(math.random(100000000, 999999999)) .. "_" .. tostring(game.PlaceId)
local LOADER_VERSION = "2026-10-10-ARCANE-70-RARE-CHART-SLOTS-PHYSICAL-ISLANDS"
local SESSION_ID = tostring(os.clock()):gsub("%.", "") .. "_" .. tostring(math.random(100000000, 999999999))

-------------------------------------------------
-- SINGLE-INSTANCE BOOTSTRAP / CLEANUP
-------------------------------------------------
-- A second execute must stop the old SolarHub session BEFORE the new UI or
-- background workers are created. This keeps old Arcane loops/event handlers
-- from overlapping the new session.
local solarHubCleanupFinished = false
local solarHubOrphanESPConnection = nil

local function destroyKnownSolarHubArtifacts()
    -- Legacy ESP objects are parented to world models/parts, not just PlayerGui.
    -- Sweep descendants so old Highlights, BillboardGuis, anchors, and chart
    -- markers are removed even if the previous session's cleanup failed.
    local ownedPrefixes = {
        "SolarHub",
        "SolarArcane",
        "SolarTreasure",
        "SolarChest",
        "SolarSideQuest",
        "SolarBoss",
        "SolarFish",
    }

    local function isOwnedSolarVisual(instance)
        local name = tostring(instance.Name or "")
        local hasOwnedPrefix = false

        for _, prefix in ipairs(ownedPrefixes) do
            if name:sub(1, #prefix) == prefix then
                hasOwnedPrefix = true
                break
            end
        end

        if not hasOwnedPrefix then
            return false
        end

        return instance:IsA("ScreenGui")
            or instance:IsA("Highlight")
            or instance:IsA("BillboardGui")
            or instance:IsA("BasePart")
            or instance:IsA("Attachment")
            or instance:IsA("Beam")
            or instance:IsA("SelectionBox")
            or instance:IsA("BoxHandleAdornment")
            or instance:IsA("SurfaceGui")
    end

    pcall(function()
        local descendants = game:GetDescendants()

        -- Delete leaf instances first; this also catches ESP objects parented
        -- directly to chest/boss models rather than to a dedicated folder.
        for index = #descendants, 1, -1 do
            local instance = descendants[index]

            if instance and instance.Parent and isOwnedSolarVisual(instance) then
                pcall(function()
                    instance:Destroy()
                end)
            end
        end
    end)

    -- Explicitly remove the three named workspace anchors for older builds.
    pcall(function()
        local ownedWorkspaceObjects = {
            SolarTreasureChartMarker = true,
            SolarTreasureEstimatedDigArea = true,
            SolarChestStaticAnchor = true,
            SolarChestStaticAttachment = true,
            SolarSideQuestVirtualAnchor = true,
            SolarSideQuestLocationAnchor = true,
        }

        for _, child in ipairs(workspace:GetDescendants()) do
            if ownedWorkspaceObjects[child.Name] then
                pcall(function()
                    child:Destroy()
                end)
            end
        end
    end)
end
local function cleanupSolarHubRuntime()
    if solarHubCleanupFinished then
        return
    end

    solarHubCleanupFinished = true

    if solarHubOrphanESPConnection then
        pcall(function()
            solarHubOrphanESPConnection:Disconnect()
        end)
        solarHubOrphanESPConnection = nil
    end

    pcall(function()
        if type(getgenv) == "function" then
            local env = getgenv()
            if env.SolarHubOrphanESPConnection then
                env.SolarHubOrphanESPConnection = nil
            end
        end
    end)

    pcall(function()
        if type(getgenv) == "function" then
            local env = getgenv()
            local arcaneCleanup = env.SolarHubArcaneCleanup

            if type(arcaneCleanup) == "function" then
                pcall(arcaneCleanup)
            end

            if env.SolarHubLoaderSession == SESSION_ID then
                env.SolarHubLoaderSession = nil
            end

            if env.SolarHubCleanup == cleanupSolarHubRuntime then
                env.SolarHubCleanup = nil
            end
        end
    end)

    destroyKnownSolarHubArtifacts()
end

-- Stop the previous run before creating any new UI or ESP. Capture both
-- callbacks first because the loader cleanup may unset the Arcane callback.
pcall(function()
    if type(getgenv) == "function" then
        local env = getgenv()
        local oldOrphanConnection = env.SolarHubOrphanESPConnection
        if oldOrphanConnection then
            pcall(function()
                oldOrphanConnection:Disconnect()
            end)
            env.SolarHubOrphanESPConnection = nil
        end

        local previousCleanup = env.SolarHubCleanup
        local previousArcaneCleanup = env.SolarHubArcaneCleanup

        if type(previousCleanup) == "function" then
            pcall(previousCleanup)
        end

        if type(previousArcaneCleanup) == "function" then
            pcall(previousArcaneCleanup)
        end

        -- Hard-stop any leftover session loops, even if an older cleanup
        -- callback was missing or raised an error.
        env.SolarHubArcaneSession = nil
        env.SolarHubLoaderSession = nil
        env.SolarHubArcaneCleanup = nil
    end
end)

destroyKnownSolarHubArtifacts()

pcall(function()
    if type(getgenv) == "function" then
        local env = getgenv()
        env.SolarHubLoaderSession = SESSION_ID
        env.SolarHubCleanup = cleanupSolarHubRuntime
    end
end)

-- Event-driven orphan cleanup: never rescan the whole Workspace/game on a timer.
local function cleanupOrphanedSolarHubVisual(instance)
    if not instance or not instance.Parent then
        return
    end

    local currentSession = nil
    pcall(function()
        if type(getgenv) == "function" then
            currentSession = getgenv().SolarHubLoaderSession
        end
    end)

    if currentSession ~= SESSION_ID then
        return
    end

    local name = tostring(instance.Name or "")
    local visualName = name:sub(1, 13) == "SolarTreasure"
        or name:sub(1, 10) == "SolarChest"
        or name:sub(1, 14) == "SolarSideQuest"
        or name:sub(1, 9) == "SolarBoss"

    if not visualName then
        return
    end

    local visualClass = instance:IsA("Highlight")
        or instance:IsA("BillboardGui")
        or instance:IsA("BasePart")
        or instance:IsA("Attachment")
        or instance:IsA("SelectionBox")
        or instance:IsA("BoxHandleAdornment")
        or instance:IsA("Beam")

    if not visualClass then
        return
    end

    local token = nil
    pcall(function()
        token = instance:GetAttribute("SolarHubSessionToken")
    end)

    -- Visuals created by this session are tagged before being parented.
    -- Old scripts that recreate untagged visuals are removed immediately.
    if token ~= SESSION_ID then
        pcall(function()
            instance:Destroy()
        end)
    end
end

local function installSolarHubOrphanCleanupConnection()
    if type(getgenv) == "function" then
        local env = getgenv()
        local previousConnection = env.SolarHubOrphanESPConnection

        if previousConnection then
            pcall(function()
                previousConnection:Disconnect()
            end)
        end
    end

    local connection = game.DescendantAdded:Connect(function(instance)
        cleanupOrphanedSolarHubVisual(instance)
    end)

    if type(getgenv) == "function" then
        getgenv().SolarHubOrphanESPConnection = connection
    end

    return connection
end

solarHubOrphanESPConnection = installSolarHubOrphanCleanupConnection()


-------------------------------------------------
-- DEBUG / DIAGNOSTICS
-------------------------------------------------

local DEBUG_LINES = {}
local MAX_DEBUG_LINES = 250

local function debugLog(message)
    local line = "[Loader] " .. tostring(message)
    table.insert(DEBUG_LINES, line)

    if #DEBUG_LINES > MAX_DEBUG_LINES then
        table.remove(DEBUG_LINES, 1)
    end

    print(line)
end

pcall(function()
    local LogService = game:GetService("LogService")

    LogService.MessageOut:Connect(function(message, messageType)
        if messageType == Enum.MessageType.MessageWarning
            or messageType == Enum.MessageType.MessageError then

            if tostring(message):find("[Loader]", 1, true)
                or tostring(message):find("SolarHub", 1, true) then

                table.insert(DEBUG_LINES, tostring(message))

                if #DEBUG_LINES > MAX_DEBUG_LINES then
                    table.remove(DEBUG_LINES, 1)
                end
            end
        end
    end)
end)

local function getDebugText()
    local lines = {
        "SolarHub Debug",
        "==============================",
        "PlaceId: " .. tostring(game.PlaceId),
        "GameId (UniverseId): " .. tostring(game.GameId),
        "JobId: " .. tostring(game.JobId),
        "GameLoaded: " .. tostring(game:IsLoaded()),
        "SessionId: " .. tostring(SESSION_ID),
    }

    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(
            game.PlaceId,
            Enum.InfoType.Asset
        )
    end)

    if ok and info then
        table.insert(lines, "PlaceName: " .. tostring(info.Name))
    else
        table.insert(lines, "PlaceName: <unavailable>")
    end

    table.insert(lines, "")
    table.insert(lines, "Logs:")
    table.insert(lines, "------------------------------")

    if #DEBUG_LINES == 0 then
        table.insert(lines, "<no loader logs captured>")
    else
        for _, line in ipairs(DEBUG_LINES) do
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

local function showDebugUI()
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    if not player then
        player = Players.PlayerAdded:Wait()
    end

    local playerGui = player:WaitForChild("PlayerGui")

    pcall(function()
        local old = playerGui:FindFirstChild("SolarHubDebug")
        if old then
            old:Destroy()
        end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = "SolarHubDebug"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 2147483647
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    local toggle = Instance.new("TextButton")
    toggle.Name = "DebugToggle"
    toggle.AnchorPoint = Vector2.new(1, 0)
    toggle.Position = UDim2.new(1, -20, 0, 20)
    toggle.Size = UDim2.fromOffset(90, 36)
    toggle.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    toggle.BorderSizePixel = 0
    toggle.Text = "DEBUG"
    toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.Parent = gui
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

    local panel = Instance.new("Frame")
    panel.Name = "DebugPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromOffset(760, 520)
    panel.BackgroundColor3 = Color3.fromRGB(15, 15, 19)
    panel.BorderSizePixel = 0
    panel.Visible = true
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 10)
    title.Size = UDim2.new(1, -210, 0, 34)
    title.Text = "SolarHub Debug"
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local copy = Instance.new("TextButton")
    copy.Size = UDim2.fromOffset(70, 30)
    copy.Position = UDim2.new(1, -150, 0, 12)
    copy.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    copy.BorderSizePixel = 0
    copy.Text = "COPY"
    copy.TextColor3 = Color3.fromRGB(255, 255, 255)
    copy.Font = Enum.Font.GothamBold
    copy.TextSize = 10
    copy.Parent = panel
    Instance.new("UICorner", copy).CornerRadius = UDim.new(0, 7)

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(60, 30)
    close.Position = UDim2.new(1, -72, 0, 12)
    close.BackgroundColor3 = Color3.fromRGB(70, 35, 35)
    close.BorderSizePixel = 0
    close.Text = "X"
    close.TextColor3 = Color3.fromRGB(255, 255, 255)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.Parent = panel
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 7)

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(14, 54)
    box.Size = UDim2.new(1, -28, 1, -68)
    box.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.MultiLine = true
    box.TextEditable = false
    box.TextWrapped = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Font = Enum.Font.Code
    box.TextSize = 12
    box.TextColor3 = Color3.fromRGB(225, 225, 230)
    box.Text = getDebugText()
    box.Parent = panel
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

    local function refresh()
        box.Text = getDebugText()
    end

    toggle.Activated:Connect(function()
        refresh()
        panel.Visible = not panel.Visible
    end)

    close.Activated:Connect(function()
        panel.Visible = false
    end)

    copy.Activated:Connect(function()
        refresh()

        local success = false

        if type(setclipboard) == "function" then
            success = pcall(function()
                setclipboard(box.Text)
            end)
        elseif type(toclipboard) == "function" then
            success = pcall(function()
                toclipboard(box.Text)
            end)
        end

        copy.Text = success and "COPIED" or "COPY FAIL"

        task.delay(1.2, function()
            if copy and copy.Parent then
                copy.Text = "COPY"
            end
        end)
    end)
end

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
    {
        Name = "Arcane Odyssey",
        GameId = 1180269832,
        -- Arcane Odyssey uses multiple places inside the same universe.
        -- Match the Universe/GameId so all supported Arcane places are allowed.
        PlaceIds = nil,
    },
}

-------------------------------------------------
-- GAME CHECK
-------------------------------------------------

local function getAllowedGame()
    local currentGameId = tonumber(game.GameId)
    local currentPlaceId = tonumber(game.PlaceId)

    for _, entry in ipairs(ALLOWED_GAMES) do
        local entryGameId = tonumber(entry.GameId)

        -- A nil PlaceIds means the whole Roblox universe is supported.
        if entryGameId and currentGameId == entryGameId then
            if entry.PlaceIds == nil then
                return entry
            end

            if entry.PlaceIds[currentPlaceId] == true then
                return entry
            end
        end

        -- Place-specific fallback.
        if entry.PlaceIds and entry.PlaceIds[currentPlaceId] == true then
            return entry
        end
    end

    return nil
end

local allowedGame = getAllowedGame()

if not allowedGame then
    debugLog("Loader version: " .. LOADER_VERSION)
    debugLog("SolarHub is not supported in this game/place.")
    debugLog("GameId (UniverseId): " .. tostring(game.GameId))
    debugLog("PlaceId: " .. tostring(game.PlaceId))

    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(
            game.PlaceId,
            Enum.InfoType.Asset
        )
    end)

    if ok and info then
        debugLog("PlaceName: " .. tostring(info.Name))
    else
        debugLog("PlaceName: <unavailable>")
    end

    showDebugUI()
    return
end

debugLog("Loader version: " .. LOADER_VERSION)
    debugLog("Supported game detected: " .. tostring(allowedGame.Name))
debugLog("GameId (UniverseId): " .. tostring(game.GameId))
debugLog("PlaceId: " .. tostring(game.PlaceId))

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
        player = Players.PlayerAdded:Wait()
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

    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(586, 304)
    card.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    card.BorderSizePixel = 0
    card.Parent = loadingGui

    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 190, 65)
    stroke.Transparency = 0.78
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
    icon.Position = UDim2.new(0.5, 0, 0, 72)
    icon.Size = UDim2.fromOffset(64, 48)
    icon.BackgroundTransparency = 1
    icon.Font = Enum.Font.GothamBlack
    icon.Text = "☀"
    icon.TextColor3 = Color3.fromRGB(255, 194, 70)
    icon.TextSize = 38
    icon.Parent = card

    local title = Instance.new("TextLabel")
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 122)
    title.Size = UDim2.fromOffset(420, 34)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "Loading Solar..."
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.TextSize = 24
    title.Parent = card

    loadingStatus = Instance.new("TextLabel")
    loadingStatus.AnchorPoint = Vector2.new(0.5, 0)
    loadingStatus.Position = UDim2.new(0.5, 0, 0, 164)
    loadingStatus.Size = UDim2.fromOffset(460, 24)
    loadingStatus.BackgroundTransparency = 1
    loadingStatus.Font = Enum.Font.Gotham
    loadingStatus.Text = "Preparing environment"
    loadingStatus.TextColor3 = Color3.fromRGB(145, 150, 165)
    loadingStatus.TextSize = 12
    loadingStatus.Parent = card

    loadingSpinner = Instance.new("TextLabel")
    loadingSpinner.AnchorPoint = Vector2.new(1, 0.5)
    loadingSpinner.Position = UDim2.new(1, -24, 0, 24)
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

    task.wait(0.35)

    local card = loadingGui:FindFirstChildWhichIsA("Frame")
    if card then
        local tween = TweenService:Create(
            card,
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
    
    local PREP_MIN_SECONDS = allowedGame.Name == "Arcane Odyssey" and 0.5 or 4
    local PREP_TIMEOUT_SECONDS = allowedGame.Name == "Arcane Odyssey" and 5 or 25

    local function isCurrentSession()
        if type(getgenv) ~= "function" then
            return true
        end

        local ok, current = pcall(function()
            return getgenv().SolarHubLoaderSession
        end)

        return not ok or current == nil or current == SESSION_ID
    end

    if not isCurrentSession() then
        return
    end
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

        -- Arcane Odyssey does not need the Anime Expeditions RemoteEvents/ReplicaClient.
        if allowedGame.Name == "Arcane Odyssey" then
            return loaded
                and player ~= nil
                and playerGui ~= nil
        end

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
    -- Fetch each module directly from the public GitHub repository.
    local moduleSources = {}

    local function fetchModule(fileName)
        local url = BASE_URL .. fileName .. "?v=" .. CACHE_BUST

        -- Arcane is fetched from an immutable commit ref so executors cannot
        -- accidentally reuse an older cached Arcane.lua from main.
        if fileName == "UI.lua"
            or fileName == "Arcane.lua"
            or fileName == "ArcaneMisc.lua"
            or fileName == "ArcaneFarming.lua" then
            url = "https://raw.githubusercontent.com/aboodpro/SolarHub/"
                .. ARCANE_SOURCE_REF
                .. "/"
                .. fileName
                .. "?v="
                .. CACHE_BUST
        end

        debugLog("Fetching " .. fileName .. " from GitHub")

        local ok, result = pcall(function()
            return game:HttpGet(url)
        end)

        if not ok then
            debugLog("Failed to fetch " .. fileName .. ": " .. tostring(result))
            return nil, "[Loader] Failed to fetch " .. fileName .. ": " .. tostring(result)
        end

        if type(result) ~= "string" or result == "" then
            return nil, "[Loader] Empty response for " .. fileName
        end

        return result, nil
    end

    local moduleLoadOrder

    if allowedGame.Name == "Arcane Odyssey" then
        moduleLoadOrder = {
            "UI.lua",
            "Arcane.lua",
            "ArcaneMisc.lua",
            "ArcaneFarming.lua",
        }
    else
        moduleLoadOrder = {
            "Shared.lua",
            "UI.lua",
            "Joiner.lua",
            "Macro.lua",
            "Webhook.lua",
        }
    end

    debugLog(
        "Module load order: "
            .. table.concat(moduleLoadOrder, ", ")
    )

    for _, fileName in ipairs(moduleLoadOrder) do
        setLoadingStatus("Loading " .. fileName .. "...")
        print("[Loader] Fetching " .. fileName .. "...")

        if not isCurrentSession() then
            debugLog("Loader session superseded; stopping old run.")
            return
        end

        local source, fetchError = fetchModule(fileName)

        if not source then
            setLoadingStatus(fileName .. " load error")
            warn(fetchError)
            debugLog(fetchError)
            showDebugUI()
            return
        end

        moduleSources[fileName] = source
    end

    -------------------------------------------------
    -- COMPILE / PREPARE
    -------------------------------------------------
    
    local function compile(fileName)
        local source = moduleSources[fileName]
        if not source then
            return nil, "[Loader] Missing collected source: " .. fileName
        end

        -- pcall(loadstring, source) returns (true, nil, compileError) when
        -- the source has a syntax/compile error. Keep that third return value.
        local ok, chunk, compileError = pcall(loadstring, source)
        if not ok then
            return nil, "[Loader] loadstring failed for " .. fileName .. ": " .. tostring(chunk)
        end

        if type(chunk) ~= "function" then
            return nil, "[Loader] COMPILE ERROR in " .. fileName .. ": " .. tostring(compileError)
        end

        return chunk, nil
    end

    setLoadingStatus("Compiling Solar modules...")
    print("[Loader] Compiling modules...")

    local compiled = {}

    for _, fileName in ipairs(moduleLoadOrder) do
        local label = fileName:gsub("%.lua$", "")
        local chunk, compileError = compile(fileName)

        if not chunk then
            setLoadingStatus(label .. " compile error")
            warn(compileError)
            debugLog(compileError)
            moduleSources = nil
            showDebugUI()
            return
        end

        compiled[label] = chunk
    end

        moduleSources = nil
    
    -------------------------------------------------
    -- LOAD / INIT
    -------------------------------------------------

    if not isCurrentSession() then
        debugLog("Loader session superseded before initialization.")
        return
    end

    
    local function runModule(label, fn)
        local capturedError = nil

        local ok, result = xpcall(fn, function(err)
            capturedError = debug.traceback(tostring(err), 2)

            local msg = "[Loader] " .. label .. " ERROR:\n" .. capturedError

            warn(msg)
            debugLog(msg)

            return capturedError
        end)

        if not ok then
            warn("[Loader] " .. label .. " failed; continuing where possible.")

            if allowedGame.Name == "Arcane Odyssey" then
                -- Arcane initialization errors used to collapse into the generic
                -- "Arcane failed to initialize" message. Keep the exact traceback
                -- visible so module-split regressions can be fixed from evidence.
                setLoadingStatus(label .. " failed - open DEBUG")
                showDebugUI()

                if capturedError then
                    print("========== SOLARHUB ARCANE INIT ERROR ==========")
                    print(capturedError)
                end
            end

            return nil
        end

        return result
    end
    
    local Shared

    -- Arcane Odyssey has a separate lightweight client context.
    -- Do not initialize the Anime Expeditions Shared module here.
    if allowedGame.Name == "Arcane Odyssey" then
        setLoadingStatus("Starting Arcane Odyssey...")
        print("[Loader] Building Arcane context...")

        local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

        Shared = {
            Players = Players,
            UserInputService = game:GetService("UserInputService"),
            HttpService = game:GetService("HttpService"),
            RunService = game:GetService("RunService"),
            ReplicatedStorage = game:GetService("ReplicatedStorage"),
            Lighting = game:GetService("Lighting"),
            player = player,
            playerGui = player:WaitForChild("PlayerGui"),
            Config = {
                ArcaneBossESP = false,
            },
            IsArcaneOdyssey = true,
        }
    else
        setLoadingStatus("Starting SolarHub...")
        print("[Loader] Loading Shared...")
        Shared = runModule("Shared", function()
            return compiled.Shared()
        end)

        if not Shared then
            return
        end
    end

    setLoadingStatus("Building interface...")
    print("[Loader] Loading UI...")
    local UI = runModule("UI.Init", function()
        local UIModule = compiled.UI()
        return UIModule.Init(Shared)
    end)

    if not UI then
        return
    end

    -- Arcane Odyssey uses only its dedicated feature module.
    if allowedGame.Name == "Arcane Odyssey" then
        setLoadingStatus("Starting Arcane Odyssey...")
        print("[Loader] Loading Arcane...")

        local Arcane = runModule("Arcane.Init", function()
            local ArcaneModule = compiled.Arcane()
            local ArcaneMiscModule = compiled.ArcaneMisc()
            local ArcaneFarmingModule = compiled.ArcaneFarming()

            -- Feature module chunks return module tables directly.
            -- Do not call ArcaneMiscModule/ArcaneFarmingModule as functions.
            return ArcaneModule.Init(Shared, UI, {
                Misc = ArcaneMiscModule,
                Farming = ArcaneFarmingModule,
            })
        end)

        if Arcane then
            setLoadingStatus("SolarHub ready")
        else
            setLoadingStatus("Arcane failed to initialize")
        end

        task.spawn(finishLoadingScreen)
        return
    end
    
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
        local macroInit = runModule("Macro.Init", function()
            local MacroModule = compiled.Macro()
            return MacroModule.Init(Shared, UI)
        end)
    
        if macroInit == true then
            setLoadingStatus("SolarHub ready")
        else
            setLoadingStatus("Macro failed to initialize")
        end

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
