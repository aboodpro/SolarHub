--!strict
local Arcane = {}

local BOSS_NAMES = {
    "Shura",
    "Iris",
    "Lord Elius",
    "General Argos",
    "Lady Carina",
    "King Calvus",
    "Captain Maria",
    "Allanon",
    "Jarl Ivar",
    "Cernyx",
    "Commodore Kai",
    "Architect Merlot",
    "Alpha",
    "The Omen",
    "Obsidian Warden",
}

local function normalizeName(value)
    return tostring(value):lower():gsub("[%W_]+", "")
end

local NORMALIZED_BOSSES = {}
for _, name in ipairs(BOSS_NAMES) do
    NORMALIZED_BOSSES[normalizeName(name)] = name
end

local function getRoot(model)
    if not model:IsA("Model") then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model.PrimaryPart
        or model:FindFirstChild("Head")
end

local function getBossDisplayName(model)
    local normalized = normalizeName(model.Name)

    for key, displayName in pairs(NORMALIZED_BOSSES) do
        if normalized == key or normalized:find(key, 1, true) then
            return displayName
        end
    end

    return nil
end

local function getHealthText(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return "HP: ?"
    end

    return ("HP: %d/%d"):format(
        math.floor(math.max(0, humanoid.Health)),
        math.floor(math.max(0, humanoid.MaxHealth))
    )
end

local function isValidBossModel(instance)
    if not instance:IsA("Model") then
        return false
    end

    if not getRoot(instance) then
        return false
    end

    local humanoid = instance:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false
    end

    return getBossDisplayName(instance) ~= nil
end

function Arcane.Init(Shared, UI)
    local Config = Shared.Config
    local tabs = UI.tabs or {}
    local tabButtons = UI.tabButtons or {}

    Config.ArcaneBossESP = Config.ArcaneBossESP == true

    local miscTab = tabs["Misc"]
    if not miscTab then
        error("[Arcane] Misc tab is missing.")
    end

    -- Arcane Odyssey does not use the Anime Expeditions tabs.
    for name, tab in pairs(tabs) do
        tab.Visible = (name == "Misc")
        tab.CanvasPosition = Vector2.zero
    end

    for name, button in pairs(tabButtons) do
        button.Visible = (name == "Misc")
    end

    local section = UI.createSection(
        miscTab,
        "Arcane Odyssey",
        120
    )

    UI.createToggle(
        section,
        "Boss ESP",
        "Shows Arcane Odyssey bosses through walls with HP and distance.",
        "ArcaneBossESP",
        32
    )

    local espObjects = {}

    local function destroyESP(model)
        local data = espObjects[model]
        if not data then
            return
        end

        if data.highlight then
            data.highlight:Destroy()
        end

        if data.billboard then
            data.billboard:Destroy()
        end

        espObjects[model] = nil
    end

    local function createESP(model)
        if espObjects[model] or not isValidBossModel(model) then
            return
        end

        local root = getRoot(model)
        if not root then
            return
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarBossESP"
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.72
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarBossESPInfo"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(220, 54)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.Parent = root

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.35
        label.TextSize = 13
        label.TextWrapped = true
        label.Parent = billboard

        espObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
    end

    local function scanBosses()
        local seen = {}

        for _, instance in ipairs(workspace:GetDescendants()) do
            if isValidBossModel(instance) then
                seen[instance] = true
                createESP(instance)
            end
        end

        for model in pairs(espObjects) do
            if not seen[model] or not model.Parent then
                destroyESP(model)
            end
        end
    end

    task.spawn(function()
        while true do
            task.wait(0.75)

            if Config.ArcaneBossESP then
                pcall(scanBosses)
            else
                for model in pairs(espObjects) do
                    destroyESP(model)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.15)

            if Config.ArcaneBossESP then
                local playerRoot = Shared.player.Character
                    and Shared.player.Character:FindFirstChild("HumanoidRootPart")

                for model, data in pairs(espObjects) do
                    if not model.Parent then
                        destroyESP(model)
                    else
                        local root = getRoot(model)

                        if not root then
                            destroyESP(model)
                        else
                            local bossName = getBossDisplayName(model) or model.Name
                            local distanceText = "Distance: ?"

                            if playerRoot then
                                distanceText = ("Distance: %d studs"):format(
                                    math.floor((playerRoot.Position - root.Position).Magnitude)
                                )
                            end

                            data.label.Text =
                                bossName
                                .. "\n"
                                .. getHealthText(model)
                                .. "  |  "
                                .. distanceText
                        end
                    end
                end
            end
        end
    end)

    return true
end

return Arcane
