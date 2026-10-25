-- AADebug.lua
-- Targeted, read-only diagnostics for the user-specified Anime Adventures place.
-- Does not invoke remotes or automate gameplay.
local AADebug = {}

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function pathOf(inst)
    local names, cur = {}, inst
    while cur and cur ~= game do
        table.insert(names, 1, tostring(cur.Name))
        cur = cur.Parent
        if #names >= 7 then break end
    end
    return table.concat(names, ".")
end

local function interesting(name)
    name = string.lower(tostring(name or ""))
    for _, word in ipairs({
        "unit", "tower", "wave", "stage", "map", "match", "lobby",
        "summon", "upgrade", "place", "sell", "trait", "raid", "portal",
        "infinite", "story", "challenge", "dungeon", "teleport", "vote",
        "start", "ready", "deploy", "inventory", "replay", "equip",
        "spawn", "skip", "world", "difficulty", "return", "leave",
    }) do
        if string.find(name, word, 1, true) then return true end
    end
    return false
end

function AADebug.Init()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local playerGui = player:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("SolarHubAADebug")
    if old then old:Destroy() end

    local lines, seen = {}, {}
    local MAX_LINES = 620
    local function add(s)
        s = tostring(s)
        if #lines < MAX_LINES and not seen[s] then
            lines[#lines + 1] = s
            seen[s] = true
        end
    end
    local function addValue(inst)
        local value
        if inst:IsA("StringValue") or inst:IsA("BoolValue") or inst:IsA("NumberValue") or inst:IsA("IntValue") then
            value = safe(function() return inst.Value end, nil)
        end
        if value ~= nil then add("VALUE " .. pathOf(inst) .. " = " .. tostring(value)) end
        for key, val in pairs(safe(function() return inst:GetAttributes() end, {})) do
            add("ATTR " .. pathOf(inst) .. " [" .. tostring(key) .. "] = " .. tostring(val))
        end
    end

    add("SolarHub / Anime Adventures Targeted Diagnostic v4")
    add("PlaceId: " .. tostring(game.PlaceId))
    add("UniverseId/GameId: " .. tostring(game.GameId))
    add("PlaceName: " .. tostring(safe(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end, "<unavailable>")))
    add("GameLoaded: " .. tostring(safe(function() return game:IsLoaded() end, false)))
    add("Player: " .. player.Name)
    add("")

    -- Endpoints: report exact hierarchy, class, and relevant names; never invoke them.
    add("[CLIENT_TO_SERVER REMOTE SIGNATURES - NAMES ONLY]")
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local c2s = endpoints and endpoints:FindFirstChild("client_to_server")
    if c2s then
        local list = safe(function() return c2s:GetDescendants() end, {})
        local count = 0
        for _, inst in ipairs(list) do
            if inst:IsA("RemoteFunction") or inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
                count += 1
                add(inst.ClassName .. " " .. pathOf(inst))
            end
        end
        add("Client-to-server remotes total: " .. tostring(count))
    else
        add("client_to_server folder not found")
    end
    add("")

    add("[SERVER_TO_CLIENT IMPORTANT EVENTS - NAMES ONLY]")
    local s2c = endpoints and endpoints:FindFirstChild("server_to_client")
    if s2c then
        local list = safe(function() return s2c:GetDescendants() end, {})
        local count = 0
        for _, inst in ipairs(list) do
            if (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) and interesting(inst.Name) then
                count += 1
                add(inst.ClassName .. " " .. pathOf(inst))
            end
        end
        add("Relevant server-to-client events total: " .. tostring(count))
    else
        add("server_to_client folder not found")
    end
    add("")

    add("[LOBBY / MAP STATE]")
    for _, name in ipairs({"_LOBBY_CONFIG", "_MAP_CONFIG", "_wave_num", "_wave_time", "SERVER_READY", "_initial_client_ready"}) do
        local inst = workspace:FindFirstChild(name)
        if inst then
            add("FOUND " .. name .. " <" .. inst.ClassName .. ">")
            addValue(inst)
            for _, child in ipairs(safe(function() return inst:GetDescendants() end, {})) do
                addValue(child)
            end
        else
            add("NOT FOUND workspace." .. name)
        end
    end
    for _, folderName in ipairs({"_LOBBIES", "_MAPS", "_BASES", "_UNITS", "_CHALLENGES", "_DUNGEONS", "_PORTALS"}) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            local children = safe(function() return folder:GetChildren() end, {})
            add(folderName .. " children=" .. tostring(#children))
            for i = 1, math.min(#children, 18) do
                local child = children[i]
                add("  " .. child.Name .. " <" .. child.ClassName .. ">")
                addValue(child)
            end
        end
    end
    add("")

    add("[VISIBLE PLAYER GUI TEXT / BUTTONS]")
    local guiCount = 0
    for _, inst in ipairs(safe(function() return playerGui:GetDescendants() end, {})) do
        if inst:IsA("TextButton") or inst:IsA("TextLabel") or inst:IsA("TextBox") then
            local text = safe(function() return inst.Text end, "")
            text = tostring(text):gsub("[%c]", " ")
            if text ~= "" or interesting(inst.Name) then
                guiCount += 1
                add(inst.ClassName .. " path=" .. pathOf(inst) .. " text=" .. string.sub(text, 1, 100))
            end
        elseif inst:IsA("ImageButton") and interesting(inst.Name) then
            guiCount += 1
            add("ImageButton path=" .. pathOf(inst) .. " image=" .. tostring(inst.Image))
        end
    end
    add("GUI text/button entries found: " .. tostring(guiCount))
    add("")

    add("[IMPORTANT REPLICATED MODULES - PATHS ONLY]")
    local moduleCount = 0
    for _, inst in ipairs(safe(function() return ReplicatedStorage:GetDescendants() end, {})) do
        if inst:IsA("ModuleScript") and interesting(inst.Name) then
            moduleCount += 1
            add("MODULE " .. pathOf(inst))
        end
    end
    add("Relevant module paths found: " .. tostring(moduleCount))
    add("")
    add("Read-only report. No remotes were called. Send this report back.")

    local gui = Instance.new("ScreenGui")
    gui.Name = "SolarHubAADebug"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147483647
    gui.Parent = playerGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0.94, 0, 0.84, 0)
    panel.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12, 6)
    title.Size = UDim2.new(1, -285, 0, 34)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.Text = "Anime Adventures Debug v4"
    title.Parent = panel

    local minimize = Instance.new("TextButton")
    minimize.Name = "Minimize"
    minimize.Position = UDim2.new(1, -256, 0, 8)
    minimize.Size = UDim2.fromOffset(78, 28)
    minimize.Text = "MINIMIZE"
    minimize.Font = Enum.Font.GothamBold
    minimize.TextSize = 10
    minimize.TextColor3 = Color3.new(1, 1, 1)
    minimize.BackgroundColor3 = Color3.fromRGB(55, 65, 78)
    minimize.BorderSizePixel = 0
    minimize.ZIndex = 5
    minimize.AutoButtonColor = true
    minimize.Parent = panel
    Instance.new("UICorner", minimize).CornerRadius = UDim.new(0, 6)

    -- Small floating restore control stays available while the report is minimized.
    local restore = Instance.new("TextButton")
    restore.Name = "RestoreButton"
    restore.AnchorPoint = Vector2.new(1, 0)
    restore.Position = UDim2.new(1, -14, 0, 14)
    restore.Size = UDim2.fromOffset(118, 36)
    restore.Text = "RESTORE DEBUG"
    restore.Font = Enum.Font.GothamBold
    restore.TextSize = 11
    restore.TextColor3 = Color3.new(1, 1, 1)
    restore.BackgroundColor3 = Color3.fromRGB(35, 54, 82)
    restore.BorderSizePixel = 0
    restore.Visible = false
    restore.ZIndex = 20
    restore.Parent = gui
    Instance.new("UICorner", restore).CornerRadius = UDim.new(0, 8)

    local copy = Instance.new("TextButton")
    copy.Position = UDim2.new(1, -164, 0, 8)
    copy.Size = UDim2.fromOffset(70, 28)
    copy.Text = "COPY"
    copy.Font = Enum.Font.GothamBold
    copy.TextSize = 11
    copy.TextColor3 = Color3.new(1, 1, 1)
    copy.BackgroundColor3 = Color3.fromRGB(48, 72, 110)
    copy.BorderSizePixel = 0
    copy.ZIndex = 5
    copy.AutoButtonColor = true
    copy.Parent = panel
    Instance.new("UICorner", copy).CornerRadius = UDim.new(0, 6)

    local close = Instance.new("TextButton")
    close.Position = UDim2.new(1, -82, 0, 8)
    close.Size = UDim2.fromOffset(70, 28)
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.TextColor3 = Color3.new(1, 1, 1)
    close.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
    close.BorderSizePixel = 0
    close.ZIndex = 5
    close.AutoButtonColor = true
    close.Parent = panel
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(10, 46)
    box.Size = UDim2.new(1, -20, 1, -56)
    box.BackgroundColor3 = Color3.fromRGB(7, 8, 11)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.MultiLine = true
    box.TextEditable = false
    box.TextWrapped = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Font = Enum.Font.Code
    box.TextSize = 11
    box.TextColor3 = Color3.fromRGB(225, 228, 235)
    box.Text = table.concat(lines, "\n")
    box.Parent = panel
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)

    local function copyReport()
        local copied = false
        if type(setclipboard) == "function" then
            copied = pcall(setclipboard, box.Text)
        elseif type(toclipboard) == "function" then
            copied = pcall(toclipboard, box.Text)
        end
        copy.Text = copied and "COPIED" or "SELECT TEXT"
        task.delay(1.5, function()
            if copy.Parent then copy.Text = "COPY" end
        end)
    end
    -- Keep all controls above the report text and use one shared callback per button.
    title.ZIndex = 5
    box.ZIndex = 1
    restore.Active = true
    restore.AutoButtonColor = true

    copy.Activated:Connect(copyReport)

    local function minimizeDebug()
        if not gui.Parent then return end
        panel.Visible = false
        restore.Visible = true
    end

    local function restoreDebug()
        if not gui.Parent then return end
        panel.Visible = true
        restore.Visible = false
    end

    minimize.Activated:Connect(minimizeDebug)
    restore.Activated:Connect(restoreDebug)
    close.Activated:Connect(function() gui:Destroy() end)
    return true
end

return AADebug
