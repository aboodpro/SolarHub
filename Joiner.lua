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
    -- DATA / REMOTES
    -------------------------------------------------
    local ReplicaSignal = Shared.ReplicatedStorage
        :WaitForChild("RemoteEvents")
        :WaitForChild("ReplicaSignal")

    -- Official game Network Nodes used by the game's own actions.
    -- Story matchmaking: REQUEST_ENTER_MATCHMAKING
    -- Return lobby: REQUEST_AFK_LEAVE
    local Nodes = require(Shared.ReplicatedStorage:WaitForChild("Nodes"))
    local RequestEnterMatchmaking = Nodes.REQUEST_ENTER_MATCHMAKING
    local RequestLeaveMatchmaking = Nodes.REQUEST_LEAVE_MATCHMAKING
    local RequestAFKLeave = Nodes.REQUEST_AFK_LEAVE

    local StoryMaps = {}
    local StoryMapDisplayToId = {}
    local StoryActs = {}
    local StoryDifficulties = {}

    local function addUnique(list: {string}, value: string)
        if value == "" then
            return
        end

        for _, existing in ipairs(list) do
            if existing == value then
                return
            end
        end

        table.insert(list, value)
    end

    local function sortActs(a: string, b: string): boolean
        local an = tonumber(a:match("%d+")) or math.huge
        local bn = tonumber(b:match("%d+")) or math.huge

        if an == bn then
            return a < b
        end

        return an < bn
    end

    local function sortDifficulties(a: string, b: string): boolean
        local order = {
            Normal = 1,
            Hard = 2,
        }

        local ao = order[a] or 100
        local bo = order[b] or 100

        if ao == bo then
            return a < b
        end

        return ao < bo
    end

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

    -- Read Story data directly from the game's own data path.
    -- New Story maps/acts/difficulties automatically appear here without
    -- needing a manual edit to SolarHub.
    pcall(function()
        local maps = require(Shared.ReplicatedStorage.Shared.Information.Maps)
        local storyData = maps and maps.MapData and maps.MapData.Story

        if type(storyData) == "table" then
            local orderedMaps = {}

            for mapName, mapInfo in pairs(storyData) do
                if type(mapName) == "string" then
                    local displayName = prettifyStoryMap(mapName)

                    table.insert(orderedMaps, {
                        Id = mapName,
                        DisplayName = displayName,
                        ProgressionIndex = (type(mapInfo) == "table" and tonumber(mapInfo.ProgressionIndex)) or math.huge,
                        Info = mapInfo,
                    })

                    StoryMapDisplayToId[displayName] = mapName

                    if type(mapInfo) == "table" then
                        local acts = mapInfo.Acts
                        if type(acts) == "table" then
                            for actName, actInfo in pairs(acts) do
                                if type(actName) == "string" then
                                    addUnique(StoryActs, actName)
                                elseif type(actInfo) == "table" and type(actInfo.Name) == "string" then
                                    addUnique(StoryActs, actInfo.Name)
                                end
                            end
                        end

                        local difficulties = mapInfo.Difficulties
                        if type(difficulties) == "table" then
                            for _, difficulty in pairs(difficulties) do
                                if type(difficulty) == "string" then
                                    addUnique(StoryDifficulties, difficulty)
                                end
                            end

                            for difficultyName, difficultyValue in pairs(difficulties) do
                                if type(difficultyName) == "string" then
                                    addUnique(StoryDifficulties, difficultyName)
                                elseif type(difficultyValue) == "table" and type(difficultyValue.Name) == "string" then
                                    addUnique(StoryDifficulties, difficultyValue.Name)
                                end
                            end
                        end
                    end
                end
            end

            table.sort(orderedMaps, function(a, b)
                if a.ProgressionIndex == b.ProgressionIndex then
                    return a.Id < b.Id
                end
                return a.ProgressionIndex < b.ProgressionIndex
            end)

            for _, entry in ipairs(orderedMaps) do
                table.insert(StoryMaps, entry.DisplayName)
            end
        end
    end)

    table.sort(StoryActs, sortActs)
    table.sort(StoryDifficulties, sortDifficulties)

    -- Only used if the game's data module is unavailable.
    if #StoryMaps == 0 then
        StoryMaps = {"School Grounds"}
        StoryMapDisplayToId["School Grounds"] = "SchoolGrounds"
    end

    if #StoryActs == 0 then
        StoryActs = {"Act 1"}
    end

    if #StoryDifficulties == 0 then
        StoryDifficulties = {"Normal"}
    end

    -- Lobby Tab
    -------------------------------------------------
    local lobbySec = createSection(tabs["Lobby"], "Lobby Utilities", 80)
    createToggle(lobbySec, "Auto Redeem Codes", "Automatically claims active promo codes.", "AutoRedeemCodes", 32)

    -------------------------------------------------
    -- Joiner Tab
    -------------------------------------------------
    local sjSec = createSection(tabs["Joiner"], "Story Joiner Configuration", 235)
    createToggle(sjSec, "Auto Join Story", "Automatically enters the selected Story stage.", "AutoJoinStory", 32)
    createDropdown(sjSec, "Select Map", "Story map", StoryMaps, "SelectedMap", 8, 74, 210)
    createDropdown(sjSec, "Select Act", "Act selector", StoryActs, "SelectedAct", 226, 74, 110)
    createDropdown(sjSec, "Select Difficulty", "Normal or Hard", StoryDifficulties, "SelectedDifficulty", 8, 134, 328)
    createToggle(sjSec, "Matchmaking", "Use public matchmaking instead of joining solo.", "StoryMatchMaking", 194)

    local rSec = createSection(tabs["Joiner"], "Raid Joiner Configuration", 175)
    createToggle(rSec, "Auto Join Raid", "Automatically enters the selected Raid stage.", "AutoJoinRaid", 32)
    createDropdown(rSec, "Select Raid Map", "Raid map", {"Spirit City", "Hill Of Swords"}, "SelectedRaidMap", 8, 74, 210)
    createDropdown(rSec, "Select Raid Act", "Raid Act", {"Act 1", "Act 2", "Act 3"}, "SelectedRaidAct", 226, 74, 110)
    createToggle(rSec, "Matchmaking", "Use public matchmaking instead of joining solo.", "RaidMatchMaking", 134)

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
                returnToLobbyRemotely()
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

        local queueData = {
            Difficulty = selectedDifficulty,
            MapName = selectedMapId,
            Gamemode = "Story",
            ActName = selectedAct,
        }

        -- This is the same Matchmaking Node path used by the game's
        -- StartMatchmaking action. RemoteSpy confirmed that the Node
        -- ultimately posts to:
        -- ReplicatedStorage.Nodes.Network.NetworkEvents._updateNode
        local ok, requestNode = pcall(function()
            return RequestEnterMatchmaking:Request(queueData)
        end)

        if ok then
            Shared.logLine(("[StoryJoiner] Matchmaking request sent: %s | %s | %s"):format(
                selectedMapId,
                selectedAct,
                selectedDifficulty
            ))
            if requestNode ~= nil then
                Shared.logLine("[StoryJoiner] REQUEST_ENTER_MATCHMAKING request node created")
            end
            toggleTimestamps.AutoJoinStory = tick() + 3
            return true
        end

        Shared.logLine("[StoryJoiner] Matchmaking request failed: " .. tostring(requestNode))
        return false
    end

    local function returnToLobbyRemotely()
        if not RequestAFKLeave then
            return false
        end

        local ok, err = pcall(function()
            RequestAFKLeave:Fire()
        end)

        if ok then
            Shared.logLine("[GameRemote] Auto Return Lobby -> REQUEST_AFK_LEAVE")
            return true
        end

        Shared.logLine("[GameRemote] Auto Return Lobby failed: " .. tostring(err))
        return false
    end

    local function handleDirectAutomation(targetPromptName: string, mapName: string, actName: string, diffName: string?, configKey: string, matchmaking: boolean)
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
                    if (matchmaking and (text:find("matchmaking") or text:find("enter matchmaking"))) or ((not matchmaking) and (text:find("solo") or text:find("private") or text:find("start"))) then foundQueueBtn = descendant end
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
                            if Config.StoryMatchMaking then
                                queueStoryRemotely()
                            else
                                handleDirectAutomation("Story", Config.SelectedMap, Config.SelectedAct, Config.SelectedDifficulty, "AutoJoinStory", false)
                            end
                        elseif Config.AutoJoinRaid then
                            handleDirectAutomation("Raid", Config.SelectedRaidMap, Config.SelectedRaidAct, nil, "AutoJoinRaid", Config.RaidMatchMaking)
                        elseif Config.AutoJoinExpedition then
                            handleDirectAutomation("Expedition", Config.SelectedExpeditionMap, "", Config.SelectedExpeditionDifficulty, "AutoJoinExpedition", Config.ExpeditionMatchMaking)
                        elseif Config.AutoJoinChallenge then
                            handleDirectAutomation("Challenge", Config.SelectedChallengeType, "Enter", nil, "AutoJoinChallenge", Config.ChallengeMatchMaking)
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
