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
    mainFrame.Size = UDim2.fromOffset(586, 304)
    mainFrame.Position = UDim2.new(0.5, -293, 0.5, -152)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

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

    makeDraggable(mainFrame)
    makeDraggable(toggleBtn)

    local resizeHandle = Instance.new("TextButton")
    resizeHandle.Size = UDim2.fromOffset(16, 16)
    resizeHandle.Position = UDim2.new(1, -16, 1, -16)
    resizeHandle.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    resizeHandle.Text = "◢"
    resizeHandle.TextColor3 = Color3.fromRGB(180, 180, 180)
    resizeHandle.TextSize = 10
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
    topBar.Size = UDim2.new(1, 0, 0, 34)
    topBar.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    topBar.BorderSizePixel = 0
    topBar.Parent = mainFrame
    Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 8)

    local brandLabel = Instance.new("TextLabel")
    brandLabel.Size = UDim2.fromOffset(400, 34)
    brandLabel.Position = UDim2.fromOffset(10, 0)
    brandLabel.BackgroundTransparency = 1
    brandLabel.Font = Enum.Font.GothamBold
    brandLabel.Text = "☀️ Solar Hub [Advanced Master Edition]"
    brandLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    brandLabel.TextSize = 11
    brandLabel.TextXAlignment = Enum.TextXAlignment.Left
    brandLabel.Parent = topBar

    local sidebar = Instance.new("ScrollingFrame")
    sidebar.Size = UDim2.new(0, 120, 1, -38)
    sidebar.Position = UDim2.new(0, 0, 0, 36)
    sidebar.BackgroundTransparency = 1
    sidebar.CanvasSize = UDim2.new(0, 0, 0, 300)
    sidebar.ScrollBarThickness = 2
    sidebar.Parent = mainFrame
    Instance.new("UIListLayout", sidebar).Padding = UDim.new(0, 4)

    local contentArea = Instance.new("Frame")
    contentArea.Size = UDim2.new(1, -124, 1, -38)
    contentArea.Position = UDim2.new(0, 122, 0, 36)
    contentArea.BackgroundTransparency = 1
    contentArea.Parent = mainFrame

    local tabs, tabButtons = {}, {}
    local tabNames = { "Lobby", "Joiner", "Game", "Auto Play", "Macro", "Webhook", "Misc" }

    for _, name in ipairs(tabNames) do
        local tabContainer = Instance.new("ScrollingFrame")
        tabContainer.Name = name .. "Tab"
        tabContainer.Size = UDim2.new(1, 0, 1, 0)
        tabContainer.BackgroundTransparency = 1
        tabContainer.Visible = (name == "Macro")
        tabContainer.CanvasSize = UDim2.new(0, 0, 0, 850)
        tabContainer.ScrollBarThickness = 3
        tabContainer.Parent = contentArea

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.Parent = tabContainer

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 8); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = tabContainer

        tabs[name] = tabContainer

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 26)
        btn.BackgroundColor3 = (name == "Macro") and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(24, 24, 30)
        btn.Text = "  " .. name
        btn.Font = Enum.Font.GothamMedium
        btn.TextColor3 = Color3.fromRGB(220, 220, 220)
        btn.TextSize = 10
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        tabButtons[name] = btn

        btn.MouseButton1Click:Connect(function()
            for tName, container in pairs(tabs) do
                container.Visible = (tName == name)
                tabButtons[tName].BackgroundColor3 = Color3.fromRGB(24, 24, 30)
            end
            btn.BackgroundColor3 = Color3.fromRGB(220, 140, 40)
        end)
    end

    local function createSection(tab, titleText, height: number?)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, height or 90)
        section.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
        section.BorderSizePixel = 0
        section.Parent = tab
        Instance.new("UICorner", section).CornerRadius = UDim.new(0, 6)

        local header = Instance.new("TextLabel")
        header.Size = UDim2.new(1, -16, 0, 26)
        header.Position = UDim2.fromOffset(8, 4)
        header.BackgroundTransparency = 1
        header.Font = Enum.Font.GothamBold
        header.Text = "- " .. titleText
        header.TextColor3 = Color3.fromRGB(200, 200, 210)
        header.TextSize = 11
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.Parent = section
        return section
    end

    local function createToggle(parent, title, desc, configKey, yPos)
        local toggleBtnItem = Instance.new("TextButton")
        toggleBtnItem.Size = UDim2.new(1, -16, 0, 36)
        toggleBtnItem.Position = UDim2.fromOffset(8, yPos)
        toggleBtnItem.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        toggleBtnItem.Text = ""
        toggleBtnItem.Parent = parent
        Instance.new("UICorner", toggleBtnItem).CornerRadius = UDim.new(0, 6)

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1, -45, 0, 16)
        titleLbl.Position = UDim2.fromOffset(8, 2)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = title
        titleLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
        titleLbl.TextSize = 10
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = toggleBtnItem

        local descLbl = Instance.new("TextLabel")
        descLbl.Size = UDim2.new(1, -45, 0, 14)
        descLbl.Position = UDim2.fromOffset(8, 18)
        descLbl.BackgroundTransparency = 1
        descLbl.Font = Enum.Font.Gotham
        descLbl.Text = desc
        descLbl.TextColor3 = Color3.fromRGB(130, 130, 140)
        descLbl.TextSize = 9
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.Parent = toggleBtnItem

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(16, 16)
        indicator.Position = UDim2.new(1, -24, 0.5, -8)
        indicator.BackgroundColor3 = Config[configKey] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)
        indicator.Parent = toggleBtnItem
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 4)

        toggleBtnItem.MouseButton1Click:Connect(function()
            Config[configKey] = not Config[configKey]
            indicator.BackgroundColor3 = Config[configKey] and Color3.fromRGB(220, 140, 40) or Color3.fromRGB(50, 50, 60)
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
        Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, 6)

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
        Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 6)

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

            optBtn.MouseButton1Click:Connect(function()
                Config[configKey] = opt
                valueLbl.Text = tostring(opt)
                listFrame.Visible = false
            end)
        end

        mainBtn.MouseButton1Click:Connect(function()
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
        Instance.new("UICorner", textBox).CornerRadius = UDim.new(0, 6)

        textBox.FocusLost:Connect(function()
            Config[configKey] = textBox.Text
        end)
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
    }
end

return UI
