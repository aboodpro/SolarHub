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

    -- Arcane Odyssey chest models use a Base part as the physical anchor.
    -- Walk upward so a tagged Base/Prompt/etc. resolves to the actual chest
    -- model instead of accidentally selecting an unrelated nested model.
    local current = object

    while current and current ~= workspace do
        if current:IsA("Model") then
            local base = current:FindFirstChild("Base")

            if base and base:IsA("BasePart") and looksLikeChestModel(current) then
                return current
            end

            if looksLikeChestModel(current) then
                return current
            end
        end

        current = current.Parent
    end

    if object:IsA("BasePart") then
        local normalized = normalizeName(object.Name)

        if normalized == "base"
            or normalized:find("chest", 1, true)
            or normalized:find("treasure", 1, true)
            or normalized:find("sealedchest", 1, true) then
            return object:IsDescendantOf(workspace) and object or nil
        end
    end

    return nil
end

local function getChestRoot(target)
    if target:IsA("Model") then
        local base = target:FindFirstChild("Base")

        if base and base:IsA("BasePart") then
            return base
        end

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
        local CollectionService = game:GetService("CollectionService")
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Players = game:GetService("Players")

        setText(
            "Running Arcane DEEP DEBUG...\\n"
            .. "Scans Arcane systems: bosses, chests, side quest NPCs/locations, templates, remotes and fishing."
        )

        local results = {
            environment = {},
            folders = {},
            activeNPCs = {},
            sideQuest = {},
            knownMissing = {},
            npcLocations = {},
            bosses = {},
            bossTemplates = {},
            chests = {},
            remotes = {},
            fishing = {},
            config = {},
        }

        local function add(list, value, limit)
            if #list < limit then
                table.insert(list, tostring(value))
            end
        end

        local function pos(root)
            if not root then
                return "<NO_POS>"
            end

            local p = root.Position
            return ("%.0f %.0f %.0f"):format(p.X, p.Y, p.Z)
        end

        local function attrs(instance)
            local ok, data = pcall(function()
                return instance:GetAttributes()
            end)

            if not ok or type(data) ~= "table" then
                return "ATTRS=<ERROR>"
            end

            local parts = {}

            for key, value in pairs(data) do
                local normalized = normalizeName(key)

                if normalized:find("quest",1,true)
                    or normalized:find("npc",1,true)
                    or normalized:find("boss",1,true)
                    or normalized:find("chest",1,true)
                    or normalized:find("open",1,true)
                    or normalized:find("name",1,true)
                    or normalized:find("type",1,true)
                    or normalized:find("rarity",1,true) then
                    table.insert(parts, tostring(key) .. "=" .. tostring(value))
                end
            end

            table.sort(parts)
            return #parts > 0 and "ATTRS=" .. table.concat(parts, ";") or "ATTRS=<none>"
        end

        local function tags(instance)
            local ok, data = pcall(function()
                return CollectionService:GetTags(instance)
            end)

            if not ok or type(data) ~= "table" or #data == 0 then
                return "TAGS=<none>"
            end

            table.sort(data)
            return "TAGS=" .. table.concat(data, ",")
        end

        local function interaction(chest)
            local parts = {}

            for _, child in ipairs(chest:GetDescendants()) do
                if child:IsA("ProximityPrompt") then
                    table.insert(
                        parts,
                        ("PROMPT=%s|Action=%s|Object=%s|Enabled=%s"):format(
                            child.Name,
                            child.ActionText,
                            child.ObjectText,
                            tostring(child.Enabled)
                        )
                    )
                elseif child:IsA("ClickDetector") then
                    table.insert(parts, "CLICK=" .. child.Name)
                end
            end

            return #parts > 0
                and table.concat(parts, " || ")
                or "INTERACTION=<none>"
        end

        local function opened(chest)
            if openedChests[chest] then
                return "OPENED=tracked"
            end

            local ok = pcall(function()
                return hasChestOpenedMarker(chest)
            end)

            if ok and hasChestOpenedMarker(chest) then
                return "OPENED=marker"
            end

            return "OPENED=no"
        end

        table.insert(results.environment, "Player=" .. tostring(Players.LocalPlayer))
        table.insert(results.environment, "PlaceId=" .. tostring(game.PlaceId))
        table.insert(results.environment, "GameId=" .. tostring(game.GameId))
        table.insert(results.environment, "JobId=" .. tostring(game.JobId))
        table.insert(results.environment, "GameLoaded=" .. tostring(game:IsLoaded()))

        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            table.insert(
                results.config,
                ("%s | Filter=%s | ScanDistance=%d"):format(
                    chestType,
                    tostring(Config.ArcaneChestFilter[chestType] == true),
                    getChestScanDistance(chestType)
                )
            )
        end

        table.insert(
            results.config,
            "BossESP=" .. tostring(Config.ArcaneBossESP)
                .. " | ChestESP=" .. tostring(Config.ArcaneChestESP)
                .. " | SideQuestESP=" .. tostring(Config.ArcaneSideQuestESP)
                .. " | AutoFishing=" .. tostring(Config.ArcaneAutoFishing)
        )

        local npcFolder = workspace:FindFirstChild("NPCs")
        local enemiesFolder = workspace:FindFirstChild("Enemies")
        local map = workspace:FindFirstChild("Map")
        local seaContent = map and map:FindFirstChild("SeaContent")
        local npcLocationsFolder = seaContent and seaContent:FindFirstChild("NPCLocations")
        local questObjectsFolder = map and map:FindFirstChild("QuestObjects")

        local rs = ReplicatedStorage:FindFirstChild("RS")
        local objects = rs and rs:FindFirstChild("Objects")
        local unloadEnemies = rs and rs:FindFirstChild("UnloadEnemies")
        local remotesFolder = rs and rs:FindFirstChild("Remotes")

        local function folderLine(name, folder)
            if not folder then
                return name .. " = <MISSING>"
            end

            return ("%s | Children=%d | Descendants=<not-counted> | %s"):format(
                name,
                #folder:GetChildren(),
                folder:GetFullName()
            )
        end

        add(results.folders, folderLine("Workspace.NPCs", npcFolder), 50)
        add(results.folders, folderLine("Workspace.Enemies", enemiesFolder), 50)
        add(results.folders, folderLine("Workspace.Map", map), 50)
        add(results.folders, folderLine("Workspace.Map.SeaContent", seaContent), 50)
        add(results.folders, folderLine("Workspace.Map.SeaContent.NPCLocations", npcLocationsFolder), 50)
        add(results.folders, folderLine("Workspace.Map.QuestObjects", questObjectsFolder), 50)
        add(results.folders, folderLine("RS", rs), 50)
        add(results.folders, folderLine("RS.Objects", objects), 50)
        add(results.folders, folderLine("RS.UnloadEnemies", unloadEnemies), 50)
        add(results.folders, folderLine("RS.Remotes", remotesFolder), 50)

        local function inspectNPC(model, source)
            if not model:IsA("Model")
                or not model:FindFirstChildOfClass("Humanoid") then
                return
            end

            local root = getRoot(model)
            local info = getSideQuestNPCInfo(model)

            add(
                results.activeNPCs,
                ("%s | SOURCE=%s | POS=%s | %s | %s | %s"):format(
                    model.Name,
                    source,
                    pos(root),
                    attrs(model),
                    tags(model),
                    model:GetFullName()
                ),
                350
            )

            if info then
                add(
                    results.sideQuest,
                    ("%s | TYPE=%s | SOURCE=%s | POS=%s | %s"):format(
                        info.name,
                        info.detectionType,
                        source,
                        pos(root),
                        model:GetFullName()
                    ),
                    500
                )
            end
        end

        if npcFolder then
            for _, model in ipairs(npcFolder:GetChildren()) do
                inspectNPC(model, "Workspace.NPCs")
            end
        end

        if enemiesFolder then
            for _, model in ipairs(enemiesFolder:GetChildren()) do
                inspectNPC(model, "Workspace.Enemies")
            end
        end

        task.wait()

        local spawningEnemies = objects and objects:FindFirstChild("SpawningEnemies")
        local bossFigures = objects and objects:FindFirstChild("BossFigures")

        if spawningEnemies then
            for _, model in ipairs(spawningEnemies:GetChildren()) do
                if model:IsA("Model") then
                    local info = getBossInfo(model)
                    local bossValue = model:FindFirstChild("Boss")
                    local miniValue = model:FindFirstChild("Miniboss")

                    if info or bossValue or miniValue then
                        add(
                            results.bossTemplates,
                            ("%s | CLASS=%s | Boss=%s | Mini=%s | %s"):format(
                                model.Name,
                                info and info.bossClass or "?",
                                tostring(bossValue and bossValue.Value),
                                tostring(miniValue and miniValue.Value),
                                model:GetFullName()
                            ),
                            400
                        )
                    end
                end
            end
        end

        if bossFigures then
            for _, model in ipairs(bossFigures:GetChildren()) do
                if model:IsA("Model") then
                    local bossValue = model:FindFirstChild("Boss")
                    local miniValue = model:FindFirstChild("Miniboss")

                    if bossValue or miniValue then
                        add(
                            results.bossTemplates,
                            ("%s | Boss=%s | Mini=%s | %s"):format(
                                model.Name,
                                tostring(bossValue and bossValue.Value),
                                tostring(miniValue and miniValue.Value),
                                model:GetFullName()
                            ),
                            400
                        )
                    end
                end
            end
        end

        if enemiesFolder then
            for _, model in ipairs(enemiesFolder:GetChildren()) do
                if model:IsA("Model") then
                    local info = getBossInfo(model)

                    if info then
                        add(
                            results.bosses,
                            ("%s | %s | HP=%d/%d | POS=%s | %s"):format(
                                info.name,
                                info.bossClass,
                                math.floor(info.humanoid.Health),
                                math.floor(info.humanoid.MaxHealth),
                                pos(info.root),
                                model:GetFullName()
                            ),
                            250
                        )
                    end
                end
            end
        end

        task.wait()

        -- Chest diagnosis. Use the known AO chest structure (Base/Open/Prompt)
        -- in addition to the three CollectionService tags.
        local chestSeen = {}

        local function addChestDiagnosis(chest, source)
            if not chest
                or not chest:IsDescendantOf(workspace)
                or chestSeen[chest] then
                return
            end

            chestSeen[chest] = true

            local root = getChestRoot(chest)
            local chestType = getChestType(chest)
            local live = hasLiveChestInteraction(chest)
            local distance = "DIST=?"
            local playerRoot = getLocalPlayerRoot()
            local base = chest:IsA("Model") and chest:FindFirstChild("Base")
            local prompt = chest:FindFirstChild("Prompt", true)
            local open = chest:FindFirstChild("Open", true)

            if playerRoot and root then
                distance = ("DIST=%.0f"):format(
                    (playerRoot.Position - root.Position).Magnitude
                )
            end

            add(
                results.chests,
                ("%s | SOURCE=%s | TYPE=%s | LIVE=%s | BASE=%s | PROMPT=%s | OPEN=%s | %s | %s | %s | %s | %s"):format(
                    chest.Name,
                    tostring(source),
                    tostring(chestType),
                    tostring(live),
                    tostring(base and base:IsA("BasePart")),
                    tostring(prompt and prompt.ClassName or "nil"),
                    tostring(open ~= nil),
                    distance,
                    opened(chest),
                    pos(root),
                    attrs(chest),
                    tags(chest),
                    interaction(chest)
                ),
                900
            )
        end

        for _, tagName in ipairs({"Chests", "Prompt_Chest", "BuriedChests"}) do
            local tagged = CollectionService:GetTagged(tagName)

            for _, object in ipairs(tagged) do
                addChestDiagnosis(
                    getChestTarget(object),
                    "TAG:" .. tagName
                )
            end
        end

        -- Also inspect Workspace-root chest models. This matches the public
        -- AO ESP implementations that resolve chests by their name/Base.
        for _, object in ipairs(workspace:GetChildren()) do
            if object:IsA("Model") then
                local normalized = normalizeName(object.Name)

                if normalized:find("chest", 1, true)
                    or object:FindFirstChild("Base") then
                    addChestDiagnosis(object, "WORKSPACE_CHILD")
                end
            end
        end

        task.wait()

        -- NPC location registry with every ObjectValue link.
        if npcLocationsFolder then
            for index, object in ipairs(npcLocationsFolder:GetDescendants()) do
                if index % 150 == 0 then
                    task.wait()
                end

                if object:IsA("BasePart") then
                    local links = {}

                    for _, child in ipairs(object:GetChildren()) do
                        if child:IsA("ObjectValue") then
                            local valueName = child.Value and child.Value.Name or "nil"
                            local childAttrs = child:GetAttributes()
                            local attrParts = {}

                            for key, value in pairs(childAttrs) do
                                table.insert(
                                    attrParts,
                                    tostring(key) .. "=" .. tostring(value)
                                )
                            end

                            table.sort(attrParts)

                            table.insert(
                                links,
                                child.Name
                                    .. "="
                                    .. valueName
                                    .. (
                                        #attrParts > 0
                                            and ("{" .. table.concat(attrParts, ";") .. "}")
                                            or ""
                                    )
                            )
                        elseif child:IsA("StringValue")
                            or child:IsA("IntValue")
                            or child:IsA("NumberValue")
                            or child:IsA("BoolValue") then
                            table.insert(
                                links,
                                child.Name .. "=" .. tostring(child.Value)
                            )
                        else
                            table.insert(
                                links,
                                child.Name .. ":" .. child.ClassName
                            )
                        end
                    end

                    local p = object.Position

                    add(
                        results.npcLocations,
                        ("%s | POS=%.0f %.0f %.0f | LINKS=[%s] | %s"):format(
                            object.Name,
                            p.X, p.Y, p.Z,
                            table.concat(links, ","),
                            object:GetFullName()
                        ),
                        600
                    )
                end
            end
        end

        if questObjectsFolder then
            for _, object in ipairs(questObjectsFolder:GetChildren()) do
                add(results.sideQuest, "QUEST_OBJECT | " .. object:GetFullName(), 500)
            end
        end

        task.wait()

        -- Every RemoteEvent/RemoteFunction under RS.Remotes plus fishing references.
        if remotesFolder then
            for index, instance in ipairs(remotesFolder:GetDescendants()) do
                if index % 200 == 0 then
                    task.wait()
                end

                if instance:IsA("RemoteEvent")
                    or instance:IsA("RemoteFunction") then

                    add(
                        results.remotes,
                        instance.ClassName .. " | " .. instance:GetFullName(),
                        700
                    )
                end
            end

            for _, name in ipairs({
                "FishEvent",
                "ToolAction",
                "ChangeToolState",
                "Notification",
            }) do
                local found = nil

                pcall(function()
                    found = remotesFolder:FindFirstChild(name, true)
                end)

                add(
                    results.fishing,
                    name .. " | " .. (
                        found
                            and (found.ClassName .. " | " .. found:GetFullName())
                            or "<MISSING>"
                    ),
                    20
                )
            end
        end

        task.wait()

        -- Deep side-quest template discovery.
        local templateSeen = {}

        local function scanTemplates(folder, recursive)
            if not folder then
                return
            end

            local source = recursive
                and folder:GetDescendants()
                or folder:GetChildren()

            for index, model in ipairs(source) do
                if index % 150 == 0 then
                    task.wait()
                end

                if model:IsA("Model")
                    and model:FindFirstChildOfClass("Humanoid") then

                    local info = getSideQuestNPCInfo(model)

                    if info then
                        local key = model:GetFullName()

                        if not templateSeen[key] then
                            templateSeen[key] = true

                            add(
                                results.sideQuest,
                                ("%s | TEMPLATE=%s | POS=%s | %s"):format(
                                    info.name,
                                    info.detectionType,
                                    pos(getRoot(model)),
                                    key
                                ),
                                700
                            )
                        end
                    end
                end
            end
        end

        scanTemplates(objects, true)
        scanTemplates(unloadEnemies, false)

        -- Report which hardcoded known side quest names have no hit anywhere
        -- in the targeted model/location sources.
        local knownFound = {}

        for _, line in ipairs(results.sideQuest) do
            local lower = normalizeName(line)

            for _, knownName in ipairs(SIDE_QUEST_NPC_NAMES) do
                if lower:find(normalizeName(knownName), 1, true) then
                    knownFound[normalizeName(knownName)] = true
                end
            end
        end

        for _, knownName in ipairs(SIDE_QUEST_NPC_NAMES) do
            if not knownFound[normalizeName(knownName)] then
                add(
                    results.knownMissing,
                    knownName .. " | NO TARGETED MATCH",
                    100
                )
            end
        end

        local lines = {
            "SOLARHUB ARCANE DEEP DEBUG",
            "===========================",
            "Targeted diagnostic: world models, quest locations, chest validity, remotes, and config.",
            "",
            "ENVIRONMENT:",
        }

        local sections = {
            {"ENVIRONMENT", results.environment},
            {"CONFIG / CHEST DISTANCES", results.config},
            {"FOLDERS / COUNTS", results.folders},
            {"ACTIVE NPC MODELS", results.activeNPCs},
            {"SIDE QUEST NPCS / TEMPLATES / QUEST OBJECTS", results.sideQuest},
            {"KNOWN SIDE QUEST NPCS NOT FOUND", results.knownMissing},
            {"ACTIVE BOSSES", results.bosses},
            {"BOSS TEMPLATES", results.bossTemplates},
            {"LIVE / TAGGED CHESTS", results.chests},
            {"STATIC NPC LOCATIONS", results.npcLocations},
            {"ALL RS.REMOTES", results.remotes},
            {"FISHING REMOTES", results.fishing},
        }

        table.clear(lines)

        table.insert(lines, "SOLARHUB ARCANE DEEP DEBUG")
        table.insert(lines, "===========================")

        for _, sectionData in ipairs(sections) do
            local title = sectionData[1]
            local list = sectionData[2]

            table.insert(lines, "")
            table.insert(lines, ("%s (%d):"):format(title, #list))

            if #list == 0 then
                table.insert(lines, "<none>")
            else
                for _, line in ipairs(list) do
                    table.insert(lines, line)
                end
            end
        end

        table.insert(lines, "")
        table.insert(lines, "DIAGNOSTIC NOTES:")
        table.insert(lines, "1) Chest LIVE=false means SolarHub intentionally rejects that target.")
        table.insert(lines, "2) OPENED=tracked means this client saw the chest interaction and will not show it again.")
        table.insert(lines, "3) Static NPCLocations are checked for NPC/NPC2/NPC3 ObjectValue links.")
        table.insert(lines, "4) A live ESP cannot render a model that Roblox has not replicated/streamed to this client.")
        table.insert(lines, "5) Template/location data can be used for a virtual marker when a valid world position exists.")

        local finalText = table.concat(lines, "\\n")
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

        print("[Arcane] Deep debug scan finished.")
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

    -- Each chest type has an independent scan distance.
    -- 1,000,000 keeps the previous effectively-unlimited behavior.
    if type(Config.ArcaneChestScanDistance) ~= "table" then
        Config.ArcaneChestScanDistance = {}
    end

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        local distance = tonumber(Config.ArcaneChestScanDistance[chestType])

        if distance == nil then
            distance = 1000000
        end

        Config.ArcaneChestScanDistance[chestType] = math.clamp(
            math.floor(distance + 0.5),
            0,
            1000000
        )
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
    scanButton.Text = "SCAN ARCANE STRUCTURE"
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
    debugBox.Text = "Ready. Press SCAN ARCANE STRUCTURE."
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
                scanButton.Text = "SCAN ARCANE STRUCTURE"
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
        1060
    )

    UI.createToggle(
        chestSection,
        "Chest ESP",
        "Shows selected chests within each type's scan distance.",
        "ArcaneChestESP",
        32
    )

    local chestFilterTitle = Instance.new("TextLabel")
    chestFilterTitle.Size = UDim2.new(1, -16, 0, 22)
    chestFilterTitle.Position = UDim2.fromOffset(8, 78)
    chestFilterTitle.BackgroundTransparency = 1
    chestFilterTitle.Text = "Chest Filter + Scan Distance"
    chestFilterTitle.TextColor3 = Color3.fromRGB(205, 205, 215)
    chestFilterTitle.Font = Enum.Font.GothamBold
    chestFilterTitle.TextSize = 9
    chestFilterTitle.TextXAlignment = Enum.TextXAlignment.Left
    chestFilterTitle.Parent = chestSection

    local chestFilterButtons = {}
    local chestDistanceSliders = {}

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

    local rowStartY = 104
    local rowHeight = 74

    for index, chestType in ipairs(CHEST_TYPE_ORDER) do
        local rowY = rowStartY + ((index - 1) * rowHeight)

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -16, 0, 70)
        row.Position = UDim2.fromOffset(8, rowY)
        row.BackgroundTransparency = 1
        row.Parent = chestSection

        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 28)
        button.Position = UDim2.fromOffset(0, 0)
        button.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        button.BorderSizePixel = 0
        button.Text = ""
        button.Parent = row
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(16, 16)
        indicator.Position = UDim2.fromOffset(7, 6)
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

        local slider = UI.createSlider(
            row,
            "Scan Distance (0 - 1,000,000)",
            "ArcaneChestScanDistance_" .. chestType,
            0,
            1000000,
            0,
            31,
            220,
            function(value)
                Config.ArcaneChestScanDistance[chestType] = math.clamp(
                    math.floor(tonumber(value) or 1000000),
                    0,
                    1000000
                )
            end
        )

        slider.setValue(
            Config.ArcaneChestScanDistance[chestType]
        )

        chestDistanceSliders[chestType] = slider
    end

    local buttonsY = rowStartY + (#CHEST_TYPE_ORDER * rowHeight) + 4

    local selectAllButton = Instance.new("TextButton")
    selectAllButton.Size = UDim2.new(0.5, -12, 0, 28)
    selectAllButton.Position = UDim2.new(0, 4, 0, buttonsY)
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
    clearAllButton.Position = UDim2.new(0.5, 8, 0, buttonsY)
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
    local openedChests = {}


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

    local function getChestScanDistance(chestType)
        local distance = tonumber(
            Config.ArcaneChestScanDistance
                and Config.ArcaneChestScanDistance[chestType]
        )

        if distance == nil then
            distance = 1000000
        end

        return math.clamp(
            math.floor(distance + 0.5),
            0,
            1000000
        )
    end

    local function getLocalPlayerRoot()
        local character = Shared.player.Character

        return character
            and character:FindFirstChild("HumanoidRootPart")
    end

    local function isChestWithinScanDistance(target, chestType)
        local maxDistance = getChestScanDistance(chestType)
        local playerRoot = getLocalPlayerRoot()
        local chestRoot = getChestRoot(target)

        if not playerRoot or not chestRoot then
            return true
        end

        return (playerRoot.Position - chestRoot.Position).Magnitude
            <= maxDistance
    end

    local function hasLiveChestInteraction(chest)
        if not chest or not chest:IsDescendantOf(workspace) then
            return false
        end

        local root = getChestRoot(chest)
        if not root or not root:IsDescendantOf(workspace) then
            return false
        end

        -- Verified Arcane Odyssey chest structure:
        -- a live chest has a Base part and normally a Prompt child/object.
        -- Open is the game's opened-state marker.
        local base = chest:IsA("Model") and chest:FindFirstChild("Base")
        if not (base and base:IsA("BasePart") and base:IsDescendantOf(workspace)) then
            return false
        end

        if chest:FindFirstChild("Open", true) then
            return false
        end

        local prompt = chest:FindFirstChild("Prompt", true)

        if prompt then
            if prompt:IsA("ProximityPrompt") then
                return prompt.Enabled
            end

            return true
        end

        -- Fallback for versions/locations where the prompt is represented
        -- by a normal ClickDetector or another prompt-like object.
        if chest:FindFirstChildWhichIsA("ClickDetector", true) then
            return true
        end

        return true
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

        if not hasLiveChestInteraction(target) then
            destroyChestESP(target)
            return
        end

        if not isChestWithinScanDistance(target, chestType) then
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

    local function markChestOpened(chest)
        if not chest then
            return
        end

        openedChests[chest] = true
        chestCandidates[chest] = nil

        destroyChestESP(chest)
    end


    local function hasChestOpenedMarker(chest)
        if not chest then
            return false
        end

        -- Attribute markers, if the game sets one.
        local okAttrs, attrs = pcall(function()
            return chest:GetAttributes()
        end)

        if okAttrs and type(attrs) == "table" then
            for key, value in pairs(attrs) do
                local normalizedKey = normalizeChestText(key)

                if (normalizedKey == "opened"
                    or normalizedKey == "open"
                    or normalizedKey == "isopen"
                    or normalizedKey == "chestopened"
                    or normalizedKey == "openedchest")
                    and value == true then
                    return true
                end
            end
        end

        -- Arcane Odyssey uses an "Open" child when a chest has been taken.
        if chest:FindFirstChild("Open", true) then
            return true
        end

        -- Common replicated Value markers.
        for _, descendant in ipairs(chest:GetDescendants()) do
            local normalizedName = normalizeChestText(descendant.Name)

            if descendant:IsA("BoolValue")
                and (normalizedName == "opened"
                    or normalizedName == "open"
                    or normalizedName == "isopen"
                    or normalizedName == "chestopened"
                    or normalizedName == "openedchest")
                and descendant.Value == true then
                return true
            end

            if descendant:IsA("BoolValue")
                and normalizedName == "chestobj"
                and descendant.Value == true then
                return true
            end
        end

        return false
    end

    local proximityPromptService = game:GetService("ProximityPromptService")

    proximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if player and player ~= Shared.player then
            return
        end

        local chest = prompt and getChestTarget(prompt)

        if chest then
            markChestOpened(chest)
        end
    end)

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

        if not hasLiveChestInteraction(chest) then
            chestCandidates[chest] = nil
            destroyChestESP(chest)
            return
        end

        local chestType = fastType or getChestType(chest)

        if not isChestFilterEnabled(Config, chestType) then
            return
        end

        if openedChests[chest] then
            markChestOpened(chest)
            return
        end

        if hasChestOpenedMarker(chest) then
            markChestOpened(chest)
            return
        end

        if not isChestWithinScanDistance(chest, chestType) then
            chestCandidates[chest] = nil
            destroyChestESP(chest)
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

                    if object:IsDescendantOf(workspace) then
                        inspectChest(object)
                    end
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

    local function createSideQuestLocationVirtualESP(name, position, key, sourceLocation)
        if not Config.ArcaneSideQuestESP then
            return
        end

        if not name or not position then
            return
        end

        key = tostring(key)

        if sideQuestVirtualESPObjects[key] then
            return
        end

        local anchor = Instance.new("Part")
        anchor.Name = "SolarSideQuestLocationAnchor"
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(1, 1, 1)
        anchor.CFrame = CFrame.new(position)
        anchor.Parent = workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarSideQuestLocationESPInfo"
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
        label.Text = "SIDE QUEST NPC | " .. tostring(name) .. " | STUDS: ?"
        label.Parent = billboard

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarSideQuestLocationHighlight"
        highlight.Adornee = anchor
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = Color3.fromRGB(220, 140, 40)
        highlight.OutlineColor = Color3.fromRGB(220, 140, 40)
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = workspace

        sideQuestVirtualESPObjects[key] = {
            source = nil,
            location = sourceLocation,
            anchor = anchor,
            billboard = billboard,
            label = label,
            highlight = highlight,
            position = position,
            name = name,
            static = true,
        }
    end

    local function findKnownSideQuestName(value)
        local text = normalizeName(value)

        if text == "" then
            return nil
        end

        local exact = NORMALIZED_SIDE_QUEST_NPCS[text]

        if exact then
            return exact
        end

        for normalizedName, displayName in pairs(NORMALIZED_SIDE_QUEST_NPCS) do
            if text:find(normalizedName, 1, true) then
                return displayName
            end
        end

        return nil
    end

    local function getWorldPositionForLocationObject(instance)
        if instance:IsA("BasePart") then
            return instance.Position
        end

        if instance:IsA("Attachment") then
            return instance.WorldPosition
        end

        if instance:IsA("Model") then
            local root = getRoot(instance)

            if root then
                return root.Position
            end

            local ok, pivot = pcall(function()
                return instance:GetPivot()
            end)

            if ok then
                return pivot.Position
            end
        end

        local parent = instance.Parent

        while parent and parent ~= workspace do
            if parent:IsA("BasePart") then
                return parent.Position
            end

            if parent:IsA("Attachment") then
                return parent.WorldPosition
            end

            parent = parent.Parent
        end

        return nil
    end

    local function getSideQuestLocationNameFromNode(node)
        -- 1) The node itself and its full path can contain the NPC name.
        local knownName = findKnownSideQuestName(node.Name)

        if knownName then
            return knownName
        end

        knownName = findKnownSideQuestName(node:GetFullName())

        if knownName then
            return knownName
        end

        -- 2) Attributes on the location/object value.
        local okAttrs, attributes = pcall(function()
            return node:GetAttributes()
        end)

        if okAttrs and type(attributes) == "table" then
            for key, value in pairs(attributes) do
                knownName = findKnownSideQuestName(key)
                    or findKnownSideQuestName(value)

                if knownName then
                    return knownName
                end
            end
        end

        -- 3) Direct metadata children. ObjectValue.Value may be nil until
        -- the NPC is actually spawned, so never make Value the only source.
        for _, child in ipairs(node:GetChildren()) do
            knownName = findKnownSideQuestName(child.Name)

            if knownName then
                return knownName
            end

            if child:IsA("StringValue")
                or child:IsA("IntValue")
                or child:IsA("NumberValue")
                or child:IsA("BoolValue") then

                knownName = findKnownSideQuestName(child.Value)

                if knownName then
                    return knownName
                end
            elseif child:IsA("ObjectValue") then
                knownName = findKnownSideQuestName(child.Name)

                if not knownName and child.Value then
                    knownName = findKnownSideQuestName(child.Value.Name)
                        or findKnownSideQuestName(child.Value:GetFullName())
                end

                local okObjectAttrs, objectAttrs = pcall(function()
                    return child:GetAttributes()
                end)

                if okObjectAttrs and type(objectAttrs) == "table" then
                    for key, value in pairs(objectAttrs) do
                        knownName = findKnownSideQuestName(key)
                            or findKnownSideQuestName(value)

                        if knownName then
                            return knownName
                        end
                    end
                end
            end

            if knownName then
                return knownName
            end
        end

        return nil
    end

    local function scanSideQuestLocationRegistry()
        if not Config.ArcaneSideQuestESP then
            return
        end

        local map = workspace:FindFirstChild("Map")
        local seaContent = map and map:FindFirstChild("SeaContent")
        local npcLocations = seaContent and seaContent:FindFirstChild("NPCLocations")

        if not npcLocations then
            return
        end

        local seenLocationKeys = {}

        for index, object in ipairs(npcLocations:GetDescendants()) do
            if index % 150 == 0 then
                task.wait()
            end

            local position = getWorldPositionForLocationObject(object)

            if position then
                local knownName = getSideQuestLocationNameFromNode(object)

                if knownName then
                    local key = "NPCLOCATION|"
                        .. object:GetFullName()
                        .. "|"
                        .. knownName

                    if not seenLocationKeys[key] then
                        seenLocationKeys[key] = true

                        createSideQuestLocationVirtualESP(
                            knownName,
                            position,
                            key,
                            object
                        )
                    end
                end
            end
        end
    end

    local function scanSideQuestTemplateSources()
        if not Config.ArcaneSideQuestESP then
            return
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")
        local objects = rs and rs:FindFirstChild("Objects")

        if not sideQuestTemplatesScanned then
            sideQuestTemplatesScanned = true

            local function scanFolder(folder, recursive)
                if not folder then
                    return
                end

                local source = recursive
                    and folder:GetDescendants()
                    or folder:GetChildren()

                for index, model in ipairs(source) do
                    if index % 150 == 0 then
                        task.wait()
                    end

                    if model:IsA("Model")
                        and model:FindFirstChildOfClass("Humanoid") then
                        createSideQuestVirtualESP(model)
                    end
                end
            end

            scanFolder(objects, true)
            scanFolder(rs and rs:FindFirstChild("UnloadEnemies"), false)
        end

        -- Location registry is cheap compared with template discovery, so
        -- re-check it periodically for late-created ObjectValue links.
        scanSideQuestLocationRegistry()
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
                inspectSideQuestModel(model)
            end
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")

        if rs then
            local unloadEnemies = rs:FindFirstChild("UnloadEnemies")

            if unloadEnemies and Config.ArcaneSideQuestESP then
                -- These are lightweight NPC definitions; scan both current
                -- children and nested models because quest NPCs can be grouped.
                for _, instance in ipairs(unloadEnemies:GetChildren()) do
                    if instance:IsA("Model") then
                        inspectSideQuestModel(instance)
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
            openedChests[instance] = nil
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
    local targetedScanAccumulator = 0

    local function getChestFilterSignature()
        local parts = {}

        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            parts[#parts + 1] = Config.ArcaneChestFilter[chestType] == true
                and "1"
                or "0"

            parts[#parts + 1] = ":"
            parts[#parts + 1] = tostring(getChestScanDistance(chestType))
            parts[#parts + 1] = ";"
        end

        return table.concat(parts, "")
    end

    task.spawn(function()
        while true do
            task.wait(0.25)

            local currentChestFilterSignature = getChestFilterSignature()
            local chestSettingsChanged =
                currentChestFilterSignature ~= lastChestFilterSignature

            local chestESPChanged =
                Config.ArcaneChestESP ~= lastChestESPEnabled

            if chestSettingsChanged or chestESPChanged then
                lastChestFilterSignature = currentChestFilterSignature
                lastChestESPEnabled = Config.ArcaneChestESP == true

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

            targetedScanAccumulator += 0.25

            if targetedScanAccumulator >= 1.5 then
                targetedScanAccumulator = 0

                if Config.ArcaneBossESP
                    or Config.ArcaneSideQuestESP then
                    pcall(scanTargetedWorldSources)
                end

                if Config.ArcaneSideQuestESP then
                    pcall(scanSideQuestTemplateSources)
                end
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
                        if openedChests[target] then
                            markChestOpened(target)
                        elseif not hasLiveChestInteraction(target) then
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
                end
            else
                -- No selected type = zero chest candidates and zero scanning work.
                table.clear(chestCandidates)

                for target in pairs(chestESPObjects) do
                    destroyChestESP(target)
                end

                -- Keep openedChests intact while ESP is OFF or filters are cleared.
                -- This prevents already-opened chests from returning after re-enable.

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
                        or (data.static and data.location and not data.location.Parent)
                        or (not data.static and (not data.source or not data.source.Parent)) then
                        destroySideQuestVirtualESP(key)
                    elseif data.static then
                        local distanceText = "STUDS: ?"

                        if playerRoot then
                            distanceText = ("STUDS: %d"):format(
                                math.floor(
                                    (playerRoot.Position - data.position).Magnitude
                                )
                            )
                        end

                        data.label.Text = "SIDE QUEST NPC | "
                            .. tostring(data.name)
                            .. " | "
                            .. distanceText
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
                else
                    local chestType = data.chestType or getChestType(target)

                    if not isChestFilterEnabled(Config, chestType)
                        or not hasLiveChestInteraction(target)
                        or not isChestWithinScanDistance(target, chestType) then

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

                        local chestDisplayName =
                            CHEST_DISPLAY_NAMES[chestType] or "Other Chest"

                        local chestColor =
                            CHEST_COLORS[chestType] or CHEST_COLORS.OTHER

                        data.label.TextColor3 = chestColor
                        data.label.Text = chestDisplayName
                            .. " | "
                            .. distanceText
                    end
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
    -- Confirmed fishing flow from RemoteSpy:
    -- Equip -> ToolAction (cast)
    -- FishEvent -> Bump (state/progress)
    -- FishEvent -> Bite (start reel)
    -- ToolAction repeated (reel)
    -- FishEvent -> Complete (catch finished)
    --
    -- Tool:Activate() is used for cast/reel so the game's own ToolAction
    -- is generated exactly like the normal rod interaction.
    -- The visual "!" is never used for bite detection.

    local fishEventRemote = nil
    local fishingEventConnection = nil
    local fishingState = "OFF"
    local biteReceived = false
    local completeReceived = false
    local fishingCycleRunning = false

    do
        local replicatedStorageFishing = game:GetService("ReplicatedStorage")
        local rsFishing = replicatedStorageFishing:FindFirstChild("RS")
        local remotesFishing = rsFishing and rsFishing:FindFirstChild("Remotes")
        local miscRemotesFishing = remotesFishing and remotesFishing:FindFirstChild("Misc")
        local remote = miscRemotesFishing
            and miscRemotesFishing:FindFirstChild("FishEvent")

        if remote and remote:IsA("RemoteEvent") then
            fishEventRemote = remote
        end
    end

    local function setFishingStatus(text)
        if fishingStatusLabel then
            fishingStatusLabel.Text = "Status: " .. tostring(text)
        end
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

        return rod
    end

    local function activateRod(rod)
        if not rod or not rod.Parent then
            return false
        end

        return pcall(function()
            rod:Activate()
        end)
    end

    local function extractFishingState(...)
        local args = {...}

        -- Works whether RemoteSpy displays Player as argument #1
        -- or only shows the actual event payload.
        for _, value in ipairs(args) do
            if value == "Bump"
                or value == "Bite"
                or value == "Complete" then
                return value
            end
        end

        return nil
    end

    if fishEventRemote then
        fishingEventConnection = fishEventRemote.OnClientEvent:Connect(function(...)
            local eventState = extractFishingState(...)

            if eventState == "Bump" then
                if fishingCycleRunning then
                    setFishingStatus("Bump received | Waiting for Bite...")
                end
                return
            end

            if eventState == "Bite" then
                biteReceived = true
                completeReceived = false
                fishingState = "REELING"

                local fishName = nil

                for _, value in ipairs({...}) do
                    if type(value) == "string"
                        and value ~= "Bump"
                        and value ~= "Bite"
                        and value ~= "Complete" then
                        fishName = value
                        break
                    end
                end

                if fishName then
                    setFishingStatus(
                        "Bite! Reeling " .. tostring(fishName) .. "..."
                    )
                else
                    setFishingStatus("Bite! Reeling...")
                end

                return
            end

            if eventState == "Complete" then
                completeReceived = true
                fishingState = "COMPLETE"
                setFishingStatus("Catch complete.")
            end
        end)
    end

    local function doFishingCycle()
        if not Config.ArcaneAutoFishing then
            return false
        end

        local rod = equipFishingRod()

        if not rod then
            fishingState = "WAITING_ROD"
            setFishingStatus("Waiting for fishing rod...")
            task.wait(0.5)
            return false
        end

        if not fishEventRemote then
            fishingState = "ERROR"
            setFishingStatus("ERROR: FishEvent not found.")
            task.wait(1)
            return false
        end

        biteReceived = false
        completeReceived = false
        fishingCycleRunning = true

        fishingState = "CASTING"
        setFishingStatus("Casting...")

        -- First activation = normal cast.
        activateRod(rod)

        fishingState = "WAITING_BITE"
        setFishingStatus("Waiting for Bite...")

        local biteDeadline = os.clock() + 90
        local nextEquipCheck = 0

        while Config.ArcaneAutoFishing
            and not biteReceived
            and os.clock() < biteDeadline do

            if os.clock() >= nextEquipCheck then
                nextEquipCheck = os.clock() + 0.10

                local currentRod = equipFishingRod()

                if currentRod then
                    rod = currentRod
                end
            end

            task.wait(0.05)
        end

        if not Config.ArcaneAutoFishing then
            fishingCycleRunning = false
            fishingState = "OFF"
            setFishingStatus("OFF")
            return false
        end

        if not biteReceived then
            fishingCycleRunning = false
            fishingState = "TIMEOUT"
            setFishingStatus("No Bite received. Recasting...")
            task.wait(0.5)
            return false
        end

        local reelDeadline = os.clock() + 30
        nextEquipCheck = 0

        while Config.ArcaneAutoFishing
            and not completeReceived
            and os.clock() < reelDeadline do

            if os.clock() >= nextEquipCheck
                or not rod
                or not rod.Parent then

                nextEquipCheck = os.clock() + 0.10

                local currentRod = equipFishingRod()

                if currentRod then
                    rod = currentRod
                end
            end

            if not rod or not rod.Parent then
                task.wait(0.05)
                continue
            end

            activateRod(rod)
            task.wait(0.08)
        end

        fishingCycleRunning = false

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

        task.wait(0.5)
        return true
    end

    task.spawn(function()
        while true do
            if not Config.ArcaneAutoFishing then
                fishingCycleRunning = false
                fishingState = "OFF"
                biteReceived = false
                completeReceived = false

                setFishingStatus(
                    "OFF | Cast -> Bite -> Reel -> Complete"
                )

                task.wait(0.25)
            else
                if not fishingCycleRunning then
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
