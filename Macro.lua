--!strict
local Macro = {}

function Macro.Init(Shared, UI)
    local Config = Shared.Config
    local savedMacros = Shared.savedMacros
    local saveMacrosToFile = Shared.saveMacrosToFile
    local showTopNotification = Shared.showTopNotification
    local HttpService = Shared.HttpService
    local serializeMacros = Shared.serializeMacros
    local isRemoteValid = Shared.isRemoteValid
    local waitForNewModel = Shared.waitForNewModel
    local captureVisibleUpgradeCost = Shared.captureVisibleUpgradeCost
    local captureVisiblePlacementCost = Shared.captureVisiblePlacementCost
    local performUnitUIUpgrade = Shared.performUnitUIUpgrade
    local getCurrentYen = Shared.getCurrentYen
    local getWaveInfo = Shared.getWaveInfo
    local copySessionLogToClipboard = Shared.copySessionLogToClipboard

    local tabs = UI.tabs
    local macroTab = tabs["Macro"]

    local recordedActions = {}
    local recordStartTime = 0
    local recordPlacementCount = 0
    local recordUnitIdMap = {}

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local packedArgs = table.pack(...)
        local isRemoteCall = (not checkcaller()) and (method == "FireServer" or method == "InvokeServer")
        local selfRef = self
        local selfName = isRemoteCall and self.Name or nil

        local result = table.pack(oldNamecall(self, ...))

        if isRemoteCall and Config.RecordMacro then
            task.spawn(function()
                pcall(function()
                    local actionDesc = "Remote"
                    local innerAction = nil
                    for _, arg in ipairs(packedArgs) do
                        if typeof(arg) == "string" then
                            innerAction = arg
                            break
                        end
                    end
                    local lowerInner = innerAction and innerAction:lower() or ""

                    if lowerInner:find("upgrade") or lowerInner:find("lvl") or lowerInner:find("level") then
                        actionDesc = "ManualUpgrade"
                    elseif lowerInner:find("place") or lowerInner:find("spawn") or lowerInner:find("deploy") then
                        actionDesc = "PlaceOrUpdateUnit"
                    else
                        actionDesc = "Other: " .. (selfName or "")
                    end

                    if actionDesc == "PlaceOrUpdateUnit" or actionDesc == "ManualUpgrade" then
                        local actionEntry = {
                            time = os.clock() - recordStartTime,
                            actionType = actionDesc,
                            remote = selfRef,
                            method = method,
                            args = packedArgs
                        }
                        table.insert(recordedActions, actionEntry)

                        if actionDesc == "PlaceOrUpdateUnit" then
                            local slotNum = typeof(packedArgs[3]) == "number" and packedArgs[3] or nil
                            actionEntry.yenCost = captureVisiblePlacementCost(slotNum)
                            Shared.clearPendingModels()
                            task.spawn(function()
                                Shared.lastIncomingSignalValue = nil
                                local newModel = waitForNewModel(2)
                                task.wait(0.3)
                                pcall(function()
                                    recordPlacementCount = recordPlacementCount + 1
                                    actionEntry.placementOrder = recordPlacementCount
                                    recordUnitIdMap[recordPlacementCount] = {
                                        model = newModel,
                                        name = newModel and newModel.Name or nil,
                                        replicaId = Shared.lastIncomingSignalValue or (packedArgs[3] and tostring(packedArgs[3]))
                                    }
                                end)
                            end)
                        elseif actionDesc == "ManualUpgrade" then
                            pcall(function()
                                local actionName = typeof(packedArgs[2]) == "string" and packedArgs[2] or ""
                                local isAuto = actionName:find("AutoUpgrade") ~= nil
                                actionEntry.uiClickButtonName = isAuto and "AutoUpgradeButton" or "UpgradeButton"

                                local unitId = packedArgs[3]
                                local matchedOrder = recordPlacementCount

                                if unitId then
                                    for order, data in pairs(recordUnitIdMap) do
                                        if tostring(data.replicaId) == tostring(unitId) then
                                            matchedOrder = order
                                            break
                                        end
                                    end
                                end

                                actionEntry.linkedPlacementOrder = matchedOrder
                                actionEntry.isUIReplay = true
                                actionEntry.yenCost = captureVisibleUpgradeCost()
                            end)
                        end
                    end
                end)
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
    Instance.new("UICorner", createBtn).CornerRadius = UDim.new(0, 6)

    local hisMacrosSec = Instance.new("Frame")
    hisMacrosSec.Size = UDim2.new(1, 0, 0, 236)
    hisMacrosSec.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    hisMacrosSec.Parent = macroTab
    Instance.new("UICorner", hisMacrosSec).CornerRadius = UDim.new(0, 6)

    local hisHeader = Instance.new("TextButton")
    hisHeader.Size = UDim2.new(1, -16, 0, 26)
    hisHeader.Position = UDim2.fromOffset(8, 4)
    hisHeader.BackgroundTransparency = 1
    hisHeader.Font = Enum.Font.GothamBold
    hisHeader.Text = "▼ His Macros (Toggle)"
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
    macrosListContainer.Visible = false
    macrosListContainer.Parent = hisMacrosSec
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = macrosListContainer

    local dropdownOpen = false
    hisHeader.MouseButton1Click:Connect(function()
        dropdownOpen = not dropdownOpen
        macrosListContainer.Visible = dropdownOpen
        hisHeader.Text = dropdownOpen and "▲ His Macros (Toggle)" or "▼ His Macros (Toggle)"
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
    Instance.new("UICorner", deleteMacroBtn).CornerRadius = UDim.new(0, 4)

    local exportMacroBtn = Instance.new("TextButton")
    exportMacroBtn.Size = UDim2.new(1, -16, 0, 26)
    exportMacroBtn.Position = UDim2.fromOffset(8, 170)
    exportMacroBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 190)
    exportMacroBtn.Text = "📋 Copy Selected Macro as JSON"
    exportMacroBtn.Font = Enum.Font.GothamBold
    exportMacroBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    exportMacroBtn.TextSize = 10
    exportMacroBtn.Parent = hisMacrosSec
    Instance.new("UICorner", exportMacroBtn).CornerRadius = UDim.new(0, 4)

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
    Instance.new("UICorner", importMacroBox).CornerRadius = UDim.new(0, 4)

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
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

            btn.MouseButton1Click:Connect(function()
                Config.CurrentMacroName = macroName
                showTopNotification(string.format("Macro '%s' selected.", macroName), 3)
                refreshMacroList()
            end)
        end
        macrosListContainer.CanvasSize = UDim2.new(0, 0, 0, count * 28)
    end

    refreshMacroList()

    deleteMacroBtn.MouseButton1Click:Connect(function()
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

    exportMacroBtn.MouseButton1Click:Connect(function()
        if Config.CurrentMacroName == "" or not savedMacros[Config.CurrentMacroName] then
            showTopNotification("Select a macro first!", 2)
            return
        end
        local ok, encoded = pcall(function()
            local single = { [Config.CurrentMacroName] = savedMacros[Config.CurrentMacroName] }
            return HttpService:JSONEncode(serializeMacros(single))
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
    Instance.new("UICorner", recordBtn).CornerRadius = UDim.new(0, 4)

    local playBtn = Instance.new("TextButton")
    playBtn.Size = UDim2.new(1, -16, 0, 32)
    playBtn.Position = UDim2.fromOffset(8, 44)
    playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    playBtn.Text = "▶ Play Macro"
    playBtn.Font = Enum.Font.GothamBold
    playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    playBtn.TextSize = 10
    playBtn.Parent = recordSec
    Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 4)

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
    Instance.new("UICorner", macroStatusLabel).CornerRadius = UDim.new(0, 4)

    local isPlayingMacro = false

    local function runMacroOnce(macroData)
        if isPlayingMacro then return end
        isPlayingMacro = true
        Shared.isPlayingMacro = true

        local lastTime = 0
        local playPlacementCount = 0
        local playUnitIdMap = {}
        local totalActions = #macroData.actions

        for actionIndex, action in ipairs(macroData.actions) do
            if not isPlayingMacro then break end
            local gap = action.time - lastTime
            local actionLabel = (action.isUIReplay and action.uiClickButtonName)
                or (action.actionType == "PlaceOrUpdateUnit" and "Place Unit")
                or (action.actionType or "Action")

            if action.yenCost then
                while isPlayingMacro do
                    local yen = getCurrentYen()
                    if yen and yen >= action.yenCost then
                        pcall(function()
                            macroStatusLabel.Text = ("Action %d/%d (%s): Ready! (Yen %d/%d)"):format(
                                actionIndex, totalActions, actionLabel, yen, action.yenCost)
                        end)
                        break
                    end
                    pcall(function()
                        if yen then
                            local missing = action.yenCost - yen
                            macroStatusLabel.Text = ("Action %d/%d (%s): Missing %d Yen (have %d/%d)"):format(
                                actionIndex, totalActions, actionLabel, missing, yen, action.yenCost)
                        else
                            macroStatusLabel.Text = ("Action %d/%d (%s): waiting for Yen data..."):format(
                                actionIndex, totalActions, actionLabel)
                        end
                    end)
                    task.wait(0.3)
                end
            elseif gap > 0 then
                local remaining = gap
                while remaining > 0 and isPlayingMacro do
                    local step = math.min(0.2, remaining)
                    pcall(function()
                        local yen = getCurrentYen()
                        local yenText = yen and (" | Yen: " .. tostring(yen)) or ""
                        macroStatusLabel.Text = ("Action %d/%d (%s) in %.1fs%s"):format(
                            actionIndex, totalActions, actionLabel, remaining, yenText)
                    end)
                    task.wait(step)
                    remaining = remaining - step
                end
            end
            lastTime = action.time

            pcall(function()
                macroStatusLabel.Text = ("Running action %d/%d: %s"):format(actionIndex, totalActions, actionLabel)
            end)

            pcall(function()
                if action.isUIReplay then
                    local entry = action.linkedPlacementOrder and playUnitIdMap[action.linkedPlacementOrder]
                    if entry and entry.model then
                        performUnitUIUpgrade(entry.model, action.uiClickButtonName)
                    end
                    return
                end

                if isRemoteValid(action) then
                    local args = { table.unpack(action.args, 1, action.args.n) }

                    local expectingPlacement = (action.actionType == "PlaceOrUpdateUnit")
                    if expectingPlacement then
                        Shared.lastIncomingSignalValue = nil
                        Shared.clearPendingModels()
                    end

                    if action.method == "InvokeServer" then
                        action.remote:InvokeServer(table.unpack(args))
                    else
                        action.remote:FireServer(table.unpack(args))
                    end

                    if expectingPlacement then
                        local newModel = waitForNewModel(2)
                        task.wait(0.3)
                        playPlacementCount = playPlacementCount + 1
                        playUnitIdMap[playPlacementCount] = {
                            model = newModel,
                            replicaId = Shared.lastIncomingSignalValue or (args[3] and tostring(args[3]))
                        }
                    end
                end
            end)
        end

        pcall(function()
            macroStatusLabel.Text = "Idle (waiting to loop)"
        end)

        isPlayingMacro = false
        Shared.isPlayingMacro = false
    end

    Shared.runMacroOnce = runMacroOnce

    createBtn.MouseButton1Click:Connect(function()
        local name = nameInput.Text
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

    recordBtn.MouseButton1Click:Connect(function()
        if Config.CurrentMacroName == "" then
            showTopNotification("Select a macro from 'His Macros' first!", 3)
            return
        end
        Config.RecordMacro = not Config.RecordMacro
        if Config.RecordMacro then
            recordedActions = {}
            recordStartTime = os.clock()
            recordPlacementCount = 0
            recordUnitIdMap = {}
            recordBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            recordBtn.Text = "🔴 Recording..."
            showTopNotification("Recording started...", 3)
        else
            recordBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            recordBtn.Text = "🔴 Record Macro"
            if savedMacros[Config.CurrentMacroName] then
                savedMacros[Config.CurrentMacroName].actions = recordedActions
                local saved = saveMacrosToFile()
                showTopNotification(saved and "Macro saved to file!" or "Macro saved (memory only - file save unsupported)", 3)
            else
                showTopNotification("Macro saved!", 3)
            end
        end
    end)

    playBtn.MouseButton1Click:Connect(function()
        if Config.CurrentMacroName == "" or not savedMacros[Config.CurrentMacroName] then
            showTopNotification("Select a valid macro first!", 3)
            return
        end
        local macroData = savedMacros[Config.CurrentMacroName]
        if #macroData.actions == 0 then
            showTopNotification("Macro is empty! Record actions first.", 3)
            return
        end

        Config.PlayMacro = not Config.PlayMacro

        if Config.PlayMacro then
            playBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
            playBtn.Text = "⏸ Playing (Smart Loop)"

            Shared.resetSessionLog()
            task.spawn(function()
                task.wait(60)
                local copied = copySessionLogToClipboard()
                showTopNotification(copied and "60s log copied to clipboard!" or "Copy failed - read console manually", 4)
            end)

            task.spawn(function()
                local lastSeenWave = nil
                while Config.PlayMacro do
                    runMacroOnce(macroData)

                    local waitStart = os.clock()
                    while Config.PlayMacro and (os.clock() - waitStart) < 120 do
                        local wave, maxWave = getWaveInfo()
                        if wave then
                            pcall(function()
                                macroStatusLabel.Text = ("Waiting for new match... (wave %s/%s)"):format(
                                    tostring(wave), tostring(maxWave or "?"))
                            end)
                            if lastSeenWave and wave < lastSeenWave then
                                lastSeenWave = wave
                                break
                            end
                            lastSeenWave = wave
                        else
                            task.wait(2)
                            break
                        end
                        task.wait(0.5)
                    end
                end
            end)
        else
            playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            playBtn.Text = "▶ Play Macro"
            pcall(function()
                macroStatusLabel.Text = "Idle"
            end)
        end
    end)
end

return Macro
