--!strict
-- Joiner.lua - populates the Lobby/Joiner/Game/Auto Play/Misc tabs and runs
-- the auto-join + in-game automation loop, plus anti-AFK.

local Joiner = {}

function Joiner.Init(Shared, UI)
    local Config = Shared.Config
    local playerGui = Shared.playerGui
    local player = Shared.player
    local Lighting = Shared.Lighting
    local isInLobby = Shared.isInLobby
    local getPrompt = Shared.getPrompt
    local clickElement = Shared.clickElement

    local tabs = UI.tabs
    local createSection = UI.createSection
    local createToggle = UI.createToggle
    local createDropdown = UI.createDropdown

    -------------------------------------------------
    -- Lobby Tab
    -------------------------------------------------
    local lobbySec = createSection(tabs["Lobby"], "Lobby Utilities", 80)
    createToggle(lobbySec, "Auto Redeem Codes", "Automatically claims active promo codes.", "AutoRedeemCodes", 32)

    -------------------------------------------------
    -- Joiner Tab
    -------------------------------------------------
    local joinerSec = createSection(tabs["Joiner"], "Queue Settings", 75)
    createToggle(joinerSec, "Matchmaking Queue", "Enables public match queues.", "MatchMaking", 32)

    local sjSec = createSection(tabs["Joiner"], "Story Joiner Configuration", 195)
    createToggle(sjSec, "Auto Join Story", "Queues into Story Mode using ReplicaSignal.", "AutoJoinStory", 32)
    createDropdown(sjSec, "Select Map", "Story map", StoryMaps, "SelectedMap", 8, 74, 210)
    createDropdown(sjSec, "Select Act", "Act selector", StoryActs, "SelectedAct", 226, 74, 110)
    createDropdown(sjSec, "Select Difficulty", "Normal or Hard", StoryDifficulties, "SelectedDifficulty", 8, 134, 328)

    local rSec = createSection(tabs["Joiner"], "Raid Joiner Configuration", 135)
    createToggle(rSec, "Auto Join Raid", "Queues into Raid Mode.", "AutoJoinRaid", 32)
    createDropdown(rSec, "Select Raid Map", "Raid map", {"Spirit City", "Wasteland Ruins"}, "SelectedRaidMap", 8, 74, 210)
    createDropdown(rSec, "Select Raid Act", "Raid Act", {"Act 1", "Act 2", "Act 3"}, "SelectedRaidAct", 226, 74, 110)

    -------------------------------------------------
    -- Game Tab
    -------------------------------------------------
    local gSec = createSection(tabs["Game"], "Gameplay Automation", 225)
    createToggle(gSec, "Auto Vote Start", "Instantly votes Yes when match begins.", "AutoVoteStart", 32)
    createToggle(gSec, "Auto Skip Wave", "Skips countdowns immediately.", "AutoSkipWave", 72)
    createToggle(gSec, "Auto Replay", "Instantly replays upon match end.", "AutoReplay", 112)
    createToggle(gSec, "Auto Next", "Advances to next stage upon victory.", "AutoNext", 152)
    createToggle(gSec, "Auto Return Lobby", "Returns directly to lobby.", "AutoReturnLobby", 192)

    -------------------------------------------------
    -- Auto Play Tab
    -------------------------------------------------
    createSection(tabs["Auto Play"], "Auto Play Settings", 40)

    -------------------------------------------------
    -- Misc Tab
    -------------------------------------------------
    local miscSec = createSection(tabs["Misc"], "Player Utilities", 110)
    createToggle(miscSec, "Walk Around", "Prevents AFK disconnections.", "WalkAround", 32)
    createToggle(miscSec, "Disable AFK Chamber", "Stops forced teleports.", "DisableAutoTeleportAFKChamber", 72)

    -------------------------------------------------
    -- AUTOMATION LOOP
    -------------------------------------------------
    local function triggerPrompt(modeName: string)
        local prompt = getPrompt(modeName)
        if prompt then
            pcall(function() fireproximityprompt(prompt) end)
            return true
        end
        return false
    end

    local toggleTimestamps = { AutoJoinStory = 0, AutoJoinRaid = 0, AutoJoinExpedition = 0, AutoJoinChallenge = 0 }

    local function queueStoryRemotely()
        local toggleTime = toggleTimestamps.AutoJoinStory or 0
        if tick() - toggleTime < 1.0 then
            return false
        end

        local selectedMapId = StoryMapDisplayToId[Config.SelectedMap] or Config.SelectedMap
        local selectedAct = Config.SelectedAct
        local selectedDifficulty = Config.SelectedDifficulty

        if type(selectedMapId) ~= "string" or selectedMapId == "" then
            return false
        end
        if type(selectedAct) ~= "string" or selectedAct == "" then
            return false
        end
        if type(selectedDifficulty) ~= "string" or selectedDifficulty == "" then
            return false
        end

        local ok = pcall(function()
            ReplicaSignal:FireServer(1062, "SetQueueData", {
                Difficulty = selectedDifficulty,
                MapName = selectedMapId,
                Gamemode = "Story",
                ActName = selectedAct,
            })
            task.wait(0.15)
            ReplicaSignal:FireServer(1062, "StartGame")
        end)

        if ok then
            Shared.logLine(("[StoryJoiner] Queued Story: %s | %s | %s"):format(
                selectedMapId,
                selectedAct,
                selectedDifficulty
            ))
            toggleTimestamps.AutoJoinStory = tick() + 3
            return true
        end

        return false
    end

    local function handleDirectAutomation(targetPromptName: string, mapName: string, actName: string, diffName: string?, configKey: string)
        local toggleTime = toggleTimestamps[configKey] or 0
        if tick() - toggleTime < 1.0 then return end

        local hub = playerGui:FindFirstChild("SolarHub")
        local foundMap, foundAct, foundDiff, foundStageBtn, foundQueueBtn = nil, nil, nil, nil, nil

        for _, descendant in ipairs(playerGui:GetDescendants()) do
            if hub and descendant:IsDescendantOf(hub) then continue end
            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                local text = descendant.Text:lower()
                if text ~= "" then
                    if text:find("start") or text:find("ready") or text:find("deploy") or text:find("select stage") then foundStageBtn = descendant end
                    if (Config.MatchMaking and (text:find("matchmaking") or text:find("enter matchmaking"))) or (not Config.MatchMaking and text:find("solo")) then foundQueueBtn = descendant end
                    if text:find(mapName:lower()) then foundMap = descendant end
                    if actName ~= "" and text:find(actName:lower()) then foundAct = descendant end
                    if diffName and diffName ~= "" and (text:find(diffName:lower()) or text:find(diffName:gsub("difficulty ", ""):lower())) then foundDiff = descendant end
                end
            end
        end

        if foundQueueBtn then clickElement(foundQueueBtn) return end
        if foundStageBtn then clickElement(foundStageBtn) return end
        if foundMap then
            clickElement(foundMap)
            task.wait()
            if foundAct then clickElement(foundAct) end
            if foundDiff then clickElement(foundDiff) end
            return
        end
        triggerPrompt(targetPromptName)
    end

    task.spawn(function()
        while true do
            task.wait(0.4)
            pcall(function()
                if Config.DeleteMap then
                    for _, obj in ipairs(workspace:GetChildren()) do
                        if obj.Name == "Map" or obj.Name == "Environment" or obj.Name == "Decorations" then obj:Destroy() end
                    end
                end
                if Config.BoostFPS then
                    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
                    Lighting.GlobalShadows = false
                end

                local inLobbyNow = isInLobby()
                local hub = playerGui:FindFirstChild("SolarHub")

                if inLobbyNow then
                    if not Config.DisableAutoJoiners then
                        if Config.AutoJoinStory then
                            queueStoryRemotely()
                        elseif Config.AutoJoinRaid then handleDirectAutomation("Raid", Config.SelectedRaidMap, Config.SelectedRaidAct, nil, "AutoJoinRaid")
                        elseif Config.AutoJoinExpedition then handleDirectAutomation("Expedition", Config.SelectedExpeditionMap, "", Config.SelectedExpeditionDifficulty, "AutoJoinExpedition")
                        elseif Config.AutoJoinChallenge then handleDirectAutomation("Challenge", Config.SelectedChallengeType, "Enter", nil, "AutoJoinChallenge")
                        end
                    end
                else
                    local needsScan = Config.PlayMacro or Config.AutoVoteStart or Config.AutoSkipWave
                        or Config.AutoReplay or Config.AutoNext or Config.AutoReturnLobby

                    if needsScan then
                        for _, descendant in ipairs(playerGui:GetDescendants()) do
                            if hub and descendant:IsDescendantOf(hub) then continue end
                            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                                local text = descendant.Text:lower()
                                if text ~= "" then
                                    if Config.PlayMacro and (text:find("start") or text:find("ready") or text:find("deploy") or text:find("select stage")) then
                                        clickElement(descendant)
                                    end

                                    if Config.AutoVoteStart and (text:find("vote") or text:find("start match") or text:find("yes")) then
                                        clickElement(descendant)
                                        task.wait(2)
                                    elseif Config.AutoSkipWave and (text:find("skip") or text:find("skip wave")) then
                                        clickElement(descendant)
                                        task.wait(2)
                                    elseif Config.AutoReplay and (text:find("replay") or text:find("repeat") or text:find("restart") or text:find("play again") or text:find("retry")) then
                                        clickElement(descendant)
                                        task.wait(5)
                                    elseif Config.AutoNext and (text:find("next") or text:find("next stage") or text:find("next act")) then
                                        clickElement(descendant)
                                        task.wait(5)
                                    elseif Config.AutoReturnLobby and (text:find("lobby") or text:find("home") or text:find("main menu")) then
                                        clickElement(descendant)
                                        task.wait(5)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end)

    -------------------------------------------------
    -- ANTI-AFK INITIALIZATION
    -------------------------------------------------
    player.Idled:Connect(function()
        pcall(function()
            game:GetService("VirtualUser"):Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            game:GetService("VirtualUser"):Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end)
    end)
end

return Joiner
