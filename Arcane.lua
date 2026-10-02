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

local function hasAnyChestFilterEnabled(Config)
    local filter = Config.ArcaneChestFilter

    if type(filter) ~= "table" then
        return false
    end

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        if filter[chestType] == true then
            return true
        end
    end

    return false
end

local function getChestTypeFast(target)
    if not target or not target.Parent then
        return nil
    end

    local text = target.Name

    -- Most live Arcane chest instances expose the exact type in their name.
    local chestType = classifyChestText(text)
    if chestType then
        return chestType
    end

    -- For generic "Treasure Chest"/"Chest" models, use the nearest model name.
    local model = target:IsA("Model")
        and target
        or target:FindFirstAncestorOfClass("Model")

    if model then
        chestType = classifyChestText(model.Name)
        if chestType then
            return chestType
        end
    end

    return nil
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
        or normalized:find("sealed", 1, true)
        or normalized == "common"
        or normalized == "uncommon"
        or normalized == "rare"
        or normalized == "mystic"
        or normalized == "legendary"
        or normalized == "privatestorage"
        or normalized == "sky"
        or normalized == "steel" then
        return true
    end

    -- Some chest models are generically named but expose their type through
    -- attributes or replicated Value objects.
    local okAttrs, attrs = pcall(function()
        return model:GetAttributes()
    end)

    if okAttrs and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            local keyText = normalizeChestText(key)
            local valueType = typeof(value)

            if keyText:find("chest", 1, true)
                or keyText:find("rarity", 1, true)
                or keyText:find("tier", 1, true)
                or keyText:find("type", 1, true) then

                if valueType == "string"
                    or valueType == "number"
                    or valueType == "boolean" then
                    if classifyChestText(value) then
                        return true
                    end
                end
            end
        end
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
        local root = getRoot(target)

        if root then
            return root
        end

        for _, descendant in ipairs(target:GetDescendants()) do
            if descendant:IsA("BasePart") then
                return descendant
            end
        end

        return nil
    end

    if target:IsA("BasePart") then
        return target
    end

    return nil
end


-------------------------------------------------
-- ARCANE SIDE QUEST NPC DISCOVERY
-------------------------------------------------

local SIDE_QUEST_NPC_NAMES = {
    "Audbjorg",
    "Asfrith",
    "Dotta",
    "Hundi",
    "Jomar",
    "Gisli",
    "Edward Kenton",
    "Ewan Avery",
    "Enizor",
    "Maya",
    "Caleb Banks",
    "Jasmine Lynn",
    "Ellie Bowen",
    "Adam Walters",
    "Mayor Tilly",
    "Tilly",
    "Captain Elliot",
    "Jay Rogers",
    "Amulius Augur",
    "Mamercus Lurco",
    "Ingvild",
    "Leto",
    "Souvella",
    "Isabel Slater",
}

local NORMALIZED_SIDE_QUEST_NPCS = {}

for _, name in ipairs(SIDE_QUEST_NPC_NAMES) do
    NORMALIZED_SIDE_QUEST_NPCS[normalizeName(name)] = name
end

local function hasSideQuestMarker(model)
    local collectionService = game:GetService("CollectionService")

    local okTags, tags = pcall(function()
        return collectionService:GetTags(model)
    end)

    if okTags and type(tags) == "table" then
        for _, tag in ipairs(tags) do
            local normalized = normalizeName(tag)

            if normalized:find("quest", 1, true)
                or normalized:find("mission", 1, true)
                or normalized:find("sidequest", 1, true) then
                return true
            end
        end
    end

    local okAttrs, attrs = pcall(function()
        return model:GetAttributes()
    end)

    if okAttrs and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            local k = normalizeChestText(key)
            local v = normalizeChestText(value)

            if k:find("quest", 1, true)
                or k:find("mission", 1, true)
                or k:find("sidequest", 1, true)
                or v:find("quest", 1, true)
                or v:find("mission", 1, true)
                or v:find("sidequest", 1, true) then
                return true
            end
        end
    end

    for _, child in ipairs(model:GetChildren()) do
        local name = normalizeChestText(child.Name)

        if name:find("quest", 1, true)
            or name:find("mission", 1, true)
            or name:find("exclamation", 1, true) then
            return true
        end
    end

    -- Arcane NPC templates can store the quest marker as:
    -- Model.Attributes.Quest (IntValue), rather than an Attribute.
    local attributesFolder = model:FindFirstChild("Attributes")
    if attributesFolder and attributesFolder:FindFirstChild("Quest") then
        return true
    end

    local questValue = model:FindFirstChild("Quest")
    if questValue
        and (questValue:IsA("IntValue")
            or questValue:IsA("NumberValue")
            or questValue:IsA("StringValue")
            or questValue:IsA("BoolValue")) then
        return true
    end

    return false
end

local function getSideQuestPrompt(model)
    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)

    if not prompt then
        return nil
    end

    local action = normalizeChestText(prompt.ActionText)
    local object = normalizeChestText(prompt.ObjectText)
    local promptName = normalizeChestText(prompt.Name)

    if action:find("quest", 1, true)
        or action:find("mission", 1, true)
        or object:find("quest", 1, true)
        or object:find("mission", 1, true)
        or promptName:find("quest", 1, true)
        or promptName:find("mission", 1, true) then
        return prompt
    end

    return nil
end

local function getSideQuestNPCInfo(model)
    if not model
        or not model:IsA("Model")
        or not model.Parent then
        return nil
    end

    if not model:FindFirstChildOfClass("Humanoid") then
        return nil
    end

    local localPlayer = game:GetService("Players").LocalPlayer

    if localPlayer and model == localPlayer.Character then
        return nil
    end

    local knownName = NORMALIZED_SIDE_QUEST_NPCS[normalizeName(model.Name)]

    if knownName then
        return {
            name = knownName,
            detectionType = "Known NPC",
        }
    end

    if hasSideQuestMarker(model) then
        return {
            name = model.Name,
            detectionType = "Quest marker",
        }
    end

    if getSideQuestPrompt(model) then
        return {
            name = model.Name,
            detectionType = "Quest prompt",
        }
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
        setText("Scanning targeted Arcane world structures...\nThis avoids freezing on the full Workspace.")

        local results = {
            activeNPCs = {},
            sideQuestNPCs = {},
            activeBosses = {},
            bossTemplates = {},
            activeChests = {},
            spawnLocations = {},
            questObjects = {},
            remotes = {},
            scripts = {},
        }

        local function addLimited(list, value, limit)
            if #list < limit then
                table.insert(list, value)
            end
        end

        local function inspectNPCModel(model, sourceName)
            if not model:IsA("Model") then
                return
            end

            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                return
            end

            local root = getRoot(model)
            local position = root and root.Position
            local questInfo = getSideQuestNPCInfo(model)

            local line = ("%s | %s | %s"):format(
                model.Name,
                sourceName,
                position
                    and ("POS %.0f %.0f %.0f"):format(
                        position.X, position.Y, position.Z
                    )
                    or "NO POS"
            )

            addLimited(results.activeNPCs, line, 150)

            if questInfo then
                local questLine = ("%s | %s | %s"):format(
                    questInfo.name,
                    questInfo.detectionType,
                    model:GetFullName()
                )

                addLimited(results.sideQuestNPCs, questLine, 150)
            end
        end

        local npcFolder = workspace:FindFirstChild("NPCs")
        if npcFolder then
            for _, model in ipairs(npcFolder:GetChildren()) do
                inspectNPCModel(model, "Workspace.NPCs")
            end
        end

        local enemiesFolder = workspace:FindFirstChild("Enemies")
        if enemiesFolder then
            for _, model in ipairs(enemiesFolder:GetChildren()) do
                inspectNPCModel(model, "Workspace.Enemies")
            end
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")

        local objects = rs and rs:FindFirstChild("Objects")

        local spawningEnemies = objects and objects:FindFirstChild("SpawningEnemies")
        if spawningEnemies then
            for _, model in ipairs(spawningEnemies:GetChildren()) do
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local bossInfo = getBossInfo(model)
                    if bossInfo then
                        addLimited(
                            results.bossTemplates,
                            ("%s | %s | %s"):format(
                                model.Name,
                                bossInfo.bossClass,
                                model:GetFullName()
                            ),
                            150
                        )
                    end
                end
            end
        end

        local bossFigures = objects and objects:FindFirstChild("BossFigures")
        if bossFigures then
            for _, model in ipairs(bossFigures:GetChildren()) do
                local bossValue = model:FindFirstChild("Boss")
                local minibossValue = model:FindFirstChild("Miniboss")

                if bossValue or minibossValue then
                    addLimited(
                        results.bossTemplates,
                        ("%s | Boss=%s | Mini=%s | %s"):format(
                            model.Name,
                            tostring(bossValue and bossValue.Value),
                            tostring(minibossValue and minibossValue.Value),
                            model:GetFullName()
                        ),
                        150
                    )
                end
            end
        end

        if enemiesFolder then
            for _, model in ipairs(enemiesFolder:GetChildren()) do
                local bossInfo = model:IsA("Model") and getBossInfo(model)
                if bossInfo then
                    local root = bossInfo.root
                    local hp = bossInfo.humanoid

                    addLimited(
                        results.activeBosses,
                        ("%s | %s | HP %d/%d | POS %.0f %.0f %.0f"):format(
                            bossInfo.name,
                            bossInfo.bossClass,
                            math.floor(hp.Health),
                            math.floor(hp.MaxHealth),
                            root.Position.X,
                            root.Position.Y,
                            root.Position.Z
                        ),
                        100
                    )
                end
            end
        end

        local collectionService = game:GetService("CollectionService")

        local function addTaggedChests(tag)
            local tagged = collectionService:GetTagged(tag)

            for _, object in ipairs(tagged) do
                local chest = getChestTarget(object)

                if chest then
                    local root = getChestRoot(chest)
                    if root then
                        addLimited(
                            results.activeChests,
                            ("%s | %s | POS %.0f %.0f %.0f | %s"):format(
                                chest.Name,
                                getChestType(chest) or "OTHER",
                                root.Position.X,
                                root.Position.Y,
                                root.Position.Z,
                                chest:GetFullName()
                            ),
                            200
                        )
                    end
                end
            end
        end

        addTaggedChests("Chests")
        addTaggedChests("Prompt_Chest")
        addTaggedChests("BuriedChests")

        local map = workspace:FindFirstChild("Map")

        if map then
            local seaContent = map:FindFirstChild("SeaContent")
            local npcLocations = seaContent and seaContent:FindFirstChild("NPCLocations")

            if npcLocations then
                for _, object in ipairs(npcLocations:GetDescendants()) do
                    if object:IsA("BasePart") then
                        addLimited(
                            results.spawnLocations,
                            ("%s | POS %.0f %.0f %.0f | %s"):format(
                                object.Name,
                                object.Position.X,
                                object.Position.Y,
                                object.Position.Z,
                                object:GetFullName()
                            ),
                            200
                        )
                    end
                end
            end

            local questObjects = map:FindFirstChild("QuestObjects")
            if questObjects then
                for _, object in ipairs(questObjects:GetChildren()) do
                    addLimited(
                        results.questObjects,
                        object:GetFullName(),
                        120
                    )
                end
            end
        end

        if rs then
            local remotesFolder = rs:FindFirstChild("Remotes")
            if remotesFolder then
                for _, instance in ipairs(remotesFolder:GetDescendants()) do
                    if instance:IsA("RemoteEvent")
                        or instance:IsA("RemoteFunction") then

                        local keyword = containsKeyword(instance.Name)

                        if keyword
                            or normalizeName(instance.Name):find("fish", 1, true)
                            or normalizeName(instance.Name):find("chest", 1, true)
                            or normalizeName(instance.Name):find("quest", 1, true) then

                            addLimited(
                                results.remotes,
                                ("%s | %s"):format(
                                    instance.ClassName,
                                    instance:GetFullName()
                                ),
                                200
                            )
                        end
                    end
                end
            end

            -- Intentionally skip RS.Modules here.
            -- It is very large and is not needed to diagnose world ESP.
        end

        -- Directly inspect quest-capable NPC templates. This includes models
        -- that are not currently streamed into Workspace.
        local function scanQuestModelFolder(folder)
            if not folder then
                return
            end

            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
                    local info = getSideQuestNPCInfo(model)

                    if info then
                        addLimited(
                            results.sideQuestNPCs,
                            ("%s | TEMPLATE %s | POS=%s | %s"):format(
                                info.name,
                                info.detectionType,
                                (getRoot(model)
                                    and tostring(getRoot(model).Position)
                                    or "NO POS"),
                                model:GetFullName()
                            ),
                            150
                        )
                    end
                end
            end
        end

        scanQuestModelFolder(objects)
        scanQuestModelFolder(rs and rs:FindFirstChild("UnloadEnemies"))

        local lines = {
            "SOLARHUB ARCANE TARGETED DEBUG",
            "==============================",
            "This scanner only checks Arcane's relevant folders/tags.",
            "",
            ("ACTIVE NPC MODELS (%d):"):format(#results.activeNPCs),
        }

        if #results.activeNPCs == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.activeNPCs) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("SIDE QUEST NPC CANDIDATES (%d):"):format(#results.sideQuestNPCs))
        if #results.sideQuestNPCs == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.sideQuestNPCs) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("ACTIVE BOSSES (%d):"):format(#results.activeBosses))
        if #results.activeBosses == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.activeBosses) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("BOSS TEMPLATES (%d):"):format(#results.bossTemplates))
        if #results.bossTemplates == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.bossTemplates) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("ACTIVE/TAGGED CHESTS (%d):"):format(#results.activeChests))
        if #results.activeChests == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.activeChests) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("NPC LOCATION / SPAWN PARTS (%d):"):format(#results.spawnLocations))
        if #results.spawnLocations == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.spawnLocations) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("QUEST OBJECTS (%d):"):format(#results.questObjects))
        if #results.questObjects == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.questObjects) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("RELEVANT REMOTES (%d):"):format(#results.remotes))
        if #results.remotes == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.remotes) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, ("RELEVANT MODULES (%d):"):format(#results.scripts))
        if #results.scripts == 0 then
            table.insert(lines, "<none>")
        else
            for _, line in ipairs(results.scripts) do
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")
        table.insert(lines, "NOTE:")
        table.insert(lines, "Live ESP still depends on objects being present/renderable on the client.")
        table.insert(lines, "Replicated NPC templates can provide static world positions for virtual markers.")

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

        print("[Arcane] Targeted debug scan finished.")
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
    Config.ArcaneSideQuestESP = Config.ArcaneSideQuestESP == true
    Config.ArcaneAutoFishing = Config.ArcaneAutoFishing == true

    -- Chest filters intentionally start OFF every time SolarHub initializes.
    if type(Config.ArcaneChestFilter) ~= "table" then
        Config.ArcaneChestFilter = {}
    end

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        Config.ArcaneChestFilter[chestType] = false
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


    -------------------------------------------------
    -- SIDE QUEST NPC ESP
    -------------------------------------------------

    local sideQuestSection = UI.createSection(
        miscTab,
        "Side Quest NPC",
        100
    )

    UI.createToggle(
        sideQuestSection,
        "Side Quest NPC ESP",
        "Shows side quest NPCs with name and distance.",
        "ArcaneSideQuestESP",
        32
    )

    -------------------------------------------------
    -- AUTO FISHING
    -------------------------------------------------

    local fishingSection = UI.createSection(
        miscTab,
        "Auto Fishing",
        120
    )

    UI.createToggle(
        fishingSection,
        "Auto Fishing",
        "Auto equips the rod, casts, reels, and recasts.",
        "ArcaneAutoFishing",
        32
    )

    local fishingStatusLabel = Instance.new("TextLabel")
    fishingStatusLabel.Size = UDim2.new(1, -16, 0, 20)
    fishingStatusLabel.Position = UDim2.fromOffset(8, 78)
    fishingStatusLabel.BackgroundTransparency = 1
    fishingStatusLabel.Text = "Status: OFF | Put cursor over water first."
    fishingStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    fishingStatusLabel.Font = Enum.Font.Gotham
    fishingStatusLabel.TextSize = 8
    fishingStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    fishingStatusLabel.Parent = fishingSection


    local espObjects = {}
    local candidateModels = {}

    local chestESPObjects = {}
    local chestCandidates = {}

    local sideQuestESPObjects = {}
    local sideQuestCandidates = {}

    local autoFishingBusy = false

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
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        local chestType = getChestTypeFast(target) or getChestType(target)

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
        billboard.MaxDistance = 0
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

    local localChestTagObjects = {}

    local function inspectChest(target)
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        -- Do the cheap name test first. Only fall back to the deeper chest
        -- classifier for generic chest names.
        local fastType = getChestTypeFast(target)
        if fastType and not isChestFilterEnabled(Config, fastType) then
            return
        end

        local chest = getChestTarget(target)
        if not chest then
            return
        end

        local chestType = fastType or getChestType(chest)

        if not isChestFilterEnabled(Config, chestType) then
            return
        end

        localChestTagObjects[chest] = true
        chestCandidates[chest] = true

        createChestESP(chest)
    end


    local function scanSelectedChests()
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        local collectionService = game:GetService("CollectionService")
        local seen = {}

        for _, tag in ipairs({
            "Chests",
            "Prompt_Chest",
            "BuriedChests",
        }) do
            for _, object in ipairs(collectionService:GetTagged(tag)) do
                if not seen[object] then
                    seen[object] = true
                    inspectChest(object)
                end
            end
        end
    end
    local collectionService = game:GetService("CollectionService")

    for _, tag in ipairs({
        "Chests",
        "Prompt_Chest",
        "BuriedChests",
    }) do
        collectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
            if Config.ArcaneChestESP and hasAnyChestFilterEnabled(Config) then
                inspectChest(instance)
            end
        end)
    end

    local function destroySideQuestESP(model)
        local data = sideQuestESPObjects[model]

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

            sideQuestESPObjects[model] = nil
        end
    end

    local function createSideQuestESP(model)
        if not Config.ArcaneSideQuestESP then
            return
        end

        if sideQuestESPObjects[model] then
            return
        end

        local info = getSideQuestNPCInfo(model)

        if not info then
            return
        end

        local root = getRoot(model)

        if not root then
            return
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarSideQuestESP"
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = Color3.fromRGB(220, 140, 40)
        highlight.OutlineColor = Color3.fromRGB(220, 140, 40)
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarSideQuestESPInfo"
        billboard.Adornee = root
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0
        billboard.Size = UDim2.fromOffset(300, 34)
        billboard.StudsOffset = Vector3.new(0, 3.8, 0)
        billboard.Parent = Shared.playerGui

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(220, 140, 40)
        label.TextStrokeTransparency = 0.15
        label.TextSize = 11
        label.Text = "SIDE QUEST NPC | " .. tostring(info.name) .. " | STUDS: ?"
        label.Parent = billboard

        sideQuestESPObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
    end

    local function inspectSideQuestModel(model)
        if not model or not model.Parent or not model:IsA("Model") then
            return
        end

        if not getSideQuestNPCInfo(model) then
            return
        end

        -- ReplicatedStorage templates are handled by the virtual-marker
        -- scanner below; live ESP objects should only target Workspace NPCs.
        if not model:IsDescendantOf(workspace) then
            return
        end

        sideQuestCandidates[model] = true

        if Config.ArcaneSideQuestESP then
            createSideQuestESP(model)
        end
    end

    local sideQuestVirtualESPObjects = {}
    local sideQuestTemplatesScanned = false

    local function destroySideQuestVirtualESP(key)
        local data = sideQuestVirtualESPObjects[key]

        if not data then
            return
        end

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

        if data.anchor then
            pcall(function()
                data.anchor:Destroy()
            end)
        end

        sideQuestVirtualESPObjects[key] = nil
    end

    local function createSideQuestVirtualESP(model)
        if not Config.ArcaneSideQuestESP then
            return
        end

        if not model
            or not model:IsA("Model")
            or model:IsDescendantOf(workspace) then
            return
        end

        local info = getSideQuestNPCInfo(model)
        local root = getRoot(model)

        if not info or not root then
            return
        end

        local position = root.Position

        -- Ignore obvious staging positions. Real Arcane templates use
        -- actual world coordinates, while utility figures often sit near 0,0,0.
        if math.abs(position.X) < 5
            and math.abs(position.Y) < 5
            and math.abs(position.Z) < 5 then
            return
        end

        local key = model:GetFullName()

        if sideQuestVirtualESPObjects[key] then
            return
        end

        local anchor = Instance.new("Part")
        anchor.Name = "SolarSideQuestVirtualAnchor"
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(1, 1, 1)
        anchor.CFrame = CFrame.new(position)
        anchor.Parent = workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarSideQuestVirtualESPInfo"
        billboard.Adornee = anchor
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0
        billboard.Size = UDim2.fromOffset(300, 34)
        billboard.StudsOffset = Vector3.new(0, 3.8, 0)
        billboard.Parent = Shared.playerGui

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(220, 140, 40)
        label.TextStrokeTransparency = 0.15
        label.TextSize = 11
        label.Text = "SIDE QUEST NPC | "
            .. tostring(info.name)
            .. " | STUDS: ?"
        label.Parent = billboard

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarSideQuestVirtualHighlight"
        highlight.Adornee = anchor
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = Color3.fromRGB(220, 140, 40)
        highlight.OutlineColor = Color3.fromRGB(220, 140, 40)
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = workspace

        sideQuestVirtualESPObjects[key] = {
            source = model,
            anchor = anchor,
            billboard = billboard,
            label = label,
            highlight = highlight,
            position = position,
            name = info.name,
        }
    end

    local function scanSideQuestTemplateSources()
        if not Config.ArcaneSideQuestESP
            or sideQuestTemplatesScanned then
            return
        end

        sideQuestTemplatesScanned = true

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")
        local objects = rs and rs:FindFirstChild("Objects")

        local function scanFolder(folder, recursive)
            if not folder then
                return
            end

            local source = recursive
                and folder:GetDescendants()
                or folder:GetChildren()

            for _, model in ipairs(source) do
                if model:IsA("Model")
                    and model:FindFirstChildOfClass("Humanoid") then
                    createSideQuestVirtualESP(model)
                end
            end
        end

        scanFolder(objects, true)
        scanFolder(rs and rs:FindFirstChild("UnloadEnemies"), false)
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
        billboard.MaxDistance = 0
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

    -------------------------------------------------
    -- TARGETED WORLD RESCAN
    -------------------------------------------------
    -- Do not call Workspace.Map:GetDescendants() repeatedly.
    -- That can walk a very large streamed map and freeze the client.
    local function scanTargetedWorldSources()
        local npcFolder = workspace:FindFirstChild("NPCs")
        if npcFolder then
            for _, model in ipairs(npcFolder:GetChildren()) do
                inspectModel(model)
                inspectSideQuestModel(model)
            end
        end

        local enemiesFolder = workspace:FindFirstChild("Enemies")
        if enemiesFolder then
            for _, model in ipairs(enemiesFolder:GetChildren()) do
                inspectModel(model)
            end
        end


        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")

        if rs then
            local unloadEnemies = rs:FindFirstChild("UnloadEnemies")

            if unloadEnemies and Config.ArcaneSideQuestESP then
                -- These are lightweight child-level NPC definitions with real
                -- world positions (NPCHitbox / SpawnPart).
                for _, model in ipairs(unloadEnemies:GetChildren()) do
                    if model:IsA("Model") then
                        inspectSideQuestModel(model)
                    end
                end
            end
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
            inspectSideQuestModel(model)

            task.delay(0.15, function()
                if model and model.Parent then
                    inspectModel(model)
                    inspectChest(model)
                    inspectSideQuestModel(model)
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
            sideQuestCandidates[instance] = nil
            destroySideQuestESP(instance)
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
        scanTargetedWorldSources()

        if Config.ArcaneChestESP and hasAnyChestFilterEnabled(Config) then
            scanSelectedChests()
        end

        if Config.ArcaneSideQuestESP then
            scanSideQuestTemplateSources()
        end

        -- Everything seen during the initial scan is considered already alive.
        task.delay(0.25, function()
            initializedBossState = true
        end)
    end)

    local lastChestFilterSignature = nil
    local lastChestESPEnabled = Config.ArcaneChestESP == true

    local function getChestFilterSignature()
        local parts = {}

        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            parts[#parts + 1] = Config.ArcaneChestFilter[chestType] == true
                and "1"
                or "0"
        end

        return table.concat(parts, "")
    end

    -- Keep a lightweight targeted world scan running. This is intentionally
    -- separate from the 2-second status/lifecycle loop so detection
    -- continues even when Arcane adds/rebuilds streamed objects.
    task.spawn(function()
        while true do
            task.wait(1.5)

            local currentChestFilterSignature = getChestFilterSignature()
            local chestFilterChanged = currentChestFilterSignature ~= lastChestFilterSignature
            local chestESPChanged = Config.ArcaneChestESP ~= lastChestESPEnabled

            lastChestFilterSignature = currentChestFilterSignature
            lastChestESPEnabled = Config.ArcaneChestESP == true

            if Config.ArcaneBossESP
                or Config.ArcaneSideQuestESP then
                pcall(scanTargetedWorldSources)
            end

            -- Chest scanning is isolated from NPC/Boss scanning.
            -- It happens only when the selected filter or Chest ESP state changes.
            if chestFilterChanged or chestESPChanged then
                if Config.ArcaneChestESP
                    and hasAnyChestFilterEnabled(Config) then
                    pcall(scanSelectedChests)
                else
                    table.clear(chestCandidates)

                    for target in pairs(chestESPObjects) do
                        destroyChestESP(target)
                    end
                end
            end

            if Config.ArcaneSideQuestESP then
                pcall(scanSideQuestTemplateSources)
            end
        end
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

            local sideQuestDetected = 0

            if Config.ArcaneSideQuestESP then
                for model in pairs(sideQuestESPObjects) do
                    if model.Parent then
                        sideQuestDetected += 1
                    end
                end
            end

            statusLabel.Text = ("Boss: %d | Chests: %d | Side NPC: %d"):format(
                detected,
                chestDetected,
                sideQuestDetected
            )
        end
    end)



    task.spawn(function()
        while true do
            task.wait(0.5)

            if Config.ArcaneSideQuestESP then
                for model in pairs(sideQuestCandidates) do
                    if not model.Parent then
                        sideQuestCandidates[model] = nil
                        destroySideQuestESP(model)
                    else
                        createSideQuestESP(model)
                    end
                end
            else
                sideQuestTemplatesScanned = false

                for model in pairs(sideQuestESPObjects) do
                    destroySideQuestESP(model)
                end

                for key in pairs(sideQuestVirtualESPObjects) do
                    destroySideQuestVirtualESP(key)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)

            if Config.ArcaneChestESP
                and hasAnyChestFilterEnabled(Config) then
                for target in pairs(chestCandidates) do
                    if not target.Parent then
                        chestCandidates[target] = nil
                        destroyChestESP(target)
                    else
                        local chestType = getChestTypeFast(target) or getChestType(target)

                        if isChestFilterEnabled(Config, chestType) then
                            createChestESP(target)
                        else
                            chestCandidates[target] = nil
                            destroyChestESP(target)
                        end
                    end
                end
            else
                -- No selected type = zero chest candidates and zero scanning work.
                table.clear(chestCandidates)

                for target in pairs(chestESPObjects) do
                    destroyChestESP(target)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.25)

            if Config.ArcaneSideQuestESP then
                local character = Shared.player.Character
                local playerRoot = character
                    and character:FindFirstChild("HumanoidRootPart")

                for key, data in pairs(sideQuestVirtualESPObjects) do
                    if not data.anchor
                        or not data.anchor.Parent
                        or not data.source
                        or not data.source.Parent then
                        destroySideQuestVirtualESP(key)
                    else
                        local sourceRoot = getRoot(data.source)

                        if sourceRoot then
                            local position = sourceRoot.Position

                            if (position - data.position).Magnitude > 0.5 then
                                data.position = position
                                data.anchor.CFrame = CFrame.new(position)
                            end

                            local distanceText = "STUDS: ?"

                            if playerRoot then
                                distanceText = ("STUDS: %d"):format(
                                    math.floor(
                                        (playerRoot.Position - position).Magnitude
                                    )
                                )
                            end

                            data.label.Text = "SIDE QUEST NPC | "
                                .. tostring(data.name)
                                .. " | "
                                .. distanceText
                        end
                    end
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

            if not Config.ArcaneChestESP
                or not hasAnyChestFilterEnabled(Config) then
                continue
            end

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


    task.spawn(function()
        while true do
            task.wait(0.25)

            if Config.ArcaneSideQuestESP then
                local character = Shared.player.Character
                local playerRoot = character
                    and character:FindFirstChild("HumanoidRootPart")

                if playerRoot then
                    for model, data in pairs(sideQuestESPObjects) do
                        local root = getRoot(model)
                        local info = getSideQuestNPCInfo(model)

                        if not model.Parent or not root or not info then
                            destroySideQuestESP(model)
                        else
                            data.label.Text = "SIDE QUEST NPC | "
                                .. tostring(info.name)
                                .. " | STUDS: "
                                .. tostring(math.floor(
                                    (playerRoot.Position - root.Position).Magnitude
                                ))
                        end
                    end
                end
            end
        end
    end)


    -------------------------------------------------
    -- AUTO FISHING
    -------------------------------------------------

    local function findFishingRod()
        local character = Shared.player.Character

        local function isFishingRod(tool)
            if not tool:IsA("Tool") then
                return false
            end

            local name = normalizeName(tool.Name)

            return name:find("fishingrod", 1, true) ~= nil
                or name == "rod"
                or name:find("woodenrod", 1, true) ~= nil
                or name:find("bronzerod", 1, true) ~= nil
                or name:find("collectorsrod", 1, true) ~= nil
                or name:find("fishmongersrod", 1, true) ~= nil
        end

        if character then
            for _, child in ipairs(character:GetChildren()) do
                if isFishingRod(child) then
                    return child
                end
            end
        end

        local backpack = Shared.player:FindFirstChildOfClass("Backpack")

        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if isFishingRod(child) then
                    return child
                end
            end
        end

        return nil
    end

    local function equipFishingRod()
        local rod = findFishingRod()

        if not rod then
            return nil
        end

        local character = Shared.player.Character
        local humanoid = character
            and character:FindFirstChildOfClass("Humanoid")

        if humanoid and rod.Parent ~= character then
            pcall(function()
                humanoid:EquipTool(rod)
            end)
            task.wait(0.2)
        end

        return rod
    end

    local function clickMouse1()
        if type(mouse1click) == "function" then
            local ok = pcall(function()
                mouse1click()
            end)

            if ok then
                return true
            end
        end

        local camera = workspace.CurrentCamera
        local virtualInputManager = game:GetService("VirtualInputManager")

        if not camera or not virtualInputManager then
            return false
        end

        local viewport = camera.ViewportSize
        local x = math.floor(viewport.X * 0.5)
        local y = math.floor(viewport.Y * 0.5)

        local okDown = pcall(function()
            virtualInputManager:SendMouseButtonEvent(
                x, y, 0, true, game, 0
            )
        end)

        local okUp = pcall(function()
            virtualInputManager:SendMouseButtonEvent(
                x, y, 0, false, game, 0
            )
        end)

        return okDown and okUp
    end

    local function detectFishingResult()
        local camera = workspace.CurrentCamera
        local guiService = game:GetService("GuiService")

        if not camera or not guiService then
            return false
        end

        local viewport = camera.ViewportSize
        local x = math.floor(viewport.X * 0.5)
        local y = math.floor(viewport.Y * 0.5)

        local ok, objects = pcall(function()
            return guiService:GetGuiObjectsAtPosition(x, y)
        end)

        if not ok or type(objects) ~= "table" then
            return false
        end

        local keywords = {
            "fish",
            "junk",
            "treasure",
            "sunken",
        }

        for _, object in ipairs(objects) do
            local name = normalizeName(object.Name)
            local text = ""

            if object:IsA("TextLabel")
                or object:IsA("TextButton") then
                text = normalizeName(object.Text)
            end

            for _, keyword in ipairs(keywords) do
                if name:find(keyword, 1, true)
                    or text:find(keyword, 1, true) then
                    return true
                end
            end
        end

        return false
    end

    task.spawn(function()
        while true do
            task.wait(0.25)

            if Config.ArcaneAutoFishing then
                fishingStatusLabel.Text = "Status: Waiting for fishing remotes..."
            else
                fishingStatusLabel.Text = "Status: OFF | Waiting for fishing remotes."
            end
        end
    end)

    return true
end

return Arcane
