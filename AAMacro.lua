-- AAMacro.lua
-- Dedicated Anime Adventures macro recorder/player.
-- Uses only the confirmed Anime Adventures remotes: vote_start, spawn_unit,
-- and upgrade_unit_ingame. Remotes are recorded from normal in-game UI calls;
-- playback reuses the captured unit type and position and resolves upgrades to
-- the newly spawned live Model instead of trying to reuse an old Instance path.

local AAMacro = {}

function AAMacro.Init(Shared, UI)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local HttpService = game:GetService("HttpService")
    local Config = Shared.Config or {}
    local player = Players.LocalPlayer
    local playerGui = player and player:WaitForChild("PlayerGui")
    local macroTab = UI and UI.tabs and UI.tabs["Macro"]

    if not player or not playerGui or not macroTab then
        error("[AAMacro] Required PlayerGui or Macro tab is missing.")
    end

    local oldPanel = macroTab:FindFirstChild("AnimeAdventuresMacroPanel")
    if oldPanel then oldPanel:Destroy() end

    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local clientToServer = endpoints and endpoints:FindFirstChild("client_to_server")
    if not clientToServer then
        error("[AAMacro] ReplicatedStorage.endpoints.client_to_server not found.")
    end

    -- Cache the exact confirmed remotes once. Comparing Instance references inside
    -- __namecall avoids nested IsA/IsDescendantOf calls while gameplay is active.
    local watchedSpawnRemote = clientToServer:FindFirstChild("spawn_unit")
    local watchedUpgradeRemote = clientToServer:FindFirstChild("upgrade_unit_ingame")
    local watchedVoteRemote = clientToServer:FindFirstChild("vote_start")
    local watchedRemotes = {}
    if watchedSpawnRemote then watchedRemotes[watchedSpawnRemote] = "spawn_unit" end
    if watchedUpgradeRemote then watchedRemotes[watchedUpgradeRemote] = "upgrade_unit_ingame" end
    if watchedVoteRemote then watchedRemotes[watchedVoteRemote] = "vote_start" end

    local FILE_NAME = "SolarHubAAMacros.json"
    local savedMacros = {}
    local selectedMacroName = nil
    local recording = false
    local playing = false
    local playToken = 0
    local recordStartedAt = 0
    local currentRecordedActions = {}
    local pendingCount = 0
    local nextPlacementOrder = 0
    local liveHookStatus = "not installed"
    local MAX_UNIT_WAIT = 10

    -- Use shared executor state so a previously installed hook can follow the
    -- current Macro UI after SolarHub is re-executed in the same client.
    local macroHookEnv = _G
    if type(getgenv) == "function" then
        local ok, executorEnv = pcall(getgenv)
        if ok and type(executorEnv) == "table" then macroHookEnv = executorEnv end
    end
    macroHookEnv.SolarHubAAMacroRecording = false
    if type(macroHookEnv.SolarHubAAMacroPendingCount) ~= "number" then
        macroHookEnv.SolarHubAAMacroPendingCount = 0
    end

    local function notify(message, duration)
        if type(Shared.showTopNotification) == "function" then
            pcall(Shared.showTopNotification, tostring(message), duration or 3)
        else
            print("[AAMacro] " .. tostring(message))
        end
    end

    local function log(message)
        local line = "[AAMacro] " .. tostring(message)
        if type(Shared.logLine) == "function" then
            pcall(Shared.logLine, line)
        else
            print(line)
        end
    end

    local function cframeToArray(cframe)
        if typeof(cframe) ~= "CFrame" then return nil end
        return { cframe:GetComponents() }
    end

    local function arrayToCFrame(values)
        if type(values) ~= "table" or #values < 12 then return nil end
        local ok, result = pcall(function()
            return CFrame.new(table.unpack(values, 1, 12))
        end)
        return ok and result or nil
    end

    local function getModelUnitType(model)
        if not model or not model:IsA("Model") then return nil end
        local stats = model:FindFirstChild("_stats")
        local uuid = stats and stats:FindFirstChild("uuid")
        if uuid and uuid:IsA("ValueBase") then
            return tostring(uuid.Value)
        end
        return nil
    end

    local function getSpawnUuid(model)
        return model and model:GetAttribute("_SPAWN_UNIT_UUID") or nil
    end

    local function getModelPivot(model)
        if not model or not model:IsA("Model") then return nil end
        local ok, pivot = pcall(function() return model:GetPivot() end)
        return ok and pivot or nil
    end

    local function getUnitModels()
        local folder = workspace:FindFirstChild("_UNITS")
        local out = {}
        if not folder then return out end

        -- Anime Adventures stores placed units as direct children of _UNITS.
        -- Avoid traversing every descendant of every unit during macro playback.
        for _, inst in ipairs(folder:GetChildren()) do
            if inst:IsA("Model") and getModelUnitType(inst) ~= nil then
                out[#out + 1] = inst
            end
        end
        return out
    end

    local function cframeDistance(a, b)
        if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then
            return math.huge
        end
        return (a.Position - b.Position).Magnitude
    end

    local function arrayPositionDistance(a, b)
        local cfA = arrayToCFrame(a)
        local cfB = arrayToCFrame(b)
        return cframeDistance(cfA, cfB)
    end

    local function findUnitNear(cframe, unitTypeUuid, beforeSet, maxDistance)
        if typeof(cframe) ~= "CFrame" then return nil end
        local best, bestDistance = nil, math.huge
        for _, model in ipairs(getUnitModels()) do
            if model.Parent and (not beforeSet or not beforeSet[model]) then
                local typeUuid = getModelUnitType(model)
                local typeMatches = unitTypeUuid == nil or typeUuid == tostring(unitTypeUuid)
                if typeMatches then
                    local pivot = getModelPivot(model)
                    if pivot then
                        local distance = cframeDistance(pivot, cframe)
                        if distance < bestDistance then
                            bestDistance, best = distance, model
                        end
                    end
                end
            end
        end
        if best and bestDistance <= (maxDistance or 10) then
            return best, bestDistance
        end
        return nil, bestDistance
    end

    local function waitForNewUnit(cframe, unitTypeUuid, beforeSet, timeout)
        local deadline = os.clock() + (timeout or MAX_UNIT_WAIT)
        while os.clock() < deadline do
            local model = findUnitNear(cframe, unitTypeUuid, beforeSet, 10)
            if model then return model end
            task.wait(0.1)
        end
        return nil
    end

    local function placementOrderForTarget(targetModel, targetCFrame, targetTypeUuid, targetSpawnUuid)
        -- Prefer the live spawn UUID if it was observed when a placement was recorded.
        if targetSpawnUuid ~= nil then
            for _, action in ipairs(currentRecordedActions) do
                if action.kind == "Place"
                    and action.spawnUnitUuid ~= nil
                    and tostring(action.spawnUnitUuid) == tostring(targetSpawnUuid) then
                    return action.placementOrder
                end
            end
        end

        local bestOrder, bestDistance = nil, math.huge
        for _, action in ipairs(currentRecordedActions) do
            if action.kind == "Place" then
                local sameType = targetTypeUuid == nil
                    or tostring(action.unitTypeUuid) == tostring(targetTypeUuid)
                local distance = arrayPositionDistance(action.cframe, cframeToArray(targetCFrame))
                if sameType and distance < bestDistance then
                    bestDistance = distance
                    bestOrder = action.placementOrder
                end
            end
        end

        if bestOrder and bestDistance <= 15 then return bestOrder end
        return nil
    end

    local function saveMacros()
        if type(writefile) ~= "function" then
            return false, "executor writefile unavailable; macro only kept in memory"
        end
        local ok, err = pcall(function()
            writefile(FILE_NAME, HttpService:JSONEncode(savedMacros))
        end)
        if not ok then return false, tostring(err) end
        return true
    end

    local function loadMacros()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        local ok, decoded = pcall(function()
            if not isfile(FILE_NAME) then return {} end
            return HttpService:JSONDecode(readfile(FILE_NAME))
        end)
        if not ok or type(decoded) ~= "table" then
            log("Could not load " .. FILE_NAME .. "; starting with an empty AA macro list.")
            return
        end
        for name, macro in pairs(decoded) do
            if type(name) == "string" and type(macro) == "table"
                and type(macro.actions) == "table" then
                savedMacros[name] = macro
            end
        end
    end

    local panel = Instance.new("Frame")
    panel.Name = "AnimeAdventuresMacroPanel"
    panel.Size = UDim2.new(1, 0, 0, 474)
    panel.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    panel.BorderSizePixel = 0
    panel.Parent = macroTab
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 9)

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -16, 0, 28)
    header.Position = UDim2.fromOffset(8, 5)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.Text = "Anime Adventures Macro"
    header.TextColor3 = Color3.fromRGB(245, 245, 250)
    header.TextSize = 14
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = panel

    local nameBox = Instance.new("TextBox")
    nameBox.Name = "MacroName"
    nameBox.Position = UDim2.fromOffset(8, 36)
    nameBox.Size = UDim2.new(0.62, -12, 0, 30)
    nameBox.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    nameBox.BorderSizePixel = 0
    nameBox.ClearTextOnFocus = false
    nameBox.PlaceholderText = "Macro name..."
    nameBox.Text = ""
    nameBox.Font = Enum.Font.Gotham
    nameBox.TextSize = 11
    nameBox.TextColor3 = Color3.fromRGB(240, 240, 245)
    nameBox.Parent = panel
    Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 6)

    local function makeButton(name, text, position, size, color)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Position = position
        button.Size = size
        button.BackgroundColor3 = color or Color3.fromRGB(50, 50, 62)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextSize = 10
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Text = text
        button.AutoButtonColor = true
        button.Parent = panel
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
        return button
    end

    local createButton = makeButton(
        "CreateMacro", "CREATE / SELECT",
        UDim2.new(0.62, 0, 0, 36), UDim2.new(0.38, -8, 0, 30),
        Color3.fromRGB(68, 92, 130)
    )

    local macroList = Instance.new("ScrollingFrame")
    macroList.Name = "SavedMacroList"
    macroList.Position = UDim2.fromOffset(8, 74)
    macroList.Size = UDim2.new(1, -16, 0, 93)
    macroList.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    macroList.BorderSizePixel = 0
    macroList.ScrollBarThickness = 3
    macroList.CanvasSize = UDim2.fromOffset(0, 0)
    macroList.Parent = panel
    Instance.new("UICorner", macroList).CornerRadius = UDim.new(0, 6)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 3)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = macroList
    listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        macroList.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 4)
    end)

    local function makePanelButton(name, text, position, size, color)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Position = position
        button.Size = size
        button.BackgroundColor3 = color or Color3.fromRGB(50, 50, 62)
        button.BorderSizePixel = 0
        button.Font = Enum.Font.GothamBold
        button.TextSize = 10
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.Text = text
        button.AutoButtonColor = true
        button.Parent = panel
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
        return button
    end

    local recordButton = makePanelButton(
        "RecordButton", "RECORD",
        UDim2.fromOffset(8, 176), UDim2.new(0.25, -6, 0, 32),
        Color3.fromRGB(140, 50, 50)
    )
    local playButton = makePanelButton(
        "PlayButton", "PLAY",
        UDim2.new(0.25, 4, 0, 176), UDim2.new(0.25, -6, 0, 32),
        Color3.fromRGB(45, 115, 70)
    )
    local stopButton = makePanelButton(
        "StopButton", "STOP",
        UDim2.new(0.5, 2, 0, 176), UDim2.new(0.25, -6, 0, 32),
        Color3.fromRGB(90, 90, 100)
    )
    local deleteButton = makePanelButton(
        "DeleteButton", "DELETE",
        UDim2.new(0.75, 0, 0, 176), UDim2.new(0.25, -8, 0, 32),
        Color3.fromRGB(100, 55, 55)
    )

    local timingButton = makePanelButton(
        "TimingButton", "○ IGNORE TIMING",
        UDim2.fromOffset(8, 214), UDim2.new(0.5, -12, 0, 27),
        Color3.fromRGB(50, 50, 62)
    )
    local copyLogButton = makePanelButton(
        "CopyLogButton", "COPY SESSION LOG",
        UDim2.new(0.5, 4, 0, 214), UDim2.new(0.5, -12, 0, 27),
        Color3.fromRGB(48, 72, 110)
    )

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Position = UDim2.fromOffset(8, 247)
    statusLabel.Size = UDim2.new(1, -16, 0, 40)
    statusLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    statusLabel.BorderSizePixel = 0
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextSize = 10
    statusLabel.TextWrapped = true
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Center
    statusLabel.TextColor3 = Color3.fromRGB(205, 220, 205)
    statusLabel.Text = "Ready. Create a macro, then record placement and upgrades."
    statusLabel.Parent = panel
    Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)

    local actionsLabel = Instance.new("TextLabel")
    actionsLabel.Name = "ActionSummary"
    actionsLabel.Position = UDim2.fromOffset(8, 293)
    actionsLabel.Size = UDim2.new(1, -16, 0, 172)
    actionsLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    actionsLabel.BorderSizePixel = 0
    actionsLabel.Font = Enum.Font.Code
    actionsLabel.TextSize = 10
    actionsLabel.TextWrapped = true
    actionsLabel.TextXAlignment = Enum.TextXAlignment.Left
    actionsLabel.TextYAlignment = Enum.TextYAlignment.Top
    actionsLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    actionsLabel.Text = "Selected macro actions will appear here."
    actionsLabel.Parent = panel
    Instance.new("UICorner", actionsLabel).CornerRadius = UDim.new(0, 6)

    local function actionSummary(macro)
        if not macro or type(macro.actions) ~= "table" or #macro.actions == 0 then
            return "No actions saved."
        end
        local out = {}
        for index, action in ipairs(macro.actions) do
            local desc
            if action.kind == "Place" then
                local cf = arrayToCFrame(action.cframe)
                local p = cf and cf.Position
                desc = ("Place #%d unit=%s at %s"):format(
                    tonumber(action.placementOrder) or index,
                    tostring(action.unitTypeUuid),
                    p and ("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z) or "unknown"
                )
            elseif action.kind == "Upgrade" then
                desc = ("Upgrade placement #%s (unit=%s)"):format(
                    tostring(action.targetPlacementOrder or "?"),
                    tostring(action.unitTypeUuid or "?")
                )
            elseif action.kind == "StartVote" then
                desc = "Vote to start"
            else
                desc = tostring(action.kind or "Unknown action")
            end
            out[#out + 1] = ("%02d. %s"):format(index, desc)
        end
        return table.concat(out, "\n")
    end

    local function refreshSelection()
        local macro
        if recording then
            macro = { actions = currentRecordedActions }
        elseif selectedMacroName then
            macro = savedMacros[selectedMacroName]
        end
        actionsLabel.Text = actionSummary(macro)
    end

    local function refreshMacroList()
        for _, child in ipairs(macroList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local names = {}
        for name in pairs(savedMacros) do names[#names + 1] = name end
        table.sort(names)
        for index, name in ipairs(names) do
            local macro = savedMacros[name]
            local button = Instance.new("TextButton")
            button.Name = "Macro_" .. index
            button.LayoutOrder = index
            button.Size = UDim2.new(1, -6, 0, 26)
            button.BackgroundColor3 = name == selectedMacroName
                and Color3.fromRGB(60, 88, 120)
                or Color3.fromRGB(35, 35, 44)
            button.BorderSizePixel = 0
            button.Font = Enum.Font.Gotham
            button.TextSize = 10
            button.TextColor3 = Color3.fromRGB(240, 240, 245)
            button.TextXAlignment = Enum.TextXAlignment.Left
            button.Text = ("  %s  |  %d actions"):format(name, #(macro.actions or {}))
            button.Parent = macroList
            Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
            button.Activated:Connect(function()
                if recording or playing then
                    notify("Stop recording/playback before selecting another macro.", 3)
                    return
                end
                selectedMacroName = name
                nameBox.Text = name
                refreshMacroList()
                refreshSelection()
                statusLabel.Text = "Selected: " .. name
            end)
        end
        macroList.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 4)
        refreshSelection()
    end

    local function saveCurrentMacro()
        if not selectedMacroName then return false end
        savedMacros[selectedMacroName] = { actions = currentRecordedActions }
        local ok, err = saveMacros()
        refreshMacroList()
        if not ok then
            statusLabel.Text = "Recorded in memory. Save error: " .. tostring(err)
            return false
        end
        return true
    end

    local function currentFolderSet()
        local set = {}
        local folder = workspace:FindFirstChild("_UNITS")
        if not folder then return set end
        -- This runs before spawn_unit is sent to the server, so keep it O(unit count)
        -- over direct children rather than walking the full descendant tree.
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                set[model] = true
            end
        end
        return set
    end

    local function findPlacementOrderByModel(model, pivot, unitTypeUuid)
        local spawnUuid = getSpawnUuid(model)
        local order = placementOrderForTarget(model, pivot, unitTypeUuid, spawnUuid)
        if order then return order end

        -- Fallback to distance and matching unit type when the runtime UUID has
        -- not yet been captured for a placement.
        local bestOrder, bestDistance = nil, math.huge
        for _, action in ipairs(currentRecordedActions) do
            if action.kind == "Place" then
                local sameType = unitTypeUuid == nil
                    or tostring(action.unitTypeUuid) == tostring(unitTypeUuid)
                local distance = arrayPositionDistance(action.cframe, cframeToArray(pivot))
                if sameType and distance < bestDistance then
                    bestOrder, bestDistance = action.placementOrder, distance
                end
            end
        end
        if bestOrder and bestDistance <= 15 then return bestOrder end
        return nil
    end

    local function onObservedRemote(remote, args, beforeSet)
        if not recording then return end
        if not remote or not remote.Parent then return end
        local remoteName = remote.Name

        if remoteName == "vote_start" then
            currentRecordedActions[#currentRecordedActions + 1] = {
                kind = "StartVote",
                time = os.clock() - recordStartedAt,
            }
            statusLabel.Text = ("Recording: captured vote_start (%d actions)"):format(#currentRecordedActions)
            refreshSelection()
            return
        end

        if remoteName == "spawn_unit" then
            local unitTypeUuid = args[1]
            local placementCFrame = args[2]
            if type(unitTypeUuid) ~= "string" or typeof(placementCFrame) ~= "CFrame" then
                log("Ignored spawn_unit because its arguments did not match the confirmed signature.")
                return
            end

            nextPlacementOrder += 1
            local action = {
                kind = "Place",
                time = os.clock() - recordStartedAt,
                unitTypeUuid = unitTypeUuid,
                cframe = cframeToArray(placementCFrame),
                placementOrder = nextPlacementOrder,
            }
            currentRecordedActions[#currentRecordedActions + 1] = action

            -- Resolve this placement asynchronously against the pre-call snapshot,
            -- so a nearby older copy of the same unit type cannot be mistaken for
            -- the newly placed instance.
            if beforeSet then
                task.spawn(function()
                    local model = waitForNewUnit(placementCFrame, unitTypeUuid, beforeSet, 4)
                    if model and model.Parent then
                        action.spawnUnitUuid = getSpawnUuid(model)
                        refreshSelection()
                        log(("Placement #%d session UUID resolved as %s"):format(
                            action.placementOrder, tostring(action.spawnUnitUuid)
                        ))
                    end
                end)
            end

            statusLabel.Text = ("Recording: placed unit #%d (%d actions)"):format(
                nextPlacementOrder, #currentRecordedActions
            )
            log(("Recorded placement #%d, unit type %s"):format(nextPlacementOrder, unitTypeUuid))
            refreshSelection()
            return
        end

        if remoteName == "upgrade_unit_ingame" then
            local target = args[1]
            if typeof(target) ~= "Instance" or not target:IsA("Model") then
                log("Ignored upgrade_unit_ingame because arg #1 was not a Model.")
                return
            end

            local pivot = getModelPivot(target)
            local unitTypeUuid = getModelUnitType(target)
            local targetOrder = findPlacementOrderByModel(target, pivot, unitTypeUuid)

            local action = {
                kind = "Upgrade",
                time = os.clock() - recordStartedAt,
                targetPlacementOrder = targetOrder,
                targetCFrame = cframeToArray(pivot),
                unitTypeUuid = unitTypeUuid,
                targetSpawnUnitUuid = getSpawnUuid(target),
            }
            currentRecordedActions[#currentRecordedActions + 1] = action
            statusLabel.Text = targetOrder
                and ("Recording: upgrade linked to placement #%d"):format(targetOrder)
                or "Recording: upgrade captured, but target link is unresolved."
            log(("Recorded upgrade: target placement #%s, spawn UUID %s"):format(
                tostring(targetOrder), tostring(action.targetSpawnUnitUuid)
            ))
            refreshSelection()
            return
        end
    end

    local function enqueueObservedRemote(remote, args, beforeSet)
        macroHookEnv.SolarHubAAMacroPendingCount =
            (tonumber(macroHookEnv.SolarHubAAMacroPendingCount) or 0) + 1

        local scheduled = pcall(function()
            task.defer(function()
                -- All UI updates, model lookups, and action linking happen after the
                -- real game remote has returned to AA's caller.
                pcall(onObservedRemote, remote, args, beforeSet)

                macroHookEnv.SolarHubAAMacroPendingCount = math.max(
                    0,
                    (tonumber(macroHookEnv.SolarHubAAMacroPendingCount) or 1) - 1
                )
            end)
        end)

        if not scheduled then
            macroHookEnv.SolarHubAAMacroPendingCount = math.max(
                0,
                (tonumber(macroHookEnv.SolarHubAAMacroPendingCount) or 1) - 1
            )
        end
    end

    local function stopRecordingCapture()
        -- Disable new captures first, then let already-started InvokeServer calls
        -- finish their deferred recording work before saving the macro.
        macroHookEnv.SolarHubAAMacroRecording = false
        Config.RecordMacro = false

        local drainDeadline = os.clock() + 10
        while (tonumber(macroHookEnv.SolarHubAAMacroPendingCount) or 0) > 0
            and os.clock() < drainDeadline do
            task.wait(0.025)
        end

        recording = false
    end

    local function installRecordingHook()
        local env = macroHookEnv
        env.SolarHubAAMacroLogger = enqueueObservedRemote
        if env.SolarHubAAMacroHookInstalled == true then
            liveHookStatus = "existing hook reused"
            return true
        end

        if type(hookmetamethod) ~= "function"
            or type(getnamecallmethod) ~= "function"
            or type(checkcaller) ~= "function" then
            liveHookStatus = "executor hook API unavailable"
            return false
        end

        local ok, err = pcall(function()
            local oldNamecall
            local hookInternalWork = false
            local wrapper = function(self, ...)
                -- Recorder-side workspace lookups call Instance methods too. Bypass
                -- interception during those internal lookups to avoid re-entering
                -- this recorder hook. Actual game remote calls still pass through.
                -- The hook cannot be uninstalled safely, so keep its idle path extremely
                -- cheap. The previous version called checkcaller() and packed arguments
                -- for every __namecall in the game, even after recording had stopped.
                if hookInternalWork or env.SolarHubAAMacroRecording ~= true then
                    return oldNamecall(self, ...)
                end

                local method = getnamecallmethod()
                if method ~= "InvokeServer" then
                    return oldNamecall(self, ...)
                end

                if typeof(self) ~= "Instance" then
                    return oldNamecall(self, ...)
                end

                local remoteName = watchedRemotes[self]
                if not remoteName then
                    return oldNamecall(self, ...)
                end

                local callerOk, executorCaller = pcall(checkcaller)
                if not callerOk or executorCaller then
                    return oldNamecall(self, ...)
                end

                local args = table.pack(...)
                local beforeSet = nil
                if self == watchedSpawnRemote then
                    hookInternalWork = true
                    pcall(function()
                        beforeSet = currentFolderSet()
                    end)
                    hookInternalWork = false
                end

                -- Preserve the original game remote invocation and its return values.
                local result = table.pack(oldNamecall(self, ...))

                -- The logger exposed through the executor env is intentionally a
                -- lightweight queue function. This preserves compatibility with a hook
                -- installed by an earlier AAMacro initialization while keeping the
                -- original AA InvokeServer result unchanged.
                local logger = env.SolarHubAAMacroLogger
                if type(logger) == "function" then
                    hookInternalWork = true
                    pcall(logger, self, args, beforeSet)
                    hookInternalWork = false
                end

                return table.unpack(result, 1, result.n)
            end

            local closure = type(newcclosure) == "function" and newcclosure(wrapper) or wrapper
            oldNamecall = hookmetamethod(game, "__namecall", closure)
            if type(oldNamecall) ~= "function" then
                error("hookmetamethod did not return the original namecall method")
            end
        end)

        if not ok then
            liveHookStatus = "hook install failed: " .. tostring(err)
            log(liveHookStatus)
            return false
        end

        env.SolarHubAAMacroHookInstalled = true
        liveHookStatus = "installed"
        log("Recording hook installed for vote_start, spawn_unit, upgrade_unit_ingame.")
        return true
    end

    local function waitForRecordedTime(startTime, actionTime, token)
        if Config.MacroIgnoreTiming == true then return true end
        local target = startTime + (tonumber(actionTime) or 0)
        while playing and playToken == token and os.clock() < target do
            task.wait(math.min(0.1, target - os.clock()))
        end
        return playing and playToken == token
    end

    local function getRemote(name)
        local remote = clientToServer:FindFirstChild(name)
        if remote and remote:IsA("RemoteFunction") then return remote end
        return nil
    end

    local function playSelectedMacro()
        if recording then
            notify("Stop recording before playback.", 3)
            return
        end
        if playing then
            notify("A macro is already playing.", 3)
            return
        end
        if not selectedMacroName or not savedMacros[selectedMacroName] then
            notify("Create or select a macro first.", 3)
            return
        end

        local macro = savedMacros[selectedMacroName]
        local actions = macro.actions
        if type(actions) ~= "table" or #actions == 0 then
            notify("This macro has no recorded actions.", 3)
            return
        end

        local spawnRemote = getRemote("spawn_unit")
        local upgradeRemote = getRemote("upgrade_unit_ingame")
        local startRemote = getRemote("vote_start")
        if not spawnRemote or not upgradeRemote then
            notify("Anime Adventures remotes are missing.", 4)
            return
        end

        playToken += 1
        local myToken = playToken
        playing = true
        local playbackStart = os.clock()
        local playbackUnitByPlacementOrder = {}
        local placementCount = 0
        statusLabel.Text = "Playback started..."
        log(("Playback started: %s (%d actions)"):format(selectedMacroName, #actions))

        task.spawn(function()
            for index, action in ipairs(actions) do
                if not playing or playToken ~= myToken then break end
                if not waitForRecordedTime(playbackStart, action.time, myToken) then break end

                if action.kind == "StartVote" then
                    if startRemote then
                        local ok, result = pcall(function()
                            return startRemote:InvokeServer()
                        end)
                        statusLabel.Text = ok and ("[%d/%d] vote_start sent"):format(index, #actions)
                            or ("[%d/%d] vote_start failed: %s"):format(index, #actions, tostring(result))
                    else
                        statusLabel.Text = "vote_start remote unavailable."
                    end

                elseif action.kind == "Place" then
                    placementCount += 1
                    local targetCFrame = arrayToCFrame(action.cframe)
                    if not targetCFrame or type(action.unitTypeUuid) ~= "string" then
                        statusLabel.Text = ("[%d/%d] Invalid placement data; skipped."):format(index, #actions)
                    else
                        local beforeSet = currentFolderSet()
                        local ok, result = pcall(function()
                            return spawnRemote:InvokeServer(action.unitTypeUuid, targetCFrame)
                        end)
                        if not ok then
                            statusLabel.Text = ("[%d/%d] spawn_unit error: %s"):format(index, #actions, tostring(result))
                            log(statusLabel.Text)
                        else
                            local model = waitForNewUnit(targetCFrame, action.unitTypeUuid, beforeSet, MAX_UNIT_WAIT)
                            if model then
                                playbackUnitByPlacementOrder[tonumber(action.placementOrder) or placementCount] = model
                                statusLabel.Text = ("[%d/%d] Placed #%d (%s)"):format(
                                    index, #actions, tonumber(action.placementOrder) or placementCount, model.Name
                                )
                                log(("Playback placement #%s resolved to %s at %s"):format(
                                    tostring(action.placementOrder), model:GetFullName(),
                                    tostring(getModelPivot(model) and getModelPivot(model).Position or "unknown")
                                ))
                            else
                                statusLabel.Text = ("[%d/%d] Spawn sent, but model wasn't found near saved position."):format(index, #actions)
                                log(statusLabel.Text)
                            end
                        end
                    end

                elseif action.kind == "Upgrade" then
                    local placementOrder = tonumber(action.targetPlacementOrder)
                    local target = placementOrder and playbackUnitByPlacementOrder[placementOrder] or nil

                    if not target or not target.Parent then
                        -- Fallback is tightly constrained by saved type + placement position.
                        local targetCFrame = arrayToCFrame(action.targetCFrame)
                        if targetCFrame then
                            target = findUnitNear(targetCFrame, action.unitTypeUuid, nil, 10)
                        end
                    end

                    if target and target.Parent then
                        local ok, result = pcall(function()
                            return upgradeRemote:InvokeServer(target)
                        end)
                        statusLabel.Text = ok
                            and ("[%d/%d] Upgraded placement #%s"):format(index, #actions, tostring(placementOrder or "?"))
                            or ("[%d/%d] Upgrade failed: %s"):format(index, #actions, tostring(result))
                        log(statusLabel.Text)
                    else
                        statusLabel.Text = ("[%d/%d] Could not resolve target placement #%s; upgrade skipped."):format(
                            index, #actions, tostring(placementOrder or "?")
                        )
                        log(statusLabel.Text)
                    end
                else
                    statusLabel.Text = ("[%d/%d] Unsupported action: %s"):format(index, #actions, tostring(action.kind))
                end
                refreshSelection()
                task.wait(0.05)
            end

            if playToken == myToken then
                playing = false
                statusLabel.Text = "Playback finished."
                notify("Macro playback finished.", 3)
                log("Playback finished.")
            end
        end)
    end

    createButton.Activated:Connect(function()
        if recording or playing then
            notify("Stop recording/playback first.", 3)
            return
        end
        local name = tostring(nameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            notify("Enter a macro name.", 3)
            return
        end
        if not savedMacros[name] then
            savedMacros[name] = { actions = {} }
            local ok, err = saveMacros()
            if not ok then
                statusLabel.Text = "Macro created in memory; persistent save unavailable: " .. tostring(err)
            else
                statusLabel.Text = "Created macro: " .. name
            end
        else
            statusLabel.Text = "Selected existing macro: " .. name
        end
        selectedMacroName = name
        refreshMacroList()
        notify("Selected macro: " .. name, 3)
    end)

    recordButton.Activated:Connect(function()
        if playing then
            notify("Stop playback before recording.", 3)
            return
        end
        if not recording then
            if not selectedMacroName then
                notify("Create or select a macro first.", 3)
                return
            end
            if not installRecordingHook() then
                notify("Recording hook unavailable: " .. liveHookStatus, 4)
                return
            end
            currentRecordedActions = {}
            nextPlacementOrder = 0
            recordStartedAt = os.clock()
            recording = true
            macroHookEnv.SolarHubAAMacroRecording = true
            Config.RecordMacro = true
            recordButton.Text = "STOP RECORDING"
            recordButton.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
            statusLabel.Text = "Recording. Use the normal in-game UI to place/upgrade units."
            log("Recording started: " .. selectedMacroName)
        else
            stopRecordingCapture()
            recordButton.Text = "RECORD"
            recordButton.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
            savedMacros[selectedMacroName] = { actions = currentRecordedActions }
            local ok, err = saveMacros()
            refreshMacroList()
            if ok then
                statusLabel.Text = ("Saved %d action(s) to %s."):format(#currentRecordedActions, selectedMacroName)
                notify("Saved " .. #currentRecordedActions .. " macro actions.", 3)
            else
                statusLabel.Text = ("Captured %d action(s) in memory; save error: %s"):format(#currentRecordedActions, tostring(err))
                notify("Recording stopped; persistent save unavailable.", 4)
            end
            log(("Recording stopped: %d actions saved to %s"):format(#currentRecordedActions, selectedMacroName))
        end
        refreshSelection()
    end)

    playButton.Activated:Connect(playSelectedMacro)

    stopButton.Activated:Connect(function()
        if recording then
            stopRecordingCapture()
            recordButton.Text = "RECORD"
            recordButton.BackgroundColor3 = Color3.fromRGB(140, 50, 50)
            if selectedMacroName then
                savedMacros[selectedMacroName] = { actions = currentRecordedActions }
                saveMacros()
            end
            refreshMacroList()
            statusLabel.Text = "Recording stopped and saved."
            return
        end
        if playing then
            playing = false
            playToken += 1
            statusLabel.Text = "Playback stop requested."
            log("Playback stop requested by user.")
        else
            statusLabel.Text = "Nothing is running."
        end
    end)

    deleteButton.Activated:Connect(function()
        if recording or playing then
            notify("Stop recording/playback before deleting.", 3)
            return
        end
        if not selectedMacroName or not savedMacros[selectedMacroName] then
            notify("Select a macro to delete.", 3)
            return
        end
        local deletedName = selectedMacroName
        savedMacros[deletedName] = nil
        selectedMacroName = nil
        nameBox.Text = ""
        local ok = saveMacros()
        refreshMacroList()
        statusLabel.Text = ok and ("Deleted " .. deletedName) or ("Deleted in memory: " .. deletedName)
    end)

    timingButton.Activated:Connect(function()
        Config.MacroIgnoreTiming = not (Config.MacroIgnoreTiming == true)
        timingButton.Text = (Config.MacroIgnoreTiming and "✓ IGNORE TIMING" or "○ IGNORE TIMING")
        timingButton.BackgroundColor3 = Config.MacroIgnoreTiming
            and Color3.fromRGB(40, 140, 75)
            or Color3.fromRGB(50, 50, 62)
    end)

    copyLogButton.Activated:Connect(function()
        local copied = false
        if type(Shared.copySessionLogToClipboard) == "function" then
            copied = Shared.copySessionLogToClipboard()
        end
        if copied then
            statusLabel.Text = "Session log copied to clipboard."
        else
            statusLabel.Text = "Clipboard unavailable. See executor console."
        end
    end)

    loadMacros()
    refreshMacroList()
    timingButton.Text = (Config.MacroIgnoreTiming and "✓ IGNORE TIMING" or "○ IGNORE TIMING")
    timingButton.BackgroundColor3 = Config.MacroIgnoreTiming
        and Color3.fromRGB(40, 140, 75)
        or Color3.fromRGB(50, 50, 62)

    if Config.MacroDebug == true then
        log("Initialized; hook APIs are installed lazily when Record is pressed.")
    end
    return true
end

return AAMacro
