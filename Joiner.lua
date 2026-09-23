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
    -------------------------------------------------
    -- DATA / REMOTES
    -------------------------------------------------
    local ReplicaSignal = Shared.ReplicatedStorage
        :WaitForChild("RemoteEvents")
        :WaitForChild("ReplicaSignal")

    local StoryMaps = {}
    local StoryMapDisplayToId = {}
    local StoryActs = {"Act 1", "Act 2", "Act 3", "Act 4", "Act 5"}
    local StoryDifficulties = {"Normal", "Hard"}

    local function prettifyStoryMap(mapName: string): string
        local ok, maps = pcall(function()
            return require(Shared.ReplicatedStorage.Shared.Information.Maps)
        end)

        if ok and maps and maps.PreviewInfo and maps.PreviewInfo[mapName] then
            local displayName = maps.PreviewInfo[mapName].DisplayName
            if type(displayName) == "string" and displayName ~= "" then
                return displayName
            end
        end

        local pretty = mapName:gsub("(%u)", " %1"):gsub("^%s+", "")
        return pretty
    end

    pcall(function()
        local maps = require(Shared.ReplicatedStorage.Shared.Information.Maps)
        if maps.MapData and maps.MapData.Story then
            for mapName in pairs(maps.MapData.Story) do
                local displayName = prettifyStoryMap(mapName)
                table.insert(StoryMaps, displayName)
                StoryMapDisplayToId[displayName] = mapName
            end
        end
    end)

    table.sort(StoryMaps)

    if #StoryMaps == 0 then
        StoryMaps = {"School Grounds"}
        StoryMapDisplayToId["School Grounds"] = "SchoolGrounds"
    end

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

    local toggleTimestamps = {
        AutoJoinStory = 0,
        AutoJoinRaid = 0,
        AutoJoinExpedition = 0,
        AutoJoinChallenge = 0,
        AutoVoteStart = 0,
        AutoSkipWave = 0,
        AutoReplay = 0,
        AutoNext = 0,
        AutoReturnLobby = 0,
    }

    local function remoteCooldown(configKey: string, seconds: number): boolean
        local now = os.clock()
        if now < (toggleTimestamps[configKey] or 0) then
            return false
        end
        toggleTimestamps[configKey] = now + seconds
        return true
    end

    local function getCurrentGameState(): string?
        local _, _, state = Shared.getWaveInfo()
        if type(state) == "string" then
            return state
        end
        return nil
    end

    local function runRemoteGameAutomation()
        if Config.AutoVoteStart and remoteCooldown("AutoVoteStart", 3) then
            pcall(function()
                ReplicaSignal:FireServer(87, "Response", true)
            end)
            Shared.logLine("[GameRemote] Auto Vote Start -> 87 Response true")
        end

        if Config.AutoSkipWave and remoteCooldown("AutoSkipWave", 2) then
            pcall(function()
                ReplicaSignal:FireServer(215, "Response", true)
            end)
            Shared.logLine("[GameRemote] Auto Skip -> 215 Response true")
        end

        local state = getCurrentGameState()

        if Config.AutoReplay and state and state ~= "InProgress" then
            if remoteCooldown("AutoReplay", 6) then
                pcall(function()
                    ReplicaSignal:FireServer(77, "Restart")
                end)
                Shared.logLine(("[GameRemote] Auto Replay/Restart -> 77 Restart (state=%s)"):format(state))
            end
        elseif Config.AutoNext and state and state ~= "InProgress" then
            if remoteCooldown("AutoNext", 6) then
                pcall(function()
                    ReplicaSignal:FireServer(77, "Next")
                end)
                Shared.logLine(("[GameRemote] Auto Next -> 77 Next (state=%s)"):format(state))
            end
        end

        if Config.AutoReturnLobby then
            if remoteCooldown("AutoReturnLobby", 10) then
                Shared.logLine("[GameRemote] Auto Return Lobby pending: remote not discovered yet")
            end
        end
    end

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
                    runRemoteGameAutomation()

                    -- Macro playback has its own remote-based action path.
                    -- Keep the small UI helper only for the initial "ready/start" action.
                    if Config.PlayMacro then
                        local hub = playerGui:FindFirstChild("SolarHub")
                        for _, descendant in ipairs(playerGui:GetDescendants()) do
                            if hub and descendant:IsDescendantOf(hub) then
                                continue
                            end
                            if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                                local text = descendant.Text:lower()
                                if text ~= "" and (
                                    text:find("start")
                                    or text:find("ready")
                                    or text:find("deploy")
                                    or text:find("select stage")
                                ) then
                                    clickElement(descendant)
                                    break
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
