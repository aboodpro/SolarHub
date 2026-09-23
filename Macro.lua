--!strict
local Macro = {}

function Macro.Init(Shared, UI)
    local Config = Shared.Config
    local savedMacros = Shared.savedMacros
    local saveMacrosToFile = Shared.saveMacrosToFile
    local showTopNotification = Shared.showTopNotification
    local playerGui = Shared.playerGui
    local logLine = Shared.logLine
    local HttpService = Shared.HttpService
    local captureVisiblePlacementCost = Shared.captureVisiblePlacementCost
    local getCurrentYen = Shared.getCurrentYen
    local waitForNewModel = Shared.waitForNewModel
    local clearPendingModels = Shared.clearPendingModels
    local performUnitUIUpgrade = Shared.performUnitUIUpgrade
    local isUnitModelValid = Shared.isUnitModelValid

    local tabs = UI.tabs
    local macroTab = tabs["Macro"]

    local recordedActions = {}
    local recordStartTime = 0
    local recordPlacementCount = 0
    local recordUnitIdMap = {}
    local scannedUnitsDatabase = {}
    local connectedAutoUpgradeButtons = setmetatable({}, { __mode = "k" })

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

    local function getButtonTextRecursive(button)
        local parts = {}
        if button:IsA("TextButton") then
            table.insert(parts, button.Text or "")
        end
        for _, child in ipairs(button:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                if child.Text and child.Text ~= "" then
                    table.insert(parts, child.Text)
                end
            end
        end
        return table.concat(parts, " ")
    end

    local function isAutoUpgradeButton(button)
        if not (button:IsA("TextButton") or button:IsA("ImageButton")) then
            return false
        end
        local hub = playerGui:FindFirstChild("SolarHub")
        if hub and button:IsDescendantOf(hub) then
            return false
        end
        local name = button.Name:lower()
        local text = getButtonTextRecursive(button):lower()
        return (name:find("auto") and name:find("upgrade"))
            or (text:find("auto") and text:find("upgrade"))
    end

    local function recordAutoUpgradeClick(button)
        if not Config.RecordMacro then return end
        if recordPlacementCount <= 0 then
            logLine("[Macro Record] Auto Upgrade clicked before any placement; ignoring.")
            return
        end

        table.insert(recordedActions, {
            time = os.clock() - recordStartTime,
            actionType = "UIAutoUpgrade",
            isUIReplay = true,
            uiClickButtonName = button.Name,
            linkedPlacementOrder = recordPlacementCount,
        })
        logLine(("[Macro Record] Recorded Auto Upgrade UI click -> placement #%d (%s)"):format(
            recordPlacementCount, button:GetFullName()))
    end

    local function connectAutoUpgradeButton(inst)
        if connectedAutoUpgradeButtons[inst] then return end
        if not isAutoUpgradeButton(inst) then return end
        connectedAutoUpgradeButtons[inst] = true
        inst.Activated:Connect(function()
            recordAutoUpgradeClick(inst)
        end)
    end

    for _, descendant in ipairs(playerGui:GetDescendants()) do
        connectAutoUpgradeButton(descendant)
    end
    playerGui.DescendantAdded:Connect(function(descendant)
        task.defer(function()
            connectAutoUpgradeButton(descendant)
        end)
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local packedArgs = table.pack(...)
        local isRemoteCall = (not checkcaller()) and (method == "FireServer" or method == "InvokeServer")
        local selfRef = self

        local result = table.pack(oldNamecall(self, ...))

        if isRemoteCall and Config.RecordMacro then
            task.spawn(function()
                pcall(function()
                    local remoteNameLower = selfRef.Name:lower()
                    
                    if remoteNameLower:find("chat") or remoteNameLower:find("ping") or remoteNameLower:find("analytics") or remoteNameLower:find("mouse") or remoteNameLower:find("camera") then
                        return
                    end

                    local actionDesc = nil
                    
                    if remoteNameLower:find("upgrade") or remoteNameLower:find("lvl") or remoteNameLower:find("level") or remoteNameLower:find("evolve") or remoteNameLower:find("rank") then
                        actionDesc = "UnitUpgrade"
                    elseif remoteNameLower:find("place") or remoteNameLower:find("spawn") or remoteNameLower:find("deploy") or remoteNameLower:find("buy") then
                        actionDesc = "UnitPlace"
                    else
                        for _, arg in ipairs(packedArgs) do
                            if typeof(arg) == "string" then
                                local lowerArg = arg:lower()
                                if lowerArg:find("upgrade") or lowerArg:find("lvl") then
                                    actionDesc = "UnitUpgrade"
                                    break
                                elseif lowerArg:find("place") or lowerArg:find("spawn") or lowerArg:find("deploy") then
                                    actionDesc = "UnitPlace"
                                    break
                                end
                            end
                        end
                    end

                    if actionDesc then
                        local actionEntry = {
                            time = os.clock() - recordStartTime,
                            actionType = actionDesc,
                            remoteName = selfRef.Name,
                            remoteClass = selfRef.ClassName,
                            method = method,
                            args = packedArgs
                        }
                        table.insert(recordedActions, actionEntry)

                        if actionDesc == "UnitPlace" then
                            local slotNum = nil
                            pcall(function()
                                for _, arg in ipairs(packedArgs) do
                                    if typeof(arg) == "number" and arg < 10 then
                                        slotNum = arg
                                        break
                                    end
                                end
                            end)
                            
                            pcall(function()
                                actionEntry.yenCost = captureVisiblePlacementCost(slotNum)
                            end)

                            pcall(function()
                                recordPlacementCount = recordPlacementCount + 1
                                actionEntry.placementOrder = recordPlacementCount
                                recordUnitIdMap[recordPlacementCount] = recordPlacementCount
                            end)
                        elseif actionDesc == "UnitUpgrade" then
                            pcall(function()
                                actionEntry.linkedPlacementOrder = recordPlacementCount
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
        local playbackUnitsByOrder = {}
        local totalActions = #macroData.actions

        for actionIndex, action in ipairs(macroData.actions) do
            if not isPlayingMacro then break end
            local gap = action.time - lastTime
            local actionLabel = action.actionType or "Action"

            if action.yenCost then
                macroStatusLabel.Text = ("[%d/%d] Waiting for Yen (Cost: %d)..."):format(actionIndex, totalActions, action.yenCost)
                while isPlayingMacro do
                    local yen = getCurrentYen()
                    if yen and yen >= action.yenCost then
                        break
                    end
                    task.wait(0.3)
                end
            elseif gap > 0 then
                local remaining = gap
                while remaining > 0 and isPlayingMacro do
                    macroStatusLabel.Text = ("[%d/%d] Waiting %.1fs (%s)"):format(actionIndex, totalActions, remaining, actionLabel)
                    local step = math.min(0.1, remaining)
                    task.wait(step)
                    remaining = remaining - step
                end
            end
            lastTime = action.time

            pcall(function()
                macroStatusLabel.Text = ("[%d/%d] Executing: %s"):format(actionIndex, totalActions, actionLabel)
            end)

            pcall(function()
                local remoteObj = findRemote(action.remoteName, action.remoteClass)
                if remoteObj then
                    local args = { table.unpack(action.args, 1, action.args.n) }

                    if action.actionType == "UnitPlace" then
                        playPlacementCount = playPlacementCount + 1
                        clearPendingModels()

                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end

                        -- Wait for the actual newly spawned unit so later upgrades/Auto Upgrade
                        -- can target the new unit instead of the stale recorded instance/ID.
                        local newUnit = waitForNewModel(3)
                        if newUnit and isUnitModelValid(newUnit) then
                            playbackUnitsByOrder[playPlacementCount] = newUnit
                            print(("[Macro] Placement #%d mapped to %s"):format(
                                playPlacementCount, newUnit:GetFullName()))
                        else
                            warn(("[Macro] Could not map placement #%d to a spawned unit."):format(playPlacementCount))
                        end
                        task.wait(0.2)

                    elseif action.actionType == "UIAutoUpgrade" then
                        local targetOrder = action.linkedPlacementOrder
                        local targetModel = targetOrder and playbackUnitsByOrder[targetOrder]
                        if targetModel and isUnitModelValid(targetModel) then
                            local buttonName = action.uiClickButtonName or "AutoUpgradeButton"
                            performUnitUIUpgrade(targetModel, buttonName)
                            task.wait(0.3)
                        else
                            warn(("[Macro] Auto Upgrade target not found for placement #%s"):format(tostring(targetOrder)))
                        end

                    elseif action.actionType == "UnitUpgrade" then
                        local targetOrder = action.linkedPlacementOrder
                        local targetModel = targetOrder and playbackUnitsByOrder[targetOrder]

                        if targetModel and isUnitModelValid(targetModel) then
                            local targetId = targetModel:GetAttribute("Id") or targetModel.Name
                            local replaced = false

                            -- Prefer the argument type that was recorded. If the game used a
                            -- Model instance, send the new Model; otherwise replace only the
                            -- first plausible unit identifier, preserving other arguments.
                            for i, arg in ipairs(args) do
                                if typeof(arg) == "Instance" then
                                    args[i] = targetModel
                                    replaced = true
                                    break
                                end
                            end

                            if not replaced then
                                for i, arg in ipairs(args) do
                                    if type(arg) == "string" or type(arg) == "number" then
                                        args[i] = targetId
                                        replaced = true
                                        break
                                    end
                                end
                            end

                            if not replaced then
                                warn(("[Macro] Could not replace UnitUpgrade target for placement #%s"):format(tostring(targetOrder)))
                            end
                        else
                            -- Legacy fallback for macros recorded before placement mapping.
                            scanAndBuildUnitDatabase()
                            if targetOrder and scannedUnitsDatabase[targetOrder] then
                                local scannedTarget = scannedUnitsDatabase[targetOrder]
                                for i, arg in ipairs(args) do
                                    if type(arg) == "number" or type(arg) == "string" then
                                        args[i] = scannedTarget.uniqueId
                                        break
                                    end
                                end
                            else
                                warn(("[Macro] UnitUpgrade target not found for placement #%s"):format(tostring(targetOrder)))
                            end
                        end

                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end
                        task.wait(0.3)
                    else
                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end
                    end
                else
                    warn("[Macro] Remote not found: " .. tostring(action.remoteName))
                end
            end)
        end

        isPlayingMacro = false
        Shared.isPlayingMacro = false
    end

    Shared.runMacroOnce = runMacroOnce

    createBtn.MouseButton1Click:Connect(function()
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

    recordBtn.MouseButton1Click:Connect(function()
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
            recordBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            recordBtn.Text = "🔴 Recording..."
            showTopNotification("Recording started...", 3)
        else
            recordBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            recordBtn.Text = "🔴 Record Macro"
            if savedMacros[Config.CurrentMacroName] then
                savedMacros[Config.CurrentMacroName].actions = recordedActions
                saveMacrosToFile()
                showTopNotification("Macro saved to file (" .. #recordedActions .. " actions)!", 3)
                print("[Macro Record] Saved " .. #recordedActions .. " actions.")
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
            showTopNotification("Macro is empty!", 3)
            return
        end

        Config.PlayMacro = not Config.PlayMacro

        if Config.PlayMacro then
            playBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
            playBtn.Text = "⏸ Playing..."

            task.spawn(function()
                while Config.PlayMacro do
                    runMacroOnce(macroData)
                    task.wait(2)
                end
            end)
        else
            playBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            playBtn.Text = "▶ Play Macro"
        end
    end)
end

return Macro
