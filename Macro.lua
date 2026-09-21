--!strict
local Macro = {}

function Macro.Init(Shared, UI)
    local Config = Shared.Config
    local savedMacros = Shared.savedMacros
    local saveMacrosToFile = Shared.saveMacrosToFile
    local showTopNotification = Shared.showTopNotification
    local HttpService = Shared.HttpService
    local captureVisiblePlacementCost = Shared.captureVisiblePlacementCost
    local getCurrentYen = Shared.getCurrentYen
    local getWaveInfo = Shared.getWaveInfo
    local copySessionLogToClipboard = Shared.copySessionLogToClipboard

    local tabs = UI.tabs
    local macroTab = tabs["Macro"]

    local recordedActions = {}
    local recordStartTime = 0
    local recordPlacementCount = 0
    local recordUnitIdMap = {}
    local scannedUnitsDatabase = {}

    -- نظام استكشاف وجلب الشخصيات (محدث ليتعامل مع الدوال بمرونة تامة وتجنب أي أخطاء)
    task.spawn(function()
        print("[Macro System] Starting Units scan...")
        local success, err = pcall(function()
            local repStorage = game:GetService("ReplicatedStorage")
            local unitsModule = nil
            
            for _, descendant in ipairs(repStorage:GetDescendants()) do
                if descendant.Name == "Units" and descendant:IsA("ModuleScript") then
                    unitsModule = descendant
                    break
                end
            end

            if unitsModule then
                print("[Macro System] Found Units ModuleScript at: " .. unitsModule:GetFullName())
                local ok, unitsData = pcall(require, unitsModule)
                
                if ok then
                    print("[Macro System] Module required successfully. Type: " .. type(unitsData))
                    
                    -- التعامل الذكي مع الدوال وإرجاع الجداول بأمان
                    if type(unitsData) == "function" then
                        local callOk, res = pcall(unitsData)
                        if callOk and type(res) == "table" then
                            unitsData = res
                            print("[Macro System] Function executed and returned table successfully.")
                        else
                            local callOk2, res2 = pcall(unitsData, {})
                            if callOk2 and type(res2) == "table" then
                                unitsData = res2
                                print("[Macro System] Function executed with {} and returned table.")
                            else
                                local callOk3, res3 = pcall(unitsData, game)
                                if callOk3 and type(res3) == "table" then
                                    unitsData = res3
                                    print("[Macro System] Function executed with game and returned table.")
                                else
                                    print("[Macro System] Function did not return a table, using safe fallback table.")
                                    unitsData = {}
                                end
                            end
                        end
                    end

                    if type(unitsData) == "table" then
                        if type(unitsData.GetAll) == "function" then pcall(function() unitsData = unitsData:GetAll() end)
                        elseif type(unitsData.GetUnits) == "function" then pcall(function() unitsData = unitsData:GetUnits() end)
                        elseif type(unitsData.Get) == "function" then pcall(function() unitsData = unitsData:Get() end)
                        end

                        local actualList = unitsData
                        if type(unitsData.Data) == "table" then actualList = unitsData.Data
                        elseif type(unitsData.Units) == "table" then actualList = unitsData.Units
                        elseif type(unitsData.Rows) == "table" then actualList = unitsData.Rows
                        elseif type(unitsData.List) == "table" then actualList = unitsData.List
                        end

                        local totalUnits = 0
                        if type(actualList) == "table" then
                            for key, value in pairs(actualList) do
                                totalUnits = totalUnits + 1
                            end
                        end
                        print("[Macro System] unit list built successfully: " .. totalUnits .. " units")
                    else
                        print("[Macro System] Initialized with safe table format.")
                    end
                else
                    warn("[Macro System] Failed to require module! Error: " .. tostring(unitsData))
                end
            else
                warn("[Macro System] Could not find any ModuleScript named 'Units'!")
            end
        end)
        
        if not success then
            warn("[Macro System] Critical Error in scan: " .. tostring(err))
        end
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
                    local innerAction = nil
                    for _, arg in ipairs(packedArgs) do
                        if typeof(arg) == "string" then
                            innerAction = arg
                            break
                        end
                    end
                    local lowerInner = innerAction and innerAction:lower() or ""

                    local actionDesc = "Other"
                    if lowerInner:find("upgrade") or lowerInner:find("lvl") or lowerInner:find("level") or lowerInner:find("priority") then
                        actionDesc = "UnitUpgrade"
                    elseif lowerInner:find("place") or lowerInner:find("spawn") or lowerInner:find("deploy") then
                        actionDesc = "UnitPlace"
                    end

                    if actionDesc == "UnitPlace" or actionDesc == "UnitUpgrade" then
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
        local playUnitIdMap = {}
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
                        playUnitIdMap[playPlacementCount] = playPlacementCount

                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end
                        task.wait(0.4)

                    elseif action.actionType == "UnitUpgrade" then
                        local targetOrder = action.linkedPlacementOrder
                        
                        scanAndBuildUnitDatabase()
                        
                        if targetOrder and scannedUnitsDatabase[targetOrder] then
                            local scannedTarget = scannedUnitsDatabase[targetOrder]
                            for i, arg in ipairs(args) do
                                if type(arg) == "number" or type(arg) == "string" then
                                    args[i] = scannedTarget.uniqueId
                                    break
                                end
                            end
                        end

                        if action.method == "InvokeServer" then
                            local ok, res = pcall(function()
                                return remoteObj:InvokeServer(table.unpack(args))
                            end)
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end
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
                showTopNotification("Macro saved to file!", 3)
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
