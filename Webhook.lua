--!strict
local Webhook = {}

function Webhook.Init(Shared, UI)
    local tabs = UI.tabs
    local createSection = UI.createSection
    local createToggle = UI.createToggle
    local createInput = UI.createInput

    local wSec = createSection(tabs["Webhook"], "Discord Notifications", 200)
    createToggle(wSec, "Unit Summoned Alert", "Sends alert when high-tier unit is summoned.", "UnitSummoned", 32)
    createToggle(wSec, "Stage Finished Alert", "Sends summary upon match completion.", "StageFinished", 72)
    createInput(wSec, "Webhook URL", "Paste Webhook URL...", "WebhookURL", 8, 112, 328)
end

return Webhook
