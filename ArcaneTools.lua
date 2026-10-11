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
            if #scanRoots > 0 then fullWorldScanDone = true end
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

    local sealedSection = UI.createSection(misc, "Sealed Chest ESP", 250)
    local function makeToggle(parent, title, key, y, desc)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -20, 0, 36)
        button.Position = UDim2.fromOffset(10, y)
        button.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = parent
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(9, 0)
        label.Size = UDim2.new(1, -52, 1, 0)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.GothamBold
        label.TextSize = 10
        label.TextColor3 = Color3.fromRGB(235, 235, 240)
        label.Text = title .. (desc and " — " .. desc or "")
        label.Parent = button
        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(18, 18)
        indicator.Position = UDim2.new(1, -28, 0.5, -9)
        indicator.BackgroundColor3 = Config[key] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)
        indicator.Parent = button
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 4)
        local function refresh()
            indicator.BackgroundColor3 = Config[key] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)
        end
        button.Activated:Connect(function()
            Config[key] = not Config[key]
            refresh()
            if key == "ArcaneSealedChestESP" and not Config[key] then clearMarkers() end
            log(title .. " = " .. tostring(Config[key]))
            task.defer(function() pcall(scan) end)
        end)
    end
    makeToggle(sealedSection, "Sealed Chest ESP", "ArcaneSealedChestESP", 34, "Independent from Treasure Chest ESP")
    makeToggle(sealedSection, "Bronze Sealed", "ArcaneSealedBronze", 76)
    makeToggle(sealedSection, "Nimbus Sealed", "ArcaneSealedNimbus", 118)
    makeToggle(sealedSection, "Dark Sealed", "ArcaneSealedDark", 160)

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -20, 0, 32)
    info.Position = UDim2.fromOffset(10, 204)
    info.BackgroundTransparency = 1
    info.Text = "Bronze/Nimbus are usually from defeated NPC ships, charts and diving spots; Dark from Dark Sea ships/islands."
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Font = Enum.Font.Gotham
    info.TextSize = 8
    info.TextColor3 = Color3.fromRGB(145, 145, 155)
    info.Parent = sealedSection

    local diagSection = UI.createSection(misc, "SolarHub Diagnostics", 330)
    local statusBox = Instance.new("TextBox")
    statusBox.Name = "SolarHubDiagnostics"
    statusBox.Position = UDim2.fromOffset(10, 34)
    statusBox.Size = UDim2.new(1, -20, 0, 156)
    statusBox.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
    statusBox.BorderSizePixel = 0
    statusBox.ClearTextOnFocus = false
    statusBox.MultiLine = true
    statusBox.TextEditable = false
    statusBox.TextWrapped = false
    statusBox.TextXAlignment = Enum.TextXAlignment.Left
    statusBox.TextYAlignment = Enum.TextYAlignment.Top
    statusBox.Font = Enum.Font.Code
    statusBox.TextSize = 9
    statusBox.TextColor3 = Color3.fromRGB(220, 220, 225)
    statusBox.Parent = diagSection

    local function buildReport()
        local lines = {
            "SOLARHUB DIAGNOSTICS",
            "Game=" .. tostring(game.PlaceId) .. " / Universe=" .. tostring(game.GameId),
            "SessionSeconds=" .. tostring(math.floor(os.clock() - startedAt)),
            "SealedESP=" .. tostring(Config.ArcaneSealedChestESP),
            "Bronze=" .. tostring(Config.ArcaneSealedBronze) .. " Nimbus=" .. tostring(Config.ArcaneSealedNimbus) .. " Dark=" .. tostring(Config.ArcaneSealedDark),
            "ScanStatus=" .. tostring(scanStatus),
            "PerformanceMode=" .. tostring(Config.SolarPerformanceMode),
            "RecoveryEnabled=" .. tostring(Config.SolarRecoveryEnabled),
            "Stats: scans=" .. stats.scans .. " detected=" .. stats.detected .. " markersCreated=" .. stats.created .. " errors=" .. stats.errors .. " recoveries=" .. stats.recovered,
            "LastError=" .. tostring(lastError),
            "",
            "FEATURE STATUS (based on current client config; not server-confirmed):",
            "Boss ESP=" .. tostring(Config.ArcaneBossESP),
            "Wanted Criminal ESP=" .. tostring(Config.ArcaneWantedCriminalESP),
            "Treasure Chest ESP=" .. tostring(Config.ArcaneChestESP),
            "Auto Fishing=" .. tostring(Config.ArcaneAutoFishing),
            "",
            "RECENT LOGS:"
        }
        for i = math.max(1, #logLines - 60), #logLines do lines[#lines + 1] = logLines[i] end
        return table.concat(lines, "\n")
    end

    local function refreshReport()
        statusBox.Text = buildReport()
    end

    local function button(parent, title, x, y, width, callback)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(width, 28)
        b.Position = UDim2.fromOffset(x, y)
        b.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
        b.BorderSizePixel = 0
        b.Text = title
        b.TextColor3 = Color3.fromRGB(235, 235, 240)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 8
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.Activated:Connect(callback)
        return b
    end

    button(diagSection, "REFRESH REPORT", 10, 200, 105, refreshReport)
    button(diagSection, "COPY / EXPORT", 122, 200, 105, function()
        refreshReport()
        local ok = safeClipboard(statusBox.Text)
        log(ok and "Diagnostics copied to clipboard" or "Clipboard unavailable; report remains selectable in the text box")
        refreshReport()
    end)
    button(diagSection, "SAVE PROFILE", 234, 200, 95, function()
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
        -- Persist across restarts when executor file APIs are available.
        if type(writefile) == "function" then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder("SolarHub") then
                    makefolder("SolarHub")
                end
                writefile("SolarHub/ArcaneProfile.json", game:GetService("HttpService"):JSONEncode(profile))
                saved = true
            end)
        end
        log(saved and "Profile saved (persistent file when supported, otherwise session environment)" or "Profile saved for this session only")
        refreshReport()
    end)
    button(diagSection, "LOAD PROFILE", 10, 234, 105, function()
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
            for key, value in pairs(profile) do Config[key] = value end
            log("Profile loaded")
            task.defer(function() pcall(scan) end)
        end
        refreshReport()
    end)
    button(diagSection, "CLEAR LOGS", 122, 234, 105, function()
        table.clear(logLines)
        log("Logs cleared")
        refreshReport()
    end)
    button(diagSection, "PERFORMANCE MODE", 234, 234, 95, function()
        Config.SolarPerformanceMode = not Config.SolarPerformanceMode
        log("Performance mode = " .. tostring(Config.SolarPerformanceMode))
        refreshReport()
    end)

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
