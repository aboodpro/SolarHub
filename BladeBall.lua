--!strict
-- SolarHub Blade Ball Auto Parry.
-- Uses a local F-key input when the live ball is approaching the local player.

local BladeBall = {}

function BladeBall.Init(Shared, UI, Context)
    local Players = game:GetService("Players")
    local RunService = Shared.RunService or game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local LocalPlayer = Shared.player or Players.LocalPlayer
    local Config = Shared.Config

    Config.BladeBallAutoParry = Config.BladeBallAutoParry == true
    Config.BladeBallParryLeadMs = math.clamp(
        math.floor(tonumber(Config.BladeBallParryLeadMs) or 180),
        50,
        420
    )
    Config.BladeBallContactDistance = math.clamp(
        math.floor(tonumber(Config.BladeBallContactDistance) or 12),
        5,
        22
    )

    local tab = UI.tabs and UI.tabs["Blade Ball"]
    if not tab then
        error("[BladeBall] Blade Ball UI tab is missing.")
    end

    local section = UI.createSection(tab, "Auto Parry", 236)

    UI.createToggle(
        section,
        "Auto Parry",
        "Automatically taps F when the incoming ball is about to reach you.",
        "BladeBallAutoParry",
        32
    )

    UI.createSlider(
        section,
        "Parry Lead (milliseconds)",
        "BladeBallParryLeadMs",
        50,
        420,
        10,
        88,
        330,
        function(value)
            Config.BladeBallParryLeadMs = value
        end
    )

    UI.createSlider(
        section,
        "Parry Distance (studs)",
        "BladeBallContactDistance",
        5,
        22,
        10,
        140,
        330,
        function(value)
            Config.BladeBallContactDistance = value
        end
    )

    local status = Instance.new("TextLabel")
    status.Name = "BladeBallAutoParryStatus"
    status.BackgroundTransparency = 1
    status.Position = UDim2.fromOffset(10, 190)
    status.Size = UDim2.new(1, -20, 0, 34)
    status.Font = Enum.Font.GothamBold
    status.Text = "Status: Auto Parry OFF"
    status.TextColor3 = Color3.fromRGB(170, 170, 180)
    status.TextSize = 9
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    status.Parent = section

    local active = true
    local heartbeatConnection
    local characterAddedConnection
    local lastStatusText = ""
    local lastStatusAt = 0
    local lastParryAt = 0
    local inputBusy = false
    local parriedBall = nil
    local PARRY_COOLDOWN = 0.28

    local function setStatus(message, urgent)
        message = tostring(message)
        if message == lastStatusText and os.clock() - lastStatusAt < 0.2 then
            return
        end

        lastStatusText = message
        lastStatusAt = os.clock()

        if status and status.Parent then
            status.Text = "Status: " .. message
            status.TextColor3 = urgent
                and Color3.fromRGB(255, 95, 105)
                or Color3.fromRGB(170, 170, 180)
        end
    end

    local function getRoot()
        local character = LocalPlayer.Character
        if not character then
            return nil
        end

        return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
    end

    local function getRealBall()
        local ballsFolder = Workspace:FindFirstChild("Balls")
        if not ballsFolder then
            return nil
        end

        local fallback = nil
        for _, item in ipairs(ballsFolder:GetChildren()) do
            if item:IsA("BasePart") then
                if item:GetAttribute("realBall") == true then
                    return item
                end

                if fallback == nil and item:GetAttribute("target") ~= nil then
                    fallback = item
                end
            end
        end

        return fallback
    end

    local function targetAttributeMatchesPlayer(value)
        if value == nil then
            return false
        end

        if typeof(value) == "Instance" then
            if value == LocalPlayer or value == LocalPlayer.Character then
                return true
            end

            if value:IsA("Player") and value.UserId == LocalPlayer.UserId then
                return true
            end
        end

        local targetText = tostring(value):lower()
        return targetText == tostring(LocalPlayer.Name):lower()
            or targetText == tostring(LocalPlayer.UserId)
            or targetText == tostring(LocalPlayer.DisplayName):lower()
    end

    local function isTargetingPlayer(ball)
        if targetAttributeMatchesPlayer(ball:GetAttribute("target")) then
            return true
        end

        -- Some rounds represent the current target with a Highlight on the
        -- local character rather than the ball's target attribute.
        local character = LocalPlayer.Character
        return character ~= nil and character:FindFirstChild("Highlight") ~= nil
    end

    local function getBallVelocity(ball)
        local zoomies = ball:FindFirstChild("zoomies")
        if zoomies then
            local ok, value = pcall(function()
                return zoomies.VectorVelocity
            end)

            if ok and typeof(value) == "Vector3" and value.Magnitude > 0 then
                return value
            end

            if zoomies:IsA("Vector3Value") and zoomies.Value.Magnitude > 0 then
                return zoomies.Value
            end
        end

        local ok, value = pcall(function()
            return ball.AssemblyLinearVelocity
        end)

        if ok and typeof(value) == "Vector3" then
            return value
        end

        return Vector3.zero
    end

    local function pressParry()
        local now = os.clock()
        if inputBusy or now - lastParryAt < PARRY_COOLDOWN then
            return false
        end

        inputBusy = true
        lastParryAt = now

        task.spawn(function()
            local keyDownSent = false
            local ok, err = pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                keyDownSent = true
                task.wait(0.035)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                keyDownSent = false
            end)

            -- Release F even if the key-up call failed midway.
            if keyDownSent then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                end)
            end

            if not ok then
                setStatus("input failed: " .. tostring(err), false)
            end

            inputBusy = false
        end)

        return true
    end

    local function update()
        if not active then
            return
        end

        if Config.BladeBallAutoParry ~= true then
            parriedBall = nil
            setStatus("Auto Parry OFF", false)
            return
        end

        local root = getRoot()
        if not root then
            parriedBall = nil
            setStatus("waiting for your character", false)
            return
        end

        local ball = getRealBall()
        if not ball then
            parriedBall = nil
            setStatus("waiting for the real ball in Workspace.Balls", false)
            return
        end

        if not isTargetingPlayer(ball) then
            parriedBall = nil
            setStatus("ball found; it is not targeting you", false)
            return
        end

        local offset = root.Position - ball.Position
        local distance = offset.Magnitude
        if distance < 0.001 then
            if parriedBall ~= ball and pressParry() then
                parriedBall = ball
                setStatus("AUTO PARRY SENT | contact range", true)
            end
            return
        end

        local directionToPlayer = offset.Unit
        local ballVelocity = getBallVelocity(ball)
        local playerVelocity = root.AssemblyLinearVelocity
        local closingSpeed = ballVelocity:Dot(directionToPlayer)
            - playerVelocity:Dot(directionToPlayer)

        if closingSpeed <= 1 then
            setStatus(("targeting you; not closing | %.0f studs"):format(distance), false)
            return
        end

        local contactDistance = tonumber(Config.BladeBallContactDistance) or 12
        local leadSeconds = (tonumber(Config.BladeBallParryLeadMs) or 180) / 1000
        local timeToContact = math.max(0, distance - contactDistance) / closingSpeed

        if distance <= contactDistance or timeToContact <= leadSeconds then
            if parriedBall ~= ball and pressParry() then
                parriedBall = ball
                setStatus(
                    ("AUTO PARRY SENT | %.0f studs | ETA %.0f ms"):format(
                        distance,
                        timeToContact * 1000
                    ),
                    true
                )
            elseif parriedBall == ball then
                setStatus(("parry sent | %.0f studs"):format(distance), true)
            else
                setStatus("incoming ball; waiting for input cooldown", false)
            end
        else
            setStatus(
                ("targeting you | %.0f studs | ETA %.0f ms"):format(
                    distance,
                    timeToContact * 1000
                ),
                false
            )
        end
    end

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(update)
        if not ok then
            setStatus("check failed: " .. tostring(err), false)
        end
    end)

    characterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
        parriedBall = nil
        setStatus("respawned; waiting for ball", false)
    end)

    local function cleanup()
        if not active then
            return
        end

        active = false

        if heartbeatConnection then
            heartbeatConnection:Disconnect()
            heartbeatConnection = nil
        end

        if characterAddedConnection then
            characterAddedConnection:Disconnect()
            characterAddedConnection = nil
        end

        if status then
            pcall(function()
                status:Destroy()
            end)
        end

        pcall(function()
            if type(getgenv) == "function" then
                local env = getgenv()
                if env.SolarHubBladeBallCleanup == cleanup then
                    env.SolarHubBladeBallCleanup = nil
                end
            end
        end)
    end

    if type(getgenv) == "function" then
        pcall(function()
            getgenv().SolarHubBladeBallCleanup = cleanup
        end)
    end

    if Context and type(Context.registerCleanup) == "function" then
        Context.registerCleanup(cleanup)
    end

    print("[BladeBall] Auto Parry loaded.")
    setStatus("ready; turn Auto Parry ON", false)
    return true
end

return BladeBall
