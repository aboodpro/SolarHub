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
    MatchMaking = false,
    AutoJoinStory = false,
    SelectedMap = "School Grounds",
    SelectedAct = "Act 1",
    SelectedDifficulty = "Normal",
    AutoJoinRaid = false,
    SelectedRaidMap = "Spirit City",
    SelectedRaidAct = "Act 1",
    AutoJoinExpedition = false,
    SelectedExpeditionMap = "School Grounds",
    SelectedExpeditionDifficulty = "Difficulty 1",
    AutoJoinChallenge = false,
    SelectedChallengeType = "Regular",
    AutoVoteStart = false,
    AutoSkipWave = false,
    AutoReplay = false,
    AutoNext = false,
    AutoReturnLobby = false,
    DeleteMap = false,
    BoostFPS = false,
    PlayMacro = false,
    RecordMacro = false,
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
        for _, action in ipairs(macro.actions or {}) do
            local argsCopy = {}
            local argCount = 0
            if action.args then
                argCount = action.args.n or #action.args
                for i = 1, argCount do
                    argsCopy[i] = serializeArgValue(action.args[i])
                end
            end

            table.insert(actions, {
                time = action.time,
                actionType = action.actionType,

                -- Keep both the old path format and the fields used by the player.
                remotePath = action.remote and action.remote:GetFullName() or action.remotePath,
                remoteName = action.remoteName,
                remoteClass = action.remoteClass,
                method = action.method,

                args = argsCopy,
                argsN = argCount,

                isUIReplay = action.isUIReplay,
                uiClickButtonName = action.uiClickButtonName,
                linkedPlacementOrder = action.linkedPlacementOrder,

                -- Yen belongs to the action that actually spends it (Upgrade),
                -- not to the Placement action.
                yenCost = action.yenCost,
                yenAtRecord = action.yenAtRecord,
                missingYen = action.missingYen,
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
    for _, a in ipairs(actions or {}) do
        local argsCopy = {}
        local argCount = a.argsN or (a.args and #a.args) or 0
        if a.args then
            for i = 1, argCount do
                argsCopy[i] = deserializeArgValue(a.args[i])
            end
        end
        argsCopy.n = argCount

        table.insert(out, {
            time = a.time,
            actionType = a.actionType,
            remote = resolveInstanceByPath(a.remotePath),
            remotePath = a.remotePath,
            remoteName = a.remoteName,
            remoteClass = a.remoteClass,
            method = a.method,
            args = argsCopy,
            isUIReplay = a.isUIReplay,
            uiClickButtonName = a.uiClickButtonName,
            linkedPlacementOrder = a.linkedPlacementOrder,
            yenCost = a.yenCost,
            yenAtRecord = a.yenAtRecord,
            missingYen = a.missingYen,
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

local function getPrompt(modeName: string)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and (obj.Parent.Name == modeName or obj.ObjectText == modeName) then
            return obj
        end
    end
    return nil
end
Shared.getPrompt = getPrompt

local function isInLobby()
    return getPrompt("Story") ~= nil or getPrompt("Raid") ~= nil or getPrompt("Challenge") ~= nil or getPrompt("Expedition") ~= nil
end
Shared.isInLobby = isInLobby

local function getBtn(desc)
    if not desc then return nil end
    if desc:IsA("TextButton") or desc:IsA("ImageButton") then return desc end
    return desc:FindFirstAncestorWhichIsA("TextButton") or desc:FindFirstAncestorWhichIsA("ImageButton")
end
Shared.getBtn = getBtn

local function clickElement(element)
    local targetBtn = getBtn(element)
    if not targetBtn then return end
    pcall(function()
        if firesignal then
            firesignal(targetBtn.MouseButton1Click)
            firesignal(targetBtn.MouseButton1Down)
            firesignal(targetBtn.MouseButton1Up)
            firesignal(targetBtn.Activated)
        elseif getconnections then
            for _, conn in ipairs(getconnections(targetBtn.MouseButton1Click)) do conn:Fire() end
            for _, conn in ipairs(getconnections(targetBtn.Activated)) do conn:Fire() end
        end
    end)
end
Shared.clickElement = clickElement

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

local function isUnitModelValid(model)
    return model ~= nil and model.Parent ~= nil and model:IsDescendantOf(workspace)
end
Shared.isUnitModelValid = isUnitModelValid

local SelectInstanceAction = nil
pcall(function()
    SelectInstanceAction = require(ReplicatedStorage.FusionPackage.Actions.SelectInstance)
end)

local function selectUnitModel(model)
    if not model or not model.Parent then
        showTopNotification("Upgrade failed: unit model not found", 3)
        return false
    end

    if SelectInstanceAction then
        local ok = pcall(function()
            if typeof(SelectInstanceAction) == "function" then
                SelectInstanceAction(model)
            elseif typeof(SelectInstanceAction) == "table" then
                if typeof(SelectInstanceAction.SelectInstance) == "function" then
                    SelectInstanceAction.SelectInstance(model)
                else
                    (SelectInstanceAction :: any)(model)
                end
            end
        end)
        if ok then
            logLine("[UnitSelect] Selected via SelectInstance action: " .. model:GetFullName())
            return true
        end
    end

    local detector = model:FindFirstChildWhichIsA("ClickDetector", true)
    if detector and fireclickdetector then
        local ok = pcall(function()
            fireclickdetector(detector)
        end)
        if ok then
            logLine("[UnitSelect] Selected via ClickDetector: " .. model:GetFullName())
            return true
        end
    end

    showTopNotification("Upgrade failed: could not select unit (no SelectInstance/ClickDetector)", 3)
    return false
end
Shared.selectUnitModel = selectUnitModel

local function findNestedText(instance)
    for _, d in ipairs(instance:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
            return d.Text
        end
    end
    return ""
end
Shared.findNestedText = findNestedText

local function findYenCostNear(instance)
    if not instance or not instance.Parent then return nil end
    for _, d in ipairs(instance.Parent:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local text = d.Text
            if text and text ~= "" then
                local numStr = text:match("¥%s*([%d,]+)")
                if numStr then
                    local num = tonumber((numStr:gsub(",", "")))
                    if num then return num end
                end
            end
        end
    end
    return nil
end
Shared.findYenCostNear = findYenCostNear

local function captureVisibleUpgradeCost()
    local exact = {}
    local fallback = {}

    local function readCostInside(button)
        local firstText = ""
        for _, d in ipairs(button:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
                if firstText == "" then firstText = d.Text end
                local numStr = d.Text:match("¥%s*([%d,]+)")
                if numStr then
                    return tonumber((numStr:gsub(",", ""))), firstText
                end
            end
        end
        return nil, firstText
    end

    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant:IsA("TextButton") and descendant.Visible then
            local selfText = descendant.Text or ""
            local nestedText = getNestedText and getNestedText(descendant) or ""
            local combined = (selfText .. " " .. nestedText):lower()
            local nameLower = descendant.Name:lower()

            local hasNormalUpgradeText = combined:find("upgrade") and not combined:find("auto")
            local exactName = nameLower == "upgradebutton" or nameLower == "upgrade"

            if exactName or hasNormalUpgradeText then
                local cost, innerText = readCostInside(descendant)

                if not cost and descendant.Parent then
                    -- Narrow fallback: inspect the immediate UI container, not the whole PlayerGui.
                    for _, sibling in ipairs(descendant.Parent:GetDescendants()) do
                        if sibling:IsA("TextLabel") or sibling:IsA("TextButton") then
                            local numStr = (sibling.Text or ""):match("¥%s*([%d,]+)")
                            if numStr then
                                cost = tonumber((numStr:gsub(",", "")))
                                break
                            end
                        end
                    end
                end

                local entry = {
                    button = descendant,
                    cost = cost,
                    text = selfText ~= "" and selfText or innerText,
                }

                if exactName then
                    table.insert(exact, entry)
                else
                    table.insert(fallback, entry)
                end
            end
        end
    end

    local candidates = (#exact > 0) and exact or fallback
    for _, entry in ipairs(candidates) do
        logLine(("[YenCapture] Upgrade button '%s' text='%s' cost=%s"):format(
            entry.button:GetFullName(), entry.text, tostring(entry.cost)))
        if entry.cost then
            return entry.cost
        end
    end

    logLine("[YenCapture] No normal Upgrade button/cost found")
    return nil
end
Shared.captureVisibleUpgradeCost = captureVisibleUpgradeCost

local function captureVisiblePlacementCost(slotNumber)
    if not slotNumber then
        logLine("[YenCapture] No slot number available for placement cost capture")
        return nil
    end
    local ok, result = pcall(function()
        local bottomHud = playerGui:FindFirstChild("BottomHUD")
        if not bottomHud then
            logLine("[YenCapture] BottomHUD not found")
            return nil
        end
        local candidates = {}
        for _, descendant in ipairs(bottomHud:GetDescendants()) do
            if descendant:IsA("TextButton") then
                local cost = nil
                for _, d in ipairs(descendant:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        local numStr = (d.Text or ""):match("¥%s*([%d,]+)")
                        if numStr then
                            cost = tonumber((numStr:gsub(",", "")))
                            break
                        end
                    end
                end
                cost = cost or findYenCostNear(descendant)
                if cost then
                    table.insert(candidates, { instance = descendant, cost = cost })
                end
            end
        end
        logLine(("[YenCapture] Placement: found %d priced hotbar slots, looking for slot %d"):format(#candidates, slotNumber))
        if candidates[slotNumber] then return candidates[slotNumber].cost end
        return nil
    end)
    if ok then return result end
    logLine("[YenCapture] Placement cost capture errored: " .. tostring(result))
    return nil
end
Shared.captureVisiblePlacementCost = captureVisiblePlacementCost

local function clickNamedUIButton(buttonName, isAutoUpgrade)
    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant.Name == buttonName and (descendant:IsA("TextButton") or descendant:IsA("ImageButton")) then
            logLine("[ButtonClick] Method 1 (exact Name) matched: " .. descendant:GetFullName())
            clickElement(descendant)
            return true
        end
    end

    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant:IsA("TextButton") then
            local text = descendant.Text:lower()
            if text ~= "" then
                if isAutoUpgrade then
                    if text:find("auto") and text:find("upgrade") then
                        logLine("[ButtonClick] Method 2 (own text) matched: " .. descendant:GetFullName())
                        clickElement(descendant)
                        return true
                    end
                else
                    if text:find("upgrade") and not text:find("auto") then
                        logLine("[ButtonClick] Method 2 (own text) matched: " .. descendant:GetFullName())
                        clickElement(descendant)
                        return true
                    end
                end
            end
        end
    end

    for _, descendant in ipairs(playerGui:GetDescendants()) do
        if descendant:IsA("TextButton") then
            local nested = findNestedText(descendant):lower()
            if nested ~= "" then
                if isAutoUpgrade then
                    if nested:find("auto") and nested:find("upgrade") then
                        logLine("[ButtonClick] Method 3 (nested text) matched: " .. descendant:GetFullName() .. " nested='" .. nested .. "'")
                        clickElement(descendant)
                        return true
                    end
                else
                    if nested:find("upgrade") and not nested:find("auto") then
                        logLine("[ButtonClick] Method 3 (nested text) matched: " .. descendant:GetFullName() .. " nested='" .. nested .. "'")
                        clickElement(descendant)
                        return true
                    end
                end
            end
        end
    end

    if isAutoUpgrade then
        for _, descendant in ipairs(playerGui:GetDescendants()) do
            if descendant:IsA("TextButton") then
                local nested = findNestedText(descendant):lower()
                if nested:find("upgrade") then
                    logLine("[ButtonClick] Method 4 (auto fallback to manual upgrade) matched: " .. descendant:GetFullName())
                    clickElement(descendant)
                    return true
                end
            end
        end
    end

    showTopNotification("Upgrade failed: button not found - check console for visible buttons dump", 4)
    pcall(function()
        logLine("========================================")
        logLine("[UpgradeButtonSearch] Looking for: " .. buttonName .. (isAutoUpgrade and " (auto)" or " (manual)"))
        local count = 0
        for _, descendant in ipairs(playerGui:GetDescendants()) do
            if descendant:IsA("TextButton") and descendant.Visible then
                count = count + 1
                local nested = findNestedText(descendant)
                logLine(("  [%d] Name=%s | Text=%s | NestedText=%s | Path=%s"):format(
                    count, descendant.Name, descendant.Text, nested, descendant:GetFullName()))
            end
        end
        if count == 0 then
            logLine("  (no visible TextButtons found at all - the unit selection UI may not have opened)")
        end
        logLine("========================================")
    end)
    return false
end
Shared.clickNamedUIButton = clickNamedUIButton

local function performUnitUIUpgrade(model, buttonName)
    if not selectUnitModel(model) then return false end
    task.wait(0.5)
    local isAutoUpgrade = buttonName == "AutoUpgradeButton"
    return clickNamedUIButton(buttonName, isAutoUpgrade)
end
Shared.performUnitUIUpgrade = performUnitUIUpgrade

Shared.isPlayingMacro = false
Shared.runMacroOnce = nil

return Shared
