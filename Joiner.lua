--!strict
-- Joiner.lua - populates the Lobby/Joiner/Game/Auto Play/Misc tabs and runs
-- the auto-join + in-game automation loop, plus anti-AFK.

local Joiner = {}

function Joiner.Init(Shared, UI)
    local Config = Shared.Config
    local player = Shared.player
    local Lighting = Shared.Lighting

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
    -- Resolve optional Node actions safely. A failure here must NEVER prevent
    -- Joiner from creating its UI sections (which used to make every non-Macro
    -- tab appear empty).
    local RequestEnterMatchmaking = nil
    local RequestLeaveMatchmaking = nil
    local RequestAFKLeave = nil

    pcall(function()
        local nodesObject = Shared.ReplicatedStorage:FindFirstChild("Nodes")
        if nodesObject and nodesObject:IsA("ModuleScript") then
            local Nodes = require(nodesObject)
            RequestEnterMatchmaking = Nodes.REQUEST_ENTER_MATCHMAKING
            RequestLeaveMatchmaking = Nodes.REQUEST_LEAVE_MATCHMAKING
            RequestAFKLeave = Nodes.REQUEST_AFK_LEAVE
        end
    end)

    -- Direct NetworkEvent used by the game's matchmaking request.
    -- This avoids depending on the Map/Matchmaking UI components.
    local NetworkEvents = Shared.ReplicatedStorage
        :WaitForChild("Nodes")
        :WaitForChild("Network")
        :WaitForChild("NetworkEvents")
    local UpdateNode = NetworkEvents:WaitForChild("_updateNode")
    local matchmakingRequestId = 0

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

    -- Joiner state is tracked independently from WaveInfo. The game can have
    -- a CurrentGameState replica while still being in the lobby/matchmaking UI.
    local joinRequested = {
        Story = false,
        Raid = false,
        Expedition = false,
        Challenge = false,
    }

    local function remoteCooldown(configKey: string, seconds: number): boolean
        local now = os.clock()
        if now < (toggleTimestamps[configKey] or 0) then
            return false
        end
        toggleTimestamps[configKey] = now + seconds
        return true
    end

    Shared.logLine(("[Joiner] Defaults: %s / %s / %s | Matchmaking=%s"):format(
        tostring(Config.SelectedMap),
        tostring(Config.SelectedAct),
        tostring(Config.SelectedDifficulty),
        tostring(Config.StoryMatchMaking)
    ))

    local function getCurrentGameState(): string?
        local _, _, state = Shared.getWaveInfo()
        return type(state) == "string" and state or nil
    end

    local function prettifyName(value: string): string
        return value:gsub("(%u)", " %1"):gsub("^%s+", "")
    end

    local function resolveMapId(modeName: string, selectedName: string): string
        local compactSelected = selectedName:gsub("%s+", "")
        local ok, maps = pcall(function()
            return require(Shared.ReplicatedStorage.Shared.Information.Maps)
        end)

        if ok and type(maps) == "table" and type(maps.MapData) == "table"
            and type(maps.MapData[modeName]) == "table" then
            local modeData = maps.MapData[modeName]

            if modeData[selectedName] then
                return selectedName
            end

            if modeData[compactSelected] then
                return compactSelected
            end

            for mapId, mapInfo in pairs(modeData) do
                if type(mapId) == "string" then
                    if mapId:gsub("%s+", ""):lower() == compactSelected:lower() then
                        return mapId
                    end

                    if type(mapInfo) == "table" and type(mapInfo.DisplayName) == "string"
                        and mapInfo.DisplayName:lower() == selectedName:lower() then
                        return mapId
                    end

                    if prettifyName(mapId):lower() == selectedName:lower() then
                        return mapId
                    end
                end
            end
        end

        return compactSelected
    end

    local function buildQueueData(modeName: string)
        if modeName == "Story" then
            return {
                Difficulty = Config.SelectedDifficulty,
                MapName = StoryMapDisplayToId[Config.SelectedMap] or resolveMapId("Story", Config.SelectedMap),
                Gamemode = "Story",
                ActName = Config.SelectedAct,
            }
        elseif modeName == "Raid" then
            return {
                MapName = resolveMapId("Raid", Config.SelectedRaidMap),
                Gamemode = "Raid",
                ActName = Config.SelectedRaidAct,
            }
        elseif modeName == "Expedition" then
            return {
                Difficulty = Config.SelectedExpeditionDifficulty,
                MapName = resolveMapId("Expedition", Config.SelectedExpeditionMap),
                Gamemode = "Expedition",
            }
        elseif modeName == "Challenge" then
            return {
                Gamemode = "Challenge",
                ChallengeType = Config.SelectedChallengeType,
            }
        end

        return nil
    end

    local function enterMatchmakingRemotely(modeName: string, configKey: string)
        local queueData = buildQueueData(modeName)
        if not queueData or not RequestEnterMatchmaking then
            return false
        end

        if not remoteCooldown(configKey, 4) then
            return false
        end

        local ok, result = pcall(function()
            if modeName == "Story" then
                -- Reproduce the game's actual Story matchmaking request.
                -- The third argument is a client-side request sequence; using
                -- a fixed 1 can fail after the first request in a session.
                pcall(function()
                    RequestLeaveMatchmaking:Request()
                end)

                matchmakingRequestId += 1
                UpdateNode:FireServer(
                    {Type = "Post"},
                    "REQUEST_ENTER_MATCHMAKING_RequestNODE",
                    matchmakingRequestId,
                    queueData
                )
                return true
            end

            return RequestEnterMatchmaking:Request(queueData)
        end)

        if ok then
            Shared.logLine("[Matchmaking] " .. modeName .. " requested through NetworkEvent")
            if result ~= nil then
                Shared.logLine("[Matchmaking] Request sent")
            end
            return true
        end

        Shared.logLine("[Matchmaking] " .. modeName .. " request failed: " .. tostring(result))
        return false
    end

    local function startSelectedModeRemotely(modeName: string, configKey: string)
        local queueData = buildQueueData(modeName)
        if not queueData then
            return false
        end

        -- Do not create a second party while the first request is still being
        -- processed. The lobby state can remain nil for several seconds after
        -- PARTY_CREATE, so relying only on getCurrentGameState() can spam
        -- PARTY_CREATE requests.
        if joinRequested[modeName] then
            return false
        end

        if not remoteCooldown(configKey, 4) then
            return false
        end

        -- Select Stage is a two-phase server flow:
        --   1) PARTY_CREATE_RequestNODE creates the local party.
        --   2) The server creates a ReplicaSignal replica with a dynamic ID.
        --   3) StartGame is sent to THAT replica.
        --
        -- The important detail is that the ReplicaSet event can arrive
        -- immediately after PARTY_CREATE. Therefore the listeners MUST be
        -- installed BEFORE PARTY_CREATE is fired. The previous implementation
        -- installed them afterwards and could miss replica 23313 entirely.

        if modeName == "Story" then
            joinRequested[modeName] = true

            local replicaEvents = Shared.ReplicatedStorage:FindFirstChild("RemoteEvents")
            local replicaSet = replicaEvents and replicaEvents:FindFirstChild("ReplicaSet")
            local replicaCreate = replicaEvents and replicaEvents:FindFirstChild("ReplicaCreate")

            if not replicaSet then
                joinRequested[modeName] = false
                Shared.logLine("[Joiner] Story Select Stage -> ReplicaSet remote is missing")
                return false
            end

            local baselineIds = {}
            local candidateIds = {}
            local seenCandidates = {}
            local connections = {}

            -- Events received before PARTY_CREATE are baseline state. Events
            -- received after PARTY_CREATE are candidates for the new party.
            -- This distinction is critical: the previous version marked every
            -- ReplicaSet/ReplicaCreate event as baseline, so candidateIds could
            -- NEVER be populated.
            local partyCreateSent = false

            local function rememberBaseline(id)
                if type(id) == "number" then
                    baselineIds[id] = true
                end
            end

            local startGameSent = false

            local function rememberCandidate(id)
                if type(id) ~= "number" or id <= 0 or id > 1000000 then
                    return
                end

                if not seenCandidates[id] then
                    seenCandidates[id] = true
                    table.insert(candidateIds, id)
                end

                -- Match the game's exact Select Stage Start sequence:
                -- PARTY_CREATE_RequestNODE -> ReplicaSet(newReplicaId) ->
                -- ReplicaSignal:FireServer(newReplicaId, "StartGame")
                if partyCreateSent and not startGameSent then
                    startGameSent = true

                    local ok = pcall(function()
                        ReplicaSignal:FireServer(id, "StartGame")
                    end)

                    if ok then
                        Shared.logLine(
                            "[Joiner] Story Select Stage -> StartGame sent immediately to replica "
                                .. tostring(id)
                        )
                    else
                        Shared.logLine(
                            "[Joiner] Story Select Stage -> StartGame failed for replica "
                                .. tostring(id)
                        )
                        startGameSent = false
                    end
                end
            end

            local function inspectValue(value)
                local function inspectNumber(id)
                    if type(id) ~= "number" then
                        return
                    end

                    if partyCreateSent then
                        rememberCandidate(id)
                    else
                        rememberBaseline(id)
                    end
                end

                if type(value) == "number" then
                    inspectNumber(value)
                elseif type(value) == "table" then
                    for key, child in pairs(value) do
                        if type(key) == "string" then
                            local lower = key:lower()
                            if lower == "id"
                                or lower == "replicaid"
                                or lower == "replica_id"
                                or lower == "queueid" then
                                inspectNumber(child)
                            end
                        end
                    end
                end
            end

            -- Install listeners BEFORE PARTY_CREATE so a same-frame ReplicaSet
            -- cannot be missed.
            connections.set = replicaSet.OnClientEvent:Connect(function(replicaId, ...)
                -- ReplicaSet's first argument is the replica ID. The live
                -- capture showed e.g. 9382 | table | false.
                if partyCreateSent and type(replicaId) == "number" then
                    rememberCandidate(replicaId)
                    return
                end

                -- Keep baseline tracking for replicas that existed before the
                -- party was created.
                inspectValue(replicaId)
                for _, value in ipairs({...}) do
                    inspectValue(value)
                end
            end)

            if replicaCreate then
                connections.create = replicaCreate.OnClientEvent:Connect(function(...)
                    for _, value in ipairs({...}) do
                        inspectValue(value)
                    end
                end)
            end

            task.wait(0.15)

            -- From the live game capture:
            -- {Type="Post"}, "PARTY_CREATE_RequestNODE", requestId, queueData
            local createOk, createErr = pcall(function()
                -- Do not send REQUEST_LEAVE_MATCHMAKING here. The real
                -- Select Stage Start button goes straight to PARTY_CREATE.
                matchmakingRequestId += 1
                partyCreateSent = true
                UpdateNode:FireServer(
                    {Type = "Post"},
                    "PARTY_CREATE_RequestNODE",
                    matchmakingRequestId,
                    queueData
                )
            end)

            if not createOk then
                for _, connection in pairs(connections) do
                    pcall(function() connection:Disconnect() end)
                end
                joinRequested[modeName] = false
                Shared.logLine("[Joiner] Story PARTY_CREATE failed: " .. tostring(createErr))
                return false
            end

            Shared.logLine("[Joiner] Story Select Stage -> PARTY_CREATE sent; waiting for new replica")

            task.spawn(function()
                local deadline = os.clock() + 10

                -- Wait only for the replica created by this PARTY_CREATE.
                -- rememberCandidate() sends StartGame immediately when it sees it,
                -- matching the game's single Start button sequence.
                while os.clock() < deadline and not startGameSent do
                    task.wait(0.05)
                end

                for _, connection in pairs(connections) do
                    pcall(function() connection:Disconnect() end)
                end

                if not startGameSent then
                    Shared.logLine("[Joiner] Story Select Stage -> no new party replica was observed within 10s")
                    joinRequested[modeName] = false
                end
            end)

            return true
        end

        -- Other modes still use the shared implementation until their exact
        -- game-side request sequence is captured independently.
        local ok, result = pcall(function()
            return Shared.startGameRemotely(queueData)
        end)

        if not ok then
            Shared.logLine("[Joiner] " .. modeName .. " start failed: " .. tostring(result))
            return false
        end

        return result ~= false
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

        if Config.AutoReturnLobby and remoteCooldown("AutoReturnLobby", 10) then
            local ok, err = pcall(function()
                RequestAFKLeave:Fire()
            end)
            if ok then
                Shared.logLine("[GameRemote] Auto Return Lobby -> REQUEST_AFK_LEAVE")
            else
                Shared.logLine("[GameRemote] Auto Return Lobby failed: " .. tostring(err))
            end
        end
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

                local state = getCurrentGameState()

                -- Do not use WaveInfo as a lobby detector. It can exist before
                -- a match starts, which previously prevented Auto Join from firing.
                if state == "InProgress" then
                    joinRequested.Story = false
                    joinRequested.Raid = false
                    joinRequested.Expedition = false
                    joinRequested.Challenge = false
                    runRemoteGameAutomation()
                elseif not Config.DisableAutoJoiners then
                    if Config.AutoJoinStory and not joinRequested.Story then
                        -- Story has two distinct flows in the game's UI:
                        -- Matchmaking -> REQUEST_ENTER_MATCHMAKING
                        -- Select Stage -> create/use the local queue, then StartGame.
                        if Config.StoryMatchMaking then
                            if enterMatchmakingRemotely("Story", "AutoJoinStory") then
                                joinRequested.Story = true
                            end
                        else
                            -- Select Stage cannot be started by guessing a Replica ID.
                            -- Keep retrying until the game's queue replica exists.
                            if startSelectedModeRemotely("Story", "AutoJoinStory") then
                                joinRequested.Story = true
                            end
                        end
                    elseif Config.AutoJoinRaid and not joinRequested.Raid then
                        if Config.RaidMatchMaking then
                            if enterMatchmakingRemotely("Raid", "AutoJoinRaid") then
                                joinRequested.Raid = true
                            end
                        else
                            if startSelectedModeRemotely("Raid", "AutoJoinRaid") then
                                joinRequested.Raid = true
                            end
                        end
                    elseif Config.AutoJoinExpedition and not joinRequested.Expedition then
                        if Config.ExpeditionMatchMaking then
                            if enterMatchmakingRemotely("Expedition", "AutoJoinExpedition") then
                                joinRequested.Expedition = true
                            end
                        else
                            if startSelectedModeRemotely("Expedition", "AutoJoinExpedition") then
                                joinRequested.Expedition = true
                            end
                        end
                    elseif Config.AutoJoinChallenge and not joinRequested.Challenge then
                        if Config.ChallengeMatchMaking then
                            if enterMatchmakingRemotely("Challenge", "AutoJoinChallenge") then
                                joinRequested.Challenge = true
                            end
                        else
                            if startSelectedModeRemotely("Challenge", "AutoJoinChallenge") then
                                joinRequested.Challenge = true
                            end
                        end
                    end
                else
                    runRemoteGameAutomation()
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
