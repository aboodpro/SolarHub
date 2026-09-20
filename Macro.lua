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

    -- دالة للبحث عن الريموت في اللعبة
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

    -- دالة مساعدة للعثور على نموذج البرج في الWorkspace أثناء التشغيل
    local function findUnitInstanceInWorkspace(orderIndex)
        local count = 0
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and (obj.Name:find("Unit") or obj.Name:find("Tower") or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Config")) then
                -- يمكنك تعديل شرط البحث بناءً على هيكلة اللعبة إذا لزم الأمر
                count = count + 1
                if count == orderIndex then
                    return obj
                end
            end
        end
        -- خيار بديل في حال لم يتم العثور على نموذج مطابق تماماً، البحث العام عن أي مودل تم وضعه حديثاً
        return nil
    end

    -- اعتراض أوامر الشبكة أثناء التسجيل
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
                            local slotNum = typeof(packedArgs[3]) == "number" and packedArgs[3] or nil
                            actionEntry.yenCost = captureVisiblePlacementCost(slotNum)
                            pcall(function()
                                recordPlacementCount = recordPlacementCount + 1
                                actionEntry.placementOrder = recordPlacementCount
                                
                                -- حفظ مرجع الكائن إن وجد في الوسائط
                                for _, arg in ipairs(packedArgs) do
                                    if typeof(arg) == "Instance" then
                                        actionEntry.targetInstanceName = arg.Name
                                        break
                                    end
                                end
                            end)
                        elseif actionDesc == "UnitUpgrade" then
                            pcall(function()
                                local matchedOrder = recordPlacementCount
                                for _, arg in ipairs(packedArgs) do
                                    if typeof(arg) == "Instance" then
                                        -- محاولة مطابقة الترتيب بناءً على الكائن
                                        break
                                    end
                                end
                                actionEntry.linkedPlacementOrder = matchedOrder
                            end)
                        end
                    end
                end)
            end)
        end

        return table.unpack(result, 1, result.n)
    end)

    -- بناء واجهة الماكرو
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

    local playPlacementCount = 0
    local isPlayingMacro = false

    -- دالة التشغيل الذكية مع تصحيح ربط كائنات الترقية
    local function runMacroOnce(macroData)
        if isPlayingMacro then return end
        isPlayingMacro = true
        Shared.isPlayingMacro = true

        local lastTime = 0
        playPlacementCount = 0
        local totalActions = #macroData.actions

        for actionIndex, action in ipairs(macroData.actions) do
            if not isPlayingMacro then break end
            local gap = action.time - lastTime
            local actionLabel = action.actionType or "Action"

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

            -- تنفيذ الأمر والبحث عن كائن الترقية في الWorkspace بدقة
            pcall(function()
                local remoteObj = findRemote(action.remoteName, action.remoteClass)
                if remoteObj then
                    local args = { table.unpack(action.args, 1, action.args.n) }

                    if action.actionType == "UnitPlace" then
                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
                        else
                            remoteObj:FireServer(table.unpack(args))
                        end
                        task.wait(0.4)
                        playPlacementCount = playPlacementCount + 1

                    elseif action.actionType == "UnitUpgrade" then
                        -- البحث عن كائن البرج الفعلي في الWorkspace بناءً على الترتيب واستبداله في الوسائط
                        local targetOrder = action.linkedPlacementOrder or playPlacementCount
                        local unitInstance = findUnitInstanceInWorkspace(targetOrder)

                        if unitInstance then
                            for i, arg in ipairs(args) do
                                if typeof(arg) == "Instance" or i == 2 or i == 3 then
                                    args[i] = unitInstance
                                    break
                                end
                            end
                        end

                        if action.method == "InvokeServer" then
                            remoteObj:InvokeServer(table.unpack(args))
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
                showTopNotification(saved and "Macro saved to file!" or "Macro saved (memory only)", 3)
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
            playBtn.Text = "⏸ Playing (Remotes Only)"

            Shared.resetSessionLog()
            task.spawn(function()
                task.wait(60)
                local copied = copySessionLogToClipboard()
                showTopNotification(copied and "60s log copied to clipboard!" or "Copy failed", 4)
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
