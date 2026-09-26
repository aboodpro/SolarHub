--!strict
local Macro = {}

function Macro.Init(Shared, UI)
    local Config = Shared.Config
    local savedMacros = Shared.savedMacros
    local saveMacrosToFile = Shared.saveMacrosToFile
    local showTopNotification = Shared.showTopNotification
    local HttpService = Shared.HttpService
    local getCurrentYen = Shared.getCurrentYen

    local tabs = UI.tabs or {}
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local macroTab = tabs["Macro"]

    -- Some executors/VMs can expose the returned UI table differently even
    -- though the actual MacroTab ScrollingFrame exists. Resolve it directly
    -- as a fallback so Macro.Init does not silently return nil.
    if not macroTab and UI.screenGui then
        pcall(function()
            for _, descendant in ipairs(UI.screenGui:GetDescendants()) do
                if descendant:IsA("ScrollingFrame") and descendant.Name == "MacroTab" then
                    macroTab = descendant
                    break
                end
            end
        end)
    end

    if not macroTab then
        error("[Macro] Macro tab container is missing (UI.tabs[Macro] and MacroTab fallback both failed).")
    end

    -- Reset the tab whenever Macro initializes so a previous UI state cannot
    -- leave the content scrolled outside the visible area.
    macroTab.CanvasPosition = Vector2.zero
    macroTab.Visible = true

    local recordedActions = {}
    local recordStartTime = 0
    local recordActionSequence = 0
    local recordPlacementCount = 0
    local recordUnitIdMap = {}
    local recordedUnitToPlacementOrder = {}
    local recordedPlacementCFrames = {}
    local pendingRecordWorkers = 0
    local scannedUnitsDatabase = {}

    local replicaClientModule = nil

    -- Resolve ReplicaClient lazily and defensively. Some game revisions/executors
    -- expose the module later, so requiring it during module fetch can break the
    -- entire Macro chunk before Init() has a chance to build the UI.
    local function getReplicaClient()
        if replicaClientModule then
            return replicaClientModule
        end

        local ok, result = pcall(function()
            local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
            local module = sharedFolder and sharedFolder:FindFirstChild("ReplicaClient")
            if not module or not module:IsA("ModuleScript") then
                return nil
            end
            return require(module)
        end)

        if ok and result and type(result.FromId) == "function" then
            replicaClientModule = result
        end

        return replicaClientModule
    end

    local function getReplicaDataById(unitId, timeoutSeconds)
        local numericId = tonumber(unitId)
        local deadline = os.clock() + (timeoutSeconds or 0)
        local replicaClient = getReplicaClient()

        if not numericId or not replicaClient or type(replicaClient.FromId) ~= "function" then
            return nil
        end

        repeat
            local ok, replica = pcall(replicaClient.FromId, numericId)
            if ok and replica and replica.Data then
                return replica.Data
            end
            if (timeoutSeconds or 0) <= 0 then
                break
            end
            task.wait(0.05)
        until os.clock() >= deadline

        return nil
    end

    local function getPlayerReplica()
        local replicaClient = getReplicaClient()
        if not replicaClient or type(replicaClient.FromId) ~= "function" then
            return nil
        end

        for id = 1, 300 do
            local ok, replica = pcall(replicaClient.FromId, id)
            if ok and replica and replica.Data and replica.Data.TotalUnitsPlaced ~= nil then
                return replica
            end
        end

        return nil
    end

    local function getOwnedGameUnitReplicas()
        local out = {}
        local playerReplica = getPlayerReplica()
        local playerId = playerReplica and playerReplica.Data
            and tostring(playerReplica.Data.ID or "")
            or ""

        local replicaClient = getReplicaClient()
        if not replicaClient or type(replicaClient.FromId) ~= "function" then
            return out
        end

        for id = 1, 3000 do
            local ok, replica = pcall(replicaClient.FromId, id)
            if ok and replica and replica.Data then
                local data = replica.Data
                if data.CFrame ~= nil and data.UnitID ~= nil then
                    local ownerId = tostring(data.GamePlayerID or "")
                    -- Prefer explicit ownership, but keep replicas without an
                    -- owner field too; some game versions populate ownership
                    -- slightly after the unit replica itself.
                    if playerId == "" or ownerId == ""
                        or ownerId == playerId then
                        out[tostring(id)] = replica
                    end
                end
            end
        end

        return out
    end

    local function snapshotOwnedGameUnits()
        local snapshot = {}
        for id in pairs(getOwnedGameUnitReplicas()) do
            snapshot[id] = true
        end
        return snapshot
    end

    local function resolveRecordedPlacementOrder(recordedUnitId)
        local replicaId = tonumber(recordedUnitId)
        local replicaClient = getReplicaClient()
        if not replicaId or not replicaClient or type(replicaClient.FromId) ~= "function" then
            return nil
        end

        local ok, replica = pcall(replicaClient.FromId, replicaId)
        if not ok or not replica or not replica.Data or typeof(replica.Data.CFrame) ~= "CFrame" then
            return nil
        end

        local targetPosition = replica.Data.CFrame.Position
        local bestOrder = nil
        local bestDistance = math.huge

        for order, placementCFrame in pairs(recordedPlacementCFrames) do
            if typeof(placementCFrame) == "CFrame" then
                local distance = (placementCFrame.Position - targetPosition).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestOrder = order
                end
            end
        end

        if bestOrder and bestDistance <= 8 then
            return bestOrder
        end

        return nil
    end

    local function findNewUnitReplicaId(beforeIds, placementCFrame, timeoutSeconds)
        local deadline = os.clock() + (timeoutSeconds or 3)
        local bestId = nil
        local bestDistance = math.huge

        while os.clock() < deadline do
            local candidates = getOwnedGameUnitReplicas()

            for id, replica in pairs(candidates) do
                if not beforeIds[id] and replica and replica.Data then
                    local cframe = replica.Data.CFrame
                    local distance = math.huge

                    if typeof(placementCFrame) == "CFrame" and typeof(cframe) == "CFrame" then
                        distance = (cframe.Position - placementCFrame.Position).Magnitude
                    end

                    if distance < bestDistance then
                        bestDistance = distance
                        bestId = id
                    end
                end
            end

            if bestId and (typeof(placementCFrame) ~= "CFrame" or bestDistance <= 10) then
                return bestId
            end

            task.wait(0.05)
        end

        return bestId
    end

    local function waitForNewPlacementReplica(beforeIds, placementCFrame, timeoutSeconds)
        local deadline = os.clock() + (timeoutSeconds or 12)

        while os.clock() < deadline do
            local candidates = getOwnedGameUnitReplicas()
            local bestId = nil
            local bestDistance = math.huge

            for id, replica in pairs(candidates) do
                if not beforeIds[id] and replica and replica.Data then
                    local cframe = replica.Data.CFrame
                    local distance = math.huge

                    if typeof(placementCFrame) == "CFrame"
                        and typeof(cframe) == "CFrame" then
                        distance = (cframe.Position - placementCFrame.Position).Magnitude
                    end

                    if distance < bestDistance then
                        bestDistance = distance
                        bestId = id
                    end
                end
            end

            if bestId and (typeof(placementCFrame) ~= "CFrame"
                or bestDistance <= 12) then
                return bestId
            end

            task.wait(0.1)
        end

        return nil
    end

    -- Unit database scanning is intentionally deferred to playback/recording paths.
    -- Never run a large ReplicatedStorage scan while loading Macro.lua.

    local function findRemote(name, className)
        local repStorage = game:GetService("ReplicatedStorage")
        local found = repStorage:FindFirstChild(name, true)
        if found and (not className or found.ClassName == className) then
            return found
        end
        for _, descendant in ipairs(game:GetDescendants()) do
            if descendant.Name == name and (not className or descendant.ClassName == className) then
                return descendant
            end
        end
        return nil
    end

    local function getReplicaSignalAction(args)
        local actionName = tostring(args[2] or "")

        if actionName == "SelectSlot" then
            return nil
        elseif actionName == "PlaceGameUnit" then
            return "UnitPlace"
        elseif actionName == "UpgradeGameUnit" then
            return "UnitUpgrade"
        elseif actionName == "ChangeGameUnitAutoUpgradePriority" then
            return "UnitAutoUpgrade"
        end

        return nil
    end

    local function scanAndBuildUnitDatabase()
        scannedUnitsDatabase = {}
        local foundCount = 0
        pcall(function()
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("Model") and descendant:FindFirstChild("HumanoidRootPart") then
                    local ownerAttr = descendant:GetAttribute("Owner") or descendant:GetAttribute("Player")
                    if ownerAttr == game.Players.LocalPlayer then
                        foundCount = foundCount + 1
                        scannedUnitsDatabase[foundCount] = {
                            instance = descendant,
                            uniqueId = descendant:GetAttribute("Id") or descendant.Name,
                        }
                    end
                end
            end
        end)
        return foundCount
    end

    -- Install the recording hook only when the user actually starts recording.
    -- This keeps Macro initialization from installing a global __namecall hook
    -- before the Joiner has finished its own game-start work.
    local recordingHookInstalled = false
    local recordingHookAvailable =
        type(hookmetamethod) == "function"
        and type(getnamecallmethod) == "function"
        and type(checkcaller) == "function"

    local function installRecordingHook()
        if recordingHookInstalled or not recordingHookAvailable then
            return recordingHookInstalled
        end

        local ok = pcall(function()
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                local packedArgs = table.pack(...)
                local isRemoteCall = (not checkcaller())
                    and (method == "FireServer" or method == "InvokeServer")
                local selfRef = self

                local yenBefore = nil
                local replicaActionBefore = nil

                if isRemoteCall and Config.RecordMacro then
                    pcall(function()
                        if selfRef.Name == "ReplicaSignal" then
                            replicaActionBefore = getReplicaSignalAction(packedArgs)
                            if replicaActionBefore == "UnitUpgrade" then
                                yenBefore = getCurrentYen()
                            end
                        end
                    end)
                end

                local result = table.pack(oldNamecall(self, ...))

                if isRemoteCall and Config.RecordMacro then
                    recordActionSequence = recordActionSequence + 1
                    local actionSequence = recordActionSequence
                    pendingRecordWorkers = pendingRecordWorkers + 1
                    task.spawn(function()
                        pcall(function()
                            local remoteNameLower = selfRef.Name:lower()

                            if remoteNameLower:find("chat")
                                or remoteNameLower:find("ping")
                                or remoteNameLower:find("analytics")
                                or remoteNameLower:find("mouse")
                                or remoteNameLower:find("camera") then
                                return
                            end

                            local actionDesc = nil
                            local isReplicaSignal = (selfRef.Name == "ReplicaSignal")

                            if isReplicaSignal then
                                actionDesc = getReplicaSignalAction(packedArgs)
                            elseif remoteNameLower == "_updatenode"
                                or remoteNameLower:find("networkevents") then
                                actionDesc = nil
                            else
                                if remoteNameLower:find("upgrade")
                                    or remoteNameLower:find("lvl")
                                    or remoteNameLower:find("level")
                                    or remoteNameLower:find("evolve")
                                    or remoteNameLower:find("rank") then
                                    actionDesc = "UnitUpgrade"
                                elseif remoteNameLower:find("place")
                                    or remoteNameLower:find("spawn")
                                    or remoteNameLower:find("deploy") then
                                    actionDesc = "UnitPlace"
                                end
                            end

                            if actionDesc then
                                local actionEntry = {
                                    time = os.clock() - recordStartTime,
                                    actionType = actionDesc,
                                    remoteName = selfRef.Name,
                                    remoteClass = selfRef.ClassName,
                                    method = method,
                                    args = packedArgs,
                                    yenBefore = yenBefore,
                                    recordSequence = actionSequence,
                                }

                                if isReplicaSignal
                                    and (actionDesc == "UnitUpgrade"
                                        or actionDesc == "UnitAutoUpgrade") then
                                    actionEntry.recordedUnitId = packedArgs[3]
                                    actionEntry.unitIdArgIndex = 3

                                    -- Save a stable target reference from the recording session.
                                    -- Replica IDs can change every game, so the playback side
                                    -- must be able to resolve the unit by its position/type too.
                                    local targetData = getReplicaDataById(packedArgs[3], 1)
                                    if targetData then
                                        if typeof(targetData.CFrame) == "CFrame" then
                                            actionEntry.targetCFrame = targetData.CFrame
                                        end
                                        if targetData.UnitID ~= nil then
                                            actionEntry.targetUnitID = tostring(targetData.UnitID)
                                        end
                                    end
                                end

                                table.insert(recordedActions, actionEntry)
                                print(("[Macro Record] #%d %s"):format(
                                    #recordedActions,
                                    actionDesc
                                ))

                                if actionDesc == "UnitPlace" then
                                    recordPlacementCount = recordPlacementCount + 1
                                    actionEntry.placementOrder = recordPlacementCount
                                    actionEntry.recordedUnitId = packedArgs[3]
                                    recordedPlacementCFrames[recordPlacementCount] = packedArgs[4]

                                    if packedArgs[3] ~= nil then
                                        recordedUnitToPlacementOrder[
                                            tostring(packedArgs[3])
                                        ] = recordPlacementCount
                                    end

                                elseif actionDesc == "UnitUpgrade" then
                                    actionEntry.linkedPlacementOrder =
                                        recordedUnitToPlacementOrder[tostring(packedArgs[3])]
                                        or resolveRecordedPlacementOrder(packedArgs[3])

                                    pcall(function()
                                        local yenAfter = getCurrentYen()
                                        local deadline = os.clock() + 1

                                        while yenBefore
                                            and yenAfter == yenBefore
                                            and os.clock() < deadline do
                                            task.wait(0.05)
                                            yenAfter = getCurrentYen()
                                        end

                                        actionEntry.yenAfter = yenAfter

                                        if yenBefore and yenAfter then
                                            local delta = yenBefore - yenAfter
                                            if delta > 0 then
                                                actionEntry.yenCost = delta
                                                actionEntry.missingYenAtRecord = 0
                                            end
                                        end

                                        print(("[Macro Record] Upgrade cost=%s | Yen %s -> %s"):format(
                                            tostring(actionEntry.yenCost),
                                            tostring(yenBefore),
                                            tostring(yenAfter)
                                        ))
                                    end)

                                elseif actionDesc == "UnitAutoUpgrade" then
                                    actionEntry.linkedPlacementOrder =
                                        recordedUnitToPlacementOrder[tostring(packedArgs[3])]
                                        or resolveRecordedPlacementOrder(packedArgs[3])
                                end
                            end
                        end)

                        pendingRecordWorkers = math.max(0, pendingRecordWorkers - 1)
                    end)
                end

                return table.unpack(result, 1, result.n)
            end)

            recordingHookInstalled = true
        end)

        if not ok then
            recordingHookInstalled = false
            warn("[Macro] Failed to install recording hook.")
        end

        return recordingHookInstalled
    end

    if not recordingHookAvailable then
        warn("[Macro] Recording hook unavailable; playback UI will still load.")
    end

    local createSec = Instance.new("Frame")
    createSec.Size = UDim2.new(1, 0, 0, 100)
    createSec.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    createSec.Parent = macroTab
    Instance.new("UICorner", createSec).CornerRadius = UDim.new(0, 6)

    local createHeader = Instance.new("TextLabel")
    createHeader.Size = UDim2.new(1, -16, 0, 26)
    createHeader.Position = UDim2.fromOffset(8, 4)
    createHeader.BackgroundTransparency = 1
    createHeader.Font = Enum.Font.GothamBold
    createHeader.Text = "- Created Macro"
    createHeader.TextColor3 = Color3.fromRGB(200, 200, 210)
    createHeader.TextSize = 11
    createHeader.TextXAlignment = Enum.TextXAlignment.Left
    createHeader.Parent = createSec

    local nameInput = Instance.new("TextBox")
    nameInput.Size = UDim2.new(1, -16, 0, 26)
    nameInput.Position = UDim2.fromOffset(8, 32)
    nameInput.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    nameInput.TextColor3 = Color3.fromRGB(200, 200, 200)
    nameInput.PlaceholderText = "Enter macro name..."
    nameInput.Text = ""
    nameInput.ClearTextOnFocus = false
    nameInput.Parent = createSec
    Instance.new("UICorner", nameInput).CornerRadius = UDim.new(0, 6)

    local createBtn = Instance.new("TextButton")
    createBtn.Size = UDim2.new(1, -16, 0, 26)
    createBtn.Position = UDim2.fromOffset(8, 64)
    createBtn.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
    createBtn.Text = "Create Macro"
    createBtn.Font = Enum.Font.GothamBold
    createBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    createBtn.TextSize = 10
    createBtn.Parent = createSec
    Instance.new("UICorner", createBtn).CornerRadius = UDim.new(0, 7)

    local hisMacrosSec = Instance.new("Frame")
    hisMacrosSec.Size = UDim2.new(1, 0, 0, 236)
    hisMacrosSec.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    hisMacrosSec.Parent = macroTab
    Instance.new("UICorner", hisMacrosSec).CornerRadius = UDim.new(0, 9)

    local hisHeader = Instance.new("TextButton")
    hisHeader.Size = UDim2.new(1, -16, 0, 26)
    hisHeader.Position = UDim2.fromOffset(8, 4)
    hisHeader.BackgroundTransparency = 1
    hisHeader.Font = Enum.Font.GothamBold
    hisHeader.Text = "▼  Your macros"
    hisHeader.TextColor3 = Color3.fromRGB(200, 200, 210)
    hisHeader.TextSize = 11
    hisHeader.TextXAlignment = Enum.TextXAlignment.Left
    hisHeader.Parent = hisMacrosSec

    local macrosListContainer = Instance.new("ScrollingFrame")
    macrosListContainer.Size = UDim2.new(1, -16, 0, 95)
    macrosListContainer.Position = UDim2.fromOffset(8, 34)
    macrosListContainer.BackgroundTransparency = 1
    macrosListContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    macrosListContainer.ScrollBarThickness = 2
    macrosListContainer.Visible = true
    macrosListContainer.Parent = hisMacrosSec
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = macrosListContainer

    local dropdownOpen = true
    hisHeader.Activated:Connect(function()
        dropdownOpen = not dropdownOpen
        macrosListContainer.Visible = dropdownOpen
        hisHeader.Text = dropdownOpen and "▼  Your macros" or "▶  Your macros"
    end)

    local deleteMacroBtn = Instance.new("TextButton")
    deleteMacroBtn.Size = UDim2.new(1, -16, 0, 26)
    deleteMacroBtn.Position = UDim2.fromOffset(8, 138)
    deleteMacroBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    deleteMacroBtn.Text = "🗑 Delete Selected Macro"
    deleteMacroBtn.Font = Enum.Font.GothamBold
    deleteMacroBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    deleteMacroBtn.TextSize = 10
    deleteMacroBtn.Parent = hisMacrosSec
    Instance.new("UICorner", deleteMacroBtn).CornerRadius = UDim.new(0, 7)

    local exportMacroBtn = Instance.new("TextButton")
    exportMacroBtn.Size = UDim2.new(1, -16, 0, 26)
    exportMacroBtn.Position = UDim2.fromOffset(8, 170)
    exportMacroBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 190)
    exportMacroBtn.Text = "📋 Copy Selected Macro as JSON"
    exportMacroBtn.Font = Enum.Font.GothamBold
    exportMacroBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    exportMacroBtn.TextSize = 10
    exportMacroBtn.Parent = hisMacrosSec
    Instance.new("UICorner", exportMacroBtn).CornerRadius = UDim.new(0, 7)

    local importMacroBox = Instance.new("TextBox")
    importMacroBox.Size = UDim2.new(1, -16, 0, 26)
    importMacroBox.Position = UDim2.fromOffset(8, 202)
    importMacroBox.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    importMacroBox.TextColor3 = Color3.fromRGB(200, 200, 200)
    importMacroBox.PlaceholderText = "Paste macro JSON here, then tap outside to import"
    importMacroBox.Text = ""
    importMacroBox.ClearTextOnFocus = false
    importMacroBox.TextSize = 9
    importMacroBox.Parent = hisMacrosSec
    Instance.new("UICorner", importMacroBox).CornerRadius = UDim.new(0, 7)

    local function refreshMacroList()
        for _, child in ipairs(macrosListContainer:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        local count = 0
        for macroName, _ in pairs(savedMacros) do
            count = count + 1
            local isSelected = (Config.CurrentMacroName == macroName)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 24)
            btn.BackgroundColor3 = isSelected and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(32, 32, 40)
            btn.Text = (isSelected and "✓ " or "  ") .. macroName
            btn.Font = Enum.Font.GothamMedium
            btn.TextColor3 = isSelected and Color3.fromRGB(30, 20, 10) or Color3.fromRGB(220, 220, 220)
            btn.TextSize = 10
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Parent = macrosListContainer
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)

            btn.Activated:Connect(function()
                Config.CurrentMacroName = macroName
                showTopNotification(string.format("Macro '%s' selected.", macroName), 3)
                refreshMacroList()
            end)
        end
        macrosListContainer.CanvasSize = UDim2.new(0, 0, 0, count * 28)
    end

    refreshMacroList()

    deleteMacroBtn.Activated:Connect(function()
        if Config.CurrentMacroName == "" or not savedMacros[Config.CurrentMacroName] then
            showTopNotification("Select a macro first!", 2)
            return
        end
        local deletedName = Config.CurrentMacroName
        savedMacros[deletedName] = nil
        Config.CurrentMacroName = ""
        saveMacrosToFile()
        refreshMacroList()
        showTopNotification("Deleted macro '" .. deletedName .. "'", 3)
    end)

    exportMacroBtn.Activated:Connect(function()
        if Config.CurrentMacroName == "" or not savedMacros[Config.CurrentMacroName] then
            showTopNotification("Select a macro first!", 2)
            return
        end
        local ok, encoded = pcall(function()
            local single = { [Config.CurrentMacroName] = savedMacros[Config.CurrentMacroName] }
            return HttpService:JSONEncode(Shared.serializeMacros(single))
        end)
        if not ok then
            showTopNotification("Export failed: " .. tostring(encoded), 3)
            return
        end
        local copied = false
        if setclipboard then
            copied = pcall(function() setclipboard(encoded) end)
        elseif toclipboard then
            copied = pcall(function() toclipboard(encoded) end)
        end
        showTopNotification(copied and "Macro JSON copied to clipboard!" or "Copy failed - see console", 3)
        if not copied then print(encoded) end
    end)

    importMacroBox.FocusLost:Connect(function()
        local raw = importMacroBox.Text
        if raw == "" then return end
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(raw)
        end)
        if not ok then
            showTopNotification("Import failed: invalid JSON", 3)
            return
        end
        local imported = 0
        for name, macro in pairs(decoded) do
            savedMacros[name] = { actions = Shared.deserializeMacroActions(macro.actions) }
            imported = imported + 1
        end
        saveMacrosToFile()
        refreshMacroList()
        importMacroBox.Text = ""
        showTopNotification("Imported " .. imported .. " macro(s) from JSON!", 3)
    end)

    local recordSec = Instance.new("Frame")
    recordSec.Size = UDim2.new(1, 0, 0, 125)
    recordSec.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    recordSec.Parent = macroTab
    Instance.new("UICorner", recordSec).CornerRadius = UDim.new(0, 6)

    local recordBtn = Instance.new("TextButton")
    recordBtn.Size = UDim2.new(1, -16, 0, 32)
    recordBtn.Position = UDim2.fromOffset(8, 8)
    recordBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    recordBtn.Text = "🔴 Record Macro"
    recordBtn.Font = Enum.Font.GothamBold
    recordBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    recordBtn.TextSize = 10
    recordBtn.Parent = recordSec
    Instance.new("UICorner", recordBtn).CornerRadius = UDim.new(0, 7)

    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(1, -16, 0, 32)
    playBtn.Position = UDim2.fromOffset(8, 44)
    playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    playBtn.Text = "▶ Play Macro"
    playBtn.Font = Enum.Font.GothamBold
    playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    playBtn.TextSize = 10
    playBtn.Parent = recordSec
    Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 7)

    local macroStatusLabel = Instance.new("TextLabel")
    macroStatusLabel.Size = UDim2.new(1, -16, 0, 32)
    macroStatusLabel.Position = UDim2.fromOffset(8, 80)
    macroStatusLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    macroStatusLabel.Font = Enum.Font.Code
    macroStatusLabel.Text = "Idle"
    macroStatusLabel.TextColor3 = Color3.fromRGB(180, 220, 180)
    macroStatusLabel.TextSize = 10
    macroStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    macroStatusLabel.TextWrapped = true
    macroStatusLabel.Parent = recordSec
    Instance.new("UICorner", macroStatusLabel).CornerRadius = UDim.new(0, 7)

    local macroOptionsSec = Instance.new("Frame")
    macroOptionsSec.Size = UDim2.new(1, 0, 0, 132)
    macroOptionsSec.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    macroOptionsSec.Parent = macroTab
    Instance.new("UICorner", macroOptionsSec).CornerRadius = UDim.new(0, 6)

    local function makeOptionToggle(textLabel, y, configKey)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 24)
        btn.Position = UDim2.fromOffset(8, y)
        btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(40, 180, 80) or Color3.fromRGB(50, 50, 60)
        btn.Text = (Config[configKey] and "✓ " or "○ ") .. textLabel
        btn.Font = Enum.Font.GothamBold
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 10
        btn.Parent = macroOptionsSec
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        btn.Activated:Connect(function()
            Config[configKey] = not Config[configKey]
            btn.BackgroundColor3 = Config[configKey] and Color3.fromRGB(40, 180, 80) or Color3.fromRGB(50, 50, 60)
            btn.Text = (Config[configKey] and "✓ " or "○ ") .. textLabel
        end)
        return btn
    end

    makeOptionToggle("Ignore Timing", 6, "MacroIgnoreTiming")

    -- Retry slider: 0 = retry forever, 1-10 = additional retries after the first attempt.
    local retryLabel = Instance.new("TextLabel")
    retryLabel.Size = UDim2.new(1, -16, 0, 18)
    retryLabel.Position = UDim2.fromOffset(8, 88)
    retryLabel.BackgroundTransparency = 1
    retryLabel.Text = "Retry: 0"
    retryLabel.Font = Enum.Font.GothamBold
    retryLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    retryLabel.TextSize = 10
    retryLabel.TextXAlignment = Enum.TextXAlignment.Left
    retryLabel.Parent = macroOptionsSec

    local retryBar = Instance.new("Frame")
    retryBar.Size = UDim2.new(1, -16, 0, 12)
    retryBar.Position = UDim2.fromOffset(8, 110)
    retryBar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    retryBar.BorderSizePixel = 0
    retryBar.Active = true
    retryBar.Parent = macroOptionsSec
    Instance.new("UICorner", retryBar).CornerRadius = UDim.new(0, 6)

    local retryFill = Instance.new("Frame")
    retryFill.Size = UDim2.new(0, 0, 1, 0)
    retryFill.Position = UDim2.fromOffset(0, 0)
    retryFill.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
    retryFill.BorderSizePixel = 0
    retryFill.Parent = retryBar
    Instance.new("UICorner", retryFill).CornerRadius = UDim.new(0, 6)

    local retryKnob = Instance.new("Frame")
    retryKnob.Size = UDim2.fromOffset(18, 18)
    retryKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    retryKnob.Position = UDim2.new(0, 0, 0.5, 0)
    retryKnob.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
    retryKnob.BorderSizePixel = 0
    retryKnob.Active = true
    retryKnob.Parent = retryBar
    Instance.new("UICorner", retryKnob).CornerRadius = UDim.new(1, 0)

    local retryDragging = false

    local function setRetryFromX(x)
        local width = retryBar.AbsoluteSize.X
        if width <= 0 then return end

        local alpha = math.clamp(
            (x - retryBar.AbsolutePosition.X) / width,
            0,
            1
        )

        local value = math.floor(alpha * 10 + 0.5)
        Config.MacroRetry = math.clamp(value, 0, 10)

        local normalized = Config.MacroRetry / 10
        retryFill.Size = UDim2.new(normalized, 0, 1, 0)
        retryKnob.Position = UDim2.new(normalized, 0, 0.5, 0)
        retryLabel.Text = ("Retry: %d"):format(Config.MacroRetry)
    end

    local function setRetryValue(value)
        Config.MacroRetry = math.clamp(math.floor(tonumber(value) or 0), 0, 10)
        local normalized = Config.MacroRetry / 10
        retryFill.Size = UDim2.new(normalized, 0, 1, 0)
        retryKnob.Position = UDim2.new(normalized, 0, 0.5, 0)
        retryLabel.Text = ("Retry: %d"):format(Config.MacroRetry)
    end

    retryBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            retryDragging = true
            setRetryFromX(input.Position.X)
        end
    end)

    retryKnob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            retryDragging = true
        end
    end)

    retryBar.InputChanged:Connect(function(input)
        if retryDragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            setRetryFromX(input.Position.X)
        end
    end)

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if retryDragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            setRetryFromX(input.Position.X)
        end
    end)

    game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            retryDragging = false
        end
    end)

    setRetryValue(Config.MacroRetry or 0)

    local isPlayingMacro = false
    local macroRunId = 0
    local macroGameSession = 0

    -- Resolve a playback unit after the placement remote has already fired.
    -- Ignore Timing removes timestamp waits, not the game's replication/readiness
    -- requirements. Keep resolving until the correct live unit is visible.
    local function resolvePlaybackUnitReplicaId(targetCFrame, targetUnitID, timeoutSeconds, preferredId, runId)
        local deadline = os.clock() + (timeoutSeconds or 12)
        local lastBestId = preferredId

        while os.clock() < deadline
            and isPlayingMacro == true
            and (runId == nil or macroRunId == runId) do
            if lastBestId then
                local data = getReplicaDataById(lastBestId, 0.15)
                if data and data.CFrame ~= nil and data.UnitID ~= nil then
                    local cframeMatches = true
                    local unitMatches = true

                    if typeof(targetCFrame) == "CFrame"
                        and typeof(data.CFrame) == "CFrame" then
                        cframeMatches =
                            (data.CFrame.Position - targetCFrame.Position).Magnitude <= 12
                    end

                    if targetUnitID ~= nil then
                        unitMatches = tostring(data.UnitID or "") == targetUnitID
                    end

                    if cframeMatches and unitMatches then
                        return lastBestId
                    end
                end
            end

            local candidates = getOwnedGameUnitReplicas()
            local bestId = nil
            local bestScore = math.huge
            local fallbackId = nil
            local fallbackDistance = math.huge

            for id, replica in pairs(candidates) do
                if replica and replica.Data then
                    local data = replica.Data
                    local distance = math.huge

                    if typeof(targetCFrame) == "CFrame"
                        and typeof(data.CFrame) == "CFrame" then
                        distance = (data.CFrame.Position - targetCFrame.Position).Magnitude
                    end

                    local unitMatches = targetUnitID == nil
                        or tostring(data.UnitID or "") == targetUnitID

                    if unitMatches and distance < bestScore then
                        bestScore = distance
                        bestId = id
                    end

                    if distance < fallbackDistance then
                        fallbackDistance = distance
                        fallbackId = id
                    end
                end
            end

            if bestId and (typeof(targetCFrame) ~= "CFrame" or bestScore <= 12) then
                return bestId
            end

            if fallbackId and targetUnitID == nil
                and (typeof(targetCFrame) ~= "CFrame" or fallbackDistance <= 12) then
                return fallbackId
            end

            if targetCFrame == nil and targetUnitID == nil then
                local onlyId = nil
                local count = 0
                for id in pairs(candidates) do
                    onlyId = id
                    count += 1
                    if count > 1 then
                        break
                    end
                end

                if count == 1 and onlyId then
                    return onlyId
                end
            end

            task.wait(0.1)
        end

        return nil
    end

    local macroGameWasInProgress = false
    local macroLastStartedSession = {}

    local function getCurrentGameState()
        local getWaveInfo = Shared.getWaveInfo
        if type(getWaveInfo) ~= "function" then
            return nil
        end

        local _, _, state = getWaveInfo()
        return type(state) == "string" and state or nil
    end

    local function updateMacroGameSession()
        local state = getCurrentGameState()

        if state == "InProgress" then
            if not macroGameWasInProgress then
                macroGameSession = macroGameSession + 1
                macroGameWasInProgress = true
            end
        else
            macroGameWasInProgress = false
        end

        return state
    end

    local function fireAction(remoteObj, action)
        if not remoteObj or not remoteObj.Parent then
            return false, "Remote not found"
        end

        local args = { table.unpack(action.args, 1, action.args.n) }
        local ok, result = pcall(function()
            if action.method == "InvokeServer" then
                return remoteObj:InvokeServer(table.unpack(args))
            end
            remoteObj:FireServer(table.unpack(args))
            return true
        end)

        if not ok then
            return false, tostring(result)
        end

        return true, result
    end

    local function getUnitLevel(data)
        if not data then return nil end
        return data.Level or data.Upgrade or data.UpgradeLevel
    end

    local function findExistingPlacementReplica(placementCFrame)
        if typeof(placementCFrame) ~= "CFrame" then
            return nil
        end

        local candidates = getOwnedGameUnitReplicas()
        local bestId = nil
        local bestDistance = math.huge

        for id, replica in pairs(candidates) do
            if replica and replica.Data and typeof(replica.Data.CFrame) == "CFrame" then
                local distance = (replica.Data.CFrame.Position - placementCFrame.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestId = id
                end
            end
        end

        if bestId and bestDistance <= 4 then
            return bestId
        end

        return nil
    end

    local function getUnitLevelByReplicaId(targetId)
        local replicaClient = getReplicaClient()
        if not targetId or not replicaClient or type(replicaClient.FromId) ~= "function" then
            return nil
        end

        local ok, replica = pcall(replicaClient.FromId, tonumber(targetId))
        if ok and replica and replica.Data then
            return getUnitLevel(replica.Data)
        end

        return nil
    end


    local function verifyAction(action, beforeYen, beforeUnits, beforeLevel)
        if action.actionType == "UnitUpgrade" or action.actionType == "UnitAutoUpgrade" then
            local targetId = action._playbackReplicaId
            if not targetId then
                return false
            end

            local replicaClient = getReplicaClient()
            if not replicaClient or type(replicaClient.FromId) ~= "function" then
                return true
            end

            local deadline = os.clock() + 1.5
            while os.clock() < deadline and isPlayingMacro == true do
                local ok, replica = pcall(replicaClient.FromId, tonumber(targetId))
                if ok and replica and replica.Data then
                    if action.actionType == "UnitAutoUpgrade" then
                        return true
                    end

                    local currentLevel = getUnitLevel(replica.Data)
                    if beforeLevel ~= nil and currentLevel ~= nil
                        and tostring(currentLevel) ~= tostring(beforeLevel) then
                        return true
                    end

                    if beforeYen ~= nil then
                        local currentYen = getCurrentYen()
                        if currentYen ~= nil and currentYen < beforeYen then
                            return true
                        end
                    end
                end

                task.wait(0.1)
            end

            if beforeYen ~= nil then
                local currentYen = getCurrentYen()
                if currentYen ~= nil and currentYen < beforeYen then
                    return true
                end
            end

            return false
        elseif action.actionType == "UnitPlace" then
            local deadline = os.clock() + 0.8
            while os.clock() < deadline and isPlayingMacro == true do
                local now = getOwnedGameUnitReplicas()
                for id in pairs(now) do
                    if not beforeUnits[id] then
                        return true
                    end
                end
                task.wait(0.08)
            end
            return false
        end

        return true
    end
    local function runUpgradeUntilAccepted(remoteObj, action, args, timeoutSeconds, runId)
        if not isPlayingMacro or (runId ~= nil and macroRunId ~= runId) then
            return false, "Macro stopped"
        end

        -- One outer loop iteration is one actual attempt. Do not hide additional
        -- remote fires inside an attempt, otherwise Retry=1 could send many
        -- Upgrade requests before the configured retry count is reached.
        local beforeYen = getCurrentYen()
        local beforeLevel = getUnitLevelByReplicaId(action._playbackReplicaId)

        local tempAction = {
            actionType = action.actionType,
            args = args,
            method = action.method,
        }

        local fired, err = fireAction(remoteObj, tempAction)
        if not fired then
            return false, err or "Remote call failed"
        end

        local deadline = os.clock() + (timeoutSeconds or 1.5)
        repeat
            if not isPlayingMacro or (runId ~= nil and macroRunId ~= runId) then
                return false, "Macro stopped"
            end

            if verifyAction(action, beforeYen, {}, beforeLevel) then
                return true
            end

            local currentYen = getCurrentYen()
            macroStatusLabel.Text =
                ("Upgrade waiting | Yen: %s"):format(tostring(currentYen or "?"))

            if os.clock() >= deadline then
                break
            end

            task.wait(0.1)
        until false

        return false, "Upgrade was not confirmed before timeout"
    end

    local function runMacroOnce(macroData)
        if isPlayingMacro then return false end
        macroRunId += 1
        local myRunId = macroRunId
        isPlayingMacro = true
        local playbackStartTime = os.clock()
        Shared.isPlayingMacro = true

        local lastTime = 0
        local playPlacementCount = 0
        local playbackUnitReplicaIds = {}
        local placementActionsByOrder = {}
        local totalActions = #macroData.actions
        local ignoreTiming = Config.MacroIgnoreTiming == true
        local retryCount = math.clamp(tonumber(Config.MacroRetry) or 0, 0, 10)

        -- Rebuild placement order from the saved macro itself. The old code
        -- depended on recordedPlacementCFrames from the recording session,
        -- which is empty when an already-saved macro is played later.
        local savedPlacementOrder = 0
        local placementActionsByRecordedUnitId = {}
        for _, savedAction in ipairs(macroData.actions) do
            if savedAction.actionType == "UnitPlace" then
                savedPlacementOrder += 1
                local order = tonumber(savedAction.placementOrder) or savedPlacementOrder
                placementActionsByOrder[order] = savedAction

                -- Older saved macros may have linkedPlacementOrder missing,
                -- but still contain the original UnitPlace recordedUnitId.
                if savedAction.recordedUnitId ~= nil then
                    placementActionsByRecordedUnitId[
                        tostring(savedAction.recordedUnitId)
                    ] = savedAction
                end
            end
        end

        for actionIndex, action in ipairs(macroData.actions) do
            if not isPlayingMacro or macroRunId ~= myRunId then break end

            local actionLabel = action.actionType or "Action"
            local effectiveYenCost = action.yenCost
            if not effectiveYenCost and action.yenBefore and action.yenAfter then
                local delta = action.yenBefore - action.yenAfter
                if delta > 0 then effectiveYenCost = delta end
            end

            -- Timing is a minimum schedule only. Once the action is due,
            -- resource readiness decides when it actually executes.
            if not ignoreTiming then
                local targetTime = tonumber(action.time) or lastTime
                local elapsed = os.clock() - playbackStartTime
                local remaining = targetTime - elapsed
                while remaining > 0 and isPlayingMacro and macroRunId == myRunId do
                    macroStatusLabel.Text = ("[%d/%d] Waiting %.1fs (%s)"):format(
                        actionIndex, totalActions, remaining, actionLabel
                    )
                    task.wait(math.min(0.1, remaining))
                    elapsed = os.clock() - playbackStartTime
                    remaining = targetTime - elapsed
                end
            end
            lastTime = tonumber(action.time) or lastTime

            -- Placement/upgrade readiness is independent from the recorded
            -- timestamp. This prevents a late playback from getting stuck.
            if action.actionType == "UnitUpgrade" and effectiveYenCost then
                local waitStartedAt = os.clock()
                local lastSampleYen = getCurrentYen()
                local lastSampleAt = os.clock()
                local estimatedRate = nil

                while isPlayingMacro and macroRunId == myRunId do
                    local yen = getCurrentYen()
                    local missing = yen and math.max(0, effectiveYenCost - yen) or effectiveYenCost
                    local now = os.clock()

                    if yen and lastSampleYen and now - lastSampleAt >= 0.3 then
                        local gained = yen - lastSampleYen
                        local elapsed = now - lastSampleAt
                        if gained > 0 and elapsed > 0 then
                            estimatedRate = gained / elapsed
                        end
                        lastSampleYen = yen
                        lastSampleAt = now
                    end

                    local etaText = "--"
                    if missing <= 0 then
                        etaText = "0.0s"
                    elseif estimatedRate and estimatedRate > 0 then
                        etaText = ("%.1fs"):format(missing / estimatedRate)
                    end

                    macroStatusLabel.Text = ("[%d/%d] Upgrade | Missing: %s Yen | Timer: %.1fs | ETA: %s"):format(
                        actionIndex, totalActions, tostring(missing),
                        now - waitStartedAt, etaText
                    )

                    if yen == nil then
                        -- If the Yen replica is temporarily unavailable, do not
                        -- freeze the whole macro. The server remains the source
                        -- of truth for whether the Upgrade is affordable.
                        break
                    end

                    if yen >= effectiveYenCost then break end
                    task.wait(0.2)
                end
            end

            if not isPlayingMacro or macroRunId ~= myRunId then break end

            local success = false
            local lastError = "unknown"
            local attempt = 0

            -- Retry semantics:
            --   0 = retry forever until this action succeeds or Play Macro is stopped.
            --   1-10 = initial attempt + that many retries, then skip.
            while isPlayingMacro
                and macroRunId == myRunId
                and (retryCount == 0 or attempt < (retryCount + 1)) do
                attempt += 1

                local remoteObj = findRemote(action.remoteName, action.remoteClass)
                if not remoteObj then
                    lastError = "Remote not found"
                else
                    local beforeIds = {}
                    if action.actionType == "UnitPlace" then
                        beforeIds = snapshotOwnedGameUnits()
                    end

                    local args = { table.unpack(action.args, 1, action.args.n) }

                    if action.actionType == "UnitPlace" then
                        if not action._playbackPlacementOrder then
                            playPlacementCount = playPlacementCount + 1
                            action._playbackPlacementOrder = playPlacementCount
                        end
                    elseif action.actionType == "UnitUpgrade" or action.actionType == "UnitAutoUpgrade" then
                        local targetOrder = action.linkedPlacementOrder
                        local targetReplicaId = targetOrder and playbackUnitReplicaIds[targetOrder]
                        local placementAction = targetOrder and placementActionsByOrder[targetOrder]

                        if not placementAction and action.recordedUnitId ~= nil then
                            placementAction = placementActionsByRecordedUnitId[
                                tostring(action.recordedUnitId)
                            ]

                            if placementAction then
                                targetOrder = tonumber(placementAction.placementOrder)
                            end
                        end

                        local placementCFrame = placementAction
                            and placementAction.args
                            and placementAction.args[4]

                        local targetCFrame = typeof(action.targetCFrame) == "CFrame"
                            and action.targetCFrame
                            or placementCFrame

                        local targetUnitID = action.targetUnitID
                            and tostring(action.targetUnitID)
                            or nil

                        if not targetOrder and typeof(targetCFrame) == "CFrame" then
                            local bestOrder = nil
                            local bestDistance = math.huge

                            for order, savedPlace in pairs(placementActionsByOrder) do
                                local cf = savedPlace.args and savedPlace.args[4]
                                if typeof(cf) == "CFrame" then
                                    local distance =
                                        (cf.Position - targetCFrame.Position).Magnitude

                                    if distance < bestDistance then
                                        bestDistance = distance
                                        bestOrder = order
                                    end
                                end
                            end

                            if bestOrder and bestDistance <= 12 then
                                targetOrder = bestOrder
                                placementAction = placementActionsByOrder[bestOrder]
                                placementCFrame = placementAction.args[4]
                                targetReplicaId = playbackUnitReplicaIds[bestOrder]
                            end
                        end

                        if not targetReplicaId then
                            targetReplicaId = resolvePlaybackUnitReplicaId(
                                targetCFrame,
                                targetUnitID,
                                15,
                                nil,
                                myRunId
                            )

                            if targetReplicaId and targetOrder then
                                playbackUnitReplicaIds[targetOrder] = targetReplicaId
                            end
                        end

                        if targetReplicaId and action.unitIdArgIndex then
                            args[action.unitIdArgIndex] = tostring(targetReplicaId)
                            action._playbackReplicaId = targetReplicaId
                        else
                            lastError = ("Target unit not ready for placement #%s"):format(tostring(targetOrder))
                            targetReplicaId = nil
                        end
                    end

                    if targetReplicaId or action.actionType == "UnitPlace" or (action.actionType ~= "UnitUpgrade" and action.actionType ~= "UnitAutoUpgrade") then
                        local fired, err
                        local beforeYenForVerification = nil
                        local beforeLevelForVerification = nil

                        if action.actionType == "UnitPlace" then
                            -- Before retrying a placement, check whether the previous
                            -- attempt actually created the unit. This prevents duplicate
                            -- placements when replica detection was delayed.
                            local existingReplicaId = findExistingPlacementReplica(args[4])
                            if existingReplicaId then
                                local placementOrder = action._playbackPlacementOrder
                                playbackUnitReplicaIds[placementOrder] = existingReplicaId
                                success = true
                                Shared.logLine(
                                    "[Macro] Place already exists -> order "
                                        .. tostring(placementOrder)
                                        .. " replica "
                                        .. tostring(existingReplicaId)
                                )
                            end
                        elseif action.actionType == "UnitUpgrade" then
                            beforeYenForVerification = getCurrentYen()
                            beforeLevelForVerification = getUnitLevelByReplicaId(action._playbackReplicaId)
                        end

                        if not success then
                            if action.actionType == "UnitUpgrade"
                                and ignoreTiming then
                                fired, err = runUpgradeUntilAccepted(
                                    remoteObj,
                                    action,
                                    args,
                                    30,
                                    myRunId
                                )
                            else
                                local tempAction = {
                                    actionType = action.actionType,
                                    args = args,
                                    method = action.method,
                                }
                                fired, err = fireAction(remoteObj, tempAction)
                            end
                        end

                        if success or fired then
                            if action.actionType == "UnitPlace" then
                                local placementOrder = action._playbackPlacementOrder
                                local newReplicaId = waitForNewPlacementReplica(
                                    beforeIds,
                                    args[4],
                                    12
                                )

                                if newReplicaId then
                                    playbackUnitReplicaIds[placementOrder] = newReplicaId
                                    Shared.logLine(
                                        "[Macro] Place mapped -> order "
                                            .. tostring(placementOrder)
                                            .. " replica "
                                            .. tostring(newReplicaId)
                                    )
                                    success = true
                                else
                                    lastError = "Placed unit replica was not detected yet"
                                end
                            else
                                local verified = verifyAction(
                                    action,
                                    beforeYenForVerification,
                                    beforeIds,
                                    beforeLevelForVerification
                                )

                                if verified then
                                    success = true
                                else
                                    lastError = "Action verification failed"
                                end
                            end
                        else
                            lastError = err or "Remote call failed"
                        end
                    end
                end

                if success then
                    break
                end

                if isPlayingMacro then
                    local maxAttempts = retryCount == 0 and "∞" or tostring(retryCount + 1)
                    macroStatusLabel.Text = ("[%d/%d] %s | Retry %d/%s"):format(
                        actionIndex, totalActions, actionLabel, attempt, maxAttempts
                    )
                    task.wait(0.2)
                end
            end

            if not success then
                if retryCount == 0 then
                    -- Retry=0 never skips an action. Reaching this point means
                    -- Play Macro was stopped while the action was still retrying.
                    macroStatusLabel.Text = ("[%d/%d] %s | STOPPED"):format(
                        actionIndex, totalActions, actionLabel
                    )
                else
                    warn(("[Macro] Skipping action #%d after %d failed attempt(s): %s"):format(
                        actionIndex, attempt, lastError
                    ))
                    macroStatusLabel.Text = ("[%d/%d] %s | SKIPPED"):format(
                        actionIndex, totalActions, actionLabel
                    )
                    task.wait(0.15)
                end
            else
                macroStatusLabel.Text = ("[%d/%d] %s | SUCCESS"):format(
                    actionIndex, totalActions, actionLabel
                )
            end
        end

        if macroRunId == myRunId then
            isPlayingMacro = false
            Shared.isPlayingMacro = false
        end
        return true
    end

    Shared.runMacroOnce = runMacroOnce

    createBtn.Activated:Connect(function()
        local name = nameInput.Text -- تم التصحيح هنا وإزالة .Test الخاطئة
        if name ~= "" then
            if not savedMacros[name] then
                savedMacros[name] = { actions = {} }
                Config.CurrentMacroName = name
                saveMacrosToFile()
                refreshMacroList()
                showTopNotification("Macro '" .. name .. "' created and selected!", 3)
                nameInput.Text = ""
            else
                showTopNotification("Macro name already exists!", 3)
            end
        else
            showTopNotification("Enter a valid macro name.", 3)
        end
    end)

    recordBtn.Activated:Connect(function()
        if Config.CurrentMacroName == "" then
            showTopNotification("Select a macro first!", 3)
            return
        end
        Config.RecordMacro = not Config.RecordMacro
        if Config.RecordMacro then
            installRecordingHook()
            recordedActions = {}
            recordStartTime = os.clock()
            recordActionSequence = 0
            recordPlacementCount = 0
            recordUnitIdMap = {}
            recordedUnitToPlacementOrder = {}
            recordedPlacementCFrames = {}
            pendingRecordWorkers = 0
            recordBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            recordBtn.Text = "🔴 Recording..."
            showTopNotification("Recording started...", 3)
        else
            recordBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            recordBtn.Text = "🔴 Record Macro"

            -- Remote recording/enrichment runs in small worker tasks.
            -- Wait for them to finish before serializing, otherwise the last
            -- Upgrade may be saved before its Yen cost is attached.
            local saveDeadline = os.clock() + 5
            while pendingRecordWorkers > 0 and os.clock() < saveDeadline do
                task.wait(0.05)
            end

            table.sort(recordedActions, function(a, b)
                return (a.recordSequence or math.huge) < (b.recordSequence or math.huge)
            end)

            if savedMacros[Config.CurrentMacroName] then
                savedMacros[Config.CurrentMacroName].actions = recordedActions
                saveMacrosToFile()
                showTopNotification("Macro saved to file (" .. #recordedActions .. " actions)!", 3)
            end
        end
    end)

    playBtn.Activated:Connect(function()
        if Config.CurrentMacroName == "" or not savedMacros[Config.CurrentMacroName] then
            showTopNotification("Select a valid macro first!", 3)
            return
        end

        local macroData = savedMacros[Config.CurrentMacroName]
        if #macroData.actions == 0 then
            showTopNotification("Macro is empty!", 3)
            return
        end

        Config.PlayMacro = not Config.PlayMacro

        if Config.PlayMacro then
            playBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
            playBtn.Text = "⏸ Playing..."
            macroStatusLabel.Text = "Waiting for stage..."

            task.spawn(function()
                local function getReplicaSignal(waitSeconds)
                    local deadline = os.clock() + (waitSeconds or 0)

                    repeat
                        local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
                        local remote = folder and folder:FindFirstChild("ReplicaSignal")

                        if remote and remote:IsA("RemoteEvent") then
                            return remote
                        end

                        local fallback = findRemote("ReplicaSignal", "RemoteEvent")
                        if fallback then
                            return fallback
                        end

                        if (waitSeconds or 0) <= 0 then
                            break
                        end

                        task.wait(0.1)
                    until os.clock() >= deadline

                    return nil
                end

                local function fireSignal(...)
                    local args = table.pack(...)

                    -- For Start/Vote, use the exact ReplicaSignal instance
                    -- that Joiner already uses successfully. This avoids
                    -- resolving another/misplaced ReplicaSignal.
                    if args[1] == 87 and args[2] == "Response" and args[3] == true
                        and type(Shared.sendGameStart) == "function" then

                        local ok, err = Shared.sendGameStart()

                        if ok then
                            Shared.logLine("[Macro] Game Start -> 87 Response true (Joiner ReplicaSignal)")
                        else
                            Shared.logLine("[Macro] Game Start ERROR -> " .. tostring(err))
                        end

                        return ok
                    end

                    local remote = Shared.ReplicaSignal
                        or getReplicaSignal(3)

                    if not remote then
                        Shared.logLine("[Macro] ReplicaSignal NOT FOUND")
                        return false
                    end

                    local ok, err = pcall(function()
                        remote:FireServer(table.unpack(args, 1, args.n))
                    end)

                    if ok then
                        Shared.logLine(
                            "[Macro] ReplicaSignal -> "
                                .. tostring(args[1]) .. " "
                                .. tostring(args[2]) .. " "
                                .. tostring(args[3])
                        )
                    else
                        Shared.logLine("[Macro] ReplicaSignal ERROR -> " .. tostring(err))
                    end

                    return ok
                end

                local cycleStarted = false
                local hasCompletedRound = false
                local startCooldown = 0

                -- Play Macro owns only the in-game Start/Vote signal.
                -- Auto Replay/Next stay in the Game tab and are handled by Joiner.
                macroStatusLabel.Text = "Sending Start..."
                fireSignal(87, "Response", true)

                while Config.PlayMacro do
                    local state = getCurrentGameState()

                    if state == "InProgress" then
                        if not cycleStarted then
                            cycleStarted = true
                            hasCompletedRound = true
                            macroStatusLabel.Text = "Starting macro..."

                            task.spawn(function()
                                runMacroOnce(macroData)
                            end)
                        end

                        startCooldown = os.clock()
                    else
                        -- Invalidate the previous round's Macro worker as soon as the
                        -- game leaves InProgress. This prevents Retry=0 or replication
                        -- waits from leaking into the next round.
                        if cycleStarted then
                            cycleStarted = false
                            isPlayingMacro = false
                            macroRunId += 1
                            Shared.isPlayingMacro = false
                        end

                        -- Initial start is always allowed. After a completed round,
                        -- keep the macro alive only when Game -> Auto Replay or Auto Next
                        -- is enabled; Joiner owns those transitions.
                        if hasCompletedRound and not Config.AutoReplay and not Config.AutoNext then
                            Config.PlayMacro = false
                            playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
                            playBtn.Text = "▶ Play Macro"
                            macroStatusLabel.Text = "Finished"
                            break
                        end

                        -- Only the first round needs Macro to send Start while
                        -- waiting in the pre-round state. After a completed round,
                        -- wait for Game -> Auto Replay/Next to create the next InProgress
                        -- state; do not spam the Start vote during that transition.
                        if not hasCompletedRound
                            and os.clock() - startCooldown >= 0.75 then
                            startCooldown = os.clock()
                            macroStatusLabel.Text = "Starting game..."
                            fireSignal(87, "Response", true)
                        elseif hasCompletedRound then
                            macroStatusLabel.Text = "Waiting for Replay/Next..."
                        end

                        cycleStarted = false
                    end

                    task.wait(0.3)
                end

                isPlayingMacro = false
                Shared.isPlayingMacro = false
            end)
        else
            isPlayingMacro = false
            Shared.isPlayingMacro = false
            playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            playBtn.Text = "▶ Play Macro"
            macroStatusLabel.Text = "Stopped"
        end
    end)

    return true
end

return Macro