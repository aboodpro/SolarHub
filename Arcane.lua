--!strict
local Arcane = {}

-------------------------------------------------
-- ARCANE ODYSSEY BOSS DATABASE
-------------------------------------------------

local BOSS_NAMES = {
    -- Bronze Sea / story
    "Shura",
    "Iris",
    "Lord Elius",
    "General Argos",
    "Lady Carina",
    "King Calvus",
    "King Calvus IV",

    -- Nimbus / story
    "Prince Revon",
    "Captain Maria",
    "Prince Allanon",
    "Allanon",
    "Jarl Ivar",

    -- Side bosses
    "Cernyx",
    "Jorund",
    "Ormolu",
    "Hallbjorn",
    "King Caesar",

    -- Sea / other boss encounters
    "Leviathan",
    "Kraken",
    "Commodore Kai",
    "Architect Merlot",
    "Alpha",
    "Rear Admiral Amelia",
    "General Valerii",
}

local function normalizeName(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local NORMALIZED_BOSSES = {}

for _, name in ipairs(BOSS_NAMES) do
    NORMALIZED_BOSSES[normalizeName(name)] = name
end

-- Known Mini Boss names seen in Arcane's SpawningEnemies definitions.
local MINIBOSS_NAMES = {
    "Evander",
    "Dusk",
    "Delamere",
    "The Crone",
    "Laelus",
    "Maine",
    "The One Beyond Reach",
    "Vatnulf",
    "Veyne",
    "Harzog",
    "Crowe",
    "Lysara",
    "Harjvindr",
}

local NORMALIZED_MINIBOSSES = {}

for _, name in ipairs(MINIBOSS_NAMES) do
    NORMALIZED_MINIBOSSES[normalizeName(name)] = name
end

-------------------------------------------------
-- ARCANE BOSS TEMPLATE REGISTRY
-------------------------------------------------
-- Arcane Odyssey exposes enemy templates under:
-- ReplicatedStorage.RS.Objects.SpawningEnemies
-- Boss templates contain a BoolValue named "Boss".
-- This lets the ESP discover bosses without a hardcoded name list.

local BOSS_TEMPLATE_NAMES = {}
local MINIBOSS_TEMPLATE_NAMES = {}

local function refreshBossTemplateRegistry()
    table.clear(BOSS_TEMPLATE_NAMES)
    table.clear(MINIBOSS_TEMPLATE_NAMES)

    local replicatedStorage = game:GetService("ReplicatedStorage")
    local rs = replicatedStorage:FindFirstChild("RS")
    local objects = rs and rs:FindFirstChild("Objects")
    local spawningEnemies = objects and objects:FindFirstChild("SpawningEnemies")

    if not spawningEnemies then
        return 0, 0
    end

    for _, child in ipairs(spawningEnemies:GetChildren()) do
        local normalized = normalizeName(child.Name)

        -- The presence of these BoolValues is the game's template classification.
        -- Do not require Value == true: some replicated templates expose the marker
        -- while keeping its runtime value false.
        local bossValue = child:FindFirstChild("Boss")
        local minibossValue = child:FindFirstChild("Miniboss")

        if bossValue and bossValue:IsA("BoolValue") then
            BOSS_TEMPLATE_NAMES[normalized] = child.Name
        end

        if minibossValue and minibossValue:IsA("BoolValue") then
            MINIBOSS_TEMPLATE_NAMES[normalized] = child.Name
        end
    end

    local bossCount = 0
    local minibossCount = 0

    for _ in pairs(BOSS_TEMPLATE_NAMES) do
        bossCount += 1
    end

    for _ in pairs(MINIBOSS_TEMPLATE_NAMES) do
        minibossCount += 1
    end

    return bossCount, minibossCount
end

local function getTemplateBossName(value)
    local normalized = normalizeName(value)

    if normalized == "" then
        return nil, nil
    end

    local bossName = BOSS_TEMPLATE_NAMES[normalized]
    if bossName then
        return bossName, "BossTemplate"
    end

    local minibossName = MINIBOSS_TEMPLATE_NAMES[normalized]
    if minibossName then
        return minibossName, "MinibossTemplate"
    end

    return nil, nil
end

refreshBossTemplateRegistry()

local function isBossTemplateName(value)
    local normalized = normalizeName(value)
    return BOSS_TEMPLATE_NAMES[normalized] ~= nil
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getRoot(model)
    if not model:IsA("Model") then
        return nil
    end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("Head")
end

local function findBossNameFromValue(value)
    local normalized = normalizeName(value)

    if normalized == "" then
        return nil
    end

    for key, displayName in pairs(NORMALIZED_BOSSES) do
        if normalized == key or normalized:find(key, 1, true) then
            return displayName
        end
    end

    return nil
end

local hasBossMarker

local function getBossDisplayName(model)
    local templateName, templateType = getTemplateBossName(model.Name)
    if templateName then
        return templateName, templateType
    end

    local normalizedModelName = normalizeName(model.Name)

    local knownBoss = NORMALIZED_BOSSES[normalizedModelName]
    if knownBoss then
        return knownBoss, "KnownName"
    end

    local knownMini = NORMALIZED_MINIBOSSES[normalizedModelName]
    if knownMini then
        return knownMini, "KnownMiniboss"
    end

    local byName = findBossNameFromValue(model.Name)
    if byName then
        return byName, "KnownName"
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local byHumanoidDisplayName = findBossNameFromValue(humanoid.DisplayName)
        if byHumanoidDisplayName then
            return byHumanoidDisplayName, "HumanoidDisplayName"
        end
    end

    for _, attributeName in ipairs({
        "BossName",
        "DisplayName",
        "Title",
        "NPCName",
    }) do
        local value = model:GetAttribute(attributeName)
        local match = findBossNameFromValue(value)
        if match then
            return match, "Attribute"
        end
    end

    return nil, nil
end

local function getBossClass(model)
    local templateName, templateType = getTemplateBossName(model.Name)

    if templateName then
        if templateType == "MinibossTemplate" then
            return "MINI BOSS"
        end

        return "BOSS"
    end

    local normalized = normalizeName(model.Name)

    if NORMALIZED_MINIBOSSES[normalized] then
        return "MINI BOSS"
    end

    if NORMALIZED_BOSSES[normalized] then
        return "BOSS"
    end

    local bossMarker = hasBossMarker(model)
    if bossMarker then
        return "BOSS"
    end

    return nil
end
local function hasBossTag(model)
    local CollectionService = game:GetService("CollectionService")

    local ok, tags = pcall(function()
        return CollectionService:GetTags(model)
    end)

    if not ok or type(tags) ~= "table" then
        return false
    end

    for _, tag in ipairs(tags) do
        local normalized = normalizeName(tag)

        if normalized == "boss"
            or normalized == "bossnpc"
            or normalized == "bossmodel"
            or normalized:find("boss", 1, true) then

            return true
        end
    end

    return false
end

hasBossMarker = function(model)
    for _, attributeName in ipairs({
        "Boss",
        "IsBoss",
        "BossType",
        "IsBossNPC",
    }) do
        local value = model:GetAttribute(attributeName)

        if value == true then
            return true
        end

        if type(value) == "string" and value:lower():find("boss", 1, true) then
            return true
        end
    end

    if hasBossTag(model) then
        return true
    end

    local parent = model.Parent

    while parent and parent ~= workspace do
        if parent:IsA("Folder") then
            local parentName = normalizeName(parent.Name)

            if parentName == "bosses"
                or parentName == "boss"
                or parentName:find("boss", 1, true) then

                return true
            end
        end

        parent = parent.Parent
    end

    return false
end

local function getBossInfo(model)
    if not model:IsA("Model") then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil
    end

    local root = getRoot(model)
    if not root then
        return nil
    end

    local bossName, detectionType = getBossDisplayName(model)
    local bossClass = getBossClass(model)
    local bossMarker = hasBossMarker(model)

    if not bossName and not bossMarker then
        return nil
    end

    return {
        name = bossName or model.Name,
        humanoid = humanoid,
        root = root,
        bossClass = bossClass or "BOSS",
        detectionType = detectionType or (bossMarker and "Marker" or "Unknown"),
    }
end


-------------------------------------------------
-- ARCANE CHEST TYPES / FILTER REGISTRY
-------------------------------------------------

local CHEST_TYPE_ORDER = {
    "COMMON",
    "UNCOMMON",
    "RARE",
    "MYSTIC",
    "LEGENDARY",
    "PRIVATE_STORAGE",
    "SKY",
    "STEEL",
    "BRONZE_SEALED",
    "NIMBUS_SEALED",
    "DARK_SEALED",
    "OTHER",
}

local CHEST_DISPLAY_NAMES = {
    COMMON = "Common Chest",
    UNCOMMON = "Uncommon Chest",
    RARE = "Rare Chest",
    MYSTIC = "Mystic Chest",
    LEGENDARY = "Legendary Chest",
    PRIVATE_STORAGE = "Private Storage Chest",
    SKY = "Sky Chest",
    STEEL = "Steel Chest",
    BRONZE_SEALED = "Bronze Sealed Chest",
    NIMBUS_SEALED = "Nimbus Sealed Chest",
    DARK_SEALED = "Dark Sealed Chest",
    OTHER = "Other Chest",
}

local CHEST_COLORS = {
    COMMON = Color3.fromRGB(175, 175, 185),
    UNCOMMON = Color3.fromRGB(255, 220, 70),
    RARE = Color3.fromRGB(70, 150, 255),
    MYSTIC = Color3.fromRGB(255, 70, 70),
    LEGENDARY = Color3.fromRGB(70, 220, 105),
    PRIVATE_STORAGE = Color3.fromRGB(175, 175, 185),
    SKY = Color3.fromRGB(175, 175, 185),
    STEEL = Color3.fromRGB(175, 175, 185),
    BRONZE_SEALED = Color3.fromRGB(175, 175, 185),
    NIMBUS_SEALED = Color3.fromRGB(175, 175, 185),
    DARK_SEALED = Color3.fromRGB(175, 175, 185),
    OTHER = Color3.fromRGB(175, 175, 185),
}

local function normalizeChestText(value)
    return tostring(value or ""):lower():gsub("[^%w]+", "")
end

local function classifyChestText(value)
    local text = normalizeChestText(value)

    if text == "" then
        return nil
    end

    if text:find("darksealed", 1, true) then
        return "DARK_SEALED"
    end

    if text:find("nimbussealed", 1, true) then
        return "NIMBUS_SEALED"
    end

    if text:find("bronze", 1, true) and text:find("sealed", 1, true) then
        return "BRONZE_SEALED"
    end

    if text:find("privatestorage", 1, true) then
        return "PRIVATE_STORAGE"
    end

    if text:find("sky", 1, true) and text:find("chest", 1, true) then
        return "SKY"
    end

    if text:find("steel", 1, true) and text:find("chest", 1, true) then
        return "STEEL"
    end

    if text:find("legendary", 1, true) then
        return "LEGENDARY"
    end

    if text:find("mystic", 1, true) then
        return "MYSTIC"
    end

    if text:find("rare", 1, true) then
        return "RARE"
    end

    if text:find("uncommon", 1, true)
        or text:find("silver", 1, true) then
        return "UNCOMMON"
    end

    if text:find("common", 1, true)
        and not text:find("uncommon", 1, true) then
        return "COMMON"
    end

    if (text:find("gold", 1, true) or text:find("golden", 1, true))
        and text:find("chest", 1, true) then
        return "RARE"
    end

    return nil
end

local function collectChestTextSources(target)
    local sources = {}

    if not target then
        return sources
    end

    table.insert(sources, target.Name)

    local function addValue(value)
        local valueType = typeof(value)

        if valueType == "string"
            or valueType == "number"
            or valueType == "boolean" then
            table.insert(sources, tostring(value))
        end
    end

    local model = target:IsA("Model")
        and target
        or target:FindFirstAncestorOfClass("Model")

    if model then
        local okAttrs, attrs = pcall(function()
            return model:GetAttributes()
        end)

        if okAttrs and type(attrs) == "table" then
            for key, value in pairs(attrs) do
                table.insert(sources, tostring(key))
                addValue(value)
            end
        end

        for _, child in ipairs(model:GetDescendants()) do
            if child:IsA("StringValue")
                or child:IsA("IntValue")
                or child:IsA("NumberValue") then
                table.insert(sources, child.Name)
                addValue(child.Value)
            elseif child:IsA("ProximityPrompt") then
                table.insert(sources, child.Name)
                addValue(child.ActionText)
                addValue(child.ObjectText)
            end
        end
    end

    return sources
end

local function getChestType(target)
    if not target or not target.Parent then
        return nil
    end

    for _, source in ipairs(collectChestTextSources(target)) do
        local chestType = classifyChestText(source)

        if chestType then
            return chestType
        end
    end

    return "OTHER"
end

local function isChestFilterEnabled(Config, chestType)
    local filter = Config.ArcaneChestFilter

    if type(filter) ~= "table" then
        return true
    end

    return filter[chestType] == true
end

local function looksLikeChestModel(model)
    if not model or not model:IsA("Model") then
        return false
    end

    local normalized = normalizeName(model.Name)

    if normalized:find("chest", 1, true)
        or normalized:find("treasure", 1, true)
        or normalized:find("sealed", 1, true) then
        return true
    end

    local collectionService = game:GetService("CollectionService")
    local okTags, tags = pcall(function()
        return collectionService:GetTags(model)
    end)

    if okTags and type(tags) == "table" then
        for _, tag in ipairs(tags) do
            local tagName = normalizeName(tag)

            if tagName:find("chest", 1, true)
                or tagName:find("treasure", 1, true) then
                return true
            end
        end
    end

    for _, child in ipairs(model:GetChildren()) do
        local childName = normalizeName(child.Name)

        if childName == "chest"
            or childName == "chestmodel"
            or childName == "treasurechest"
            or childName == "sealedchest" then
            return true
        end

        if child:IsA("ProximityPrompt") then
            local promptText = normalizeChestText(child.ObjectText)

            if promptText:find("chest", 1, true)
                or promptText:find("treasure", 1, true) then
                return true
            end
        end
    end

    return false
end

local function getChestTarget(object)
    if not object or not object.Parent then
        return nil
    end

    local model = object:IsA("Model")
        and object
        or object:FindFirstAncestorOfClass("Model")

    if model and looksLikeChestModel(model) then
        return model
    end

    if object:IsA("BasePart") then
        local normalized = normalizeName(object.Name)

        if normalized:find("chest", 1, true)
            or normalized:find("treasure", 1, true)
            or normalized:find("sealedchest", 1, true) then
            return object
        end
    end

    return nil
end

local function getChestRoot(target)
    if target:IsA("Model") then
        return getRoot(target)
    end

    if target:IsA("BasePart") then
        return target
    end

    return nil
end


-------------------------------------------------
-- DEBUG SCANNER
-------------------------------------------------

local DEBUG_KEYWORDS = {
    "boss",
    "enemy",
    "npc",
    "mob",
    "elite",
    "miniboss",
    "spawn",
    "ai",
    "health",
}

local function containsKeyword(value)
    local normalized = normalizeName(value)

    for _, keyword in ipairs(DEBUG_KEYWORDS) do
        if normalized:find(keyword, 1, true) then
            return keyword
        end
    end

    return nil
end

local function getAttributeSummary(instance)
    local ok, attributes = pcall(function()
        return instance:GetAttributes()
    end)

    if not ok or type(attributes) ~= "table" then
        return ""
    end

    local parts = {}

    for key, value in pairs(attributes) do
        local keyLower = tostring(key):lower()

        if keyLower:find("boss", 1, true)
            or keyLower:find("name", 1, true)
            or keyLower:find("type", 1, true)
            or keyLower:find("enemy", 1, true)
            or keyLower:find("npc", 1, true) then

            table.insert(parts, ("%s=%s"):format(
                tostring(key),
                tostring(value)
            ))
        end
    end

    table.sort(parts)

    return table.concat(parts, ", ")
end

local function appendLimited(list, value, limit)
    if #list < limit then
        table.insert(list, value)
        return true
    end

    return false
end

local function runDebugScan(setText)
    task.spawn(function()
        setText("Scanning Arcane client objects...\nThis is a one-time scan.")

        local results = {
            knownBosses = {},
            bossMarkers = {},
            suspiciousModels = {},
            highHpModels = {},
            bossFolders = {},
            scripts = {},
            remotes = {},
            humanoidCount = 0,
            modelCount = 0,
            scannedCount = 0,
        }

        local seenKnown = {}
        local seenMarker = {}
        local seenSuspicious = {}
        local seenHighHp = {}

        local containers = {
            workspace,
            game:GetService("ReplicatedStorage"),
            game:GetService("ReplicatedFirst"),
        }

        for _, container in ipairs(containers) do
            local descendants = container:GetDescendants()

            for _, instance in ipairs(descendants) do
                results.scannedCount += 1

                if instance:IsA("Model") then
                    results.modelCount += 1

                    local humanoid = instance:FindFirstChildOfClass("Humanoid")

                    if humanoid then
                        results.humanoidCount += 1

                        local info = getBossInfo(instance)

                        if info and not seenKnown[instance] then
                            seenKnown[instance] = true

                            appendLimited(
                                results.knownBosses,
                                ("%s | HP %d/%d | %s"):format(
                                    tostring(info.name),
                                    math.floor(humanoid.Health),
                                    math.floor(humanoid.MaxHealth),
                                    instance:GetFullName()
                                ),
                                100
                            )
                        end

                        if hasBossMarker(instance) and not seenMarker[instance] then
                            seenMarker[instance] = true

                            appendLimited(
                                results.bossMarkers,
                                ("%s | attrs: %s | %s"):format(
                                    instance.Name,
                                    getAttributeSummary(instance),
                                    instance:GetFullName()
                                ),
                                100
                            )
                        end

                        local keyword = containsKeyword(instance.Name)

                        if keyword and not seenSuspicious[instance] then
                            seenSuspicious[instance] = true

                            appendLimited(
                                results.suspiciousModels,
                                ("%s | keyword=%s | HP %d/%d | %s"):format(
                                    instance.Name,
                                    keyword,
                                    math.floor(humanoid.Health),
                                    math.floor(humanoid.MaxHealth),
                                    instance:GetFullName()
                                ),
                                150
                            )
                        end

                        if humanoid.MaxHealth >= 1000 and not seenHighHp[instance] then
                            seenHighHp[instance] = true

                            appendLimited(
                                results.highHpModels,
                                ("%s | HP %d/%d | %s"):format(
                                    instance.Name,
                                    math.floor(humanoid.Health),
                                    math.floor(humanoid.MaxHealth),
                                    instance:GetFullName()
                                ),
                                60
                            )
                        end
                    end
                end

                if instance:IsA("Folder") then
                    local keyword = containsKeyword(instance.Name)

                    if keyword and (
                        normalizeName(instance.Name) == "boss"
                        or normalizeName(instance.Name) == "bosses"
                        or keyword == "boss"
                    ) then
                        appendLimited(
                            results.bossFolders,
                            instance:GetFullName(),
                            80
                        )
                    end
                end

                if instance:IsA("ModuleScript")
                    or instance:IsA("LocalScript")
                    or instance:IsA("Script") then

                    local keyword = containsKeyword(instance.Name)

                    if keyword then
                        appendLimited(
                            results.scripts,
                            ("%s | keyword=%s"):format(
                                instance:GetFullName(),
                                keyword
                            ),
                            120
                        )
                    end
                end

                if instance:IsA("RemoteEvent")
                    or instance:IsA("RemoteFunction") then

                    local keyword = containsKeyword(instance.Name)

                    if keyword then
                        appendLimited(
                            results.remotes,
                            ("%s | %s | keyword=%s"):format(
                                instance:GetFullName(),
                                instance.ClassName,
                                keyword
                            ),
                            120
                        )
                    end
                end

                if results.scannedCount % 250 == 0 then
                    setText(("Scanning... %d objects"):format(results.scannedCount))
                    task.wait()
                end
            end
        end

        -- Explicit Arcane boss-template discovery.
        local bossTemplateCount, minibossTemplateCount = refreshBossTemplateRegistry()
        results.bossTemplateCount = bossTemplateCount
        results.minibossTemplateCount = minibossTemplateCount
        results.bossTemplates = {}

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")
        local objects = rs and rs:FindFirstChild("Objects")
        local spawningEnemies = objects and objects:FindFirstChild("SpawningEnemies")

        if spawningEnemies then
            for _, child in ipairs(spawningEnemies:GetChildren()) do
                local bossValue = child:FindFirstChild("Boss")
                local minibossValue = child:FindFirstChild("Miniboss")

                if bossValue and bossValue:IsA("BoolValue") then
                    appendLimited(
                        results.bossTemplates,
                        ("BOSS TEMPLATE | %s | Boss.Value=%s | %s"):format(
                            child.Name,
                            tostring(bossValue.Value),
                            child:GetFullName()
                        ),
                        150
                    )
                end

                if minibossValue and minibossValue:IsA("BoolValue") then
                    appendLimited(
                        results.bossTemplates,
                        ("MINIBOSS TEMPLATE | %s | Miniboss.Value=%s | %s"):format(
                            child.Name,
                            tostring(minibossValue.Value),
                            child:GetFullName()
                        ),
                        150
                    )
                end
            end
        end

        table.sort(results.highHpModels, function(a, b)
            local aHp = tonumber(a:match("HP %d+/(%d+)")) or 0
            local bHp = tonumber(b:match("HP %d+/(%d+)")) or 0
            return aHp > bHp
        end)

        local lines = {
            "ARCANE BOSS DEBUG",
            "==============================",
            ("Scanned objects: %d"):format(results.scannedCount),
            ("Models: %d"):format(results.modelCount),
            ("Models with Humanoid: %d"):format(results.humanoidCount),
            "",
            ("KNOWN BOSS DETECTIONS (%d):"):format(#results.knownBosses),
        }

        if #results.knownBosses == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.knownBosses) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("BOSS MARKERS / TAGS / FOLDERS (%d):"):format(#results.bossMarkers))

        if #results.bossMarkers == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.bossMarkers) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("SUSPICIOUS HUMANOIDS (%d):"):format(#results.suspiciousModels))

        if #results.suspiciousModels == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.suspiciousModels) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("HIGH HP HUMANOIDS (>=1000) (%d):"):format(#results.highHpModels))

        if #results.highHpModels == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.highHpModels) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("BOSS FOLDERS (%d):"):format(#results.bossFolders))

        if #results.bossFolders == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.bossFolders) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("SCRIPTS / MODULES MATCHING BOSS/NPC/AI (%d):"):format(#results.scripts))

        if #results.scripts == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.scripts) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("REMOTES MATCHING BOSS/NPC/AI (%d):"):format(#results.remotes))

        if #results.remotes == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.remotes) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("BOSS TEMPLATES FROM SpawningEnemies (%d):"):format(#(results.bossTemplates or {})))
        if #(results.bossTemplates or {}) == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.bossTemplates) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, "NOTE:")
        table.insert(lines, "Client-side scans can only see objects replicated to the client.")
        table.insert(lines, "ServerStorage / ServerScriptService server-only contents will not appear here.")

        local finalText = table.concat(lines, "\n")
        setText(finalText)

        if type(setclipboard) == "function" then
            pcall(function()
                setclipboard(finalText)
            end)
        elseif type(toclipboard) == "function" then
            pcall(function()
                toclipboard(finalText)
            end)
        end

        print("[Arcane] Boss debug scan finished.")
        print(finalText)
    end)
end

-------------------------------------------------
-- ESP
-------------------------------------------------

function Arcane.Init(Shared, UI)
    local Config = Shared.Config
    local tabs = UI.tabs or {}
    local tabButtons = UI.tabButtons or {}

    Config.ArcaneBossESP = Config.ArcaneBossESP == true
    Config.ArcaneBossDebug = Config.ArcaneBossDebug == true
    Config.ArcaneChestESP = Config.ArcaneChestESP == true

    if type(Config.ArcaneChestFilter) ~= "table" then
        Config.ArcaneChestFilter = {}
    end

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        if Config.ArcaneChestFilter[chestType] == nil then
            Config.ArcaneChestFilter[chestType] = true
        end
    end

    local miscTab = tabs["Misc"]
    if not miscTab then
        error("[Arcane] Misc tab is missing.")
    end

    for name, tab in pairs(tabs) do
        tab.Visible = (name == "Misc")
        tab.CanvasPosition = Vector2.zero
    end

    for name, button in pairs(tabButtons) do
        button.Visible = (name == "Misc")
    end

    -------------------------------------------------
    -- BOSS RESPAWN NOTIFICATIONS
    -------------------------------------------------

    local bossNotificationGui = Instance.new("ScreenGui")
    bossNotificationGui.Name = "SolarArcaneBossNotifications"
    bossNotificationGui.ResetOnSpawn = false
    bossNotificationGui.DisplayOrder = 999998
    bossNotificationGui.IgnoreGuiInset = true
    bossNotificationGui.Parent = Shared.playerGui

    local notificationHolder = Instance.new("Frame")
    notificationHolder.Name = "Holder"
    notificationHolder.AnchorPoint = Vector2.new(1, 0)
    notificationHolder.Position = UDim2.new(1, -18, 0, 18)
    notificationHolder.Size = UDim2.fromOffset(330, 260)
    notificationHolder.BackgroundTransparency = 1
    notificationHolder.Parent = bossNotificationGui

    local notificationLayout = Instance.new("UIListLayout")
    notificationLayout.FillDirection = Enum.FillDirection.Vertical
    notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    notificationLayout.Padding = UDim.new(0, 8)
    notificationLayout.Parent = notificationHolder

    local function formatPosition(position)
        if not position then
            return "Unknown"
        end

        return ("X %.0f | Y %.0f | Z %.0f"):format(
            position.X,
            position.Y,
            position.Z
        )
    end

    local function showBossSpawnNotification(bossName, bossClass, spawnPosition, deathPosition)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(340, deathPosition and 90 or 62)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
        frame.BackgroundTransparency = 0.05
        frame.BorderSizePixel = 0
        frame.Parent = notificationHolder

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 9)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(220, 140, 40)
        stroke.Thickness = 1
        stroke.Transparency = 0.15
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -18, 0, 22)
        title.Position = UDim2.fromOffset(9, 6)
        title.BackgroundTransparency = 1
        title.Text = "⚔ " .. tostring(bossClass or "BOSS") .. " RESPAWNED"
        title.TextColor3 = Color3.fromRGB(220, 140, 40)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 11
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -18, 0, 22)
        nameLabel.Position = UDim2.fromOffset(9, 29)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = tostring(bossName) .. " spawned at: " .. formatPosition(spawnPosition)
        nameLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 9
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = frame

        if deathPosition then
            local previousLabel = Instance.new("TextLabel")
            previousLabel.Size = UDim2.new(1, -18, 0, 24)
            previousLabel.Position = UDim2.fromOffset(9, 53)
            previousLabel.BackgroundTransparency = 1
            previousLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
            previousLabel.Font = Enum.Font.Gotham
            previousLabel.TextSize = 8
            previousLabel.TextXAlignment = Enum.TextXAlignment.Left

            local distance = (spawnPosition - deathPosition).Magnitude

            if distance <= 12 then
                previousLabel.Text = ("Death: %s | Spawn moved: %.0f studs (same area)"):format(
                    formatPosition(deathPosition),
                    distance
                )
            else
                previousLabel.Text = ("Death: %s | Spawn moved: %.0f studs"):format(
                    formatPosition(deathPosition),
                    distance
                )
            end

            previousLabel.Parent = frame
        end

        task.delay(5, function()
            if frame and frame.Parent then
                frame:Destroy()
            end
        end)
    end


    local section = UI.createSection(
        miscTab,
        "Arcane Odyssey",
        330
    )

    UI.createToggle(
        section,
        "Boss ESP",
        "Shows detected bosses with HP and distance.",
        "ArcaneBossESP",
        32
    )

    UI.createToggle(
        section,
        "Boss Debug",
        "Shows detection information and discovery results.",
        "ArcaneBossDebug",
        80
    )

    local scanButton = Instance.new("TextButton")
    scanButton.Size = UDim2.new(1, -16, 0, 34)
    scanButton.Position = UDim2.fromOffset(8, 124)
    scanButton.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    scanButton.BorderSizePixel = 0
    scanButton.Text = "SCAN BOSS STRUCTURE"
    scanButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    scanButton.Font = Enum.Font.GothamBold
    scanButton.TextSize = 10
    scanButton.Parent = section
    Instance.new("UICorner", scanButton).CornerRadius = UDim.new(0, 8)

    local copyButton = Instance.new("TextButton")
    copyButton.Size = UDim2.fromOffset(70, 24)
    copyButton.Position = UDim2.new(1, -78, 0, 166)
    copyButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    copyButton.BorderSizePixel = 0
    copyButton.Text = "COPY"
    copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyButton.Font = Enum.Font.GothamBold
    copyButton.TextSize = 9
    copyButton.Parent = section
    Instance.new("UICorner", copyButton).CornerRadius = UDim.new(0, 6)

    local debugBox = Instance.new("TextBox")
    debugBox.Position = UDim2.fromOffset(8, 195)
    debugBox.Size = UDim2.new(1, -16, 0, 125)
    debugBox.BackgroundColor3 = Color3.fromRGB(8, 8, 11)
    debugBox.BorderSizePixel = 0
    debugBox.ClearTextOnFocus = false
    debugBox.MultiLine = true
    debugBox.TextEditable = false
    debugBox.TextWrapped = false
    debugBox.TextXAlignment = Enum.TextXAlignment.Left
    debugBox.TextYAlignment = Enum.TextYAlignment.Top
    debugBox.Font = Enum.Font.Code
    debugBox.TextSize = 9
    debugBox.TextColor3 = Color3.fromRGB(220, 220, 225)
    debugBox.Text = "Ready. Press SCAN BOSS STRUCTURE."
    debugBox.Parent = section
    Instance.new("UICorner", debugBox).CornerRadius = UDim.new(0, 7)

    local lastScanText = debugBox.Text

    local function setDebugText(text)
        lastScanText = tostring(text)
        debugBox.Text = lastScanText
    end

    scanButton.Activated:Connect(function()
        if scanButton.Text == "SCANNING..." then
            return
        end

        scanButton.Text = "SCANNING..."
        runDebugScan(setDebugText)

        task.delay(0.2, function()
            while scanButton and scanButton.Parent and debugBox.Text:find("Scanning", 1, true) do
                task.wait(0.2)
            end

            if scanButton and scanButton.Parent then
                scanButton.Text = "SCAN BOSS STRUCTURE"
            end
        end)
    end)

    copyButton.Activated:Connect(function()
        local success = false

        if type(setclipboard) == "function" then
            success = pcall(function()
                setclipboard(lastScanText)
            end)
        elseif type(toclipboard) == "function" then
            success = pcall(function()
                toclipboard(lastScanText)
            end)
        end

        copyButton.Text = success and "COPIED" or "COPY FAIL"

        task.delay(1.2, function()
            if copyButton and copyButton.Parent then
                copyButton.Text = "COPY"
            end
        end)
    end)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -90, 0, 24)
    statusLabel.Position = UDim2.fromOffset(8, 166)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "ESP: waiting for boss models..."
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 9
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = section

    
    -------------------------------------------------
    -- CHEST ESP / MULTI-FILTER UI
    -------------------------------------------------

    local chestSection = UI.createSection(
        miscTab,
        "Chest ESP",
        370
    )

    UI.createToggle(
        chestSection,
        "Chest ESP",
        "Shows chests with their type and distance.",
        "ArcaneChestESP",
        32
    )

    local chestFilterTitle = Instance.new("TextLabel")
    chestFilterTitle.Size = UDim2.new(1, -16, 0, 22)
    chestFilterTitle.Position = UDim2.fromOffset(8, 78)
    chestFilterTitle.BackgroundTransparency = 1
    chestFilterTitle.Text = "Chest Filter — select multiple types"
    chestFilterTitle.TextColor3 = Color3.fromRGB(205, 205, 215)
    chestFilterTitle.Font = Enum.Font.GothamBold
    chestFilterTitle.TextSize = 9
    chestFilterTitle.TextXAlignment = Enum.TextXAlignment.Left
    chestFilterTitle.Parent = chestSection

    local chestFilterButtons = {}

    local function updateChestFilterButton(chestType)
        local buttonData = chestFilterButtons[chestType]
        if not buttonData then
            return
        end

        local enabled = Config.ArcaneChestFilter[chestType] == true

        buttonData.indicator.BackgroundColor3 = enabled
            and CHEST_COLORS[chestType]
            or Color3.fromRGB(50, 50, 60)

        buttonData.text.TextColor3 = enabled
            and Color3.fromRGB(240, 240, 240)
            or Color3.fromRGB(120, 120, 130)

        buttonData.check.Text = enabled and "✓" or ""
    end

    local filterStartY = 104
    local filterRowHeight = 34

    for index, chestType in ipairs(CHEST_TYPE_ORDER) do
        local zeroIndex = index - 1
        local column = zeroIndex % 2
        local row = math.floor(zeroIndex / 2)

        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0.5, -12, 0, 30)
        button.Position = UDim2.new(
            0.5 * column,
            column == 0 and 4 or 8,
            0,
            filterStartY + (row * filterRowHeight)
        )
        button.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = chestSection
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(16, 16)
        indicator.Position = UDim2.fromOffset(7, 7)
        indicator.BorderSizePixel = 0
        indicator.Parent = button
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 4)

        local check = Instance.new("TextLabel")
        check.Size = UDim2.fromScale(1, 1)
        check.BackgroundTransparency = 1
        check.Font = Enum.Font.GothamBold
        check.TextSize = 11
        check.TextColor3 = Color3.fromRGB(255, 255, 255)
        check.Parent = indicator

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -31, 1, 0)
        textLabel.Position = UDim2.fromOffset(29, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = CHEST_DISPLAY_NAMES[chestType]
        textLabel.TextSize = 9
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
        textLabel.Parent = button

        chestFilterButtons[chestType] = {
            button = button,
            indicator = indicator,
            check = check,
            text = textLabel,
        }

        updateChestFilterButton(chestType)

        button.Activated:Connect(function()
            Config.ArcaneChestFilter[chestType] = not (
                Config.ArcaneChestFilter[chestType] == true
            )
            updateChestFilterButton(chestType)
        end)
    end

    local selectAllButton = Instance.new("TextButton")
    selectAllButton.Size = UDim2.new(0.5, -12, 0, 28)
    selectAllButton.Position = UDim2.new(0, 4, 0, 322)
    selectAllButton.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
    selectAllButton.BorderSizePixel = 0
    selectAllButton.Text = "SELECT ALL"
    selectAllButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    selectAllButton.Font = Enum.Font.GothamBold
    selectAllButton.TextSize = 9
    selectAllButton.Parent = chestSection
    Instance.new("UICorner", selectAllButton).CornerRadius = UDim.new(0, 7)

    local clearAllButton = Instance.new("TextButton")
    clearAllButton.Size = UDim2.new(0.5, -12, 0, 28)
    clearAllButton.Position = UDim2.new(0.5, 8, 0, 322)
    clearAllButton.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
    clearAllButton.BorderSizePixel = 0
    clearAllButton.Text = "CLEAR ALL"
    clearAllButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    clearAllButton.Font = Enum.Font.GothamBold
    clearAllButton.TextSize = 9
    clearAllButton.Parent = chestSection
    Instance.new("UICorner", clearAllButton).CornerRadius = UDim.new(0, 7)

    selectAllButton.Activated:Connect(function()
        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            Config.ArcaneChestFilter[chestType] = true
            updateChestFilterButton(chestType)
        end
    end)

    clearAllButton.Activated:Connect(function()
        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            Config.ArcaneChestFilter[chestType] = false
            updateChestFilterButton(chestType)
        end
    end)


    local espObjects = {}
    local candidateModels = {}

    local chestESPObjects = {}
    local chestCandidates = {}

    -- Boss lifecycle state is tracked by boss name, not by spawn position.
    -- This means a boss can die at Point A and respawn at Point B.
    local bossStates = {}
    local activeBossModels = {}
    local bossDeathHooks = {}
    local initializedBossState = false

    local function destroyESP(model)
        local data = espObjects[model]

        if data then
            if data.highlight then
                pcall(function()
                    data.highlight:Destroy()
                end)
            end

            if data.billboard then
                pcall(function()
                    data.billboard:Destroy()
                end)
            end

            espObjects[model] = nil
        end
    end

    local function destroyChestESP(target)
        local data = chestESPObjects[target]

        if data then
            if data.highlight then
                pcall(function()
                    data.highlight:Destroy()
                end)
            end

            if data.billboard then
                pcall(function()
                    data.billboard:Destroy()
                end)
            end

            chestESPObjects[target] = nil
        end
    end

    local function createChestESP(target)
        if not Config.ArcaneChestESP then
            return
        end

        local chestType = getChestType(target)

        if not chestType or not isChestFilterEnabled(Config, chestType) then
            destroyChestESP(target)
            return
        end

        if chestESPObjects[target] then
            return
        end

        local root = getChestRoot(target)

        if not root then
            return
        end

        local chestColor = CHEST_COLORS[chestType] or CHEST_COLORS.OTHER
        local chestDisplayName = CHEST_DISPLAY_NAMES[chestType] or "Other Chest"

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarChestESP"
        highlight.Adornee = target
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = chestColor
        highlight.OutlineColor = chestColor
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = target:IsA("Model") and target or Workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarChestESPInfo"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(260, 32)
        billboard.StudsOffset = Vector3.new(0, 2.8, 0)
        billboard.Parent = Shared.playerGui

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = chestColor
        label.TextStrokeTransparency = 0.15
        label.TextSize = 12
        label.Text = chestDisplayName .. " | STUDS: ?"
        label.Parent = billboard

        chestESPObjects[target] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
            chestType = chestType,
        }
    end

    local function inspectChest(target)
        local chest = getChestTarget(target)

        if not chest then
            return
        end

        chestCandidates[chest] = true

        if Config.ArcaneChestESP then
            createChestESP(chest)
        end
    end

    local function markBossDead(model, bossName)
        if not initializedBossState then
            return
        end

        local key = normalizeName(bossName)
        if key == "" then
            return
        end

        local state = bossStates[key] or {}

        local root = getRoot(model)
        local position = root and root.Position or state.lastPosition

        state.alive = false
        state.lastDeathPosition = position
        state.lastDeathTime = os.clock()
        state.model = nil

        bossStates[key] = state
    end

    local function removeModel(model)
        candidateModels[model] = nil

        local bossName = getBossDisplayName(model)
        if bossName then
            activeBossModels[model] = nil
            markBossDead(model, bossName)
        end

        bossDeathHooks[model] = nil
        destroyESP(model)
    end

    local function createESP(model)
        if not Config.ArcaneBossESP then
            return
        end

        if espObjects[model] then
            return
        end

        local info = getBossInfo(model)
        if not info then
            return
        end

        local root = info.root or getRoot(model)
        if not root then
            return
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarBossESP"
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarBossESPInfo"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.fromOffset(270, 76)
        billboard.StudsOffset = Vector3.new(0, 4.2, 0)
        billboard.Parent = root

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.25
        label.TextSize = 13
        label.TextWrapped = true
        label.Parent = billboard

        espObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
            detectionType = info.detectionType,
            bossClass = info.bossClass,
        }
    end

    local function inspectModel(model)
        if not model or not model.Parent or not model:IsA("Model") then
            return
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return
        end

        local bossName, detectionType = getBossDisplayName(model)

        local bossClass = getBossClass(model)

        if bossName and bossClass and (
            isBossTemplateName(model.Name)
            or bossClass == "MINI BOSS"
            or bossClass == "BOSS"
        ) then
            local key = normalizeName(bossName)
            local state = bossStates[key] or {}
            local root = getRoot(model)
            local spawnPosition = root and root.Position or state.lastPosition

            -- A new model for the same boss after a confirmed death is a respawn.
            -- We use the NEW model's current position as the actual spawn location.
            if initializedBossState
                and state.alive == false
                and not activeBossModels[model] then

                showBossSpawnNotification(
                    bossName,
                    bossClass,
                    spawnPosition,
                    state.lastDeathPosition
                )
            end

            state.alive = true
            state.model = model
            state.lastPosition = spawnPosition
            bossStates[key] = state
            activeBossModels[model] = true

            if not bossDeathHooks[model] then
                bossDeathHooks[model] = true

                humanoid.Died:Connect(function()
                    local currentRoot = getRoot(model)
                    local deathPosition = currentRoot and currentRoot.Position or state.lastPosition

                    local currentState = bossStates[key] or {}
                    currentState.alive = false
                    currentState.model = nil
                    currentState.lastDeathPosition = deathPosition
                    currentState.lastDeathTime = os.clock()
                    currentState.lastPosition = deathPosition
                    bossStates[key] = currentState

                    activeBossModels[model] = nil
                end)
            end
        end

        candidateModels[model] = true

        if Config.ArcaneBossESP then
            createESP(model)
        end
    end

    local replicatedStorage = game:GetService("ReplicatedStorage")
    local rs = replicatedStorage:FindFirstChild("RS")
    local objectsFolder = rs and rs:FindFirstChild("Objects")
    local spawningEnemies = objectsFolder and objectsFolder:FindFirstChild("SpawningEnemies")

    if spawningEnemies then
        spawningEnemies.ChildAdded:Connect(function()
            task.defer(refreshBossTemplateRegistry)
        end)

        spawningEnemies.ChildRemoved:Connect(function()
            task.defer(refreshBossTemplateRegistry)
        end)
    end

    workspace.DescendantAdded:Connect(function(instance)
        local model = instance:IsA("Model")
            and instance
            or instance:FindFirstAncestorOfClass("Model")

        if model then
            inspectModel(model)
            inspectChest(model)

            task.delay(0.15, function()
                if model and model.Parent then
                    inspectModel(model)
                    inspectChest(model)
                end
            end)
        end

        if instance:IsA("BasePart")
            and normalizeName(instance.Name):find("chest", 1, true) then
            inspectChest(instance)
        end
    end)

    workspace.DescendantRemoving:Connect(function(instance)
        if instance:IsA("Model") then
            removeModel(instance)
            chestCandidates[instance] = nil
            destroyChestESP(instance)
        end

        if instance:IsA("BasePart") then
            local chest = getChestTarget(instance)

            if chest then
                chestCandidates[chest] = nil
                destroyChestESP(chest)
            end
        end
    end)

    task.spawn(function()
        local descendants = workspace:GetDescendants()
        local processed = 0

        for _, instance in ipairs(descendants) do
            if instance:IsA("Model") then
                inspectModel(instance)
                inspectChest(instance)
            elseif instance:IsA("BasePart") then
                if normalizeName(instance.Name):find("chest", 1, true) then
                    inspectChest(instance)
                end
            end

            processed += 1

            if processed % 200 == 0 then
                task.wait()
            end
        end

        -- Everything seen during the initial scan is considered already alive.
        task.delay(0.25, function()
            initializedBossState = true
        end)
    end)

    task.spawn(function()
        while true do
            task.wait(2)

            refreshBossTemplateRegistry()

            for model in pairs(activeBossModels) do
                if not model.Parent then
                    local bossName = getBossDisplayName(model)
                    if bossName then
                        markBossDead(model, bossName)
                    end

                    activeBossModels[model] = nil
                    bossDeathHooks[model] = nil
                end
            end

            local detected = 0

            if Config.ArcaneBossESP then
                for model in pairs(candidateModels) do
                    if not model.Parent then
                        removeModel(model)
                    else
                        createESP(model)
                    end
                end

                for model in pairs(espObjects) do
                    if model.Parent then
                        detected += 1
                    end
                end
            else
                for model in pairs(espObjects) do
                    destroyESP(model)
                end
            end

            local chestDetected = 0

            if Config.ArcaneChestESP then
                for target in pairs(chestESPObjects) do
                    if target.Parent then
                        chestDetected += 1
                    end
                end
            end

            statusLabel.Text = ("Boss: %d | Chests: %d"):format(
                detected,
                chestDetected
            )
        end
    end)


    task.spawn(function()
        while true do
            task.wait(0.5)

            if Config.ArcaneChestESP then
                for target in pairs(chestCandidates) do
                    if not target.Parent then
                        chestCandidates[target] = nil
                        destroyChestESP(target)
                    elseif isChestFilterEnabled(Config, getChestType(target)) then
                        createChestESP(target)
                    else
                        destroyChestESP(target)
                    end
                end
            else
                for target in pairs(chestESPObjects) do
                    destroyChestESP(target)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.25)

            if Config.ArcaneBossESP then
                local character = Shared.player.Character
                local playerRoot = character
                    and character:FindFirstChild("HumanoidRootPart")

                for model, data in pairs(espObjects) do
                    if not model.Parent then
                        removeModel(model)
                    else
                        local root = getRoot(model)
                        local humanoid = model:FindFirstChildOfClass("Humanoid")

                        if not root or not humanoid then
                            destroyESP(model)
                        else
                            local bossName = getBossDisplayName(model) or model.Name
                            local distanceText = "STUDS: ?"

                            if playerRoot then
                                distanceText = ("STUDS: %d"):format(
                                    math.floor(
                                        (playerRoot.Position - root.Position).Magnitude
                                    )
                                )
                            end

                            local health = math.max(0, humanoid.Health)
                            local maxHealth = math.max(0, humanoid.MaxHealth)

                            local bossClass = getBossClass(model) or "BOSS"

                            data.label.Text = string.format(
                                "%s\n%s\nHP: %d/%d  |  %s",
                                tostring(bossClass),
                                tostring(bossName),
                                math.floor(health),
                                math.floor(maxHealth),
                                distanceText
                            )
                        end
                    end
                end
            end
        end
    end)


    task.spawn(function()
        while true do
            task.wait(0.25)

            local character = Shared.player.Character
            local playerRoot = character
                and character:FindFirstChild("HumanoidRootPart")

            for target, data in pairs(chestESPObjects) do
                local root = getChestRoot(target)

                if not target.Parent or not root then
                    destroyChestESP(target)
                elseif not Config.ArcaneChestESP
                    or not isChestFilterEnabled(Config, getChestType(target)) then
                    destroyChestESP(target)
                else
                    local distanceText = "STUDS: ?"

                    if playerRoot then
                        distanceText = ("STUDS: %d"):format(
                            math.floor(
                                (playerRoot.Position - root.Position).Magnitude
                            )
                        )
                    end

                    local chestType = data.chestType or getChestType(target)
                    local chestDisplayName = CHEST_DISPLAY_NAMES[chestType]
                        or "Other Chest"

                    local chestColor = CHEST_COLORS[chestType]
                        or CHEST_COLORS.OTHER

                    data.label.TextColor3 = chestColor
                    data.label.Text = chestDisplayName
                        .. " | "
                        .. distanceText
                end
            end
        end
    end)

    return true
end

return Arcane
