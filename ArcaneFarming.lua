--!strict
local ArcaneFarming = {}

local function normalizeName(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local FISHING_ROD_BASE_NAMES = {
    "Wooden Rod",
    "Bronze Rod",
    "Collector's Rod",
    "Fishmonger's Rod",
}

local FISHING_ROD_ENCHANTMENTS = {
    "Luring",
    "Sturdy",
    "Lucky",
    "Magnetic",
    "Ensnaring",
    "Toughened",
    "Graced",
    "Treasurer",
}

local FISHING_ROD_OPTIONS = {}

-- Expose every known base rod and enchantment combination in the selector.
for _, baseRod in ipairs(FISHING_ROD_BASE_NAMES) do
    table.insert(FISHING_ROD_OPTIONS, baseRod)

    for _, enchantment in ipairs(FISHING_ROD_ENCHANTMENTS) do
        table.insert(
            FISHING_ROD_OPTIONS,
            enchantment .. " " .. baseRod
        )
    end
end

local function getFishingRodDisplayOptions(player)
    local options = {}
    local seen = {}

    local function add(name)
        if type(name) ~= "string" or name == "" then
            return
        end

        local key = normalizeName(name)
        if key == "" or seen[key] then
            return
        end

        seen[key] = true
        table.insert(options, name)
    end

    for _, name in ipairs(FISHING_ROD_OPTIONS) do
        add(name)
    end

    -- Also expose any actual fishing-tool names present in the player's
    -- inventory, so newly-added rod variants remain selectable.
    local function scan(container)
        if not container then
            return
        end

        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                local normalized = normalizeName(child.Name)

                if normalized:find("fishingrod", 1, true) ~= nil
                    or normalized == "rod"
                    or normalized:find("woodenrod", 1, true) ~= nil
                    or normalized:find("bronzerod", 1, true) ~= nil
                    or normalized:find("collectorsrod", 1, true) ~= nil
                    or normalized:find("fishmongersrod", 1, true) ~= nil then
                    add(child.Name)
                end
            end
        end
    end

    if player then
        scan(player.Character)
        scan(player:FindFirstChildOfClass("Backpack"))
    end

    return options
end



function ArcaneFarming.Init(Shared, UI, Context)
    local isArcaneSessionActive = Context.isSessionActive
    local Config = Shared.Config
    local fishingDebugConnections = {}

    -------------------------------------------------
    -- FARMING / AUTO FISHING UI
    -------------------------------------------------

    local tabs = UI.tabs or {}
    local farmingTab = tabs["Farming"]

    if not farmingTab then
        error("[ArcaneFarming] Farming tab is missing.")
    end

    Config.ArcaneAutoFishing = Config.ArcaneAutoFishing == true
    Config.ArcaneFishingDebug = Config.ArcaneFishingDebug == true

    if type(Config.ArcaneFishingRod) ~= "string"
        or Config.ArcaneFishingRod == "" then
        Config.ArcaneFishingRod = FISHING_ROD_OPTIONS[1] or "Wooden Rod"
    end

    local openFishingDebugList
    local connectFishingDebugHooks

    local fishingSection = UI.createSection(
        farmingTab,
        "Auto Fishing",
        236
    )

    UI.createToggle(
        fishingSection,
        "Auto Fishing",
        "Auto equips the selected rod, casts, reels, and recasts.",
        "ArcaneAutoFishing",
        36
    )

    UI.createDropdown(
        fishingSection,
        "Fishing Rod",
        "Select the exact rod Auto Fishing should use.",
        getFishingRodDisplayOptions(Shared.player),
        "ArcaneFishingRod",
        10,
        94,
        330
    )

    local fishingHint = Instance.new("TextLabel")
    fishingHint.Size = UDim2.new(1, -20, 0, 46)
    fishingHint.Position = UDim2.fromOffset(10, 176)
    fishingHint.BackgroundTransparency = 1
    fishingHint.Text = "Auto Fishing keeps the selected rod equipped and automatically recovers after an accidental click or item change."
    fishingHint.TextColor3 = Color3.fromRGB(145, 145, 155)
    fishingHint.Font = Enum.Font.Gotham
    fishingHint.TextSize = 9
    fishingHint.TextWrapped = true
    fishingHint.TextXAlignment = Enum.TextXAlignment.Left
    fishingHint.TextYAlignment = Enum.TextYAlignment.Top
    fishingHint.Parent = fishingSection

    local fishingDebugSection = UI.createSection(
        farmingTab,
        "Fishing Debug",
        168
    )

    UI.createToggle(
        fishingDebugSection,
        "Fishing Debug",
        "Records rod state, ToolAction, Tool.Activated and FishEvent details.",
        "ArcaneFishingDebug",
        36
    )

    local debugListButton = Instance.new("TextButton")
    debugListButton.Size = UDim2.fromOffset(130, 28)
    debugListButton.Position = UDim2.fromOffset(10, 88)
    debugListButton.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
    debugListButton.BorderSizePixel = 0
    debugListButton.Text = "VIEW DEBUG"
    debugListButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    debugListButton.Font = Enum.Font.GothamBold
    debugListButton.TextSize = 9
    debugListButton.Parent = fishingDebugSection
    Instance.new("UICorner", debugListButton).CornerRadius = UDim.new(0, 7)

    local fishingStatusLabel = Instance.new("TextLabel")
    fishingStatusLabel.Size = UDim2.new(1, -155, 0, 42)
    fishingStatusLabel.Position = UDim2.fromOffset(150, 80)
    fishingStatusLabel.BackgroundTransparency = 1
    fishingStatusLabel.Text = "Status: OFF | Cast -> Bite -> Reel -> Complete"
    fishingStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    fishingStatusLabel.Font = Enum.Font.Gotham
    fishingStatusLabel.TextSize = 9
    fishingStatusLabel.TextWrapped = true
    fishingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    fishingStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
    fishingStatusLabel.Parent = fishingDebugSection

    debugListButton.Activated:Connect(function()
        if type(openFishingDebugList) == "function" then
            openFishingDebugList()
        end
    end)

    -------------------------------------------------
    -- AUTO FISHING
    -------------------------------------------------
    -- Confirmed fishing flow from RemoteSpy:
    -- Equip -> ToolAction (cast)
    -- FishEvent -> Bump (state/progress)
    -- FishEvent -> Bite (start reel)
    -- ToolAction repeated (reel)
    -- FishEvent -> Complete (catch finished)
    --
    -- Tool:Activate() is used for cast/reel so the game's own ToolAction
    -- is generated exactly like the normal rod interaction.
    -- The visual "!" is never used for bite detection.

    local fishEventRemote = nil
    local fishingEventConnection = nil
    local fishingState = "OFF"
    local fishingDebugLines = {}
    local MAX_FISHING_DEBUG_LINES = 160
    local fishingDebugGui = nil

    local function formatFishingDebugValue(value, depth, seen)
        depth = depth or 0
        seen = seen or {}

        local valueType = typeof(value)

        if valueType == "Instance" then
            local ok, fullName = pcall(function()
                return value:GetFullName()
            end)

            return "Instance<"
                .. (ok and tostring(fullName) or tostring(value))
                .. ">"
        end

        if valueType == "Vector3" then
            return ("Vector3(%.3f, %.3f, %.3f)"):format(
                value.X,
                value.Y,
                value.Z
            )
        end

        if valueType == "CFrame" then
            local p = value.Position
            return ("CFrame(%.3f, %.3f, %.3f)"):format(
                p.X,
                p.Y,
                p.Z
            )
        end

        if valueType ~= "table" then
            return tostring(value)
        end

        if depth >= 2 then
            return "<table>"
        end

        if seen[value] then
            return "<table:cycle>"
        end

        seen[value] = true

        local parts = {}
        local count = 0

        for key, item in pairs(value) do
            count += 1

            if count > 24 then
                table.insert(parts, "...")
                break
            end

            table.insert(
                parts,
                "["
                    .. formatFishingDebugValue(key, depth + 1, seen)
                    .. "]="
                    .. formatFishingDebugValue(item, depth + 1, seen)
            )
        end

        seen[value] = nil

        table.sort(parts)
        return "{"
            .. table.concat(parts, ", ")
            .. "}"
    end

    local function fishingDebugLog(message)
        if not Config.ArcaneFishingDebug then
            return
        end

        local line = "[FishingDebug] "
            .. ("%.3f"):format(os.clock())
            .. " | "
            .. tostring(message)

        table.insert(fishingDebugLines, line)

        if #fishingDebugLines > MAX_FISHING_DEBUG_LINES then
            table.remove(fishingDebugLines, 1)
        end

        print(line)
    end

    local function fishingDebugDumpEvent(eventName, rod, ...)
        if not Config.ArcaneFishingDebug then
            return
        end

        local args = {...}

        fishingDebugLog(
            ("%s | ArgCount=%d | Rod=%s | State=%s"):format(
                tostring(eventName),
                #args,
                tostring(rod and rod.Name or "<none>"),
                tostring(fishingState)
            )
        )

        for index, value in ipairs(args) do
            fishingDebugLog(
                ("Arg[%d] Type=%s Value=%s"):format(
                    index,
                    typeof(value),
                    formatFishingDebugValue(value)
                )
            )
        end
    end

    openFishingDebugList = function()
        local playerGui = Shared.playerGui

        if not playerGui then
            return
        end

        if fishingDebugGui and fishingDebugGui.Parent then
            fishingDebugGui.Enabled = true

            local panel = fishingDebugGui:FindFirstChild("Panel")
            local box = panel and panel:FindFirstChild("Logs")

            if box and box:IsA("TextBox") then
                box.Text = #fishingDebugLines > 0
                    and table.concat(fishingDebugLines, "\n")
                    or "No fishing debug logs yet. Enable Fishing Debug and make a manual fishing attempt."
            end

            return
        end

        fishingDebugGui = Instance.new("ScreenGui")
        fishingDebugGui.Name = "SolarHubFishingDebug"
        fishingDebugGui.ResetOnSpawn = false
        fishingDebugGui.DisplayOrder = 1000001
        fishingDebugGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        fishingDebugGui.Parent = playerGui

        local overlay = Instance.new("TextButton")
        overlay.Name = "Overlay"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 0.45
        overlay.BorderSizePixel = 0
        overlay.Text = ""
        overlay.AutoButtonColor = false
        overlay.Parent = fishingDebugGui

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.Position = UDim2.fromScale(0.5, 0.5)
        panel.Size = UDim2.fromOffset(760, 500)
        panel.BackgroundColor3 = Color3.fromRGB(17, 17, 22)
        panel.BorderSizePixel = 0
        panel.Parent = overlay
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -150, 0, 36)
        title.Position = UDim2.fromOffset(14, 8)
        title.BackgroundTransparency = 1
        title.Text = "Fishing Debug Log"
        title.TextColor3 = Color3.fromRGB(245, 245, 250)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 16
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = panel

        local close = Instance.new("TextButton")
        close.Size = UDim2.fromOffset(58, 28)
        close.Position = UDim2.new(1, -70, 0, 11)
        close.BackgroundColor3 = Color3.fromRGB(70, 35, 35)
        close.BorderSizePixel = 0
        close.Text = "CLOSE"
        close.TextColor3 = Color3.fromRGB(255, 255, 255)
        close.Font = Enum.Font.GothamBold
        close.TextSize = 8
        close.Parent = panel
        Instance.new("UICorner", close).CornerRadius = UDim.new(0, 7)

        local copy = Instance.new("TextButton")
        copy.Size = UDim2.fromOffset(74, 28)
        copy.Position = UDim2.new(1, -150, 0, 11)
        copy.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
        copy.BorderSizePixel = 0
        copy.Text = "COPY ALL"
        copy.TextColor3 = Color3.fromRGB(235, 235, 240)
        copy.Font = Enum.Font.GothamBold
        copy.TextSize = 8
        copy.Parent = panel
        Instance.new("UICorner", copy).CornerRadius = UDim.new(0, 7)

        local refresh = Instance.new("TextButton")
        refresh.Size = UDim2.fromOffset(70, 28)
        refresh.Position = UDim2.new(1, -228, 0, 11)
        refresh.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
        refresh.BorderSizePixel = 0
        refresh.Text = "REFRESH"
        refresh.TextColor3 = Color3.fromRGB(235, 235, 240)
        refresh.Font = Enum.Font.GothamBold
        refresh.TextSize = 8
        refresh.Parent = panel
        Instance.new("UICorner", refresh).CornerRadius = UDim.new(0, 7)

        local logs = Instance.new("TextBox")
        logs.Name = "Logs"
        logs.Position = UDim2.fromOffset(12, 50)
        logs.Size = UDim2.new(1, -24, 1, -62)
        logs.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
        logs.BorderSizePixel = 0
        logs.ClearTextOnFocus = false
        logs.MultiLine = true
        logs.TextEditable = false
        logs.TextWrapped = false
        logs.TextXAlignment = Enum.TextXAlignment.Left
        logs.TextYAlignment = Enum.TextYAlignment.Top
        logs.Font = Enum.Font.Code
        logs.TextSize = 11
        logs.TextColor3 = Color3.fromRGB(225, 225, 230)
        logs.Text = #fishingDebugLines > 0
            and table.concat(fishingDebugLines, "\n")
            or "No fishing debug logs yet. Enable Fishing Debug and make a manual fishing attempt."
        logs.Parent = panel
        Instance.new("UICorner", logs).CornerRadius = UDim.new(0, 8)

        local function refreshLogs()
            logs.Text = #fishingDebugLines > 0
                and table.concat(fishingDebugLines, "\n")
                or "No fishing debug logs yet. Enable Fishing Debug and make a manual fishing attempt."
            logs.CursorPosition = #logs.Text + 1
        end

        refresh.Activated:Connect(refreshLogs)

        copy.Activated:Connect(function()
            refreshLogs()

            local success = false

            if type(setclipboard) == "function" then
                success = pcall(function()
                    setclipboard(logs.Text)
                end)
            elseif type(toclipboard) == "function" then
                success = pcall(function()
                    toclipboard(logs.Text)
                end)
            end

            copy.Text = success and "COPIED" or "COPY FAIL"

            task.delay(1.2, function()
                if copy and copy.Parent then
                    copy.Text = "COPY ALL"
                end
            end)
        end)

        close.Activated:Connect(function()
            fishingDebugGui.Enabled = false
        end)

        overlay.Activated:Connect(function()
            -- Ignore overlay clicks that are actually inside the panel.
            -- The panel itself is parented to the button, so clicks there
            -- do not bubble to this TextButton.
            fishingDebugGui.Enabled = false
        end)
    end
    local biteReceived = false
    local completeReceived = false
    local fishingCycleRunning = false

    -- Auto Fishing watchdog state.
    -- It tracks whether the selected rod should currently have its line in the
    -- water and recovers the cycle if a manual click, equip change, or unequip
    -- interrupts the cast.
    local fishingLineInWater = false
    local fishingRecoveryRequested = false
    local fishingForceRemoteCast = false
    local fishingRodRecoveryConnections = setmetatable({}, {__mode = "k"})
    local fishingExpectedActivations = setmetatable({}, {__mode = "k"})
    local hookFishingRodRecovery

    local function requestFishingRecovery(reason)
        -- Recovery is persistent. It must also work during the tiny gaps between
        -- fishing cycles, because the player can interrupt the rod at any time.
        if not Config.ArcaneAutoFishing then
            return
        end

        fishingRecoveryRequested = true
        fishingForceRemoteCast = true
        fishingLineInWater = false

        fishingDebugLog(
            "FISHING RECOVERY REQUESTED | "
                .. tostring(reason)
                .. " | State="
                .. tostring(fishingState)
        )

        setFishingStatus("Recovering fishing cycle...")
    end

    do
        local replicatedStorageFishing = game:GetService("ReplicatedStorage")
        local rsFishing = replicatedStorageFishing:FindFirstChild("RS")
        local remotesFishing = rsFishing and rsFishing:FindFirstChild("Remotes")
        local miscRemotesFishing = remotesFishing and remotesFishing:FindFirstChild("Misc")
        local remote = miscRemotesFishing
            and miscRemotesFishing:FindFirstChild("FishEvent")

        if remote and remote:IsA("RemoteEvent") then
            fishEventRemote = remote
        end
    end

    local function setFishingStatus(text)
        if fishingStatusLabel then
            fishingStatusLabel.Text = "Status: " .. tostring(text)
        end
    end

    local function fishingRodDebugSnapshot(reason, rod)
        if not Config.ArcaneFishingDebug then
            return
        end

        local character = Shared.player.Character
        local backpack = Shared.player:FindFirstChildOfClass("Backpack")
        local equippedTool = character
            and character:FindFirstChildWhichIsA("Tool")

        local selectedName = tostring(Config.ArcaneFishingRod)
        local selectedNormalized = normalizeName(Config.ArcaneFishingRod)

        local selectedInCharacter = nil
        local selectedInBackpack = nil
        local selectedTool = rod

        local function scan(container)
            if not container then
                return
            end

            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool")
                    and normalizeName(child.Name) == selectedNormalized then

                    if container == character then
                        selectedInCharacter = child
                    elseif container == backpack then
                        selectedInBackpack = child
                    end

                    if not selectedTool then
                        selectedTool = child
                    end
                end
            end
        end

        scan(character)
        scan(backpack)

        local selectedParent = selectedTool
            and selectedTool.Parent
            and selectedTool.Parent:GetFullName()
            or "<none>"

        local enabled = "<n/a>"
        local requiresHandle = "<n/a>"

        if selectedTool then
            pcall(function()
                enabled = tostring(selectedTool.Enabled)
            end)
            pcall(function()
                requiresHandle = tostring(selectedTool.RequiresHandle)
            end)
        end

        fishingDebugLog(
            ("ROD SNAPSHOT | Reason=%s | Selected=%s | Tool=%s | Parent=%s | "
                .. "EquippedTool=%s | InCharacter=%s | InBackpack=%s | Enabled=%s | "
                .. "RequiresHandle=%s | LineInWater=%s | CycleRunning=%s | State=%s"):format(
                tostring(reason),
                selectedName,
                tostring(selectedTool and selectedTool.Name or "<none>"),
                selectedParent,
                tostring(equippedTool and equippedTool.Name or "<none>"),
                tostring(selectedInCharacter ~= nil),
                tostring(selectedInBackpack ~= nil),
                tostring(enabled),
                tostring(requiresHandle),
                tostring(fishingLineInWater),
                tostring(fishingCycleRunning),
                tostring(fishingState)
            )
        )
    end

    hookFishingRodRecovery = function(tool)
        if not tool or not tool:IsA("Tool") then
            return
        end

        local selectedName = normalizeName(Config.ArcaneFishingRod)

        if selectedName == ""
            or normalizeName(tool.Name) ~= selectedName then
            return
        end

        if fishingRodRecoveryConnections[tool] then
            return
        end

        local ok, connection = pcall(function()
            return tool.Activated:Connect(function()
                fishingRodDebugSnapshot("Tool.Activated", tool)

                local expected = fishingExpectedActivations[tool] or 0

                if expected > 0 then
                    fishingExpectedActivations[tool] = expected - 1
                    return
                end

                -- A Tool:Activated that was not caused by Auto Fishing itself
                -- means the player manually clicked/activated the selected rod.
                -- During WAITING_BITE this pulls/cancels the cast, so force a
                -- clean recast instead of leaving Auto Fishing stuck.
                if Config.ArcaneAutoFishing
                    and normalizeName(Config.ArcaneFishingRod) == normalizeName(tool.Name)
                    and (
                        fishingState == "CASTING"
                        or fishingState == "WAITING_BITE"
                        or fishingState == "REELING"
                        or fishingState == "RECOVERY"
                    ) then

                    requestFishingRecovery(
                        "Manual rod activation detected; restoring Auto Fishing"
                    )
                end
            end)
        end)

        if ok and connection then
            fishingRodRecoveryConnections[tool] = connection
        end
    end

    local function findFishingRod()
        local selectedName = normalizeName(Config.ArcaneFishingRod)
        local character = Shared.player.Character
        local backpack = Shared.player:FindFirstChildOfClass("Backpack")

        if selectedName == "" then
            return nil
        end

        local function findExact(container)
            if not container then
                return nil
            end

            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Tool")
                    and normalizeName(child.Name) == selectedName then

                    hookFishingRodRecovery(child)
                    return child
                end
            end

            return nil
        end

        -- Exact-name matching prevents Auto Fishing from silently switching
        -- to a different rod when multiple rods are in the inventory.
        return findExact(character) or findExact(backpack)
    end

    local function disconnectFishingDebugHooks()
        for _, connection in ipairs(fishingDebugConnections) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        table.clear(fishingDebugConnections)
    end

    connectFishingDebugHooks = function()
        disconnectFishingDebugHooks()

        if not Config.ArcaneFishingDebug then
            return
        end

        local function isFishingRodTool(tool)
            if not tool or not tool:IsA("Tool") then
                return false
            end

            local name = normalizeName(tool.Name)

            return name:find("fishingrod", 1, true) ~= nil
                or name == "rod"
                or name:find("woodenrod", 1, true) ~= nil
                or name:find("bronzerod", 1, true) ~= nil
                or name:find("collectorsrod", 1, true) ~= nil
                or name:find("fishmongersrod", 1, true) ~= nil
        end

        local function hookTool(tool)
            if not isFishingRodTool(tool) then
                return
            end

            local ok, connection = pcall(function()
                return tool.Activated:Connect(function()
                    fishingDebugLog(
                        ("ROD ACTIVATED | Tool=%s | Parent=%s | State=%s"):format(
                            tostring(tool.Name),
                            tostring(tool.Parent and tool.Parent:GetFullName() or "<none>"),
                            tostring(fishingState)
                        )
                    )
                end)
            end)

            if ok and connection then
                table.insert(fishingDebugConnections, connection)
            end
        end

        local character = Shared.player.Character
        local backpack = Shared.player:FindFirstChildOfClass("Backpack")

        if character then
            for _, child in ipairs(character:GetChildren()) do
                hookTool(child)
            end

            table.insert(
                fishingDebugConnections,
                character.ChildAdded:Connect(function(child)
                    if Config.ArcaneFishingDebug then
                        hookTool(child)
                    end
                end)
            )
        end

        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                hookTool(child)
            end

            table.insert(
                fishingDebugConnections,
                backpack.ChildAdded:Connect(function(child)
                    if Config.ArcaneFishingDebug then
                        hookTool(child)
                    end
                end)
            )
        end

        fishingDebugLog(
            ("DEBUG HOOKS READY | Rod=%s | FishEvent=%s | ToolAction=%s"):format(
                tostring(findFishingRod() and findFishingRod().Name or "<none>"),
                tostring(
                    fishEventRemote
                        and fishEventRemote:GetFullName()
                        or "<missing>"
                ),
                tostring(
                    (function()
                        local rs = game:GetService("ReplicatedStorage"):FindFirstChild("RS")
                        local remotes = rs and rs:FindFirstChild("Remotes")
                        local misc = remotes and remotes:FindFirstChild("Misc")
                        local toolAction = misc and misc:FindFirstChild("ToolAction")
                        return toolAction and toolAction:GetFullName() or "<missing>"
                    end)()
                )
            )
        )
    end

    local function equipFishingRod(forceClean)
        local rod = findFishingRod()

        if not rod then
            return nil
        end

        local character = Shared.player.Character
        local humanoid = character
            and character:FindFirstChildOfClass("Humanoid")

        if not humanoid or not character then
            return rod
        end

        local currentTool = character:FindFirstChildWhichIsA("Tool")
        local needsEquip = rod.Parent ~= character or currentTool ~= rod

        if forceClean and needsEquip then
            fishingRodDebugSnapshot("Before UnequipTools", rod)

            pcall(function()
                humanoid:UnequipTools()
            end)

            fishingRodDebugSnapshot("After UnequipTools", rod)
            task.wait(0.08)
        end

        if needsEquip or rod.Parent ~= character then
            fishingDebugLog(
                ("EQUIP ATTEMPT | Rod=%s | PreviousParent=%s | ForceClean=%s"):format(
                    tostring(rod.Name),
                    tostring(rod.Parent and rod.Parent:GetFullName() or "<none>"),
                    tostring(forceClean == true)
                )
            )

            pcall(function()
                humanoid:EquipTool(rod)
            end)

            task.wait(0.22)
            fishingRodDebugSnapshot("After EquipTool", rod)
        end

        -- Verify the selected rod is actually the equipped tool.
        for verifyAttempt = 1, 4 do
            if rod.Parent == character
                and character:FindFirstChildWhichIsA("Tool") == rod then

                fishingRodDebugSnapshot(
                    "Equip verified attempt " .. tostring(verifyAttempt),
                    rod
                )
                break
            end

            fishingDebugLog(
                ("EQUIP VERIFY FAILED | Attempt=%d | RodParent=%s | CurrentTool=%s"):format(
                    verifyAttempt,
                    tostring(rod.Parent and rod.Parent:GetFullName() or "<none>"),
                    tostring(character:FindFirstChildWhichIsA("Tool") and character:FindFirstChildWhichIsA("Tool").Name or "<none>")
                )
            )

            pcall(function()
                humanoid:EquipTool(rod)
            end)

            task.wait(0.08)
        end

        return rod
    end

    -- Persistent Auto Fishing watchdog.
    -- While Auto Fishing is ON, the selected rod always has priority: if the
    -- player equips another item, unequips the rod, or the selected rod drops
    -- back into the Backpack, immediately restore the selected rod and request
    -- a clean fishing cycle when the current one was interrupted.
    task.spawn(function()
        local nextWatchdogCheck = 0

        while isArcaneSessionActive() do
            if Config.ArcaneAutoFishing and os.clock() >= nextWatchdogCheck then
                nextWatchdogCheck = os.clock() + 0.10

                local selectedRod = equipFishingRod()

                if selectedRod then
                    hookFishingRodRecovery(selectedRod)

                    if fishingRecoveryRequested
                        or fishingState == "RECOVERY" then
                        fishingRodDebugSnapshot("Watchdog recovery", selectedRod)
                    end

                    local character = Shared.player.Character

                    if character and selectedRod.Parent ~= character then
                        requestFishingRecovery(
                            "Selected rod is not equipped; forcing it back"
                        )
                    end
                else
                    requestFishingRecovery(
                        "Selected rod is unavailable; waiting and retrying"
                    )
                end

                -- A lost line cannot be allowed to leave Auto Fishing in a
                -- half-finished state. Any interruption remains recoverable.
                if fishingRecoveryRequested
                    and fishingCycleRunning
                    and (
                        fishingState == "CASTING"
                        or fishingState == "WAITING_BITE"
                        or fishingState == "REELING"
                    ) then
                    fishingDebugLog(
                        "WATCHDOG | Recovery pending | State="
                            .. tostring(fishingState)
                            .. " | SelectedRod="
                            .. tostring(Config.ArcaneFishingRod)
                    )
                end
            end

            task.wait(0.03)
        end
    end)

    local function fireFishingToolAction(rod)
        if not rod or not rod.Parent then
            return false
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")
        local remotes = rs and rs:FindFirstChild("Remotes")
        local misc = remotes and remotes:FindFirstChild("Misc")
        local toolAction = misc and misc:FindFirstChild("ToolAction")

        if not toolAction or not toolAction:IsA("RemoteEvent") then
            fishingDebugLog("REMOTE CAST FAILED | ToolAction missing")
            return false
        end

        fishingRodDebugSnapshot("Before ToolAction CAST", rod)

        pcall(function()
            rod.Enabled = true
        end)

        local ok = pcall(function()
            toolAction:FireServer(rod)
        end)

        fishingRodDebugSnapshot("After ToolAction CAST", rod)

        fishingDebugLog(
            ("ToolAction CAST | Rod=%s | Success=%s | State=%s"):format(
                tostring(rod.Name),
                tostring(ok),
                tostring(fishingState)
            )
        )

        return ok
    end

    local function activateRod(rod)
        if not rod or not rod.Parent then
            return false
        end

        fishingDebugLog(
            ("Tool:Activate() | Rod=%s | Parent=%s | State=%s"):format(
                tostring(rod.Name),
                tostring(rod.Parent and rod.Parent:GetFullName() or "<none>"),
                tostring(fishingState)
            )
        )

        hookFishingRodRecovery(rod)

        fishingExpectedActivations[rod] =
            (fishingExpectedActivations[rod] or 0) + 1

        local ok = pcall(function()
            rod:Activate()
        end)

        if not ok then
            fishingExpectedActivations[rod] =
                math.max(0, (fishingExpectedActivations[rod] or 1) - 1)
            return false
        end

        -- Failsafe in case Roblox does not emit Tool.Activated for a specific
        -- activation. Normally the Activated callback consumes this count
        -- immediately.
        task.delay(0.5, function()
            local count = fishingExpectedActivations[rod] or 0
            if count > 0 then
                fishingExpectedActivations[rod] = count - 1
            end
        end)

        return true
    end

    task.spawn(function()
        local lastDebugState = Config.ArcaneFishingDebug == true

        if lastDebugState then
            connectFishingDebugHooks()
            fishingDebugLog("Fishing Debug INITIALIZED")
        end

        while isArcaneSessionActive() do
            local enabled = Config.ArcaneFishingDebug == true

            if enabled ~= lastDebugState then
                lastDebugState = enabled

                if enabled then
                    connectFishingDebugHooks()
                    fishingDebugLog("Fishing Debug ENABLED")
                else
                    fishingDebugLog("Fishing Debug DISABLED")
                    disconnectFishingDebugHooks()
                end
            end

            task.wait(0.25)
        end

        disconnectFishingDebugHooks()
    end)

    local function extractFishingState(...)
        local args = {...}

        -- Arcane's FishEvent is a global client event. Bump/Bite/Complete
        -- include the player who owns that fishing event as argument #1.
        -- Auto Fishing must NEVER react to another player's Bite.
        local eventPlayer = args[1]

        if typeof(eventPlayer) ~= "Instance"
            or not eventPlayer:IsA("Player") then
            return nil
        end

        if eventPlayer ~= Shared.player then
            fishingDebugLog(
                "IGNORED FOREIGN FISHEVENT | Player="
                    .. tostring(eventPlayer.Name)
                    .. " | State="
                    .. tostring(args[2])
            )
            return nil
        end

        local state = args[2]

        if state == "Bump"
            or state == "Bite"
            or state == "Complete" then
            return state
        end

        return nil
    end

    if fishEventRemote then
        fishingEventConnection = fishEventRemote.OnClientEvent:Connect(function(...)
            local args = {...}
            fishingDebugLog("========== FishEvent RECEIVED ==========")
            fishingDebugDumpEvent("FishEvent", (function()
                local character = Shared.player.Character
                local rod = character and character:FindFirstChildWhichIsA("Tool")
                return rod
            end)(), table.unpack(args))

            local eventState = extractFishingState(table.unpack(args))

            fishingDebugLog(
                ("DetectedState=%s | RawArgCount=%d"):format(
                    tostring(eventState or "<none>"),
                    #args
                )
            )

            if eventState == "Bump" then
                if fishingCycleRunning then
                    setFishingStatus("Bump received | Waiting for Bite...")
                end
                return
            end

            if eventState == "Bite" then
                biteReceived = true
                completeReceived = false
                fishingState = "REELING"
                fishingDebugLog("STATE -> REELING | Bite received")

                local fishName = nil

                for _, value in ipairs({...}) do
                    if type(value) == "string"
                        and value ~= "Bump"
                        and value ~= "Bite"
                        and value ~= "Complete" then
                        fishName = value
                        break
                    end
                end

                if fishName then
                    setFishingStatus(
                        "Bite! Reeling " .. tostring(fishName) .. "..."
                    )
                else
                    setFishingStatus("Bite! Reeling...")
                end

                return
            end

            if eventState == "Complete" then
                completeReceived = true
                fishingLineInWater = false
                fishingState = "COMPLETE"
                fishingDebugLog("STATE -> COMPLETE")
                setFishingStatus("Catch complete.")
            end
        end)
    end

    local function doFishingCycle()
        if not Config.ArcaneAutoFishing then
            return false
        end

        -- A recovery starts as a completely fresh fishing attempt.
        -- Cleanly unequip the current item first so Tool:Activate() behaves
        -- exactly like a normal manual cast.
        local rod = equipFishingRod(true)

        if not rod then
            fishingState = "WAITING_ROD"
            setFishingStatus(
                "Waiting for selected rod: " .. tostring(Config.ArcaneFishingRod)
            )
            task.wait(0.5)
            return false
        end

        if not fishEventRemote then
            fishingState = "ERROR"
            setFishingStatus("ERROR: FishEvent not found.")
            task.wait(1)
            return false
        end

        biteReceived = false
        completeReceived = false
        fishingCycleRunning = true
        fishingRecoveryRequested = false
        fishingLineInWater = false

        fishingState = "CASTING"
        fishingDebugLog("STATE -> CASTING | Rod=" .. tostring(rod.Name))
        setFishingStatus("Casting...")

        local character = Shared.player.Character

        if not character
            or rod.Parent ~= character
            or character:FindFirstChildWhichIsA("Tool") ~= rod then

            rod = equipFishingRod(true)
        end

        if not rod or not rod.Parent then
            fishingCycleRunning = false
            fishingLineInWater = false
            fishingState = "RECOVERY"
            fishingDebugLog(
                "CAST PREP FAILED | SelectedRod="
                    .. tostring(Config.ArcaneFishingRod)
            )
            setFishingStatus("Preparing selected rod...")
            task.wait(0.15)
            return false
        end

        task.wait(0.10)

        pcall(function()
            rod.Enabled = true
        end)

        local forceRemoteCast = fishingForceRemoteCast
        fishingForceRemoteCast = false

        local castOk

        fishingRodDebugSnapshot(
            forceRemoteCast and "Recovery cast preparation" or "Normal cast preparation",
            rod
        )

        if forceRemoteCast then
            -- Recovery casts use the game's direct ToolAction path because a
            -- previous manual activation can leave Tool:Activate() unusable.
            castOk = fireFishingToolAction(rod)

            if not castOk then
                castOk = activateRod(rod)
            end
        else
            -- First/normal cast keeps the original behavior.
            castOk = activateRod(rod)
        end

        if not castOk then
            fishingCycleRunning = false
            fishingLineInWater = false
            fishingState = "RECOVERY"
            fishingDebugLog(
                "CAST FAILED | SelectedRod="
                    .. tostring(Config.ArcaneFishingRod)
            )
            setFishingStatus("Cast failed. Retrying...")
            task.wait(0.15)
            return false
        end

        fishingLineInWater = true
        fishingState = "WAITING_BITE"
        fishingDebugLog("STATE -> WAITING_BITE | Waiting up to 90s for FishEvent Bite")
        setFishingStatus("Waiting for Bite...")

        local biteDeadline = os.clock() + 90
        local nextEquipCheck = 0

        while Config.ArcaneAutoFishing
            and not biteReceived
            and not fishingRecoveryRequested
            and os.clock() < biteDeadline do

            if os.clock() >= nextEquipCheck then
                nextEquipCheck = os.clock() + 0.10

                local currentRod = equipFishingRod()

                if currentRod then
                    rod = currentRod

                    local character = Shared.player.Character
                    if character and rod.Parent ~= character then
                        requestFishingRecovery(
                            "Selected rod could not stay equipped"
                        )
                    end
                else
                    requestFishingRecovery(
                        "Selected rod is missing from character/backpack"
                    )
                end
            end

            task.wait(0.05)
        end

        if not Config.ArcaneAutoFishing then
            fishingCycleRunning = false
            fishingLineInWater = false
            fishingState = "OFF"
            setFishingStatus("OFF")
            return false
        end

        if fishingRecoveryRequested then
            fishingLineInWater = false
            fishingState = "RECOVERY"
            fishingDebugLog("STATE -> RECOVERY | Selected rod was interrupted; restarting full cycle")
            setFishingStatus("Recovering selected rod and recasting...")
            fishingRecoveryRequested = false
            fishingCycleRunning = false
            task.wait(0.10)
            return false
        end

        if not biteReceived then
            fishingLineInWater = false
            fishingCycleRunning = false
            fishingState = "TIMEOUT"
            fishingDebugLog("STATE -> TIMEOUT | No Bite event before deadline")
            setFishingStatus("No Bite received. Recasting...")
            task.wait(0.5)
            return false
        end

        local reelDeadline = os.clock() + 30
        nextEquipCheck = 0

        while Config.ArcaneAutoFishing
            and not completeReceived
            and not fishingRecoveryRequested
            and os.clock() < reelDeadline do

            if os.clock() >= nextEquipCheck
                or not rod
                or not rod.Parent then

                nextEquipCheck = os.clock() + 0.10

                local currentRod = equipFishingRod()

                if currentRod then
                    rod = currentRod
                else
                    requestFishingRecovery(
                        "Selected rod was unequipped or removed during reeling"
                    )
                    task.wait(0.05)
                    continue
                end
            end

            local character = Shared.player.Character

            if character and rod.Parent ~= character then
                local currentRod = equipFishingRod()

                if currentRod and currentRod.Parent == character then
                    rod = currentRod
                else
                    requestFishingRecovery(
                        "Another item replaced the selected rod during reeling"
                    )
                    task.wait(0.05)
                    continue
                end
            end

            if fishingRecoveryRequested then
                break
            end

            local activated = activateRod(rod)

            if not activated then
                requestFishingRecovery("Selected rod activation failed")
                task.wait(0.05)
                continue
            end

            task.wait(0.08)
        end

        fishingCycleRunning = false

        if not Config.ArcaneAutoFishing then
            fishingLineInWater = false
            fishingState = "OFF"
            setFishingStatus("OFF")
            return false
        end

        if fishingRecoveryRequested then
            fishingLineInWater = false
            fishingState = "RECOVERY"
            fishingDebugLog("STATE -> RECOVERY | Recovered gear; restarting full cycle")
            setFishingStatus("Recovering selected rod and recasting...")
            fishingRecoveryRequested = false
            fishingCycleRunning = false
            task.wait(0.10)
            return false
        end

        if not completeReceived then
            fishingState = "REEL_TIMEOUT"
            fishingDebugLog("STATE -> REEL_TIMEOUT | No Complete event before deadline")
            setFishingStatus("Reel timeout. Recasting...")
            task.wait(0.5)
            return false
        end

        task.wait(0.5)
        return true
    end

    task.spawn(function()
        while isArcaneSessionActive() do
            if not Config.ArcaneAutoFishing then
                fishingCycleRunning = false
                fishingRecoveryRequested = false
                fishingForceRemoteCast = false
                fishingLineInWater = false
                fishingState = "OFF"
                biteReceived = false
                completeReceived = false

                setFishingStatus(
                    "OFF | Cast -> Bite -> Reel -> Complete"
                )

                task.wait(0.25)
            else
                if not fishingCycleRunning then
                    doFishingCycle()
                else
                    task.wait(0.1)
                end
            end
        end
    end)


    local function cleanupFarming()
        if type(disconnectFishingDebugHooks) == "function" then
            disconnectFishingDebugHooks()
        end

        for tool, connection in pairs(fishingRodRecoveryConnections) do
            pcall(function()
                connection:Disconnect()
            end)
            fishingRodRecoveryConnections[tool] = nil
        end

        table.clear(fishingExpectedActivations)
        fishingRecoveryRequested = false
        fishingForceRemoteCast = false
        fishingLineInWater = false

        if fishingDebugGui then
            pcall(function()
                fishingDebugGui:Destroy()
            end)
            fishingDebugGui = nil
        end
    end

    Context.registerCleanup(cleanupFarming)

    return true
end

return ArcaneFarming
