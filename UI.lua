--!strict
local UI = {}

function UI.Init(Shared)
    local playerGui = Shared.playerGui
    local Config = Shared.Config
    local UserInputService = Shared.UserInputService

    if playerGui:FindFirstChild("SolarHub") then playerGui.SolarHub:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SolarHub"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999999
    screenGui.Parent = playerGui

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.fromOffset(40, 40)
    toggleBtn.Position = UDim2.new(0, 40, 0, 40)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    toggleBtn.Text = "☀️"
    toggleBtn.TextSize = 20
    toggleBtn.Parent = screenGui
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.fromOffset(720, 430)
    mainFrame.Position = UDim2.new(0.5, -360, 0.5, -215)
    mainFrame.BackgroundColor3 = Color3.fromRGB(17, 17, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 14)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(52, 52, 64)
    mainStroke.Transparency = 0.35
    mainStroke.Thickness = 1
    mainStroke.Parent = mainFrame

    local function makeDraggable(frame, handle)
        handle = handle or frame
        local dragging, dragInput, dragStart, startPos
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        handle.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    makeDraggable(toggleBtn)

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Size = UDim2.fromOffset(16, 16)
    resizeHandle.Position = UDim2.new(1, -16, 1, -16)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    resizeHandle.Text = "◢"
    resizeHandle.TextColor3 = Color3.fromRGB(180, 180, 180)
    resizeHandle.TextSize = 10
    resizeHandle.ZIndex = 100
    resizeHandle.Active = true
    resizeHandle.Parent = mainFrame
    Instance.new("UICorner", resizeHandle).CornerRadius = UDim.new(0, 4)

    local resizing = false
    local resizeStart, startSize
    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStart = input.Position
            startSize = mainFrame.AbsoluteSize
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then resizing = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - resizeStart
            local newWidth = math.clamp(startSize.X + delta.X, 400, 1400)
            local newHeight = math.clamp(startSize.Y + delta.Y, 250, 900)
            mainFrame.Size = UDim2.fromOffset(newWidth, newHeight)
        end
    end)

    local clickPos
    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then clickPos = input.Position end
    end)
    toggleBtn.InputEnded:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and clickPos then
            if (input.Position - clickPos).Magnitude < 5 then mainFrame.Visible = not mainFrame.Visible end
            clickPos = nil
        end
    end)

    local topBar = Instance.new("Frame")
    topBar.Active = true
    topBar.ZIndex = 10
    topBar.Size = UDim2.new(1, 0, 0, 44)
    topBar.BackgroundColor3 = Color3.fromRGB(23, 23, 30)
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame
    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 14)
    topCorner.Parent = topBar
    makeDraggable(mainFrame, topBar)

    local brandLabel = Instance.new("TextLabel")
    brandLabel.Size = UDim2.new(1, -140, 0, 44)
    brandLabel.Position = UDim2.fromOffset(14, 0)
    brandLabel.BackgroundTransparency = 1
    brandLabel.Font = Enum.Font.GothamBold
    brandLabel.Text = "☀️ Solar Hub [Advanced Master Edition]"
    brandLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    brandLabel.TextSize = 13
    brandLabel.TextXAlignment = Enum.TextXAlignment.Left
    brandLabel.Parent = topBar

    local sidebar = Instance.new("ScrollingFrame")
    sidebar.Size = UDim2.new(0, 148, 1, -48)
    sidebar.Position = UDim2.new(0, 0, 0, 46)
    sidebar.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
    sidebar.BackgroundTransparency = 0.12
    sidebar.CanvasSize = UDim2.new(0, 0, 0, 300)
    sidebar.ScrollBarThickness = 2
    sidebar.ZIndex = 1
    sidebar.Parent = mainFrame
    Instance.new("UIListLayout", sidebar).Padding = UDim.new(0, 4)

    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, -154, 1, -48)
    contentArea.Position = UDim2.new(0, 152, 0, 46)
    contentArea.BackgroundTransparency = 1
    contentArea.ZIndex = 1
    contentArea.Parent = mainFrame

    local tabs, tabButtons = {}, {}
    local tabErrors = {}
    local tabNames

    if Shared.IsArcaneOdyssey == true then
        tabNames = { "Misc" }
    else
        tabNames = { "Lobby", "Joiner", "Game", "Auto Play", "Macro", "Webhook", "Misc" }
    end

    for _, name in ipairs(tabNames) do
        local tabContainer = Instance.new("ScrollingFrame")
        tabContainer.Name = name .. "Tab"
        tabContainer.Size = UDim2.new(1, 0, 1, 0)
        tabContainer.BackgroundTransparency = 1
        tabContainer.Visible = (name == "Macro")
        tabContainer.CanvasSize = UDim2.new(0, 0, 0, 900)
        tabContainer.ScrollBarThickness = 3
        tabContainer.Parent = contentArea

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = tabContainer

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.Parent = tabContainer

        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            tabContainer.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 16)
        end)
        task.defer(function()
            tabContainer.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 16)
        end)

        tabs[name] = tabContainer

        if name == "Macro" then
            local errorLabel = Instance.new("TextLabel")
            errorLabel.Name = "Diagnostic"
            errorLabel.Size = UDim2.new(1, -16, 0, 54)
            errorLabel.BackgroundColor3 = Color3.fromRGB(70, 28, 28)
            errorLabel.TextColor3 = Color3.fromRGB(255, 190, 190)
            errorLabel.Text = ""
            errorLabel.TextWrapped = true
            errorLabel.TextSize = 10
            errorLabel.Font = Enum.Font.Gotham
            errorLabel.Visible = false
            errorLabel.LayoutOrder = -1000
            errorLabel.Parent = tabContainer
            Instance.new("UICorner", errorLabel).CornerRadius = UDim.new(0, 8)
            tabErrors[name] = errorLabel
        end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -12, 0, 34)
        btn.BackgroundColor3 = (name == "Macro") and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(28, 28, 36)
        btn.Text = "   " .. name
        btn.Font = Enum.Font.GothamMedium
        btn.TextColor3 = Color3.fromRGB(225, 225, 232)
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        tabButtons[name] = btn

        btn.Activated:Connect(function()
            for tName, container in pairs(tabs) do
                local selected = (tName == name)
                container.Visible = selected
                tabButtons[tName].BackgroundColor3 = selected and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(24, 24, 30)
                if selected then
                    container.CanvasPosition = Vector2.zero
                end
            end
        end)
    end

    local function createSection(tab, titleText, height: number?)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, height or 100)
        section.BackgroundColor3 = Color3.fromRGB(24, 24, 31)
        section.BorderSizePixel = 0
        section.Parent = tab
        local sectionCorner = Instance.new("UICorner")
        sectionCorner.CornerRadius = UDim.new(0, 11)
        sectionCorner.Parent = section

        local header = Instance.new("TextLabel")
        header.Size = UDim2.new(1, -20, 0, 30)
        header.Position = UDim2.fromOffset(10, 6)
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = "▸  " .. titleText
        header.TextColor3 = Color3.fromRGB(200, 200, 210)
        header.TextSize = 12
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Parent = section
        return section
    end

    local function createToggle(parent, title, desc, configKey, yPos)
        local toggleBtnItem = Instance.new("TextButton")
        toggleBtnItem.Size = UDim2.new(1, -20, 0, 44)
        toggleBtnItem.Position = UDim2.fromOffset(10, yPos)
        toggleBtnItem.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        toggleBtnItem.Text = ""
        toggleBtnItem.Parent = parent
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(0, 9)
        toggleCorner.Parent = toggleBtnItem

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, -58, 0, 19)
        titleLbl.Position = UDim2.fromOffset(10, 3)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = title
        titleLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
        titleLbl.TextSize = 11
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = toggleBtnItem

        local descLbl = Instance.new("TextLabel")
        descLbl.Size = UDim2.new(1, -58, 0, 16)
        descLbl.Position = UDim2.fromOffset(10, 22)
        descLbl.BackgroundTransparency = 1
        descLbl.Font = Enum.Font.Gotham
        descLbl.Text = desc
        descLbl.TextColor3 = Color3.fromRGB(130, 130, 140)
        descLbl.TextSize = 9
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.Parent = toggleBtnItem

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(18, 18)
        indicator.Position = UDim2.new(1, -29, 0.5, -9)
        indicator.BackgroundColor3 = Config[configKey] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)
        indicator.Parent = toggleBtnItem
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 4)

        toggleBtnItem.Activated:Connect(function()
            Config[configKey] = not Config[configKey]
            indicator.BackgroundColor3 = Config[configKey] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)

            if Config.MacroDebug == true and type(Shared.logLine) == "function" then
                Shared.logLine(
                    ("[ConfigDebug] %s (%s) = %s"):format(
                        tostring(configKey),
                        tostring(title),
                        tostring(Config[configKey])
                    )
                )
            end
        end)
    end

    local function createDropdown(parent, title, desc, options, configKey, posX, posY, width)
        local container = Instance.new("Frame")
        container.Size = UDim2.fromOffset(width, 58)
        container.Position = UDim2.fromOffset(posX, posY)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, 0, 0, 14)
        titleLbl.Position = UDim2.fromOffset(0, 0)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = title
        titleLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
        titleLbl.TextSize = 9
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = container

        local mainBtn = Instance.new("TextButton")
        mainBtn.Size = UDim2.new(1, 0, 0, 24)
        mainBtn.Position = UDim2.fromOffset(0, 15)
        mainBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        mainBtn.Text = ""
        mainBtn.Parent = container
        local mainBtnCorner = Instance.new("UICorner")
        mainBtnCorner.CornerRadius = UDim.new(0, 8)
        mainBtnCorner.Parent = mainBtn

        local valueLbl = Instance.new("TextLabel")
        valueLbl.Size = UDim2.new(1, -26, 1, 0)
        valueLbl.Position = UDim2.fromOffset(6, 0)
        valueLbl.BackgroundTransparency = 1
        valueLbl.Font = Enum.Font.GothamBold
        valueLbl.Text = tostring(Config[configKey])
        valueLbl.TextColor3 = Color3.fromRGB(220, 140, 40)
        valueLbl.TextSize = 9
        valueLbl.TextXAlignment = Enum.TextXAlignment.Left
        valueLbl.Parent = mainBtn

        local arrowLbl = Instance.new("TextLabel")
        arrowLbl.Size = UDim2.fromOffset(16, 16)
        arrowLbl.Position = UDim2.new(1, -20, 0.5, -8)
        arrowLbl.BackgroundTransparency = 1
        arrowLbl.Font = Enum.Font.GothamBold
        arrowLbl.Text = "▼"
        arrowLbl.TextColor3 = Color3.fromRGB(180, 180, 190)
        arrowLbl.TextSize = 9
        arrowLbl.Parent = mainBtn

        local listFrame = Instance.new("ScrollingFrame")
        listFrame.Size = UDim2.new(1, 0, 0, 80)
        listFrame.Position = UDim2.fromOffset(0, 42)
        listFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
        listFrame.BorderSizePixel = 0
        listFrame.Visible = false
        listFrame.ZIndex = 5
        listFrame.CanvasSize = UDim2.new(0, 0, 0, #options * 22)
        listFrame.ScrollBarThickness = 3
        listFrame.Parent = container
        local listCorner = Instance.new("UICorner")
        listCorner.CornerRadius = UDim.new(0, 8)
        listCorner.Parent = listFrame

        local listLayout = Instance.new("UIListLayout")
        listLayout.Parent = listFrame

        for _, opt in ipairs(options) do
            local optBtn = Instance.new("TextButton")
            optBtn.Size = UDim2.new(1, 0, 0, 22)
            optBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
            optBtn.BackgroundTransparency = 0.5
            optBtn.ZIndex = 6
            optBtn.Text = "  " .. opt
            optBtn.Font = Enum.Font.Gotham
            optBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
            optBtn.TextSize = 9
            optBtn.TextXAlignment = Enum.TextXAlignment.Left
            optBtn.Parent = listFrame

            optBtn.Activated:Connect(function()
                Config[configKey] = opt
                valueLbl.Text = tostring(opt)
                listFrame.Visible = false

                if Config.MacroDebug == true and type(Shared.logLine) == "function" then
                    Shared.logLine(
                        ("[ConfigDebug] %s (%s) = %s"):format(
                            tostring(configKey),
                            tostring(title),
                            tostring(Config[configKey])
                        )
                    )
                end
            end)
        end

        mainBtn.Activated:Connect(function()
            listFrame.Visible = not listFrame.Visible
        end)
    end

    local function createInput(parent, title, desc, configKey, posX, posY, width)
        local container = Instance.new("Frame")
        container.Size = UDim2.fromOffset(width, 45)
        container.Position = UDim2.fromOffset(posX, posY)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, 0, 0, 14)
        titleLbl.Position = UDim2.fromOffset(0, 0)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = title
        titleLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
        titleLbl.TextSize = 9
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = container

        local textBox = Instance.new("TextBox")
        textBox.Size = UDim2.new(1, 0, 0, 24)
        textBox.Position = UDim2.fromOffset(0, 15)
        textBox.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        textBox.BorderSizePixel = 0
        textBox.Text = tostring(Config[configKey])
        textBox.PlaceholderText = desc
        textBox.Font = Enum.Font.Gotham
        textBox.TextColor3 = Color3.fromRGB(220, 140, 40)
        textBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
        textBox.TextSize = 9
        textBox.TextXAlignment = Enum.TextXAlignment.Left
        textBox.ClearTextOnFocus = false
        textBox.Parent = container
        local inputCorner = Instance.new("UICorner")
        inputCorner.CornerRadius = UDim.new(0, 8)
        inputCorner.Parent = textBox

        textBox.FocusLost:Connect(function()
            Config[configKey] = textBox.Text

            if Config.MacroDebug == true and type(Shared.logLine) == "function" then
                Shared.logLine(
                    ("[ConfigDebug] %s (%s) = %s"):format(
                        tostring(configKey),
                        tostring(title),
                        tostring(Config[configKey])
                    )
                )
            end
        end)
    end


    local function createSlider(parent, title, configKey, minValue, maxValue, posX, posY, width, onChanged)
        minValue = tonumber(minValue) or 0
        maxValue = tonumber(maxValue) or 100

        if maxValue < minValue then
            minValue, maxValue = maxValue, minValue
        end

        local value = tonumber(Config[configKey])
        if value == nil then
            value = maxValue
        end

        value = math.clamp(value, minValue, maxValue)
        Config[configKey] = value

        local container = Instance.new("Frame")
        container.Size = UDim2.fromOffset(width, 42)
        container.Position = UDim2.fromOffset(posX, posY)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, -74, 0, 16)
        titleLabel.Position = UDim2.fromOffset(0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.Text = title
        titleLabel.TextColor3 = Color3.fromRGB(185, 185, 195)
        titleLabel.TextSize = 8
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = container

        local valueBox = Instance.new("TextBox")
        valueBox.Size = UDim2.fromOffset(68, 18)
        valueBox.Position = UDim2.new(1, -68, 0, -2)
        valueBox.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        valueBox.BorderSizePixel = 0
        valueBox.Text = tostring(math.floor(value + 0.5))
        valueBox.TextColor3 = Color3.fromRGB(220, 140, 40)
        valueBox.PlaceholderText = tostring(math.floor(maxValue))
        valueBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
        valueBox.Font = Enum.Font.GothamBold
        valueBox.TextSize = 8
        valueBox.TextXAlignment = Enum.TextXAlignment.Center
        valueBox.ClearTextOnFocus = false
        valueBox.Parent = container
        Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 6)

        local bar = Instance.new("TextButton")
        bar.Size = UDim2.new(1, 0, 0, 8)
        bar.Position = UDim2.fromOffset(0, 24)
        bar.BackgroundColor3 = Color3.fromRGB(48, 48, 58)
        bar.BorderSizePixel = 0
        bar.AutoButtonColor = false
        bar.Text = ""
        bar.Parent = container
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        local knob = Instance.new("TextButton")
        knob.Size = UDim2.fromOffset(14, 14)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
        knob.BorderSizePixel = 0
        knob.AutoButtonColor = false
        knob.Text = ""
        knob.ZIndex = 3
        knob.Parent = bar
        Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

        local dragging = false
        local dragInput = nil

        local function setValue(newValue)
            newValue = tonumber(newValue)

            if newValue == nil then
                return
            end

            newValue = math.clamp(newValue, minValue, maxValue)
            newValue = math.floor(newValue + 0.5)

            Config[configKey] = newValue

            if type(onChanged) == "function" then
                pcall(function()
                    onChanged(newValue)
                end)
            end

            local alpha = 0
            if maxValue > minValue then
                alpha = (newValue - minValue) / (maxValue - minValue)
            end

            fill.Size = UDim2.fromScale(alpha, 1)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            valueBox.Text = tostring(newValue)
        end

        local function setFromMouseX(x)
            local left = bar.AbsolutePosition.X
            local widthAbsolute = math.max(1, bar.AbsoluteSize.X)
            local alpha = math.clamp((x - left) / widthAbsolute, 0, 1)

            setValue(
                minValue + ((maxValue - minValue) * alpha)
            )
        end

        setValue(value)

        local function beginDrag(input)
            dragging = true
            setFromMouseX(input.Position.X)

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end

        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                beginDrag(input)
            end
        end)

        bar.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        knob.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                beginDrag(input)
            end
        end)

        knob.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging
                and dragInput == input then
                setFromMouseX(input.Position.X)
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        valueBox.FocusLost:Connect(function()
            local raw = tostring(valueBox.Text or "")
            local cleaned = raw
                :gsub(",", "")
                :gsub("%s+", "")

            local typed = tonumber(cleaned)

            if typed == nil then
                valueBox.Text = tostring(math.floor(Config[configKey] + 0.5))
                return
            end

            -- Typing a value is exactly the same as dragging the slider to it.
            setValue(typed)
        end)

        valueBox.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode == Enum.KeyCode.Return then

                local raw = tostring(valueBox.Text or "")
                local cleaned = raw
                    :gsub(",", "")
                    :gsub("%s+", "")

                local typed = tonumber(cleaned)

                if typed ~= nil then
                    setValue(typed)
                else
                    valueBox.Text = tostring(math.floor(Config[configKey] + 0.5))
                end
            end
        end)

        return {
            container = container,
            bar = bar,
            fill = fill,
            knob = knob,
            valueBox = valueBox,
            setValue = setValue,
        }
    end

    return {
        screenGui = screenGui,
        toggleBtn = toggleBtn,
        mainFrame = mainFrame,
        tabs = tabs,
        tabButtons = tabButtons,
        createSection = createSection,
        createToggle = createToggle,
        createDropdown = createDropdown,
        createInput = createInput,
        createSlider = createSlider,
        setTabError = function(name, message)
            local label = tabErrors[name]
            if label then
                label.Text = tostring(message)
                label.Visible = true
                tabs[name].CanvasPosition = Vector2.zero
            end
        end,
        clearTabError = function(name)
            local label = tabErrors[name]
            if label then label.Visible = false end
        end,
    }
end

return UI
