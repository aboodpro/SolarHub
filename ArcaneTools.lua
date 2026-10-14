--!strict
-- SolarHub Arcane Tools: sealed-chest ESP and shared diagnostics controls.
local ArcaneTools = {}

local function normalize(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function getRoot(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance end
    if instance:IsA("Model") then
        return instance.PrimaryPart
            or instance:FindFirstChild("HumanoidRootPart", true)
            or instance:FindFirstChild("Base", true)
            or instance:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function safeClipboard(text)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        if ok then return true end
    end
    if type(toclipboard) == "function" then
        local ok = pcall(toclipboard, text)
        if ok then return true end
    end
    return false
end

function ArcaneTools.Init(Shared, UI, Context)
    local Config = Shared.Config
    local misc = UI.tabs and UI.tabs["Misc"]
    if not misc then error("[ArcaneTools] Misc tab missing") end

    local active = true
    local connections = {}
    local markers = setmetatable({}, {__mode = "k"})
    local seen = setmetatable({}, {__mode = "k"})
    local logLines = {}
    local MAX_LOGS = 250
    local stats = { detected = 0, created = 0, errors = 0, scans = 0, recovered = 0 }
    local startedAt = os.clock()
    local lastError = "None"
    local scanStatus = "Idle"
    local retryCount = 0
    local fullWorldScanDone = false
    local MAX_RETRIES = 3

    Config.ArcaneSealedChestESP = Config.ArcaneSealedChestESP == true
    Config.ArcaneSealedBronze = Config.ArcaneSealedBronze ~= false
    Config.ArcaneSealedNimbus = Config.ArcaneSealedNimbus ~= false
    Config.ArcaneSealedDark = Config.ArcaneSealedDark ~= false
    Config.SolarPerformanceMode = Config.SolarPerformanceMode == true
    Config.SolarRecoveryEnabled = Config.SolarRecoveryEnabled ~= false

    local function log(message)
        local line = ("[SolarDiagnostics %.2f] %s"):format(os.clock(), tostring(message))
        table.insert(logLines, line)
        if #logLines > MAX_LOGS then table.remove(logLines, 1) end
        print(line)
    end

    local function mark(instance)
        pcall(function()
            if type(getgenv) == "function" then
                instance:SetAttribute("SolarHubSessionToken", tostring(getgenv().SolarHubLoaderSession or ""))
            end
        end)
    end

    local function destroyMarker(target)
        local data = markers[target]
        if not data then return end
        pcall(function() if data.highlight then data.highlight:Destroy() end end)
        pcall(function() if data.billboard then data.billboard:Destroy() end end)
        markers[target] = nil
    end

    local function detectType(target)
        local parts = {target.Name}
        local model = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
        local current = target
        while current and current ~= workspace do
            table.insert(parts, current.Name)
            current = current.Parent
        end
        if model then
            local ok, attrs = pcall(function() return model:GetAttributes() end)
            if ok then
                for key, value in pairs(attrs) do
                    table.insert(parts, tostring(key))
                    table.insert(parts, tostring(value))
                end
            end
            for _, child in ipairs(model:GetDescendants()) do
                if child:IsA("ProximityPrompt") then
                    table.insert(parts, child.Name)
                    table.insert(parts, child.ActionText)
                    table.insert(parts, child.ObjectText)
                elseif child:IsA("StringValue") then
                    table.insert(parts, child.Name)
                    table.insert(parts, child.Value)
                end
            end
        end
        local all = normalize(table.concat(parts, " "))
        if not all:find("sealed", 1, true) then return nil end
        if all:find("darksealed", 1, true) or all:find("darksea", 1, true) then return "Dark" end
        if all:find("nimbussealed", 1, true) or all:find("nimbus", 1, true) then return "Nimbus" end
        if all:find("bronze sealed", 1, true) or all:find("bronze", 1, true) then return "Bronze" end
        if all:find("sealedchest", 1, true) then return "Sealed" end
        return nil
    end

    local function typeEnabled(kind)
        if kind == "Bronze" then return Config.ArcaneSealedBronze == true end
        if kind == "Nimbus" then return Config.ArcaneSealedNimbus == true end
        if kind == "Dark" then return Config.ArcaneSealedDark == true end
        return true
    end

    local function resolveChest(instance)
        if not instance or not instance.Parent then return nil end
        local current = instance
        while current and current ~= workspace do
            if (current:IsA("Model") or current:IsA("BasePart")) and detectType(current) then
                return current
            end
            current = current.Parent
        end
        return nil
    end

    local function createMarker(target, kind)
        if not Config.ArcaneSealedChestESP or markers[target] then return end
        if not target:IsDescendantOf(workspace) then return end
        local root = getRoot(target)
        if not root then return end
        local color = kind == "Dark" and Color3.fromRGB(185, 85, 255)
            or kind == "Nimbus" and Color3.fromRGB(75, 190, 255)
            or kind == "Bronze" and Color3.fromRGB(220, 150, 75)
            or Color3.fromRGB(90, 220, 190)

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarSealedChestESP"
        mark(highlight)
        highlight.Adornee = target
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0
        highlight.Parent = target

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarSealedChestESPInfo"
        mark(billboard)
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0
        billboard.Size = UDim2.fromOffset(250, 32)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = Shared.playerGui

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.15
        label.TextSize = 11
        label.Text = kind .. " Sealed Chest | STUDS: ?"
        label.Parent = billboard

        markers[target] = { highlight = highlight, billboard = billboard, label = label, root = root, kind = kind }
        stats.created += 1
    end

    local function inspect(instance)
        local target = resolveChest(instance)
        if not target then return end
        local kind = detectType(target)
        if not kind or not typeEnabled(kind) then return end
        if not seen[target] then
            seen[target] = true
            stats.detected += 1
            log(("Detected %s sealed chest at %s"):format(kind, target:GetFullName()))
        end
        if Config.ArcaneSealedChestESP then createMarker(target, kind) end
    end

    local function clearMarkers()
        for target in pairs(markers) do destroyMarker(target) end
    end

    local function scan()
        if not active or not Context.isSessionActive() then return end
        if not Config.ArcaneSealedChestESP then
            clearMarkers()
            scanStatus = "Disabled"
            return
        end
        scanStatus = "Scanning"
        stats.scans += 1
        local collection = game:GetService("CollectionService")
        local candidateSet = {}
        for _, tag in ipairs({"Chests", "Prompt_Chest"}) do
            local ok, tagged = pcall(function() return collection:GetTagged(tag) end)
            if ok then
                for _, item in ipairs(tagged) do candidateSet[item] = true end
            end
        end
        -- Map scan finds island/diving/structure chests; ship roots also catch
        -- sealed chests parented outside Map.
        local map = workspace:FindFirstChild("Map")
        local scanRoots = {}
        if not fullWorldScanDone then
            if map then table.insert(scanRoots, map) end
            for _, child in ipairs(workspace:GetChildren()) do
                local n = normalize(child.Name)
                if child ~= map and (n:find("ship", 1, true) or n:find("boat", 1, true) or n:find("npc", 1, true)) then
                    table.insert(scanRoots, child)
                end
            end
            for _, rootFolder in ipairs(scanRoots) do
                for _, item in ipairs(rootFolder:GetDescendants()) do
                    if item:IsA("Model") or item:IsA("BasePart") then
                        local n = normalize(item.Name)
                        if n:find("sealed", 1, true) or n == "chest" then candidateSet[item] = true end
                    end
                end
            end
            if map then fullWorldScanDone = true end
        end
        for item in pairs(candidateSet) do
            local ok, err = pcall(inspect, item)
            if not ok then
                stats.errors += 1
                lastError = tostring(err)
                log("Inspect error: " .. lastError)
            end
        end
        for target, data in pairs(markers) do
            if not target.Parent or not target:IsDescendantOf(workspace) or not typeEnabled(data.kind) then
                destroyMarker(target)
            else
                local root = getRoot(target)
                if root then
                    data.root = root
                    local character = Shared.player.Character
                    local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
                    local distance = playerRoot and (playerRoot.Position - root.Position).Magnitude
                    data.label.Text = ("%s Sealed Chest | STUDS: %s"):format(data.kind, distance and tostring(math.floor(distance + 0.5)) or "?")
                end
            end
        end
        scanStatus = "Running"
        retryCount = 0
    end

    -------------------------------------------------
    -- SEALED CHEST ESP: CONSISTENT CARD-BASED CONTROLS
    -------------------------------------------------
    local sealedSection = UI.createSection(misc, "Sealed Chest ESP", 300)
    local toggleRefreshers = {}

    local sealedRows = Instance.new("Frame")
    sealedRows.Name = "SealedChestOptions"
    sealedRows.Position = UDim2.fromOffset(10, 39)
    sealedRows.Size = UDim2.new(1, -20, 0, 162)
    sealedRows.BackgroundTransparency = 1
    sealedRows.Parent = sealedSection

    local rowsLayout = Instance.new("UIListLayout")
    rowsLayout.FillDirection = Enum.FillDirection.Vertical
    rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowsLayout.Padding = UDim.new(0, 6)
    rowsLayout.Parent = sealedRows

    local function makeToggle(parent, title, key, order, desc)
        local row = Instance.new("Frame")
        row.Name = key .. "Row"
        row.LayoutOrder = order
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
        row.BorderSizePixel = 0
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(63, 67, 82)
        stroke.Transparency = 0.72
        stroke.Thickness = 1
        stroke.Parent = row

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "Title"
        titleLabel.Position = UDim2.fromOffset(11, 3)
        titleLabel.Size = UDim2.new(1, -100, 0, 15)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamSemibold
        titleLabel.Text = title
        titleLabel.TextColor3 = Color3.fromRGB(239, 241, 247)
        titleLabel.TextSize = 10
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = row

        local descLabel = Instance.new("TextLabel")
        descLabel.Position = UDim2.fromOffset(11, 18)
        descLabel.Size = UDim2.new(1, -100, 0, 13)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Enum.Font.Gotham
        descLabel.Text = desc or "Enable or disable this option."
        descLabel.TextColor3 = Color3.fromRGB(151, 158, 174)
        descLabel.TextSize = 8
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = row

        local switch = Instance.new("TextButton")
        switch.Name = "State"
        switch.AnchorPoint = Vector2.new(1, 0.5)
        switch.Position = UDim2.new(1, -9, 0.5, 0)
        switch.Size = UDim2.fromOffset(62, 23)
        switch.BorderSizePixel = 0
        switch.AutoButtonColor = true
        switch.Font = Enum.Font.GothamBold
        switch.TextSize = 9
        switch.Parent = row
        Instance.new("UICorner", switch).CornerRadius = UDim.new(0, 7)

        local function refresh()
            local enabled = Config[key] == true
            switch.Text = enabled and "ON" or "OFF"
            switch.TextColor3 = enabled and Color3.fromRGB(255, 248, 231) or Color3.fromRGB(176, 182, 195)
            switch.BackgroundColor3 = enabled and Color3.fromRGB(183, 111, 31) or Color3.fromRGB(48, 52, 65)
            stroke.Color = enabled and Color3.fromRGB(202, 139, 62) or Color3.fromRGB(63, 67, 82)
            stroke.Transparency = enabled and 0.4 or 0.72
        end

        toggleRefreshers[key] = refresh
        refresh()

        switch.Activated:Connect(function()
            Config[key] = not (Config[key] == true)
            refresh()

            if key == "ArcaneSealedChestESP" and not Config[key] then
                clearMarkers()
            elseif key ~= "ArcaneSealedChestESP" and not Config[key] then
                for target, data in pairs(markers) do
                    if (key == "ArcaneSealedBronze" and data.kind == "Bronze")
                        or (key == "ArcaneSealedNimbus" and data.kind == "Nimbus")
                        or (key == "ArcaneSealedDark" and data.kind == "Dark") then
                        destroyMarker(target)
                    end
                end
            end

            log(title .. " = " .. tostring(Config[key]))
            task.defer(function() pcall(scan) end)
        end)
    end

    makeToggle(sealedRows, "Sealed Chest ESP", "ArcaneSealedChestESP", 1, "Independent from regular Treasure Chest ESP")
    makeToggle(sealedRows, "Bronze Sealed", "ArcaneSealedBronze", 2, "Bronze Sea sealed chests")
    makeToggle(sealedRows, "Nimbus Sealed", "ArcaneSealedNimbus", 3, "Nimbus Sea sealed chests")
    makeToggle(sealedRows, "Dark Sealed", "ArcaneSealedDark", 4, "Dark Sea sealed chests")

    local sourceCard = Instance.new("Frame")
    sourceCard.Name = "SealedChestGuide"
    sourceCard.Position = UDim2.fromOffset(10, 209)
    sourceCard.Size = UDim2.new(1, -20, 0, 76)
    sourceCard.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    sourceCard.BorderSizePixel = 0
    sourceCard.Parent = sealedSection
    Instance.new("UICorner", sourceCard).CornerRadius = UDim.new(0, 8)

    local sourceStroke = Instance.new("UIStroke")
    sourceStroke.Color = Color3.fromRGB(69, 72, 86)
    sourceStroke.Transparency = 0.72
    sourceStroke.Parent = sourceCard

    local sourceTitle = Instance.new("TextLabel")
    sourceTitle.Position = UDim2.fromOffset(10, 6)
    sourceTitle.Size = UDim2.new(1, -20, 0, 14)
    sourceTitle.BackgroundTransparency = 1
    sourceTitle.Font = Enum.Font.GothamBold
    sourceTitle.Text = "WHERE TO FIND THEM"
    sourceTitle.TextColor3 = Color3.fromRGB(221, 157, 72)
    sourceTitle.TextSize = 9
    sourceTitle.TextXAlignment = Enum.TextXAlignment.Left
    sourceTitle.Parent = sourceCard

    local sourceText = Instance.new("TextLabel")
    sourceText.Position = UDim2.fromOffset(10, 22)
    sourceText.Size = UDim2.new(1, -20, 1, -27)
    sourceText.BackgroundTransparency = 1
    sourceText.Font = Enum.Font.Gotham
    sourceText.Text = "Bronze/Nimbus: NPC ship decks, treasure-chart sites, diving spots and underwater structures. Dark: Atlantean ships, Dark Sea structures/Siren Rocks, some fleet and daily-quest rewards. Carry to a Shipwright to open."
    sourceText.TextColor3 = Color3.fromRGB(176, 182, 195)
    sourceText.TextSize = 8
    sourceText.TextWrapped = true
    sourceText.TextXAlignment = Enum.TextXAlignment.Left
    sourceText.TextYAlignment = Enum.TextYAlignment.Top
    sourceText.Parent = sourceCard

    -------------------------------------------------
    -- DIAGNOSTICS CENTER: STATUS, STATISTICS AND ACTION GRID
    -------------------------------------------------
    local diagSection = UI.createSection(misc, "Diagnostics Center", 334)

    local statsPanel = Instance.new("Frame")
    statsPanel.Name = "SessionStats"
    statsPanel.Position = UDim2.fromOffset(10, 38)
    statsPanel.Size = UDim2.new(1, -20, 0, 44)
    statsPanel.BackgroundTransparency = 1
    statsPanel.Parent = diagSection

    local statsGrid = Instance.new("UIGridLayout")
    statsGrid.CellSize = UDim2.new(0.25, -5, 1, 0)
    statsGrid.CellPadding = UDim2.fromOffset(6, 0)
    statsGrid.FillDirectionMaxCells = 4
    statsGrid.SortOrder = Enum.SortOrder.LayoutOrder
    statsGrid.Parent = statsPanel

    local statValues = {}
    local function makeStatCard(key, title, order)
        local card = Instance.new("Frame")
        card.Name = key .. "Card"
        card.LayoutOrder = order
        card.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
        card.BorderSizePixel = 0
        card.Parent = statsPanel
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

        local value = Instance.new("TextLabel")
        value.Name = "Value"
        value.Position = UDim2.fromOffset(9, 3)
        value.Size = UDim2.new(1, -18, 0, 19)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.GothamBold
        value.Text = "0"
        value.TextColor3 = Color3.fromRGB(239, 168, 77)
        value.TextSize = 14
        value.TextXAlignment = Enum.TextXAlignment.Left
        value.Parent = card
        statValues[key] = value

        local caption = Instance.new("TextLabel")
        caption.Position = UDim2.fromOffset(9, 24)
        caption.Size = UDim2.new(1, -18, 0, 14)
        caption.BackgroundTransparency = 1
        caption.Font = Enum.Font.Gotham
        caption.Text = title
        caption.TextColor3 = Color3.fromRGB(158, 165, 180)
        caption.TextSize = 8
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.Parent = card
    end

    makeStatCard("Scans", "Scans", 1)
    makeStatCard("Detected", "Detected", 2)
    makeStatCard("Errors", "Errors", 3)
    makeStatCard("Recoveries", "Recoveries", 4)

    local statusBox = Instance.new("TextBox")
    statusBox.Name = "SolarHubDiagnostics"
    statusBox.Position = UDim2.fromOffset(10, 90)
    statusBox.Size = UDim2.new(1, -20, 0, 104)
    statusBox.BackgroundColor3 = Color3.fromRGB(12, 15, 21)
    statusBox.BorderSizePixel = 0
    statusBox.ClearTextOnFocus = false
    statusBox.MultiLine = true
    statusBox.TextEditable = false
    statusBox.TextWrapped = false
    statusBox.TextXAlignment = Enum.TextXAlignment.Left
    statusBox.TextYAlignment = Enum.TextYAlignment.Top
    statusBox.Font = Enum.Font.Code
    statusBox.TextSize = 9
    statusBox.TextColor3 = Color3.fromRGB(208, 215, 228)
    statusBox.Parent = diagSection
    Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0, 8)
    local reportPadding = Instance.new("UIPadding")
    reportPadding.PaddingTop = UDim.new(0, 7)
    reportPadding.PaddingBottom = UDim.new(0, 7)
    reportPadding.PaddingLeft = UDim.new(0, 8)
    reportPadding.PaddingRight = UDim.new(0, 8)
    reportPadding.Parent = statusBox

    local function buildReport()
        local lines = {
            "SOLARHUB DIAGNOSTICS",
            "PlaceId=" .. tostring(game.PlaceId) .. " | UniverseId=" .. tostring(game.GameId),
            "Session=" .. tostring(math.floor(os.clock() - startedAt)) .. "s | ScanStatus=" .. tostring(scanStatus),
            "SealedESP=" .. tostring(Config.ArcaneSealedChestESP)
                .. " | Bronze=" .. tostring(Config.ArcaneSealedBronze)
                .. " | Nimbus=" .. tostring(Config.ArcaneSealedNimbus)
                .. " | Dark=" .. tostring(Config.ArcaneSealedDark),
            "PerformanceMode=" .. tostring(Config.SolarPerformanceMode)
                .. " | RecoveryEnabled=" .. tostring(Config.SolarRecoveryEnabled),
            "Scans=" .. stats.scans .. " | Detected=" .. stats.detected
                .. " | Markers=" .. stats.created .. " | Errors=" .. stats.errors
                .. " | Recoveries=" .. stats.recovered,
            "LastError=" .. tostring(lastError),
            "",
            "FEATURE STATUS (client-side state, not server-confirmed):",
            "Boss ESP=" .. tostring(Config.ArcaneBossESP),
            "Wanted Criminal ESP=" .. tostring(Config.ArcaneWantedCriminalESP),
            "Treasure Chest ESP=" .. tostring(Config.ArcaneChestESP),
            "Auto Fishing=" .. tostring(Config.ArcaneAutoFishing),
            "",
            "RECENT LOGS:"
        }
        for i = math.max(1, #logLines - 60), #logLines do
            lines[#lines + 1] = logLines[i]
        end
        return table.concat(lines, "\n")
    end

    local function refreshReport()
        statusBox.Text = buildReport()
        statValues.Scans.Text = tostring(stats.scans)
        statValues.Detected.Text = tostring(stats.detected)
        statValues.Errors.Text = tostring(stats.errors)
        statValues.Recoveries.Text = tostring(stats.recovered)
    end

    local actionsPanel = Instance.new("Frame")
    actionsPanel.Name = "DiagnosticActions"
    actionsPanel.Position = UDim2.fromOffset(10, 202)
    actionsPanel.Size = UDim2.new(1, -20, 0, 96)
    actionsPanel.BackgroundTransparency = 1
    actionsPanel.Parent = diagSection

    local actionsGrid = Instance.new("UIGridLayout")
    actionsGrid.CellSize = UDim2.new(1/3, -6, 0, 28)
    actionsGrid.CellPadding = UDim2.fromOffset(6, 6)
    actionsGrid.FillDirectionMaxCells = 3
    actionsGrid.SortOrder = Enum.SortOrder.LayoutOrder
    actionsGrid.Parent = actionsPanel

    local function button(title, order, callback)
        local b = Instance.new("TextButton")
        b.Name = title:gsub("[^%w]+", "") .. "Button"
        b.LayoutOrder = order
        b.BackgroundColor3 = Color3.fromRGB(42, 47, 61)
        b.BorderSizePixel = 0
        b.Text = title
        b.TextColor3 = Color3.fromRGB(228, 233, 243)
        b.Font = Enum.Font.GothamSemibold
        b.TextSize = 9
        b.AutoButtonColor = true
        b.Parent = actionsPanel
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(73, 79, 96)
        stroke.Transparency = 0.65
        stroke.Parent = b
        b.Activated:Connect(callback)
        return b
    end

    button("Refresh report", 1, function()
        refreshReport()
        log("Diagnostics report refreshed")
        refreshReport()
    end)

    button("Copy / export", 2, function()
        refreshReport()
        local ok = safeClipboard(statusBox.Text)
        log(ok and "Diagnostics copied to clipboard" or "Clipboard API unavailable; use the report text box")
        refreshReport()
    end)

    button("Save profile", 3, function()
        local profile = {
            ArcaneSealedChestESP = Config.ArcaneSealedChestESP,
            ArcaneSealedBronze = Config.ArcaneSealedBronze,
            ArcaneSealedNimbus = Config.ArcaneSealedNimbus,
            ArcaneSealedDark = Config.ArcaneSealedDark,
            ArcaneChestESP = Config.ArcaneChestESP,
            ArcaneBossESP = Config.ArcaneBossESP,
            ArcaneWantedCriminalESP = Config.ArcaneWantedCriminalESP,
            ArcaneAutoFishing = Config.ArcaneAutoFishing,
            SolarPerformanceMode = Config.SolarPerformanceMode,
            SolarRecoveryEnabled = Config.SolarRecoveryEnabled,
        }
        local saved = false
        if type(getgenv) == "function" then
            getgenv().SolarHubArcaneProfile = profile
            saved = true
        end
        if type(writefile) == "function" then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder("SolarHub") then
                    makefolder("SolarHub")
                end
                writefile("SolarHub/ArcaneProfile.json", game:GetService("HttpService"):JSONEncode(profile))
                saved = true
            end)
        end
        log(saved and "Profile saved (file persistence depends on executor support)" or "Profile saved for this session only")
        refreshReport()
    end)

    button("Load profile", 4, function()
        local profile = nil
        if type(readfile) == "function" and type(isfile) == "function" then
            pcall(function()
                if isfile("SolarHub/ArcaneProfile.json") then
                    profile = game:GetService("HttpService"):JSONDecode(readfile("SolarHub/ArcaneProfile.json"))
                end
            end)
        end
        if type(profile) ~= "table" and type(getgenv) == "function" then
            profile = getgenv().SolarHubArcaneProfile
        end
        if type(profile) ~= "table" then
            log("No saved profile found (file APIs may be unavailable)")
        else
            for key, value in pairs(profile) do
                Config[key] = value
                if toggleRefreshers[key] then toggleRefreshers[key]() end
            end
            log("Profile loaded")
            task.defer(function() pcall(scan) end)
        end
        refreshReport()
    end)

    button("Clear logs", 5, function()
        table.clear(logLines)
        log("Logs cleared")
        refreshReport()
    end)

    button("Performance mode", 6, function()
        Config.SolarPerformanceMode = not Config.SolarPerformanceMode
        log("Performance mode = " .. tostring(Config.SolarPerformanceMode))
        refreshReport()
    end)

    button("Auto recovery", 7, function()
        Config.SolarRecoveryEnabled = not Config.SolarRecoveryEnabled
        log("Recovery enabled = " .. tostring(Config.SolarRecoveryEnabled))
        refreshReport()
    end)

    local footer = Instance.new("TextLabel")
    footer.Position = UDim2.fromOffset(10, 303)
    footer.Size = UDim2.new(1, -20, 0, 19)
    footer.BackgroundTransparency = 1
    footer.Font = Enum.Font.Gotham
    footer.Text = "Status is client-observed; some game objects may be hidden until streamed in."
    footer.TextColor3 = Color3.fromRGB(142, 149, 165)
    footer.TextSize = 8
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.TextTruncate = Enum.TextTruncate.AtEnd
    footer.Parent = diagSection

    local function tryScan()
        local ok, err = xpcall(scan, debug.traceback)
        if not ok then
            stats.errors += 1
            lastError = tostring(err)
            scanStatus = "Error"
            log("Scan failed: " .. lastError)
            if Config.SolarRecoveryEnabled and retryCount < MAX_RETRIES then
                retryCount += 1
                stats.recovered += 1
                scanStatus = ("Recovering %d/%d"):format(retryCount, MAX_RETRIES)
                task.delay(0.5 * retryCount, function()
                    if active then tryScan() end
                end)
            else
                scanStatus = "Failed (retry limit reached)"
            end
        end
        refreshReport()
    end

    table.insert(connections, Shared.RunService.Heartbeat:Connect(function()
        if not active or not Context.isSessionActive() then return end
        local interval = Config.SolarPerformanceMode and 6 or 2.5
        if os.clock() - (ArcaneTools._lastScan or 0) >= interval then
            ArcaneTools._lastScan = os.clock()
            tryScan()
        end
    end))

    table.insert(connections, workspace.DescendantAdded:Connect(function(instance)
        if not active or not Config.ArcaneSealedChestESP then return end
        local n = normalize(instance.Name)
        if n:find("sealed", 1, true) or instance:IsA("ProximityPrompt") then
            task.defer(function()
                if active then pcall(inspect, instance) end
            end)
        end
    end))

    local function cleanup()
        if not active then return end
        active = false
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        clearMarkers()
    end
    if Context and type(Context.registerCleanup) == "function" then Context.registerCleanup(cleanup) end

    log("Arcane tools initialized")
    refreshReport()
    return { cleanup = cleanup, getReport = buildReport }
end

return ArcaneTools
