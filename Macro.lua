--!strict
local Macro = {}

function Macro.Init(Shared, UI)
    local Config = Shared.Config
    local savedMacros = Shared.savedMacros
    local saveMacrosToFile = Shared.saveMacrosToFile
    local showTopNotification = Shared.showTopNotification
    local HttpService = Shared.HttpService
    local getCurrentYen = Shared.getCurrentYen

    local tabs = UI.tabs
    local macroTab = tabs["Macro"]

    local recordedActions = {}
    local recordStartTime = 0
    local recordPlacementCount = 0
    local recordUnitIdMap = {}
    local recordedPlacementCFrames = {}
    local pendingRecordWorkers = 0
    local scannedUnitsDatabase = {}

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local replicaClientModule = nil
    pcall(function()
        replicaClientModule = require(ReplicatedStorage.Shared.ReplicaClient)
    end)

    local function getPlayerReplica()
        if not replicaClientModule or type(replicaClientModule.FromId) ~= "function" then
            return nil
        end

        for id = 1, 300 do
            local ok, replica = pcall(replicaClientModule.FromId, id)
            if ok and replica and replica.Data and replica.Data.TotalUnitsPlaced ~= nil then
                return replica
            end
        end

        return nil
    end

    local function getOwnedGameUnitReplicas()
        local out = {}
        local playerReplica = getPlayerReplica()
        if not playerReplica or not playerReplica.Data then
            return out
        end

        local playerId = tostring(playerReplica.Data.ID or "")
        if playerId == "" then
            return out
        end

        if not replicaClientModule or type(replicaClientModule.FromId) ~= "function" then
            return out
        end

        for id = 1, 2000 do
            local ok, replica = pcall(replicaClientModule.FromId, id)
            if ok and replica and replica.Data then
                local data = replica.Data
                if tostring(data.GamePlayerID or "") == playerId
                    and data.CFrame ~= nil
                    and data.UnitID ~= nil
                    and data.MaxUpgrade ~= nil then
                    out[tostring(id)] = replica
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
        if not replicaId or not replicaClientModule or type(replicaClientModule.FromId) ~= "function" then
            return nil
        end

        local ok, replica = pcall(replicaClientModule.FromId, replicaId)
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
                    local distance = 0

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

    -- نظام فحص آمن لقاعدة بيانات الوحدات (99 وحدة)
    task.spawn(function()
        print("[Macro System] Starting Units scan (Safe Mode)...")
        pcall(function()
            local repStorage = game:GetService("ReplicatedStorage")
            local actualList = {}

            for _, descendant in ipairs(repStorage:GetDescendants()) do
                if descendant:IsA("ModuleScript") then
                    local name = descendant.Name:lower()
                    local fullName = descendant:GetFullName()
                    
                    if not fullName:find("FusionPackage") and not fullName:find("Components") and not fullName:find("UI") and not fullName:find("SandboxControls") then
                        if name == "units" or name == "unitdata" or name == "characters" or name == "unitconfig" then
                            local ok, data = pcall(require, descendant)
                            if ok and type(data) == "table" and next(data) ~= nil then
                                actualList = data
                                print("[Macro System] Loaded units data from: " .. descendant:GetFullName())
                                break
                            end
                        end
                    end
                end
            end
        end)
    end)

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

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local packedArgs = table.pack(...)
        local isRemoteCall = (not checkcaller()) and (method == "FireServer" or method == "InvokeServer")
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
            pendingRecordWorkers = pendingRecordWorkers + 1
            task.spawn(function()
                pcall(function()
                    local remoteNameLower = selfRef.Name:lower()
                    
                    if remoteNameLower:find("chat") or remoteNameLower:find("ping") or remoteNameLower:find("analytics") or remoteNameLower:find("mouse") or remoteNameLower:find("camera") then
                        return
                    end

                    local actionDesc = nil
                    local isReplicaSignal = (selfRef.Name == "ReplicaSignal")

                    if isReplicaSignal then
                        -- ReplicaSignal exposes the real gameplay operation in args[2].
                        -- Only these are meaningful Macro actions.
                        actionDesc = getReplicaSignalAction(packedArgs)
                    elseif remoteNameLower == "_updatenode" or remoteNameLower:find("networkevents") then
                        -- Visual/node traffic such as PlacementVFX is not a Macro action.
                        actionDesc = nil
                    else
                        -- Keep the generic fallback for other gameplay remotes, but do not
                        -- infer an action from arbitrary argument strings like "PlacementVFX".
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
                        }

                        if isReplicaSignal and (actionDesc == "UnitUpgrade" or actionDesc == "UnitAutoUpgrade") then
                            actionEntry.recordedUnitId = packedArgs[3]
                            actionEntry.unitIdArgIndex = 3
                        end

                        table.insert(recordedActions, actionEntry)
                        print(("[Macro Record] #%d %s"):format(#recordedActions, actionDesc))

                        if actionDesc == "UnitPlace" then
                            recordPlacementCount = recordPlacementCount + 1
                            actionEntry.placementOrder = recordPlacementCount
                            recordedPlacementCFrames[recordPlacementCount] = packedArgs[4]

                        elseif actionDesc == "UnitUpgrade" then
                            actionEntry.linkedPlacementOrder = resolveRecordedPlacementOrder(packedArgs[3])

                            pcall(function()
                                local yenAfter = getCurrentYen()
                                local deadline = os.clock() + 1
                                while yenBefore and yenAfter == yenBefore and os.clock() < deadline do
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
                                    tostring(yenAfter)))
                            end)

                        elseif actionDesc == "UnitAutoUpgrade" then
                            actionEntry.linkedPlacementOrder = resolveRecordedPlacementOrder(packedArgs[3])
                        end
                    end
                end)
                pendingRecordWorkers = math.max(0, pendingRecordWorkers - 1)
            end)
        end

        return table.unpack(result, 1, result.n)
    end)

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
    macroOptionsSec.Size = UDim2.new(1, 0, 0, 126)
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

    makeOptionToggle("Replay after stage", 6, "MacroReplay")
    makeOptionToggle("Next after stage", 34, "MacroNext")
    makeOptionToggle("Ignore Timing", 62, "MacroIgnoreTiming")

    local retryLabel = Instance.new("TextLabel")
    retryLabel.Size = UDim2.new(0.45, -8, 0, 24)
    retryLabel.Position = UDim2.fromOffset(8, 90)
    retryLabel.BackgroundTransparency = 1
    retryLabel.Text = "Retry:"
    retryLabel.Font = Enum.Font.GothamBold
    retryLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    retryLabel.TextSize = 10
    retryLabel.TextXAlignment = Enum.TextXAlignment.Left
    retryLabel.Parent = macroOptionsSec

    local retryBox = Instance.new("TextBox")
    retryBox.Size = UDim2.new(0.55, -8, 0, 24)
    retryBox.Position = UDim2.new(0.45, 0, 0, 90)
    retryBox.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    retryBox.TextColor3 = Color3.fromRGB(220, 220, 220)
    retryBox.Text = tostring(Config.MacroRetry)
    retryBox.PlaceholderText = "1-10"
    retryBox.ClearTextOnFocus = false
    retryBox.Font = Enum.Font.Gotham
    retryBox.TextSize = 10
    retryBox.Parent = macroOptionsSec
    Instance.new("UICorner", retryBox).CornerRadius = UDim.new(0, 6)

    retryBox.FocusLost:Connect(function()
        local value = math.clamp(math.floor(tonumber(retryBox.Text) or Config.MacroRetry or 2), 1, 10)
        Config.MacroRetry = value
        retryBox.Text = tostring(value)
    end)

    local isPlayingMacro = false
    local macroGameSession = 0
    local macroGameWasInProgress = false
    local macroLastStartedSession = {}

    local function getCurrentGameState()
        if not replicaClientModule or type(replicaClientModule.FromId) ~= "function" then
            return nil
        end

        for id = 1, 200 do
            local ok, replica = pcall(replicaClientModule.FromId, id)
            if ok and replica and replica.Data and replica.Data.CurrentGameState ~= nil then
                return tostring(replica.Data.CurrentGameState)
            end
        end

        return nil
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

    local function verifyAction(action, beforeYen, beforeUnits)
        if action.actionType == "UnitUpgrade" or action.actionType == "UnitAutoUpgrade" then
            local targetId = action._playbackReplicaId
            if not targetId or not replicaClientModule or type(replicaClientModule.FromId) ~= "function" then
                return true
            end

            local deadline = os.clock() + 1
            while os.clock() < deadline and isPlayingMacro do
                local ok, replica = pcall(replicaClientModule.FromId, tonumber(targetId))
                if ok and replica and replica.Data then
                    if action.actionType == "UnitAutoUpgrade" then
                        -- Priority changes are difficult to verify generically.
                        return true
                    end

                    if beforeYen ~= nil and replica.Data.Yen == nil then
                        return true
                    end

                    local currentLevel = replica.Data.Level or replica.Data.Upgrade or replica.Data.UpgradeLevel
                    if currentLevel ~= nil then
                        return true
                    end
                end
                task.wait(0.08)
            end

            -- If the remote executed without an observable level field, don't
            -- falsely mark it as failed.
            return true
        elseif action.actionType == "UnitPlace" then
            local deadline = os.clock() + 0.8
            while os.clock() < deadline and isPlayingMacro do
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

    local function runMacroOnce(macroData)
        if isPlayingMacro then return false end
        isPlayingMacro = true
        local playbackStartTime = os.clock()
        Shared.isPlayingMacro = true

        local lastTime = 0
        local playPlacementCount = 0
        local playbackUnitReplicaIds = {}
        local totalActions = #macroData.actions
        local ignoreTiming = Config.MacroIgnoreTiming == true
        local retryCount = math.clamp(tonumber(Config.MacroRetry) or 2, 1, 10)

        for actionIndex, action in ipairs(macroData.actions) do
            if not isPlayingMacro then break end

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
                while remaining > 0 and isPlayingMacro do
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

                while isPlayingMacro do
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

                    if yen and yen >= effectiveYenCost then break end
                    task.wait(0.2)
                end
            end

            if not isPlayingMacro then break end

            local success = false
            local lastError = "unknown"
            local attemptTotal = retryCount

            for attempt = 1, attemptTotal do
                if not isPlayingMacro then break end

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
                        if targetReplicaId and action.unitIdArgIndex then
                            args[action.unitIdArgIndex] = tostring(targetReplicaId)
                            action._playbackReplicaId = targetReplicaId
                        else
                            lastError = ("Target mapping missing for placement #%s"):format(tostring(targetOrder))
                            targetReplicaId = nil
                        end
                    end

                    if targetReplicaId or action.actionType == "UnitPlace" or (action.actionType ~= "UnitUpgrade" and action.actionType ~= "UnitAutoUpgrade") then
                        local tempAction = {
                            actionType = action.actionType,
                            args = args,
                            method = action.method,
                        }
                        local fired, err = fireAction(remoteObj, tempAction)
                        if fired then
                            if action.actionType == "UnitPlace" then
                                local newReplicaId = findNewUnitReplicaId(beforeIds, args[4], 3)
                                if newReplicaId then
                                    playbackUnitReplicaIds[action._playbackPlacementOrder] = newReplicaId
                                else
                                    lastError = "Placement could not be mapped"
                                end
                            end

                            local verified = verifyAction(action, nil, beforeIds)
                            if verified then
                                success = true
                            else
                                lastError = "Action verification failed"
                            end
                        else
                            lastError = err or "Remote call failed"
                        end
                    end
                end

                if success then break end

                if attempt < attemptTotal then
                    macroStatusLabel.Text = ("[%d/%d] %s | Retry %d/%d"):format(
                        actionIndex, totalActions, actionLabel, attempt, retryCount
                    )
                    task.wait(0.2)
                end
            end

            if not success then
                -- An action is skipped only after all configured retries fail.
                warn(("[Macro] Skipping action #%d after %d failed attempt(s): %s"):format(
                    actionIndex, attemptTotal, lastError
                ))
                macroStatusLabel.Text = ("[%d/%d] %s | SKIPPED"):format(
                    actionIndex, totalActions, actionLabel
                )
                task.wait(0.15)
            else
                macroStatusLabel.Text = ("[%d/%d] %s | SUCCESS"):format(
                    actionIndex, totalActions, actionLabel
                )
            end
        end

        isPlayingMacro = false
        Shared.isPlayingMacro = false
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
            recordedActions = {}
            recordStartTime = os.clock()
            recordPlacementCount = 0
            recordUnitIdMap = {}
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
            local saveDeadline = os.clock() + 1.5
            while pendingRecordWorkers > 0 and os.clock() < saveDeadline do
                task.wait(0.05)
            end

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
                local function getReplicaSignal()
                    local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
                    return folder and folder:FindFirstChild("ReplicaSignal")
                end

                local function fireSignal(...)
                    local remote = getReplicaSignal()
                    if not remote then return false end
                    return pcall(function()
                        remote:FireServer(...)
                    end)
                end

                local lastState = getCurrentGameState()
                local cycleStarted = false
                local transitionSent = false
                local lastStartAttempt = 0

                while Config.PlayMacro do
                    local state = updateMacroGameSession()

                    if state == "InProgress" and not cycleStarted then
                        cycleStarted = true
                        transitionSent = false
                        macroStatusLabel.Text = "Starting macro..."
                        task.spawn(function()
                            runMacroOnce(macroData)
                        end)
                    end

                    if lastState == "InProgress" and state ~= "InProgress" then
                        cycleStarted = false

                        if not transitionSent then
                            transitionSent = true
                            if Config.MacroReplay then
                                if fireSignal(77, "Restart") then
                                    macroStatusLabel.Text = "Replay requested..."
                                else
                                    macroStatusLabel.Text = "Replay request failed..."
                                end
                            elseif Config.MacroNext then
                                if fireSignal(77, "Next") then
                                    macroStatusLabel.Text = "Next requested..."
                                else
                                    macroStatusLabel.Text = "Next request failed..."
                                end
                            else
                                Config.PlayMacro = false
                                playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
                                playBtn.Text = "▶ Play Macro"
                                macroStatusLabel.Text = "Finished"
                                break
                            end
                        end
                    end

                    if state ~= "InProgress" and not transitionSent then
                        if os.clock() - lastStartAttempt >= 3 then
                            lastStartAttempt = os.clock()
                            if fireSignal(87, "Response", true) then
                                macroStatusLabel.Text = "Start requested..."
                            end
                        end
                    end

                    lastState = state
                    task.wait(0.5)
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
end

return Macro