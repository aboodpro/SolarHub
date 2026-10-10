--!strict
-- SolarHub Murder Mystery 2 feature entry point.

local MurderMystery2 = {}

function MurderMystery2.Init(Shared, UI, Context)
    local tab = UI.tabs and UI.tabs["Murder Mystery 2"]
    if not tab then
        error("[MurderMystery2] Murder Mystery 2 UI tab is missing.")
    end

    local section = UI.createSection(tab, "Murder Mystery 2", 92)

    local status = Instance.new("TextLabel")
    status.Name = "MurderMystery2Status"
    status.BackgroundTransparency = 1
    status.Position = UDim2.fromOffset(12, 36)
    status.Size = UDim2.new(1, -24, 0, 36)
    status.Font = Enum.Font.Gotham
    status.Text = "Base loaded. Ready to add the first MM2 feature."
    status.TextColor3 = Color3.fromRGB(170, 170, 180)
    status.TextSize = 10
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = section

    print("[MurderMystery2] Base module loaded.")
    return true
end

return MurderMystery2
