--!strict
-- SolarHub diagnostics and settings profiles.
-- Chest ESP itself lives in ArcaneMisc so it shares one discovery/filter pipeline.
local ArcaneTools = {}

local CONFIG_KEYS = {
    "ArcaneBossESP",
    "ArcaneWantedCriminalESP",
    "ArcaneBossDebug",
    "ArcaneSideQuestESP",
    "ArcaneChestESP",
    "ArcaneChestFilter",
    "ArcaneInfiniteDistanceScan",
    "ArcaneChestScanDistanceLimitEnabled",
    "ArcaneChestScanDistance",
    "ArcaneAutoFishing",
    "ArcaneFishingDebug",
    "ArcaneFishingRod",
    "SolarHubUIScale",
    "SolarPerformanceMode",
    "SolarRecoveryEnabled",
}

local function cloneSerializable(value)
    if type(value) ~= "table" then
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then
            return value
        end
        return nil
    end

    local copy = {}
    for key, item in pairs(value) do
        local cloned = cloneSerializable(item)
        if cloned ~= nil then
            copy[key] = cloned
        end
    end
    return copy
end

local function safeClipboard(value)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, value)
        if ok then return true end
    end
    if type(toclipboard) == "function" then
        local ok = pcall(toclipboard, value)
        if ok then return true end
    end
    return false
end

function ArcaneTools.Init(Shared, UI, Context)
    local Config = Shared.Config
    local miscTab = UI.tabs and UI.tabs["Misc"]
    if not miscTab then
        error("[ArcaneTools] Misc tab is missing.")
    end

    local active = true
    local startedAt = os.clock()
    local actions = 0
    local errors = 0
    local logLines = {}
    local MAX_LOG_LINES = 180
    local lastMessage = "Diagnostics initialized"

    Config.SolarPerformanceMode = Config.SolarPerformanceMode == true
    Config.SolarRecoveryEnabled = Config.SolarRecoveryEnabled ~= false
    Shared.SolarHubStats = Shared.SolarHubStats or {
        chestScans = 0,
        chestsDetected = 0,
        chestMarkersCreated = 0,
        chestScanErrors = 0,
        chestRecoveries = 0,
    }

    local function log(message, isError)
        local line = ("[SolarHub %.2f] %s"):format(os.clock(), tostring(message))
        lastMessage = tostring(message)
        if isError then errors += 1 end
        table.insert(logLines, line)
        if #logLines > MAX_LOG_LINES then
            table.remove(logLines, 1)
        end
        print(line)
    end

    local function enabledFilterNames()
        local labels = {
            COMMON = "Common",
            UNCOMMON = "Uncommon",
            RARE = "Rare",
            MYSTIC = "Mystic",
            LEGENDARY = "Legendary",
            PRIVATE_STORAGE = "Private Storage",
            SKY = "Sky",
            SEALED = "Sealed Chests (Bronze/Nimbus/Dark)",
        }
        local result = {}
        local filters = Config.ArcaneChestFilter
        if type(filters) == "table" then
            for key, label in pairs(labels) do
                if filters[key] == true then
                    result[#result + 1] = label
                end
            end
        end
        table.sort(result)
        return #result > 0 and table.concat(result, ", ") or "None"
    end

    local function buildReport()
        local stats = Shared.SolarHubStats or {}
        local lines = {
            "SOLARHUB DIAGNOSTICS",
            ("PlaceId=%s | UniverseId=%s"):format(tostring(game.PlaceId), tostring(game.GameId)),
            ("Session uptime=%ds"):format(math.floor(os.clock() - startedAt)),
            "",
            "FEATURE CONFIGURATION (client state, not server-confirmed):",
            "Chest ESP=" .. tostring(Config.ArcaneChestESP == true),
            "Selected chest categories=" .. enabledFilterNames(),
            "Boss ESP=" .. tostring(Config.ArcaneBossESP == true),
            "Wanted Criminal ESP=" .. tostring(Config.ArcaneWantedCriminalESP == true),
            "Side Quest ESP=" .. tostring(Config.ArcaneSideQuestESP == true),
            "Auto Fishing=" .. tostring(Config.ArcaneAutoFishing == true),
            "Performance Mode=" .. tostring(Config.SolarPerformanceMode == true),
            "Recovery Enabled=" .. tostring(Config.SolarRecoveryEnabled ~= false),
            "",
            "CHEST SCANNER STATISTICS:",
            "Full/live scan passes=" .. tostring(stats.chestScans or 0),
            "Unique live targets detected=" .. tostring(stats.chestsDetected or 0),
            "Markers created=" .. tostring(stats.chestMarkersCreated or 0),
            "Scan errors=" .. tostring(stats.chestScanErrors or 0),
            "Recovery attempts=" .. tostring(stats.chestRecoveries or 0),
            "",
            "DIAGNOSTICS:",
            "Actions=" .. tostring(actions) .. " | Diagnostics errors=" .. tostring(errors),
            "Last message=" .. tostring(lastMessage),
            "",
            "RECENT LOGS:",
        }
        for i = math.max(1, #logLines - 50), #logLines do
            lines[#lines + 1] = logLines[i]
        end
        return table.concat(lines, "\n")
    end

    local section = UI.createSection(miscTab, "SolarHub Diagnostics", 382)

    local summary = Instance.new("Frame")
    summary.Name = "DiagnosticsSummary"
    summary.Position = UDim2.fromOffset(10, 38)
    summary.Size = UDim2.new(1, -20, 0, 43)
    summary.BackgroundColor3 = Color3.fromRGB(27, 30, 39)
    summary.BorderSizePixel = 0
    summary.Parent = section
    Instance.new("UICorner", summary).CornerRadius = UDim.new(0, 8)

    local summaryStroke = Instance.new("UIStroke")
    summaryStroke.Color = Color3.fromRGB(67, 73, 89)
    summaryStroke.Transparency = 0.65
    summaryStroke.Parent = summary

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.Position = UDim2.fromOffset(12, 17)
    statusDot.BackgroundColor3 = Color3.fromRGB(82, 200, 136)
    statusDot.BorderSizePixel = 0
    statusDot.Parent = summary
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

    local statusTitle = Instance.new("TextLabel")
    statusTitle.Position = UDim2.fromOffset(28, 5)
    statusTitle.Size = UDim2.new(1, -40, 0, 17)
    statusTitle.BackgroundTransparency = 1
    statusTitle.Font = Enum.Font.GothamSemibold
    statusTitle.Text = "Diagnostics ready"
    statusTitle.TextColor3 = Color3.fromRGB(239, 241, 247)
    statusTitle.TextSize = 10
    statusTitle.TextXAlignment = Enum.TextXAlignment.Left
    statusTitle.Parent = summary

    local statusDetail = Instance.new("TextLabel")
    statusDetail.Position = UDim2.fromOffset(28, 22)
    statusDetail.Size = UDim2.new(1, -40, 0, 14)
    statusDetail.BackgroundTransparency = 1
    statusDetail.Font = Enum.Font.Gotham
    statusDetail.Text = "Feature toggles show local configuration only."
    statusDetail.TextColor3 = Color3.fromRGB(151, 158, 174)
    statusDetail.TextSize = 8
    statusDetail.TextXAlignment = Enum.TextXAlignment.Left
    statusDetail.TextTruncate = Enum.TextTruncate.AtEnd
    statusDetail.Parent = summary

    local statPanel = Instance.new("Frame")
    statPanel.Name = "SessionStats"
    statPanel.Position = UDim2.fromOffset(10, 89)
    statPanel.Size = UDim2.new(1, -20, 0, 42)
    statPanel.BackgroundTransparency = 1
    statPanel.Parent = section

    local statGrid = Instance.new("UIGridLayout")
    statGrid.CellSize = UDim2.new(0.25, -5, 1, 0)
    statGrid.CellPadding = UDim2.fromOffset(6, 0)
    statGrid.FillDirectionMaxCells = 4
    statGrid.SortOrder = Enum.SortOrder.LayoutOrder
    statGrid.Parent = statPanel

    local statLabels = {}
    local function createStat(key, title, order)
        local card = Instance.new("Frame")
        card.Name = key .. "Card"
        card.LayoutOrder = order
        card.BackgroundColor3 = Color3.fromRGB(29, 32, 42)
        card.BorderSizePixel = 0
        card.Parent = statPanel
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 7)

        local value = Instance.new("TextLabel")
        value.Position = UDim2.fromOffset(8, 3)
        value.Size = UDim2.new(1, -16, 0, 18)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.GothamBold
        value.Text = "0"
        value.TextColor3 = Color3.fromRGB(239, 168, 77)
        value.TextSize = 13
        value.TextXAlignment = Enum.TextXAlignment.Left
        value.Parent = card
        statLabels[key] = value

        local caption = Instance.new("TextLabel")
        caption.Position = UDim2.fromOffset(8, 22)
        caption.Size = UDim2.new(1, -16, 0, 12)
        caption.BackgroundTransparency = 1
        caption.Font = Enum.Font.Gotham
        caption.Text = title
        caption.TextColor3 = Color3.fromRGB(158, 165, 180)
        caption.TextSize = 8
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.Parent = card
    end

    createStat("Scans", "Chest scans", 1)
    createStat("Detected", "Targets", 2)
    createStat("Errors", "Errors", 3)
    createStat("Recoveries", "Recoveries", 4)

    local reportBox = Instance.new("TextBox")
    reportBox.Name = "DiagnosticsReport"
    reportBox.Position = UDim2.fromOffset(10, 139)
    reportBox.Size = UDim2.new(1, -20, 0, 121)
    reportBox.BackgroundColor3 = Color3.fromRGB(12, 15, 21)
    reportBox.BorderSizePixel = 0
    reportBox.ClearTextOnFocus = false
    reportBox.MultiLine = true
    reportBox.TextEditable = false
    reportBox.TextWrapped = false
    reportBox.TextXAlignment = Enum.TextXAlignment.Left
    reportBox.TextYAlignment = Enum.TextYAlignment.Top
    reportBox.Font = Enum.Font.Code
    reportBox.TextSize = 9
    reportBox.TextColor3 = Color3.fromRGB(208, 215, 228)
    reportBox.Parent = section
    Instance.new("UICorner", reportBox).CornerRadius = UDim.new(0, 8)
    local reportPadding = Instance.new("UIPadding")
    reportPadding.PaddingTop = UDim.new(0, 7)
    reportPadding.PaddingBottom = UDim.new(0, 7)
    reportPadding.PaddingLeft = UDim.new(0, 8)
    reportPadding.PaddingRight = UDim.new(0, 8)
    reportPadding.Parent = reportBox

    local actionPanel = Instance.new("Frame")
    actionPanel.Name = "DiagnosticsActions"
    actionPanel.Position = UDim2.fromOffset(10, 268)
    actionPanel.Size = UDim2.new(1, -20, 0, 78)
    actionPanel.BackgroundTransparency = 1
    actionPanel.Parent = section

    local actionGrid = Instance.new("UIGridLayout")
    actionGrid.CellSize = UDim2.new(1/3, -6, 0, 24)
    actionGrid.CellPadding = UDim2.fromOffset(6, 6)
    actionGrid.FillDirectionMaxCells = 3
    actionGrid.SortOrder = Enum.SortOrder.LayoutOrder
    actionGrid.Parent = actionPanel

    local refreshReport
    local function makeButton(title, order, callback)
        local button = Instance.new("TextButton")
        button.Name = title:gsub("[^%w]+", "") .. "Button"
        button.LayoutOrder = order
        button.BackgroundColor3 = Color3.fromRGB(42, 47, 61)
        button.BorderSizePixel = 0
        button.Text = title
        button.TextColor3 = Color3.fromRGB(228, 233, 243)
        button.Font = Enum.Font.GothamSemibold
        button.TextSize = 9
        button.AutoButtonColor = true
        button.Parent = actionPanel
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(73, 79, 96)
        stroke.Transparency = 0.65
        stroke.Parent = button
        button.Activated:Connect(function()
            actions += 1
            local ok, err = xpcall(callback, debug.traceback)
            if not ok then log("Action failed (" .. title .. "): " .. tostring(err), true) end
            if refreshReport then refreshReport() end
        end)
        return button
    end

    local function createProfile()
        local profile = {}
        for _, key in ipairs(CONFIG_KEYS) do
            if key == "ArcaneChestFilter" then
                profile[key] = cloneSerializable(Config[key] or {})
            else
                profile[key] = cloneSerializable(Config[key])
            end
        end
        profile.ProfileVersion = 1
        return profile
    end

    local function saveProfile()
        local profile = createProfile()
        local saved = false

        if type(getgenv) == "function" then
            pcall(function()
                getgenv().SolarHubArcaneProfile = profile
                saved = true
            end)
        end

        if type(writefile) == "function" then
            pcall(function()
                if type(makefolder) == "function" then
                    pcall(makefolder, "SolarHub")
                end
                local http = game:GetService("HttpService")
                writefile("SolarHub/ArcaneProfile.json", http:JSONEncode(profile))
                saved = true
            end)
        end

        if not saved then
            log("Profile could not be persisted; executor file/environment APIs are unavailable.", true)
            return
        end
        log("Settings profile saved.")
    end

    local function readProfile()
        local profile = nil
        if type(readfile) == "function" and type(isfile) == "function" then
            pcall(function()
                if isfile("SolarHub/ArcaneProfile.json") then
                    profile = game:GetService("HttpService"):JSONDecode(readfile("SolarHub/ArcaneProfile.json"))
                end
            end)
        end
        if type(profile) ~= "table" and type(getgenv) == "function" then
            pcall(function()
                profile = getgenv().SolarHubArcaneProfile
            end)
        end
        return profile
    end

    local function loadProfile()
        local profile = readProfile()
        if type(profile) ~= "table" then
            log("No saved settings profile was found.", true)
            return
        end
        for _, key in ipairs(CONFIG_KEYS) do
            if profile[key] ~= nil then
                Config[key] = cloneSerializable(profile[key])
            end
        end
        if type(Shared.refreshArcaneChestFilters) == "function" then
            pcall(Shared.refreshArcaneChestFilters)
        end
        if type(Shared.configRefreshers) == "table" then
            for key, refresh in pairs(Shared.configRefreshers) do
                if type(refresh) == "function" then pcall(refresh) end
            end
        end
        log("Settings profile loaded.")
    end

    refreshReport = function()
        local stats = Shared.SolarHubStats or {}
        statLabels.Scans.Text = tostring(stats.chestScans or 0)
        statLabels.Detected.Text = tostring(stats.chestsDetected or 0)
        statLabels.Errors.Text = tostring((stats.chestScanErrors or 0) + errors)
        statLabels.Recoveries.Text = tostring(stats.chestRecoveries or 0)
        statusDetail.Text = ("Uptime %ds  •  Chest ESP %s  •  Performance %s"):format(
            math.floor(os.clock() - startedAt),
            Config.ArcaneChestESP == true and "ON" or "OFF",
            Config.SolarPerformanceMode and "ON" or "OFF"
        )
        reportBox.Text = buildReport()
    end

    makeButton("Refresh report", 1, function()
        log("Diagnostics report refreshed.")
    end)
    makeButton("Copy / export", 2, function()
        local text = buildReport()
        if safeClipboard(text) then
            log("Diagnostics copied to clipboard.")
        else
            log("Clipboard API unavailable; report can be selected and copied from the text area.")
        end
    end)
    makeButton("Save profile", 3, saveProfile)
    makeButton("Load profile", 4, loadProfile)
    makeButton("Clear logs", 5, function()
        table.clear(logLines)
        log("Log history cleared.")
    end)
    makeButton("Performance mode", 6, function()
        Config.SolarPerformanceMode = not (Config.SolarPerformanceMode == true)
        log("Performance mode = " .. tostring(Config.SolarPerformanceMode))
    end)
    makeButton("Auto recovery", 7, function()
        Config.SolarRecoveryEnabled = not (Config.SolarRecoveryEnabled ~= false)
        log("Chest scan recovery = " .. tostring(Config.SolarRecoveryEnabled))
    end)

    local footer = Instance.new("TextLabel")
    footer.Position = UDim2.fromOffset(10, 354)
    footer.Size = UDim2.new(1, -20, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Font = Enum.Font.Gotham
    footer.Text = "Status comes from client-observed configuration and scanner counters."
    footer.TextColor3 = Color3.fromRGB(142, 149, 165)
    footer.TextSize = 8
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.TextTruncate = Enum.TextTruncate.AtEnd
    footer.Parent = section

    local function cleanup()
        if not active then return end
        active = false
    end

    if Context and type(Context.registerCleanup) == "function" then
        Context.registerCleanup(cleanup)
    end

    log("Diagnostics Center initialized.")
    refreshReport()

    return {
        cleanup = cleanup,
        getReport = buildReport,
    }
end

return ArcaneTools
