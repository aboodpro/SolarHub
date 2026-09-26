--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = {}
Shared.Players = Players
Shared.UserInputService = UserInputService
Shared.HttpService = HttpService
Shared.RunService = RunService
Shared.ReplicatedStorage = ReplicatedStorage
Shared.Lighting = Lighting
Shared.player = player
Shared.playerGui = playerGui

local Config = {
    AutoRedeemCodes = true,
    DisableAutoJoiners = false,
    AutoJoinStory = false,
    SelectedMap = "School Grounds",
    SelectedAct = "Act 1",
    SelectedDifficulty = "Normal",
    StoryMatchMaking = false,
    AutoJoinRaid = false,
    SelectedRaidMap = "Spirit City",
    SelectedRaidAct = "Act 1",
    RaidMatchMaking = false,
    AutoJoinExpedition = false,
    SelectedExpeditionMap = "School Grounds",
    SelectedExpeditionDifficulty = "Difficulty 1",
    ExpeditionMatchMaking = false,
    AutoJoinChallenge = false,
    SelectedChallengeType = "Regular",
    ChallengeMatchMaking = false,
    AutoVoteStart = false,
    AutoSkipWave = false,
    AutoReplay = false,
    AutoNext = false,
    AutoReturnLobby = false,
    DeleteMap = false,
    BoostFPS = false,
    PlayMacro = false,
    RecordMacro = false,
    MacroIgnoreTiming = false,
    MacroRetry = 0,
    CurrentMacroName = "",
    WebhookURL = "",
    UnitSummoned = false,
    StageFinished = false,
    WalkAround = true,
    DisableAutoTeleportAFKChamber = true,
}
Shared.Config = Config

local savedMacros = {}
Shared.savedMacros = savedMacros
local MACRO_SAVE_FILE = "SolarHubMacros.json"

local function resolveInstanceByPath(path)
    if not path or path == "" then return nil end
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    local current: Instance? = game
    for i, part in ipairs(parts) do
        if i == 1 then continue end
        current = current and current:FindFirstChild(part)
        if not current then return nil end
    end
    return current
end
Shared.resolveInstanceByPath = resolveInstanceByPath

local function serializeArgValue(v)
    local t = typeof(v)
    if t == "Instance" then
        return { __type = "Instance", path = v:GetFullName() }
    elseif t == "CFrame" then
        return { __type = "CFrame", c = { v:GetComponents() } }
    elseif t == "Vector3" then
        return { __type = "Vector3", x = v.X, y = v.Y, z = v.Z }
    else
        return v
    end
end
Shared.serializeArgValue = serializeArgValue

local function deserializeArgValue(v)
    if typeof(v) == "table" and v.__type then
        if v.__type == "Instance" then
            return resolveInstanceByPath(v.path)
        elseif v.__type == "CFrame" then
            return CFrame.new(table.unpack(v.c))
        elseif v.__type == "Vector3" then
            return Vector3.new(v.x, v.y, v.z)
        end
    end
    return v
end
Shared.deserializeArgValue = deserializeArgValue

local function serializeMacros(sourceTable)
    sourceTable = sourceTable or savedMacros
    local out = {}
    for name, macro in pairs(sourceTable) do
        local actions = {}
        for _, action in ipairs(macro.actions) do
            local argsCopy = {}
            for i = 1, (action.args.n or #action.args) do
                argsCopy[i] = serializeArgValue(action.args[i])
            end
            table.insert(actions, {
                time = action.time,
                actionType = action.actionType,
                remotePath = action.remote and action.remote:GetFullName() or action.remotePath,
                remoteName = action.remoteName,
                remoteClass = action.remoteClass,
                method = action.method,
                args = argsCopy,
                argsN = action.args.n or #action.args,
                linkedPlacementOrder = action.linkedPlacementOrder,
                recordedUnitId = action.recordedUnitId,
                recordedPlacementReplicaId = action.recordedPlacementReplicaId,
                unitIdArgIndex = action.unitIdArgIndex,
                yenCost = action.yenCost,
                yenBefore = action.yenBefore,
                yenAfter = action.yenAfter,
                missingYenAtRecord = action.missingYenAtRecord,
                targetCFrame = action.targetCFrame and serializeArgValue(action.targetCFrame) or nil,
                targetUnitID = action.targetUnitID,
            })
        end
        out[name] = { actions = actions }
    end
    return out
end
Shared.serializeMacros = serializeMacros

local function saveMacrosToFile()
    if not writefile then return false end
    local ok = pcall(function()
        local encoded = HttpService:JSONEncode(serializeMacros())
        writefile(MACRO_SAVE_FILE, encoded)
    end)
    return ok
end
Shared.saveMacrosToFile = saveMacrosToFile

local function deserializeMacroActions(actions)
    local out = {}
    for _, a in ipairs(actions) do
        local argsCopy = {}
        for i = 1, (a.argsN or #a.args) do
            argsCopy[i] = deserializeArgValue(a.args[i])
        end
        argsCopy.n = a.argsN or #a.args
        table.insert(out, {
            time = a.time,
            actionType = a.actionType,
            remote = resolveInstanceByPath(a.remotePath),
            remotePath = a.remotePath,
            remoteName = a.remoteName,
            remoteClass = a.remoteClass,
            method = a.method,
            args = argsCopy,
            linkedPlacementOrder = a.linkedPlacementOrder,
            recordedUnitId = a.recordedUnitId,
            recordedPlacementReplicaId = a.recordedPlacementReplicaId,
            unitIdArgIndex = a.unitIdArgIndex,
            yenCost = a.yenCost,
            yenBefore = a.yenBefore,
            yenAfter = a.yenAfter,
            missingYenAtRecord = a.missingYenAtRecord,
            targetCFrame = a.targetCFrame and deserializeArgValue(a.targetCFrame) or nil,
            targetUnitID = a.targetUnitID,
        })
    end
    return out
end
Shared.deserializeMacroActions = deserializeMacroActions

local function loadMacrosFromFile()
    if not readfile or not isfile then return end
    local ok = pcall(function()
        if not isfile(MACRO_SAVE_FILE) then return end
        local raw = readfile(MACRO_SAVE_FILE)
        local decoded = HttpService:JSONDecode(raw)
        for name, macro in pairs(decoded) do
            savedMacros[name] = { actions = deserializeMacroActions(macro.actions) }
        end
    end)
    return ok
end
Shared.loadMacrosFromFile = loadMacrosFromFile
loadMacrosFromFile()

local sessionLog = {}
local function logLine(msg)
    table.insert(sessionLog, msg)
    print(msg)
end
Shared.logLine = logLine
Shared.resetSessionLog = function() sessionLog = {} end

local function copySessionLogToClipboard()
    local fullText = table.concat(sessionLog, "\n")
    local copied = false
    if setclipboard then
        copied = pcall(function() setclipboard(fullText) end)
    elseif toclipboard then
        copied = pcall(function() toclipboard(fullText) end)
    end
    return copied
end
Shared.copySessionLogToClipboard = copySessionLogToClipboard

local function showSessionLogWindow()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local existing = playerGui:FindFirstChild("SolarHubSessionLog")
    if existing then
        existing:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "SolarHubSessionLog"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147483647
    gui.Parent = playerGui

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromOffset(760, 500)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 190, 65)
    stroke.Transparency = 0.55
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 0, 38)
    title.Position = UDim2.fromOffset(14, 8)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "☀ SolarHub Session Log"
    title.TextColor3 = Color3.fromRGB(245, 245, 245)
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local close = Instance.new("TextButton")
    close.AnchorPoint = Vector2.new(1, 0)
    close.Position = UDim2.new(1, -12, 0, 10)
    close.Size = UDim2.fromOffset(32, 28)
    close.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    close.BorderSizePixel = 0
    close.Text = "×"
    close.TextColor3 = Color3.fromRGB(230, 230, 230)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 18
    close.Parent = frame
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 7)

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -28, 1, -86)
    box.Position = UDim2.fromOffset(14, 50)
    box.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    box.BorderSizePixel = 0
    box.TextColor3 = Color3.fromRGB(235, 235, 235)
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.TextWrapped = false
    box.MultiLine = true
    box.ClearTextOnFocus = false
    box.TextEditable = true
    box.Text = table.concat(sessionLog, "\n")
    box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -28, 0, 24)
    hint.Position = UDim2.new(0, 14, 1, -30)
    hint.BackgroundTransparency = 1
    hint.Font = Enum.Font.Gotham
    hint.Text = "Ctrl+A ثم Ctrl+C لنسخ اللوق"
    hint.TextColor3 = Color3.fromRGB(145, 150, 165)
    hint.TextSize = 11
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Parent = frame

    close.Activated:Connect(function()
        gui:Destroy()
    end)

    task.defer(function()
        box:CaptureFocus()
        box.CursorPosition = #box.Text + 1
        box.SelectionStart = 1
    end)

    return gui
end

Shared.showSessionLogWindow = showSessionLogWindow

-- Publish a direct executor command. Use both environments because different
-- executors isolate getgenv() and _G differently.
pcall(function()
    _G.SolarHub_ShowLog = showSessionLogWindow
end)

pcall(function()
    if type(getgenv) == "function" then
        local env = getgenv()
        env.SolarHub_ShowLog = showSessionLogWindow
        env.SolarHub = env.SolarHub or {}
        env.SolarHub.ShowLog = showSessionLogWindow
        env.SolarHub.Shared = Shared
    end
end)

local function showTopNotification(message, duration)
    duration = duration or 3
    logLine("[Notification] " .. message)
    local existing = playerGui:FindFirstChild("SolarNotification")
    if existing then existing:Destroy() end

    local notifGui = Instance.new("ScreenGui")
    notifGui.Name = "SolarNotification"
    notifGui.DisplayOrder = 1000000
    notifGui.Parent = playerGui

    local notifFrame = Instance.new("Frame")
    notifFrame.Size = UDim2.fromOffset(320, 40)
    notifFrame.Position = UDim2.new(1, -340, 0, 20)
    notifFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    notifFrame.BorderSizePixel = 0
    notifFrame.Parent = notifGui
    Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 1, 0)
    lbl.Position = UDim2.fromOffset(8, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = message
    lbl.TextColor3 = Color3.fromRGB(255, 200, 80)
    lbl.TextSize = 11
    lbl.TextWrapped = true
    lbl.Parent = notifFrame

    task.spawn(function()
        task.wait(duration)
        notifGui:Destroy()
    end)
end
Shared.showTopNotification = showTopNotification

local replicaClientModule = nil
pcall(function()
    replicaClientModule = require(ReplicatedStorage.Shared.ReplicaClient)
end)

local cachedGameReplica = nil
local function findGameReplica()
    local stillValid = false
    pcall(function()
        stillValid = cachedGameReplica ~= nil and cachedGameReplica.Data ~= nil and cachedGameReplica.Data.CurrentGameState ~= nil
    end)
    if stillValid then return cachedGameReplica end
    if not replicaClientModule or not replicaClientModule.FromId then return nil end
    for i = 1, 300 do
        local ok, replica = pcall(replicaClientModule.FromId, i)
        if ok and replica and replica.Data and replica.Data.CurrentGameState ~= nil then
            cachedGameReplica = replica
            return replica
        end
    end
    return nil
end

local function getWaveInfo()
    local ok, r1, r2, r3 = pcall(function()
        local replica = findGameReplica()
        if not replica or not replica.Data then return nil, nil, nil end
        return replica.Data.Wave, replica.Data.MaxWave, replica.Data.CurrentGameState
    end)
    if ok then return r1, r2, r3 end
    return nil, nil, nil
end
Shared.getWaveInfo = getWaveInfo

local cachedPlayerMatchReplica = nil
local function findPlayerMatchReplica()
    local stillValid = false
    pcall(function()
        stillValid = cachedPlayerMatchReplica ~= nil and cachedPlayerMatchReplica.Data ~= nil
            and cachedPlayerMatchReplica.Data.TotalUnitsPlaced ~= nil
    end)
    if stillValid then return cachedPlayerMatchReplica end
    if not replicaClientModule or not replicaClientModule.FromId then return nil end
    for i = 1, 300 do
        local ok, replica = pcall(replicaClientModule.FromId, i)
        if ok and replica and replica.Data and replica.Data.TotalUnitsPlaced ~= nil then
            cachedPlayerMatchReplica = replica
            return replica
        end
    end
    return nil
end

local function getCurrentYen()
    local ok, result = pcall(function()
        local replica = findPlayerMatchReplica()
        if not replica or not replica.Data then return nil end
        return replica.Data.Yen
    end)
    if ok then return result end
    return nil
end
Shared.getCurrentYen = getCurrentYen
-------------------------------------------------
-- DIRECT GAME REMOTES
-------------------------------------------------
local ReplicaSignal = ReplicatedStorage
    :WaitForChild("RemoteEvents")
    :WaitForChild("ReplicaSignal")

local function queueDataMatches(data, queueData)
    if type(data) ~= "table" or type(queueData) ~= "table" then
        return false
    end

    local score = 0
    for _, key in ipairs({"Gamemode", "MapName", "ActName", "Difficulty", "ChallengeType"}) do
        local expected = queueData[key]
        local actual = data[key]
        if expected ~= nil and actual ~= nil and tostring(expected) == tostring(actual) then
            score += 1
        end
    end

    return score >= 1
end

local function findQueueReplica(queueData)
    if not replicaClientModule or not replicaClientModule.FromId then
        return nil
    end

    -- Queue replica IDs are server-assigned and can change between sessions.
    -- Never hard-code the old 1062 ID.
    for id = 1, 2000 do
        local ok, replica = pcall(replicaClientModule.FromId, id)
        if ok and replica and replica.Data then
            local data = replica.Data
            local candidates = {
                data.QueueData,
                data.LocalQueueData,
                data,
            }

            for _, candidate in ipairs(candidates) do
                if queueData and queueDataMatches(candidate, queueData) then
                    return id
                end

                -- Play Macro may call StartGame without queue data. In that case
                -- use the active lobby queue replica rather than a hard-coded ID.
                if not queueData and type(candidate) == "table"
                    and (candidate.Gamemode ~= nil or candidate.MapName ~= nil or candidate.ActName ~= nil) then
                    return id
                end
            end
        end
    end

    return nil
end

local function startGameRemotely(queueData)
    local queueReplicaId = findQueueReplica(queueData or {})

    if not queueReplicaId then
        logLine("[GameRemote] No active queue replica found")
        return false
    end

    local ok, err = pcall(function()
        if queueData then
            ReplicaSignal:FireServer(queueReplicaId, "SetQueueData", queueData)
            task.wait(0.12)
        end

        ReplicaSignal:FireServer(queueReplicaId, "StartGame")
    end)

    if ok then
        logLine(("[GameRemote] StartGame -> queue replica %d"):format(queueReplicaId))
        return true
    end

    logLine("[GameRemote] StartGame failed: " .. tostring(err))
    return false
end
Shared.startGameRemotely = startGameRemotely



local pendingNewModels = {}
workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("Model") and inst.Parent and inst.Parent.Name == "Units" then
        table.insert(pendingNewModels, inst)
        if #pendingNewModels > 60 then
            table.remove(pendingNewModels, 1)
        end
    end
end)
Shared.clearPendingModels = function() table.clear(pendingNewModels) end

local function waitForNewModel(timeoutSeconds)
    local deadline = os.clock() + (timeoutSeconds or 2)
    while os.clock() < deadline do
        local m = table.remove(pendingNewModels)
        if m and m.Parent then return m end
        task.wait(0.05)
    end
    return nil
end
Shared.waitForNewModel = waitForNewModel

Shared.lastIncomingSignalValue = nil
task.spawn(function()
    pcall(function()
        local remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 5)
        local replicaSignalRemote = remoteEventsFolder and remoteEventsFolder:WaitForChild("ReplicaSignal", 5)
        if replicaSignalRemote then
            replicaSignalRemote.OnClientEvent:Connect(function(...)
                local args = {...}
                for _, a in ipairs(args) do
                    if typeof(a) == "number" or typeof(a) == "string" then
                        Shared.lastIncomingSignalValue = tostring(a)
                    end
                end
            end)
        end
    end)
end)

local function isRemoteValid(action)
    return action.remote ~= nil and action.remote.Parent ~= nil
end
Shared.isRemoteValid = isRemoteValid

Shared.isPlayingMacro = false
Shared.runMacroOnce = nil

-- Expose the live Shared table to an executor-side command so diagnostics can
-- be opened without reinitializing SolarHub.
pcall(function()
    local env = (getgenv and getgenv()) or _G
    env.SolarHub = env.SolarHub or {}
    env.SolarHub.Shared = Shared
end)

return Shared
