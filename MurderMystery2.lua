--!strict
-- SolarHub Murder Mystery 2 ESP and gun-drop alerts.

local MurderMystery2 = {}

function MurderMystery2.Init(Shared, UI, Context)
    local Players = Shared.Players or game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Shared.player or Players.LocalPlayer
    local Config = Shared.Config
    local tab = UI.tabs and UI.tabs["Murder Mystery 2"]

    if not tab then
        error("[MurderMystery2] Murder Mystery 2 UI tab is missing.")
    end

    Config.MM2RoleESP = Config.MM2RoleESP ~= false
    Config.MM2PlayersESP = Config.MM2PlayersESP ~= false
    Config.MM2GunDropESP = Config.MM2GunDropESP ~= false
    Config.MM2GunDropNotifications = Config.MM2GunDropNotifications ~= false
    Config.MM2PickedGunESP = Config.MM2PickedGunESP ~= false

    local RED = Color3.fromRGB(255, 55, 65)
    local BLUE = Color3.fromRGB(65, 145, 255)
    local GREEN = Color3.fromRGB(70, 235, 110)
    local YELLOW = Color3.fromRGB(255, 220, 55)
    local MUTED = Color3.fromRGB(170, 170, 180)

    local playerSection = UI.createSection(tab, "Players & Roles ESP", 228)
    UI.createToggle(
        playerSection,
        "Murderer / Sheriff ESP",
        "Murderer red; Sheriff blue. Includes body fill and name.",
        "MM2RoleESP",
        38
    )
    UI.createToggle(
        playerSection,
        "Picked-Up Gun ESP",
        "Highlights the player who picks up the dropped gun in yellow.",
        "MM2PickedGunESP",
        86
    )

    UI.createToggle(
        playerSection,
        "Players ESP",
        "Shows ordinary players in green; recognized roles keep their role colors.",
        "MM2PlayersESP",
        134
    )

    local playerStatus = Instance.new("TextLabel")
    playerStatus.Name = "SolarHubMM2RoleStatus"
    playerStatus.BackgroundTransparency = 1
    playerStatus.Position = UDim2.fromOffset(12, 184)
    playerStatus.Size = UDim2.new(1, -24, 0, 25)
    playerStatus.Font = Enum.Font.Gotham
    playerStatus.Text = "Role ESP: starting..."
    playerStatus.TextColor3 = MUTED
    playerStatus.TextSize = 10
    playerStatus.TextXAlignment = Enum.TextXAlignment.Left
    playerStatus.Parent = playerSection

    local gunSection = UI.createSection(tab, "Dropped Gun", 184)
    UI.createToggle(
        gunSection,
        "Dropped Gun ESP",
        "Yellow highlight and GUN DROPPED label above the weapon.",
        "MM2GunDropESP",
        38
    )
    UI.createToggle(
        gunSection,
        "Gun Drop Notification",
        "Shows an alert in the upper-right when the Sheriff gun drops.",
        "MM2GunDropNotifications",
        86
    )

    local gunStatus = Instance.new("TextLabel")
    gunStatus.Name = "SolarHubMM2GunStatus"
    gunStatus.BackgroundTransparency = 1
    gunStatus.Position = UDim2.fromOffset(12, 136)
    gunStatus.Size = UDim2.new(1, -24, 0, 25)
    gunStatus.Font = Enum.Font.Gotham
    gunStatus.Text = "Gun: waiting for round..."
    gunStatus.TextColor3 = MUTED
    gunStatus.TextSize = 10
    gunStatus.TextXAlignment = Enum.TextXAlignment.Left
    gunStatus.Parent = gunSection

    local active = true
    local connections = {}
    local playerVisuals = {}
    local pickedGunPlayers = {}
    local currentGunDrop = nil
    local gunDropHighlight = nil
    local gunDropLabel = nil
    local lastKnownGunHolder = nil
    local droppedGunHolder = nil
    local awaitingPickup = false
    local lastGunDropStatus = false
    local notificationGui = nil
    local notificationCard = nil
    local notificationTitle = nil
    local notificationBody = nil
    local notificationSerial = 0
    local lastStatus = {}

    local function addConnection(connection)
        table.insert(connections, connection)
        return connection
    end

    local function getTool(player, toolName)
        local character = player.Character
        if character then
            local tool = character:FindFirstChild(toolName)
            if tool and tool:IsA("Tool") then
                return tool
            end
        end

        local backpack = player:FindFirstChildOfClass("Backpack")
            or player:FindFirstChild("Backpack")
        if backpack then
            local tool = backpack:FindFirstChild(toolName)
            if tool and tool:IsA("Tool") then
                return tool
            end
        end

        return nil
    end

    local function getRole(player)
        if getTool(player, "Knife") then
            return "MURDERER"
        end
        if getTool(player, "Gun") then
            if pickedGunPlayers[player] and Config.MM2PickedGunESP then
                return "GUN PICKUP"
            end
            return "SHERIFF"
        end
        return nil
    end

    local function isAlive(player)
        local character = player and player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function getCharacterRoot(character)
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Head")
            or character.PrimaryPart
    end

    local function destroyPlayerVisual(player)
        local data = playerVisuals[player]
        if not data then
            return
        end

        for _, object in ipairs({data.highlight, data.labelGui}) do
            if object then
                pcall(function()
                    object:Destroy()
                end)
            end
        end

        playerVisuals[player] = nil
    end

    local function ensurePlayerVisual(player, role)
        if player == LocalPlayer or not player.Character or not role then
            destroyPlayerVisual(player)
            return
        end

        local character = player.Character
        local data = playerVisuals[player]
        if data and (data.character ~= character or data.role ~= role) then
            destroyPlayerVisual(player)
            data = nil
        end

        local roleColor = role == "MURDERER" and RED
            or role == "SHERIFF" and BLUE
            or role == "GUN PICKUP" and YELLOW
            or GREEN

        local displayText
        if role == "GUN PICKUP" or role == "PLAYER" then
            displayText = player.DisplayName
        else
            displayText = role .. " | " .. player.DisplayName
        end

        if not data then
            local highlight = Instance.new("Highlight")
            highlight.Name = "SolarHubMM2RoleHighlight"
            highlight.Adornee = character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = roleColor
            highlight.FillTransparency = 0.56
            highlight.OutlineColor = roleColor
            highlight.OutlineTransparency = 0
            highlight.Parent = character

            local root = character:FindFirstChild("Head")
                or getCharacterRoot(character)
            local labelGui
            if root then
                labelGui = Instance.new("BillboardGui")
                labelGui.Name = "SolarHubMM2RoleLabel"
                labelGui.Adornee = root
                labelGui.AlwaysOnTop = true
                labelGui.MaxDistance = math.huge
                labelGui.Size = UDim2.fromOffset(220, 30)
                labelGui.StudsOffset = Vector3.new(0, 2.7, 0)
                labelGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

                local label = Instance.new("TextLabel")
                label.Name = "Name"
                label.BackgroundTransparency = 1
                label.Size = UDim2.fromScale(1, 1)
                label.Font = Enum.Font.GothamBold
                label.TextSize = 13
                label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                label.TextStrokeTransparency = 0.25
                label.TextColor3 = roleColor
                label.Text = displayText
                label.Parent = labelGui
            end

            data = {
                character = character,
                role = role,
                highlight = highlight,
                labelGui = labelGui,
            }
            playerVisuals[player] = data
        end

        data.highlight.FillColor = roleColor
        data.highlight.OutlineColor = roleColor
        data.role = role

        if data.labelGui then
            local label = data.labelGui:FindFirstChild("Name")
            if label and label:IsA("TextLabel") then
                label.TextColor3 = roleColor
                label.Text = displayText
            end
            local root = character:FindFirstChild("Head") or getCharacterRoot(character)
            if root then
                data.labelGui.Adornee = root
            end
        end
    end

    local function findGunDrop()
        local found = Workspace:FindFirstChild("GunDrop", true)
        if found and found ~= LocalPlayer.Character then
            return found
        end
        return nil
    end

    local function getGunDropRoot(instance)
        if not instance then
            return nil
        end
        if instance:IsA("BasePart") then
            return instance
        end
        if instance:IsA("Model") then
            return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        end
        if instance:IsA("Tool") then
            return instance:FindFirstChild("Handle") or instance:FindFirstChildWhichIsA("BasePart", true)
        end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function destroyGunDropVisual()
        for _, object in ipairs({gunDropHighlight, gunDropLabel}) do
            if object then
                pcall(function()
                    object:Destroy()
                end)
            end
        end
        gunDropHighlight = nil
        gunDropLabel = nil
    end

    local function ensureGunDropVisual(instance)
        if not Config.MM2GunDropESP or not instance or not instance.Parent then
            destroyGunDropVisual()
            return
        end

        if gunDropHighlight and gunDropHighlight.Adornee ~= instance then
            destroyGunDropVisual()
        end

        if not gunDropHighlight then
            local highlight = Instance.new("Highlight")
            highlight.Name = "SolarHubMM2GunDropHighlight"
            highlight.Adornee = instance
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = YELLOW
            highlight.FillTransparency = 0.5
            highlight.OutlineColor = YELLOW
            highlight.OutlineTransparency = 0
            highlight.Parent = Workspace
            gunDropHighlight = highlight
        end

        local root = getGunDropRoot(instance)
        if root then
            if not gunDropLabel then
                local billboard = Instance.new("BillboardGui")
                billboard.Name = "SolarHubMM2GunDropLabel"
                billboard.Adornee = root
                billboard.AlwaysOnTop = true
                billboard.MaxDistance = math.huge
                billboard.Size = UDim2.fromOffset(180, 30)
                billboard.StudsOffset = Vector3.new(0, 2.2, 0)
                billboard.Parent = LocalPlayer:WaitForChild("PlayerGui")

                local label = Instance.new("TextLabel")
                label.Name = "Name"
                label.BackgroundTransparency = 1
                label.Size = UDim2.fromScale(1, 1)
                label.Font = Enum.Font.GothamBold
                label.Text = "GUN DROPPED"
                label.TextSize = 14
                label.TextColor3 = YELLOW
                label.TextStrokeColor3 = Color3.new(0, 0, 0)
                label.TextStrokeTransparency = 0.2
                label.Parent = billboard

                gunDropLabel = billboard
            else
                gunDropLabel.Adornee = root
            end
        end
    end

    local function ensureNotificationGui()
        if notificationGui and notificationGui.Parent then
            return
        end

        notificationGui = Instance.new("ScreenGui")
        notificationGui.Name = "SolarHubMM2Notifications"
        notificationGui.ResetOnSpawn = false
        notificationGui.DisplayOrder = 100000
        notificationGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

        notificationCard = Instance.new("Frame")
        notificationCard.Name = "GunDropNotification"
        notificationCard.AnchorPoint = Vector2.new(1, 0)
        notificationCard.Position = UDim2.new(1, -18, 0, 18)
        notificationCard.Size = UDim2.fromOffset(300, 76)
        notificationCard.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
        notificationCard.BackgroundTransparency = 0.08
        notificationCard.BorderSizePixel = 0
        notificationCard.Visible = false
        notificationCard.Parent = notificationGui
        Instance.new("UICorner", notificationCard).CornerRadius = UDim.new(0, 10)

        local stroke = Instance.new("UIStroke")
        stroke.Color = YELLOW
        stroke.Transparency = 0.12
        stroke.Thickness = 1.3
        stroke.Parent = notificationCard

        notificationTitle = Instance.new("TextLabel")
        notificationTitle.BackgroundTransparency = 1
        notificationTitle.Position = UDim2.fromOffset(12, 7)
        notificationTitle.Size = UDim2.new(1, -24, 0, 24)
        notificationTitle.Font = Enum.Font.GothamBold
        notificationTitle.Text = "GUN DROPPED"
        notificationTitle.TextColor3 = YELLOW
        notificationTitle.TextSize = 13
        notificationTitle.TextXAlignment = Enum.TextXAlignment.Left
        notificationTitle.Parent = notificationCard

        notificationBody = Instance.new("TextLabel")
        notificationBody.BackgroundTransparency = 1
        notificationBody.Position = UDim2.fromOffset(12, 32)
        notificationBody.Size = UDim2.new(1, -24, 0, 34)
        notificationBody.Font = Enum.Font.Gotham
        notificationBody.Text = "The armed player was eliminated."
        notificationBody.TextColor3 = Color3.fromRGB(235, 235, 240)
        notificationBody.TextSize = 11
        notificationBody.TextWrapped = true
        notificationBody.TextXAlignment = Enum.TextXAlignment.Left
        notificationBody.Parent = notificationCard
    end

    local function showGunDropNotification(wasHolderEliminated)
        if not Config.MM2GunDropNotifications then
            return
        end

        ensureNotificationGui()
        if not notificationCard then
            return
        end

        notificationSerial += 1
        local thisNotification = notificationSerial

        if notificationTitle then
            notificationTitle.Text = "GUN DROPPED"
        end
        if notificationBody then
            notificationBody.Text = wasHolderEliminated
                and "The armed player was eliminated — the gun is on the ground."
                or "The Sheriff's gun is on the ground."
        end
        notificationCard.Visible = true

        task.delay(4.5, function()
            if active and notificationCard and notificationCard.Parent
                and notificationSerial == thisNotification then
                notificationCard.Visible = false
            end
        end)
    end

    local function checkPlayersAndRoles()
        local murdererCount = 0
        local sheriffCount = 0
        local pickedUpCount = 0
        local ordinaryCount = 0
        local currentGunHolder = nil

        -- Identify roles when the corresponding Tool is already replicated
        -- to this client. No client-only animation timer is used as evidence.
        for _, player in ipairs(Players:GetPlayers()) do
            local hasKnife = getTool(player, "Knife") ~= nil
            local hasGun = getTool(player, "Gun") ~= nil

            if hasGun then
                currentGunHolder = currentGunHolder or player
            end

            if hasGun and awaitingPickup and currentGunDrop == nil
                and player ~= droppedGunHolder then
                pickedGunPlayers[player] = true
                awaitingPickup = false
            elseif not hasGun then
                pickedGunPlayers[player] = nil
            end

            local role
            if hasKnife then
                role = "MURDERER"
            elseif hasGun then
                if pickedGunPlayers[player] and Config.MM2PickedGunESP then
                    role = "GUN PICKUP"
                else
                    role = "SHERIFF"
                end
            else
                role = "PLAYER"
            end

            if player ~= LocalPlayer then
                if role == "MURDERER" then
                    murdererCount += 1
                elseif role == "SHERIFF" then
                    sheriffCount += 1
                elseif role == "GUN PICKUP" then
                    pickedUpCount += 1
                elseif role == "PLAYER" then
                    ordinaryCount += 1
                end

                if role == "GUN PICKUP" then
                    if Config.MM2PickedGunESP then
                        ensurePlayerVisual(player, role)
                    elseif Config.MM2PlayersESP then
                        ensurePlayerVisual(player, "PLAYER")
                    else
                        destroyPlayerVisual(player)
                    end
                elseif role == "MURDERER" or role == "SHERIFF" then
                    if Config.MM2RoleESP then
                        ensurePlayerVisual(player, role)
                    elseif Config.MM2PlayersESP then
                        ensurePlayerVisual(player, "PLAYER")
                    else
                        destroyPlayerVisual(player)
                    end
                elseif Config.MM2PlayersESP then
                    ensurePlayerVisual(player, "PLAYER")
                else
                    destroyPlayerVisual(player)
                end

                local visual = playerVisuals[player]
                if visual and visual.highlight then
                    local roleColor = visual.role == "MURDERER" and RED
                        or visual.role == "SHERIFF" and BLUE
                        or visual.role == "GUN PICKUP" and YELLOW
                        or GREEN

                    visual.highlight.FillTransparency = 0.56
                    visual.highlight.FillColor = roleColor
                    visual.highlight.OutlineColor = roleColor
                end
            end
        end

        -- Track the latest live holder for subsequent drop notification.
        if currentGunHolder and currentGunDrop == nil and not awaitingPickup then
            lastKnownGunHolder = currentGunHolder
        end

        if playerStatus and playerStatus.Parent then
            local nextStatus = ("Murderer: %d | Sheriff: %d | Picked up: %d | Players: %d"):format(
                murdererCount,
                sheriffCount,
                pickedUpCount,
                ordinaryCount
            )
            if lastStatus.player ~= nextStatus then
                lastStatus.player = nextStatus
                playerStatus.Text = nextStatus
            end
        end
    end

    local function processGunDrop()
        local found = findGunDrop()

        if found and found ~= currentGunDrop then
            destroyGunDropVisual()
            currentGunDrop = found

            droppedGunHolder = lastKnownGunHolder
            awaitingPickup = true

            local holderWasEliminated = droppedGunHolder ~= nil
                and not isAlive(droppedGunHolder)
            showGunDropNotification(holderWasEliminated)
        elseif not found and currentGunDrop then
            currentGunDrop = nil
            destroyGunDropVisual()
        end

        if currentGunDrop and currentGunDrop.Parent then
            ensureGunDropVisual(currentGunDrop)
            if gunStatus and gunStatus.Parent then
                gunStatus.Text = "Gun: DROPPED"
                gunStatus.TextColor3 = YELLOW
            end
        else
            if gunStatus and gunStatus.Parent then
                gunStatus.Text = awaitingPickup
                    and "Gun: waiting for a new holder..."
                    or "Gun: not dropped"
                gunStatus.TextColor3 = MUTED
            end
        end
    end

    local function onPlayerRemoving(player)
        destroyPlayerVisual(player)
        pickedGunPlayers[player] = nil
        if droppedGunHolder == player then
            droppedGunHolder = nil
        end
        if lastKnownGunHolder == player then
            -- Keep the last reference long enough to connect a gun-drop event
            -- that arrives immediately after the character/player is removed.
        end
    end

    addConnection(Players.PlayerRemoving:Connect(onPlayerRemoving))
    addConnection(Workspace.DescendantAdded:Connect(function(instance)
        if active and instance.Name == "GunDrop" then
            task.defer(processGunDrop)
        end
    end))
    addConnection(Workspace.DescendantRemoving:Connect(function(instance)
        if instance == currentGunDrop or (currentGunDrop and instance:IsDescendantOf(currentGunDrop)) then
            task.defer(processGunDrop)
        end
    end))

    ensureNotificationGui()

    local function cleanup()
        if not active then
            return
        end
        active = false

        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(connections)

        for player in pairs(playerVisuals) do
            destroyPlayerVisual(player)
        end
        destroyGunDropVisual()

        for _, object in ipairs({notificationGui, playerStatus, gunStatus}) do
            if object then
                pcall(function()
                    object:Destroy()
                end)
            end
        end

        pcall(function()
            if type(getgenv) == "function" then
                local env = getgenv()
                if env.SolarHubMurderMystery2Cleanup == cleanup then
                    env.SolarHubMurderMystery2Cleanup = nil
                end
            end
        end)
    end

    if type(getgenv) == "function" then
        pcall(function()
            getgenv().SolarHubMurderMystery2Cleanup = cleanup
        end)
    end
    if Context and type(Context.registerCleanup) == "function" then
        Context.registerCleanup(cleanup)
    end

    task.spawn(function()
        while active do
            local ok, err = pcall(function()
                processGunDrop()
                checkPlayersAndRoles()
            end)
            if not ok then
                warn("[MurderMystery2] Update failed: " .. tostring(err))
            end
            task.wait(0.2)
        end
    end)

    print("[MurderMystery2] Role ESP and gun-drop alerts loaded.")
    return true
end

return MurderMystery2
