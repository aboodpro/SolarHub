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
    -- Real Arcane Odyssey fishing flow discovered through RemoteSpy:
    -- Equip:
    --   RS.Remotes.Combat.ChangeToolState -> player, rodName, "Equip"
    -- Cast / Reel:
    --   RS.Remotes.Misc.ToolAction -> player, rodName
    -- Server fishing state:
    --   RS.Remotes.Misc.FishEvent -> player, "Bump" / "Bite" / "Complete"
    --
    -- IMPORTANT:
    -- We do NOT detect the "!" GUI. Bite is driven by FishEvent.

    local replicatedStorageFishing = game:GetService("ReplicatedStorage")
    local rsFishing = replicatedStorageFishing:FindFirstChild("RS")
    local remotesFishing = rsFishing and rsFishing:FindFirstChild("Remotes")
    local miscRemotesFishing = remotesFishing and remotesFishing:FindFirstChild("Misc")
    local combatRemotesFishing = remotesFishing and remotesFishing:FindFirstChild("Combat")

    local toolActionRemote = miscRemotesFishing
        and miscRemotesFishing:FindFirstChild("ToolAction")

    local fishEventRemote = miscRemotesFishing
        and miscRemotesFishing:FindFirstChild("FishEvent")

    local changeToolStateRemote = combatRemotesFishing
        and combatRemotesFishing:FindFirstChild("ChangeToolState")

    local fishingState = "OFF"
    local biteReceived = false
    local completeReceived = false
    local fishingEventConnection = nil

    local function setFishingStatus(text)
        if fishingStatusLabel then
            fishingStatusLabel.Text = "Status: " .. tostring(text)
        end
    end

    local function getFishingRodName(tool)
        if not tool or not tool:IsA("Tool") then
            return nil
        end

        return tool.Name
    end

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

        -- Also mirror the exact state remote observed in RemoteSpy.
        if changeToolStateRemote
            and changeToolStateRemote:IsA("RemoteEvent") then

            local rodName = getFishingRodName(rod)

            if rodName then
                pcall(function()
                    changeToolStateRemote:FireServer(
                        Shared.player,
                        rodName,
                        "Equip"
                    )
                end)
            end
        end

        return rod
    end

    local function useFishingTool(rod)
        if not toolActionRemote
            or not toolActionRemote:IsA("RemoteEvent") then
            return false
        end

        local rodName = getFishingRodName(rod)

        if not rodName then
            return false
        end

        local ok = pcall(function()
            -- This exact call matches the observed Cast/Reel RemoteSpy entry.
            toolActionRemote:FireServer(
                Shared.player,
                rodName
            )
        end)

        return ok
    end

    local function installFishingEventListener()
        if fishingEventConnection then
            return true
        end

        if not fishEventRemote
            or not fishEventRemote:IsA("RemoteEvent") then
            return false
        end

        fishingEventConnection = fishEventRemote.OnClientEvent:Connect(
            function(...)
                local args = {...}

                -- RemoteSpy showed:
                -- [1] = player, [2] = "Bump"/"Bite"/"Complete"
                local state = args[2]

                if state == "Bump" then
                    if fishingState == "CASTING"
                        or fishingState == "WAITING_BITE" then
                        fishingState = "WAITING_BITE"
                        setFishingStatus("Waiting for Bite...")
                    end

                    return
                end

                if state == "Bite" then
                    biteReceived = true
                    completeReceived = false
                    fishingState = "REELING"

                    local fishName = args[3]
                    if fishName then
                        setFishingStatus(
                            "Bite! Reeling " .. tostring(fishName) .. "..."
                        )
                    else
                        setFishingStatus("Bite! Reeling...")
                    end

                    return
                end

                if state == "Complete" then
                    completeReceived = true
                    fishingState = "COMPLETE"
                    setFishingStatus("Catch complete.")
                end
            end
        )

        return true
    end

    installFishingEventListener()

    local function doFishingCycle()
        if not Config.ArcaneAutoFishing then
            return false
        end

        if not toolActionRemote
            or not toolActionRemote:IsA("RemoteEvent") then
            setFishingStatus("ERROR: ToolAction RemoteEvent not found.")
            return false
        end

        if not fishEventRemote
            or not fishEventRemote:IsA("RemoteEvent") then
            setFishingStatus("ERROR: FishEvent RemoteEvent not found.")
            return false
        end

        local rod = equipFishingRod()

        if not rod then
            setFishingStatus("Waiting for fishing rod...")
            task.wait(0.5)
            return false
        end

        biteReceived = false
        completeReceived = false

        fishingState = "CASTING"
        setFishingStatus("Casting...")

        -- First ToolAction = Cast.
        if not useFishingTool(rod) then
            setFishingStatus("ERROR: Cast failed.")
            task.wait(0.5)
            return false
        end

        fishingState = "WAITING_BITE"
        setFishingStatus("Waiting for Bite...")

        -- Wait for the real FishEvent.Bite.
        local biteDeadline = os.clock() + 75

        while Config.ArcaneAutoFishing
            and not biteReceived
            and os.clock() < biteDeadline do

            task.wait(0.05)
        end

        if not Config.ArcaneAutoFishing then
            fishingState = "OFF"
            setFishingStatus("OFF")
            return false
        end

        if not biteReceived then
            fishingState = "TIMEOUT"
            setFishingStatus("No Bite received. Recasting...")
            task.wait(0.4)
            return false
        end

        -- Once Bite arrives, spam the SAME ToolAction used by manual clicks.
        local reelDeadline = os.clock() + 20

        while Config.ArcaneAutoFishing
            and not completeReceived
            and os.clock() < reelDeadline do

            useFishingTool(rod)
            task.wait(0.08)
        end

        if not Config.ArcaneAutoFishing then
            fishingState = "OFF"
            setFishingStatus("OFF")
            return false
        end

        if not completeReceived then
            fishingState = "REEL_TIMEOUT"
            setFishingStatus("Reel timeout. Recasting...")
            task.wait(0.5)
            return false
        end

        task.wait(0.4)
        return true
    end

    task.spawn(function()
        while true do
            if not Config.ArcaneAutoFishing then
                fishingState = "OFF"
                biteReceived = false
                completeReceived = false

                setFishingStatus(
                    "OFF | Cast → Bite → Reel → Complete"
                )

                task.wait(0.25)
            else
                if fishingState == "OFF"
                    or fishingState == "COMPLETE"
                    or fishingState == "TIMEOUT"
                    or fishingState == "REEL_TIMEOUT" then

                    doFishingCycle()
                else
                    task.wait(0.1)
                end
            end
        end
    end)

    return true
end

return Arcane
