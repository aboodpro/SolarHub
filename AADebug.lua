-- AADebug.lua
-- Read-only diagnostics for the Anime Adventures place supplied by the user.
-- This module does not invoke game remotes or automate gameplay.
local AADebug = {}

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function shortPath(instance)
    local names = {}
    local current = instance
    while current and current ~= game do
        table.insert(names, 1, tostring(current.Name))
        current = current.Parent
        if #names >= 6 then break end
    end
    return table.concat(names, ".")
end

local function isInterestingName(name)
    name = string.lower(tostring(name or ""))
    local terms = {
        "remote", "replica", "unit", "tower", "wave", "stage", "map",
        "match", "lobby", "summon", "upgrade", "place", "sell", "trait",
        "raid", "portal", "infinite", "story", "challenge", "dungeon",
        "teleport", "vote", "start", "ready", "deploy", "inventory",
    }
    for _, term in ipairs(terms) do
        if string.find(name, term, 1, true) then return true end
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

    local lines = {}
    local MAX_LINES = 500
    local function add(line)
        if #lines < MAX_LINES then
            lines[#lines + 1] = tostring(line)
        end
    end

    add("SolarHub / Anime Adventures Diagnostic")
    add("======================================")
    add("PlaceId: " .. tostring(game.PlaceId))
    add("UniverseId/GameId: " .. tostring(game.GameId))
    add("JobId: " .. tostring(game.JobId))
    add("PlaceName: " .. tostring(safe(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    end, "<unavailable>")))
    add("GameLoaded: " .. tostring(safe(function() return game:IsLoaded() end, false)))
    add("Player: " .. player.Name .. " (" .. tostring(player.UserId) .. ")")
    add("Character: " .. tostring(player.Character and player.Character.Name or "<nil>"))
    add("")

    local serviceNames = {"ReplicatedStorage", "Workspace", "Players", "Lighting", "StarterGui", "StarterPlayer"}
    for _, serviceName in ipairs(serviceNames) do
        local service = safe(function() return game:GetService(serviceName) end, nil)
        if service then
            add("[" .. serviceName .. "] direct children:")
            local children = safe(function() return service:GetChildren() end, {})
            for _, child in ipairs(children) do
                add("  " .. child.Name .. " <" .. child.ClassName .. ">")
            end
            add("")
        end
    end

    add("[Interesting descendants] (bounded scan)")
    local roots = {ReplicatedStorage, workspace, playerGui}
    local count, remotes, modules, prompts, guiObjects = 0, 0, 0, 0, 0
    local MAX_SCAN = 12000
    for _, root in ipairs(roots) do
        local descendants = safe(function() return root:GetDescendants() end, {})
        for _, inst in ipairs(descendants) do
            count += 1
            if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
                remotes += 1
                if isInterestingName(inst.Name) then
                    add("REMOTE " .. inst.ClassName .. " " .. shortPath(inst))
                end
            elseif inst:IsA("ModuleScript") then
                modules += 1
                if isInterestingName(inst.Name) then
                    add("MODULE " .. shortPath(inst))
                end
            elseif inst:IsA("ProximityPrompt") then
                prompts += 1
                if isInterestingName(inst.Name) then
                    add("PROMPT " .. shortPath(inst))
                end
            elseif inst:IsA("GuiObject") then
                guiObjects += 1
                if isInterestingName(inst.Name) then
                    add("GUI " .. inst.ClassName .. " " .. shortPath(inst))
                end
            end
            if count >= MAX_SCAN then
                add("SCAN LIMIT reached (" .. tostring(MAX_SCAN) .. " descendants).")
                break
            end
        end
        if count >= MAX_SCAN then break end
    end

    add("")
    add("[Scan summary]")
    add("Descendants visited: " .. tostring(count))
    add("Remote instances found: " .. tostring(remotes))
    add("ModuleScripts found: " .. tostring(modules))
    add("ProximityPrompts found: " .. tostring(prompts))
    add("GuiObjects found: " .. tostring(guiObjects))
    add("")
    add("NOTE: this diagnostic is read-only. It does not call remotes.")
    add("Copy this report and send it back to continue AA integration.")

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
    panel.Size = UDim2.new(0.92, 0, 0.82, 0)
    panel.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12, 6)
    title.Size = UDim2.new(1, -170, 0, 34)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(245, 245, 250)
    title.Text = "Anime Adventures Debug"
    title.Parent = panel

    local copy = Instance.new("TextButton")
    copy.Position = UDim2.new(1, -148, 0, 8)
    copy.Size = UDim2.fromOffset(66, 28)
    copy.Text = "COPY"
    copy.Font = Enum.Font.GothamBold
    copy.TextSize = 11
    copy.TextColor3 = Color3.new(1, 1, 1)
    copy.BackgroundColor3 = Color3.fromRGB(48, 72, 110)
    copy.BorderSizePixel = 0
    copy.Parent = panel
    Instance.new("UICorner", copy).CornerRadius = UDim.new(0, 6)

    local close = Instance.new("TextButton")
    close.Position = UDim2.new(1, -74, 0, 8)
    close.Size = UDim2.fromOffset(62, 28)
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.TextColor3 = Color3.new(1, 1, 1)
    close.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
    close.BorderSizePixel = 0
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

    copy.Activated:Connect(copyReport)
    close.Activated:Connect(function() gui:Destroy() end)
    return true
end

return AADebug
