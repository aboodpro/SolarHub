--!strict
local Arcane = {}

-------------------------------------------------
-- ARCANE ODYSSEY BOSS DATABASE
-------------------------------------------------

local BOSS_NAMES = {
    -- Story bosses
    "Shura",
    "Iris",
    "Lord Elius",
    "General Argos",
    "Lady Carina",
    "King Calvus",
    "King Calvus IV",
    "Prince Revon",
    "Captain Maria",
    "Prince Allanon",
    "Jarl Ivar",

    -- Side bosses
    "Cernyx",
    "Jorund",
    "Ormolu",
    "Hallbjorn",
    "King Caesar",
    "Leviathan",

    -- Other boss / strong boss encounters
    "Commodore Kai",
    "Architect Merlot",
    "Alpha",
    "Rear Admiral Amelia",
    "General Valerii",
}

local function normalizeName(value)
    return tostring(value):lower():gsub("[^%w]+", "")
end

local NORMALIZED_BOSSES = {}

for _, name in ipairs(BOSS_NAMES) do
    NORMALIZED_BOSSES[normalizeName(name)] = name
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getRoot(model)
    if not model:IsA("Model") then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("Head")
end

local function findBossNameFromValue(value)
    local normalized = normalizeName(value)

    if normalized == "" then
        return nil
    end

    for key, displayName in pairs(NORMALIZED_BOSSES) do
        if normalized == key or normalized:find(key, 1, true) then
            return displayName
        end
    end

    return nil
end

local function getBossDisplayName(model)
    -- Name is the fastest/common path.
    local byName = findBossNameFromValue(model.Name)
    if byName then
        return byName
    end

    -- Some game revisions expose a title/display attribute instead.
    for _, attributeName in ipairs({
        "BossName",
        "DisplayName",
        "Title",
        "NPCName",
    }) do
        local value = model:GetAttribute(attributeName)
        local match = findBossNameFromValue(value)
        if match then
            return match
        end
    end

    return nil
end

local function hasBossMarker(model)
    for _, attributeName in ipairs({
        "Boss",
        "IsBoss",
        "BossType",
        "IsBossNPC",
    }) do
        local value = model:GetAttribute(attributeName)

        if value == true then
            return true
        end

        if type(value) == "string" and value:lower():find("boss", 1, true) then
            return true
        end
    end

    local parent = model.Parent
    if parent and parent:IsA("Folder") then
        local parentName = normalizeName(parent.Name)
        if parentName == "bosses" or parentName == "boss" then
            return true
        end
    end

    return false
end

local function getBossInfo(model)
    if not model:IsA("Model") then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end

    if not getRoot(model) then
        return nil
    end

    local bossName = getBossDisplayName(model)

    if not bossName and not hasBossMarker(model) then
        return nil
    end

    return {
        name = bossName or model.Name,
        humanoid = humanoid,
    }
end

-------------------------------------------------
-- ESP
-------------------------------------------------

function Arcane.Init(Shared, UI)
    local Config = Shared.Config
    local tabs = UI.tabs or {}
    local tabButtons = UI.tabButtons or {}

    Config.ArcaneBossESP = Config.ArcaneBossESP == true

    local miscTab = tabs["Misc"]
    if not miscTab then
        error("[Arcane] Misc tab is missing.")
    end

    -- Arcane only needs the Misc tab.
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
        "Shows detected bosses with HP and distance.",
        "ArcaneBossESP",
        32
    )

    local espObjects = {}
    local candidateModels = {}

    local function destroyESP(model)
        local data = espObjects[model]

        if data then
            if data.highlight then
                pcall(function()
                    data.highlight:Destroy()
                end)
            end

            if data.billboard then
                pcall(function()
                    data.billboard:Destroy()
                end)
            end

            espObjects[model] = nil
        end
    end

    local function removeModel(model)
        candidateModels[model] = nil
        destroyESP(model)
    end

    local function createESP(model)
        if not Config.ArcaneBossESP then
            return
        end

        if espObjects[model] then
            return
        end

        local info = getBossInfo(model)
        if not info then
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
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarBossESPInfo"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(250, 58)
        billboard.StudsOffset = Vector3.new(0, 3.6, 0)
        billboard.Parent = root

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.25
        label.TextSize = 13
        label.TextWrapped = true
        label.Parent = billboard

        espObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
    end

    local function inspectModel(model)
        if not model or not model.Parent or not model:IsA("Model") then
            return
        end

        candidateModels[model] = true

        if Config.ArcaneBossESP then
            createESP(model)
        end
    end

    -- Watch only newly-created models instead of repeatedly scanning the entire
    -- workspace. This is much cheaper while the player is moving/fighting.
    workspace.DescendantAdded:Connect(function(instance)
        local model = instance:IsA("Model")
            and instance
            or instance:FindFirstAncestorOfClass("Model")

        if model then
            inspectModel(model)

            -- A boss may gain its Humanoid/root a moment after the Model appears.
            task.delay(0.15, function()
                if model and model.Parent then
                    inspectModel(model)
                end
            end)
        end
    end)

    workspace.DescendantRemoving:Connect(function(instance)
        if instance:IsA("Model") then
            removeModel(instance)
        end
    end)

    -- One initial scan, processed in small batches to avoid a frame hitch.
    task.spawn(function()
        local descendants = workspace:GetDescendants()
        local processed = 0

        for _, instance in ipairs(descendants) do
            if instance:IsA("Model") then
                inspectModel(instance)
            end

            processed += 1

            if processed % 200 == 0 then
                task.wait()
            end
        end
    end)

    -- Low-frequency validation instead of a full workspace scan.
    task.spawn(function()
        while true do
            task.wait(2)

            if Config.ArcaneBossESP then
                for model in pairs(candidateModels) do
                    if not model.Parent then
                        removeModel(model)
                    else
                        createESP(model)
                    end
                end
            else
                for model in pairs(espObjects) do
                    destroyESP(model)
                end
            end
        end
    end)

    -- Lightweight UI updates only for currently detected bosses.
    task.spawn(function()
        while true do
            task.wait(0.25)

            if Config.ArcaneBossESP then
                local character = Shared.player.Character
                local playerRoot = character
                    and character:FindFirstChild("HumanoidRootPart")

                for model, data in pairs(espObjects) do
                    if not model.Parent then
                        removeModel(model)
                    else
                        local root = getRoot(model)
                        local humanoid = model:FindFirstChildOfClass("Humanoid")

                        if not root or not humanoid then
                            destroyESP(model)
                        else
                            local bossName = getBossDisplayName(model) or model.Name
                            local distanceText = "Distance: ?"

                            if playerRoot then
                                distanceText = ("Distance: %d studs"):format(
                                    math.floor(
                                        (playerRoot.Position - root.Position).Magnitude
                                    )
                                )
                            end

                            local health = math.max(0, humanoid.Health)
                            local maxHealth = math.max(0, humanoid.MaxHealth)

                            data.label.Text = string.format(
                                "%s\nHP: %d/%d  |  %s",
                                tostring(bossName),
                                math.floor(health),
                                math.floor(maxHealth),
                                distanceText
                            )
                        end
                    end
                end
            end
        end
    end)

    return true
end

return Arcane
