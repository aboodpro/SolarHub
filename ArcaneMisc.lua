--!strict
local ArcaneMisc = {}

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
    "TREASURE_MAP",
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
    TREASURE_MAP = "Treasure Map Chest",
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
    TREASURE_MAP = Color3.fromRGB(255, 200, 70),
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

    if text:find("treasurechest", 1, true)
        or text == "treasure" then
        return "COMMON"
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

local function isTreasureMapChest(target)
    if not target then
        return false
    end

    local collectionService = game:GetService("CollectionService")
    local current = target

    while current and current ~= workspace do
        local okTags, tags = pcall(function()
            return collectionService:GetTags(current)
        end)

        if okTags and type(tags) == "table" then
            for _, tag in ipairs(tags) do
                if normalizeName(tag) == "buriedchests" then
                    return true
                end
            end
        end

        if current:IsA("Model") or current:IsA("BasePart") then
            local normalized = normalizeName(current.Name)

            if normalized:find("buriedtreasure", 1, true)
                or normalized:find("buriedchest", 1, true) then
                return true
            end
        end

        current = current.Parent
    end

    return false
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

    if isTreasureMapChest(target) then
        return "TREASURE_MAP"
    end

    -- Prefer specific rarity/type data over the generic "Treasure Chest"
    -- name. A live Rare Chest can still be named Treasure Chest while its
    -- actual rarity is exposed by a value, attribute, prompt, or child.
    local genericCommon = false

    for _, source in ipairs(collectChestTextSources(target)) do
        local chestType = classifyChestText(source)

        if chestType then
            if chestType == "COMMON" then
                genericCommon = true
            else
                return chestType
            end
        end
    end

    if genericCommon then
        return "COMMON"
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

    -- Generic Treasure Chest is deliberately deferred to getChestType(),
    -- because its real live rarity may be stored in metadata/prompt values.
    local chestType = classifyChestText(text)
    if chestType and chestType ~= "COMMON" then
        return chestType
    end

    local model = target:IsA("Model")
        and target
        or target:FindFirstAncestorOfClass("Model")

    if model then
        chestType = classifyChestText(model.Name)
        if chestType and chestType ~= "COMMON" then
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

local function getChestTagState(model)
    if not model then
        return false
    end

    local collectionService = game:GetService("CollectionService")
    local okTags, tags = pcall(function()
        return collectionService:GetTags(model)
    end)

    if not okTags or type(tags) ~= "table" then
        return false
    end

    for _, tag in ipairs(tags) do
        local normalizedTag = normalizeName(tag)

        if normalizedTag == "chests"
            or normalizedTag == "promptchest"
            or normalizedTag == "buriedchests"
            or normalizedTag == "chest" then
            return true
        end
    end

    return false
end

local function looksLikeChestModel(model)
    if not model or not model:IsA("Model") then
        return false
    end

    local base = model:FindFirstChild("Base")
    local anyBasePart = model:FindFirstChildWhichIsA("BasePart", true)

    local normalized = normalizeName(model.Name)

    -- Strong identity from the model name. A named chest is enough to identify
    -- it; the actual root can be any BasePart when the model has no direct Base.
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

        return anyBasePart ~= nil
    end

    -- Strong identity from the game's exact tag.
    if getChestTagState(model) then
        return true
    end

    -- Generic chests: look for an interaction attached to THIS chest's Base,
    -- not a prompt somewhere inside an outer underwater structure.
    local interactionRoot = base
        or anyBasePart

    if interactionRoot
        and interactionRoot:FindFirstChildWhichIsA("ProximityPrompt", true) then
        return true
    end

    if interactionRoot
        and interactionRoot:FindFirstChildWhichIsA("ClickDetector", true) then
        return true
    end

    -- Generic chests can expose their rarity through exact model attributes.
    local okAttrs, attrs = pcall(function()
        return model:GetAttributes()
    end)

    if okAttrs and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            local keyText = normalizeChestText(key)

            if keyText:find("rarity", 1, true)
                or keyText:find("tier", 1, true)
                or keyText:find("chesttype", 1, true) then

                if classifyChestText(value) then
                    return true
                end
            end
        end
    end

    return false
end

-- getChestRoot() is defined outside Arcane.Init(), so its weak cache
-- must also live at module scope. Keeping it inside Init() would make the
-- helper resolve a nil/global cache and spam "attempt to index nil".
local chestRootCache = setmetatable({}, {__mode = "k"})

local function getChestTarget(object)
    if not object or not object.Parent then
        return nil
    end

    -- Resolve the nearest actual chest model above the scanned object.
    -- Outer structures are intentionally ignored because they do not satisfy
    -- looksLikeChestModel unless they are themselves a real chest.
    local current = object

    while current and current ~= workspace do
        if current:IsA("Model") and looksLikeChestModel(current) then
            return current
        end

        current = current.Parent
    end

    -- Tagged/container objects may be the thing reported by CollectionService.
    -- Find a concrete chest model inside rather than targeting the container.
    if object:IsA("Model") then
        local best = nil
        local bestDepth = -1

        for _, descendant in ipairs(object:GetDescendants()) do
            if descendant:IsA("Model") and looksLikeChestModel(descendant) then
                local depth = 0
                local parent = descendant

                while parent and parent ~= object do
                    depth += 1
                    parent = parent.Parent
                end

                if depth > bestDepth then
                    best = descendant
                    bestDepth = depth
                end
            end
        end

        if best then
            return best
        end
    end

    return nil
end

local function getChestRoot(target)
    if not target then
        return nil
    end

    local cachedRoot = chestRootCache[target]

    if cachedRoot and cachedRoot.Parent then
        return cachedRoot
    end

    local root = nil

    if target:IsA("Model") then
        root = getRoot(target)

        if not root then
            for _, descendant in ipairs(target:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    root = descendant
                    break
                end
            end
        end
    elseif target:IsA("BasePart") then
        root = target
    end

    chestRootCache[target] = root
    return root
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

    local localPlayer = game:GetService("Players").LocalPlayer

    if localPlayer and model == localPlayer.Character then
        return nil
    end

    -- Workspace.NPCs contains persistent NPC records even when the visible
    -- humanoid model is unloaded. These records are keyed by the real NPC name.
    local knownName = NORMALIZED_SIDE_QUEST_NPCS[normalizeName(model.Name)]

    if knownName then
        return {
            name = knownName,
            detectionType = "Known NPC Record",
        }
    end

    -- Only live-model detection needs a Humanoid.
    if not model:FindFirstChildOfClass("Humanoid") then
        return nil
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
                ("%s | Filter=%s"):format(
                    chestType,
                    tostring(Config.ArcaneChestFilter[chestType] == true)
                )
            )
        end

        table.insert(
            results.config,
            "BossESP=" .. tostring(Config.ArcaneBossESP)
                .. " | ChestESP=" .. tostring(Config.ArcaneChestESP)
                .. " | InfiniteScan=" .. tostring(Config.ArcaneInfiniteDistanceScan)
                .. " | ScanLimit=" .. tostring(Config.ArcaneChestScanDistanceLimitEnabled)
                .. " | ScanDistance=" .. tostring(Config.ArcaneChestScanDistance)
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

        local chestDebug = {
            workspaceModels = 0,
            modelsWithBase = 0,
            namedCandidates = 0,
            taggedCandidates = 0,
            resolvedTargets = 0,
            rareTargets = 0,
            selectedTargets = 0,
            liveTargets = 0,
            withinDistance = 0,
            rejectedNoTarget = 0,
            rejectedFilter = 0,
            rejectedDistance = 0,
            openedTargets = 0,
            samples = {},
        }

        local function addChestSample(value)
            if #chestDebug.samples < 300 then
                table.insert(chestDebug.samples, tostring(value))
            end
        end

        local function isNamedChestModel(model)
            if not model or not model:IsA("Model") then
                return false
            end

            local normalized = normalizeName(model.Name)

            return normalized:find("chest", 1, true) ~= nil
                or normalized:find("treasure", 1, true) ~= nil
                or normalized:find("sealed", 1, true) ~= nil
                or normalized == "common"
                or normalized == "uncommon"
                or normalized == "rare"
                or normalized == "mystic"
                or normalized == "legendary"
                or normalized == "privatestorage"
                or normalized == "sky"
                or normalized == "steel"
        end

        local function hasChestDebugTag(model)
            if not model then
                return false
            end

            local okTags, data = pcall(function()
                return CollectionService:GetTags(model)
            end)

            if not okTags or type(data) ~= "table" then
                return false
            end

            for _, tag in ipairs(data) do
                local normalized = normalizeName(tag)

                if normalized == "chests"
                    or normalized == "promptchest"
                    or normalized == "buriedchests"
                    or normalized:find("chest", 1, true) then
                    return true
                end
            end

            return false
        end

        local function addChestDiagnosis(chest, source)
            if not chest or not chest:IsDescendantOf(workspace) then
                chestDebug.rejectedNoTarget += 1
                return
            end

            if chestSeen[chest] then
                return
            end

            chestSeen[chest] = true
            chestDebug.resolvedTargets += 1

            local root = getChestRoot(chest)
            local chestType = getChestType(chest)
            local live = hasLiveChestInteraction(chest)
            local selected = isChestFilterEnabled(Config, chestType)
            local character = player and player.Character
            local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
            local distanceValue = nil

            if playerRoot and root then
                distanceValue = (playerRoot.Position - root.Position).Magnitude
            end

            if chestType == "RARE" then
                chestDebug.rareTargets += 1
            end

            if selected then
                chestDebug.selectedTargets += 1
            else
                chestDebug.rejectedFilter += 1
            end

            local wasOpened = openedChests[chest] or hasChestOpenedMarker(chest)

            if wasOpened then
                chestDebug.openedTargets += 1
            elseif live then
                chestDebug.liveTargets += 1
            end

            if selected and not wasOpened then
                if isChestWithinScanDistance(chest, chestType) then
                    chestDebug.withinDistance += 1
                else
                    chestDebug.rejectedDistance += 1
                end
            end

            addChestSample(
                ("%s | SRC=%s | TYPE=%s | LIVE=%s | SELECTED=%s | DIST=%s | BASE=%s | %s"):format(
                    chest.Name,
                    tostring(source),
                    tostring(chestType),
                    tostring(live),
                    tostring(selected),
                    distanceValue and ("%.0f"):format(distanceValue) or "?",
                    tostring(chest:IsA("Model") and chest:FindFirstChild("Base") ~= nil),
                    chest:GetFullName()
                )
            )

            local distance = "DIST=?"

            if distanceValue then
                distance = ("DIST=%.0f"):format(distanceValue)
            end

            local base = chest:IsA("Model") and chest:FindFirstChild("Base")
            local prompt = chest:FindFirstChild("Prompt", true)
            local open = chest:FindFirstChild("Open", true)

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

        -- Manual structure scan: recursively inspect Workspace once so this
        -- button can discover chests/NPCs even when they are not tagged.
        local visitedWorkspace = {}

        for index, instance in ipairs(workspace:GetDescendants()) do
            if index % 250 == 0 then
                task.wait()
            end

            if instance:IsA("Model") then
                chestDebug.workspaceModels += 1

                local base = instance:FindFirstChild("Base")
                if base and base:IsA("BasePart") then
                    chestDebug.modelsWithBase += 1
                end

                local named = isNamedChestModel(instance)
                local tagged = hasChestDebugTag(instance)

                if named then
                    chestDebug.namedCandidates += 1
                end

                if tagged then
                    chestDebug.taggedCandidates += 1
                end
                visitedWorkspace[instance] = true

                local normalized = normalizeName(instance.Name)

                if normalized:find("chest", 1, true)
                    or instance:FindFirstChild("Base") then
                    addChestDiagnosis(instance, "WORKSPACE_DEEP")
                end

                local info = getSideQuestNPCInfo(instance)

                if info then
                    add(
                        results.sideQuest,
                        ("%s | LIVE_MODEL | DETECT=%s | POS=%s | %s"):format(
                            info.name,
                            info.detectionType,
                            pos(getRoot(instance)),
                            instance:GetFullName()
                        ),
                        1000
                    )
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
        table.insert(lines, "CHEST DEBUG SUMMARY:")
        table.insert(lines, ("Workspace Models=%d"):format(chestDebug.workspaceModels))
        table.insert(lines, ("Models with Base=%d"):format(chestDebug.modelsWithBase))
        table.insert(lines, ("Named Chest Candidates=%d"):format(chestDebug.namedCandidates))
        table.insert(lines, ("Tagged Chest Candidates=%d"):format(chestDebug.taggedCandidates))
        table.insert(lines, ("Resolved Chest Targets=%d"):format(chestDebug.resolvedTargets))
        table.insert(lines, ("Rare Targets=%d"):format(chestDebug.rareTargets))
        table.insert(lines, ("Selected Targets=%d"):format(chestDebug.selectedTargets))
        table.insert(lines, ("Live Targets=%d"):format(chestDebug.liveTargets))
        table.insert(lines, ("Within Distance=%d"):format(chestDebug.withinDistance))
        table.insert(lines, ("Rejected: No Target=%d"):format(chestDebug.rejectedNoTarget))
        table.insert(lines, ("Rejected: Filter=%d"):format(chestDebug.rejectedFilter))
        table.insert(lines, ("Rejected: Distance=%d"):format(chestDebug.rejectedDistance))
        table.insert(lines, ("Opened/Tracked=%d"):format(chestDebug.openedTargets))
        table.insert(lines, "")
        table.insert(lines, "CHEST DEBUG SAMPLES:")
        for _, sample in ipairs(chestDebug.samples) do
            table.insert(lines, sample)
        end

        table.insert(lines, "")
        table.insert(lines, "DIAGNOSTIC NOTES:")
        table.insert(lines, "1) Chest LIVE=false means no Base+Prompt/Click interaction was found, or the chest is opened.")
        table.insert(lines, "2) OPENED=tracked means this client saw the chest interaction and will not show it again.")
        table.insert(lines, "3) Static NPCLocations are checked for ObjectValues, value/attribute names, nested metadata and world positions.")
        table.insert(lines, "4) A location entry with no NPC identity cannot be safely assigned to a specific quest giver without a name/id in the replicated data.")
        table.insert(lines, "5) Known NPC/template/location data is used for virtual markers when an unambiguous world position exists.")

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
local function runChestDebug(setText, Config)
    task.spawn(function()
        local ok, err = xpcall(function()
            local Players = game:GetService("Players")
            local CollectionService = game:GetService("CollectionService")
            local WorkspaceService = game:GetService("Workspace")
            local ReplicatedStorageService = game:GetService("ReplicatedStorage")

            setText("CHEST DEBUG v6 | GLOBAL + INFINITE RANGE | SCANNING...")

            local player = Players.LocalPlayer
            local character = player and player.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            local map = WorkspaceService:FindFirstChild("Map")
            local rs = ReplicatedStorageService
            local unloadIslands = rs and rs:FindFirstChild("RS")
            unloadIslands = unloadIslands and unloadIslands:FindFirstChild("UnloadIslands")

            local function safeNumber(value)
                local n = tonumber(value)
                return n and math.floor(n + 0.5) or nil
            end

            local function safeString(value)
                local okValue, result = pcall(function()
                    return tostring(value)
                end)

                return okValue and result or "<error>"
            end

            local function isChestName(value)
                local normalized = normalizeName(value)

                return normalized:find("chest", 1, true) ~= nil
                    or normalized:find("treasure", 1, true) ~= nil
                    or normalized:find("sealed", 1, true) ~= nil
                    or normalized == "common"
                    or normalized == "uncommon"
                    or normalized == "rare"
                    or normalized == "mystic"
                    or normalized == "legendary"
                    or normalized == "privatestorage"
                    or normalized == "sky"
                    or normalized == "steel"
            end

            local function getAnyRoot(instance)
                if not instance then
                    return nil
                end

                if instance:IsA("BasePart") then
                    return instance
                end

                if instance:IsA("Model") then
                    local root = nil

                    pcall(function()
                        root = getChestRoot(instance)
                    end)

                    if root and root:IsA("BasePart") then
                        return root
                    end

                    pcall(function()
                        root = instance.PrimaryPart
                            or instance:FindFirstChild("Base", true)
                            or instance:FindFirstChildWhichIsA("BasePart", true)
                    end)

                    if root and root:IsA("BasePart") then
                        return root
                    end
                end

                return nil
            end

            local function isInWorkspace(instance)
                return instance ~= nil and instance:IsDescendantOf(WorkspaceService)
            end

            local function getDistance(instance, root)
                if not hrp or not root then
                    return nil
                end

                local okDistance, distance = pcall(function()
                    return (hrp.Position - root.Position).Magnitude
                end)

                return okDistance and distance or nil
            end

            local function getCandidateReason(instance)
                local reasons = {}

                if not instance then
                    return reasons
                end

                if isChestName(instance.Name) then
                    reasons[#reasons + 1] = "NAME"
                end

                for _, tagName in ipairs({
                    "Chests",
                    "Prompt_Chest",
                    "BuriedChests",
                }) do
                    local hasTag = false

                    pcall(function()
                        hasTag = CollectionService:HasTag(instance, tagName)
                    end)

                    if hasTag then
                        reasons[#reasons + 1] = "TAG:" .. tagName
                    end
                end

                return reasons
            end

            local function getType(instance)
                local chestType = "?"

                pcall(function()
                    chestType = tostring(getChestTypeFast(instance) or getChestType(instance) or "?")
                end)

                return chestType
            end

            local function getFilterState(chestType)
                local selected = false

                pcall(function()
                    selected = isChestFilterEnabled(Config, chestType)
                end)

                return selected
            end

            local function getConfiguredDistance(chestType)
                local distance = nil

                pcall(function()
                    local value = Config.ArcaneChestScanDistance
                        and Config.ArcaneChestScanDistance[chestType]

                    if value ~= nil then
                        distance = tonumber(value)
                    end
                end)

                return distance
            end

            local function getAttributeSummary(instance)
                local values = {}

                local okAttributes, attributes = pcall(function()
                    return instance:GetAttributes()
                end)

                if not okAttributes or type(attributes) ~= "table" then
                    return ""
                end

                for key, value in pairs(attributes) do
                    local keyText = normalizeChestText(key)

                    if keyText:find("pos", 1, true)
                        or keyText:find("location", 1, true)
                        or keyText:find("cframe", 1, true)
                        or keyText:find("position", 1, true)
                        or keyText:find("spawn", 1, true)
                        or keyText:find("coord", 1, true) then

                        values[#values + 1] = safeString(key) .. "=" .. safeString(value)
                    end
                end

                table.sort(values)

                if #values == 0 then
                    return ""
                end

                return table.concat(values, ", ")
            end

            local function getValueObjectSummary(instance)
                local values = {}
                local count = 0

                pcall(function()
                    for _, descendant in ipairs(instance:GetDescendants()) do
                        if descendant:IsA("Vector3Value") then
                            local n = normalizeName(descendant.Name)

                            if n:find("pos", 1, true)
                                or n:find("location", 1, true)
                                or n:find("spawn", 1, true)
                                or n:find("coord", 1, true) then

                                count += 1

                                if #values < 8 then
                                    values[#values + 1] = descendant.Name
                                        .. "="
                                        .. safeString(descendant.Value)
                                end
                            end
                        elseif descendant:IsA("CFrameValue") then
                            local n = normalizeName(descendant.Name)

                            if n:find("pos", 1, true)
                                or n:find("location", 1, true)
                                or n:find("spawn", 1, true)
                                or n:find("coord", 1, true)
                                or n:find("cframe", 1, true) then

                                count += 1

                                if #values < 8 then
                                    values[#values + 1] = descendant.Name
                                        .. "=CFrame"
                                end
                            end
                        end
                    end
                end)

                if count == 0 then
                    return ""
                end

                return ("count=%d [%s]"):format(count, table.concat(values, ", "))
            end

            local out = {
                "SOLARHUB CHEST DEBUG v6",
                "BUILD: GLOBAL + INFINITE-RANGE CHEST DISCOVERY",
                "==============================",
                "PlaceId: " .. safeString(game.PlaceId),
                "GameId: " .. safeString(game.GameId),
                "JobId: " .. safeString(game.JobId),
                "LocalPlayer: " .. safeString(player),
                "Character: " .. safeString(character),
                "HRP: " .. safeString(hrp),
                "Workspace.StreamingEnabled: " .. (function()
                    local value = "<unavailable>"
                    pcall(function()
                        value = tostring(WorkspaceService.StreamingEnabled)
                    end)
                    return value
                end)(),
                "Map: " .. safeString(map),
                "ReplicatedStorage.RS.UnloadIslands: " .. safeString(unloadIslands),
                "DISTANCE FILTER: DISABLED FOR THIS DEBUG",
                "",
            }

            local stats = {
                workspaceDescendants = 0,
                workspaceModels = 0,
                workspaceFolders = 0,
                workspaceParts = 0,
                workspacePrompts = 0,
                workspaceClicks = 0,
                workspaceNamedChestModels = 0,

                rsDescendants = 0,
                rsModels = 0,
                rsFolders = 0,
                rsParts = 0,
                rsPrompts = 0,
                rsClicks = 0,
                rsNamedChestModels = 0,

                taggedObjects = 0,
                tagChests = 0,
                tagPromptChests = 0,
                tagBuriedChests = 0,

                uniqueCandidates = 0,
                liveWorkspaceCandidates = 0,
                templateCandidates = 0,

                workspaceWithRoot = 0,
                workspaceWithoutRoot = 0,
                workspaceSelected = 0,
                workspaceRejected = 0,
                workspacePassDistance = 0,
                workspaceFailDistance = 0,
                workspaceEspEligibleIgnoringDistance = 0,
                workspaceEspEligibleWithDistance = 0,
                workspaceOpened = 0,

                unresolvedTagged = 0,
                unresolvedInteraction = 0,
            }

            local seenCandidates = {}
            local workspaceSamples = {}
            local templateSamples = {}
            local unresolvedSamples = {}
            local sourceCounts = {}
            local typeCounts = {}
            local distanceBuckets = {
                ["0-500"] = 0,
                ["500-2000"] = 0,
                ["2000-5000"] = 0,
                ["5000-10000"] = 0,
                ["10000+"] = 0,
                ["UNKNOWN"] = 0,
            }

            local function addSample(list, value, limit)
                if #list < limit then
                    list[#list + 1] = tostring(value)
                end
            end

            local function addCount(tableRef, key)
                key = tostring(key or "?")
                tableRef[key] = (tableRef[key] or 0) + 1
            end

            local function addDistanceBucket(distance)
                if not distance then
                    distanceBuckets.UNKNOWN += 1
                elseif distance <= 500 then
                    distanceBuckets["0-500"] += 1
                elseif distance <= 2000 then
                    distanceBuckets["500-2000"] += 1
                elseif distance <= 5000 then
                    distanceBuckets["2000-5000"] += 1
                elseif distance <= 10000 then
                    distanceBuckets["5000-10000"] += 1
                else
                    distanceBuckets["10000+"] += 1
                end
            end

            local function resolveTarget(instance)
                local target = nil

                pcall(function()
                    target = getChestTarget(instance)
                end)

                if target then
                    return target
                end

                if instance and instance:IsA("Model") and looksLikeChestModel(instance) then
                    return instance
                end

                return nil
            end

            local function recordCandidate(target, source, explicitReasons)
                if not target then
                    return
                end

                if seenCandidates[target] then
                    return
                end

                seenCandidates[target] = true
                stats.uniqueCandidates += 1

                local inWorkspace = isInWorkspace(target)
                local root = getAnyRoot(target)
                local chestType = getType(target)
                local selected = getFilterState(chestType)
                local distance = getDistance(target, root)
                local configuredDistance = getConfiguredDistance(chestType)
                local passDistance = true

                if configuredDistance ~= nil and distance ~= nil then
                    passDistance = distance <= configuredDistance
                end

                local opened = false
                pcall(function()
                    opened = openedChests[target] == true
                        or hasChestOpenedMarker(target)
                end)

                local reasonList = explicitReasons or getCandidateReason(target)
                if #reasonList == 0 then
                    reasonList = {"RESOLVED"}
                end

                if inWorkspace then
                    stats.liveWorkspaceCandidates += 1

                    if root then
                        stats.workspaceWithRoot += 1
                    else
                        stats.workspaceWithoutRoot += 1
                    end

                    if selected then
                        stats.workspaceSelected += 1
                    else
                        stats.workspaceRejected += 1
                    end

                    if passDistance then
                        stats.workspacePassDistance += 1
                    else
                        stats.workspaceFailDistance += 1
                    end

                    local eligibleIgnoringDistance =
                        root ~= nil
                        and not opened
                        and selected

                    local eligibleWithDistance =
                        eligibleIgnoringDistance
                        and passDistance

                    if eligibleIgnoringDistance then
                        stats.workspaceEspEligibleIgnoringDistance += 1
                    end

                    if eligibleWithDistance then
                        stats.workspaceEspEligibleWithDistance += 1
                    end

                    if opened then
                        stats.workspaceOpened += 1
                    end

                    addDistanceBucket(distance)
                else
                    stats.templateCandidates += 1
                end

                addCount(sourceCounts, table.concat(reasonList, "+"))
                addCount(typeCounts, chestType)

                local rootPosition = root and (
                    ("%d,%d,%d"):format(
                        root.Position.X,
                        root.Position.Y,
                        root.Position.Z
                    )
                ) or "?"

                local attrs = getAttributeSummary(target)
                local values = getValueObjectSummary(target)

                local line = (
                    "%s | %s | TYPE=%s | ROOT=%s | OPENED=%s | FILTER=%s | DIST=%s | CFG=%s | PASSDIST=%s | POS=%s | %s | PATH=%s"
                ):format(
                    inWorkspace and "LIVE-WORKSPACE" or "REPLICATED-TEMPLATE",
                    table.concat(reasonList, "+"),
                    chestType,
                    root and "YES" or "NO",
                    tostring(opened),
                    tostring(selected),
                    distance and tostring(safeNumber(distance)) or "?",
                    configuredDistance and tostring(safeNumber(configuredDistance)) or "N/A",
                    tostring(passDistance),
                    rootPosition,
                    (attrs ~= "" and "ATTR={" .. attrs .. "} " or "")
                        .. (values ~= "" and "VALUES={" .. values .. "}" or ""),
                    target:GetFullName()
                )

                if inWorkspace then
                    addSample(workspaceSamples, line, 600)
                else
                    addSample(templateSamples, line, 600)
                end
            end

            -- 1) Scan CollectionService tags globally.
            local tagLists = {
                Chests = {},
                Prompt_Chest = {},
                BuriedChests = {},
            }

            for tagName, targetList in pairs(tagLists) do
                pcall(function()
                    targetList = CollectionService:GetTagged(tagName)
                    tagLists[tagName] = targetList
                end)

                addCount(sourceCounts, "TAG-LIST:" .. tagName)

                if tagName == "Chests" then
                    stats.tagChests = #targetList
                elseif tagName == "Prompt_Chest" then
                    stats.tagPromptChests = #targetList
                elseif tagName == "BuriedChests" then
                    stats.tagBuriedChests = #targetList
                end

                stats.taggedObjects += #targetList

                for index, taggedObject in ipairs(targetList) do
                    local target = resolveTarget(taggedObject)

                    if target then
                        recordCandidate(target, "TAG:" .. tagName)
                    else
                        stats.unresolvedTagged += 1

                        addSample(
                            unresolvedSamples,
                            ("TAG:%s | NO_TARGET | %s"):format(
                                tagName,
                                taggedObject:GetFullName()
                            ),
                            250
                        )
                    end

                    if index % 250 == 0 then
                        task.wait()
                    end
                end
            end

            -- 2) Scan ALL Workspace descendants. No distance gate whatsoever.
            do
                local descendants = WorkspaceService:GetDescendants()

                for index, object in ipairs(descendants) do
                    stats.workspaceDescendants += 1

                    if index % 750 == 0 then
                        task.wait()
                    end

                    if object:IsA("Model") then
                        stats.workspaceModels += 1

                        if isChestName(object.Name) then
                            stats.workspaceNamedChestModels += 1

                            local target = resolveTarget(object)

                            if target then
                                recordCandidate(target, "WORKSPACE-NAME")
                            else
                                addSample(
                                    unresolvedSamples,
                                    ("WORKSPACE-NAME | NO_TARGET | %s"):format(
                                        object:GetFullName()
                                    ),
                                    250
                                )
                            end
                        end
                    elseif object:IsA("Folder") then
                        stats.workspaceFolders += 1
                    elseif object:IsA("BasePart") then
                        stats.workspaceParts += 1

                        if isChestName(object.Name) then
                            local target = resolveTarget(object)

                            if target then
                                recordCandidate(target, "WORKSPACE-PART-NAME")
                            end
                        end
                    elseif object:IsA("ProximityPrompt") then
                        stats.workspacePrompts += 1

                        local target = resolveTarget(object)

                        if target then
                            recordCandidate(target, "WORKSPACE-PROMPT")
                        else
                            local parentName = object.Parent and object.Parent:GetFullName() or "?"
                            if parentName:lower():find("chest", 1, true)
                                or parentName:lower():find("treasure", 1, true)
                                or parentName:lower():find("sealed", 1, true) then

                                stats.unresolvedInteraction += 1

                                addSample(
                                    unresolvedSamples,
                                    ("PROMPT | CHEST-LIKE-PARENT | %s"):format(
                                        object:GetFullName()
                                    ),
                                    250
                                )
                            end
                        end
                    elseif object:IsA("ClickDetector") then
                        stats.workspaceClicks += 1

                        local target = resolveTarget(object)

                        if target then
                            recordCandidate(target, "WORKSPACE-CLICK")
                        end
                    end
                end
            end

            -- 3) Scan ALL ReplicatedStorage descendants, especially the
            --    UnloadIslands hierarchy that already contains chest templates.
            do
                local descendants = ReplicatedStorageService:GetDescendants()

                for index, object in ipairs(descendants) do
                    stats.rsDescendants += 1

                    if index % 750 == 0 then
                        task.wait()
                    end

                    local isUnderUnload = unloadIslands
                        and object:IsDescendantOf(unloadIslands)

                    if object:IsA("Model") then
                        stats.rsModels += 1

                        if isChestName(object.Name) then
                            stats.rsNamedChestModels += 1

                            local target = resolveTarget(object)

                            if target then
                                recordCandidate(target, isUnderUnload and "RS-UNLOAD-NAME" or "RS-NAME")
                            else
                                addSample(
                                    unresolvedSamples,
                                    ("RS-NAME | NO_TARGET | %s"):format(
                                        object:GetFullName()
                                    ),
                                    250
                                )
                            end
                        end
                    elseif object:IsA("Folder") then
                        stats.rsFolders += 1
                    elseif object:IsA("BasePart") then
                        stats.rsParts += 1

                        if isChestName(object.Name) then
                            local target = resolveTarget(object)

                            if target then
                                recordCandidate(target, isUnderUnload and "RS-UNLOAD-PART-NAME" or "RS-PART-NAME")
                            end
                        end
                    elseif object:IsA("ProximityPrompt") then
                        stats.rsPrompts += 1

                        local target = resolveTarget(object)

                        if target then
                            recordCandidate(target, isUnderUnload and "RS-UNLOAD-PROMPT" or "RS-PROMPT")
                        end
                    elseif object:IsA("ClickDetector") then
                        stats.rsClicks += 1

                        local target = resolveTarget(object)

                        if target then
                            recordCandidate(target, isUnderUnload and "RS-UNLOAD-CLICK" or "RS-CLICK")
                        end
                    end
                end
            end

            local function appendLine(value)
                out[#out + 1] = tostring(value)
            end

            appendLine("WORKSPACE SCAN:")
            appendLine(("Workspace descendants: %d"):format(stats.workspaceDescendants))
            appendLine(("Workspace models: %d"):format(stats.workspaceModels))
            appendLine(("Workspace folders: %d"):format(stats.workspaceFolders))
            appendLine(("Workspace BaseParts: %d"):format(stats.workspaceParts))
            appendLine(("Workspace ProximityPrompts: %d"):format(stats.workspacePrompts))
            appendLine(("Workspace ClickDetectors: %d"):format(stats.workspaceClicks))
            appendLine(("Workspace named chest models: %d"):format(stats.workspaceNamedChestModels))
            appendLine("")

            appendLine("REPLICATEDSTORAGE SCAN:")
            appendLine(("RS descendants: %d"):format(stats.rsDescendants))
            appendLine(("RS models: %d"):format(stats.rsModels))
            appendLine(("RS folders: %d"):format(stats.rsFolders))
            appendLine(("RS BaseParts: %d"):format(stats.rsParts))
            appendLine(("RS ProximityPrompts: %d"):format(stats.rsPrompts))
            appendLine(("RS ClickDetectors: %d"):format(stats.rsClicks))
            appendLine(("RS named chest models: %d"):format(stats.rsNamedChestModels))
            appendLine("")

            appendLine("TAGS:")
            appendLine(("Chests = %d"):format(stats.tagChests))
            appendLine(("Prompt_Chest = %d"):format(stats.tagPromptChests))
            appendLine(("BuriedChests = %d"):format(stats.tagBuriedChests))
            appendLine(("Tagged objects total = %d"):format(stats.taggedObjects))
            appendLine("")

            appendLine("GLOBAL CHEST DISCOVERY:")
            appendLine(("Unique chest candidates: %d"):format(stats.uniqueCandidates))
            appendLine(("LIVE Workspace chest candidates: %d"):format(stats.liveWorkspaceCandidates))
            appendLine(("ReplicatedStorage/template chest candidates: %d"):format(stats.templateCandidates))
            appendLine(("Unresolved tagged chest objects: %d"):format(stats.unresolvedTagged))
            appendLine(("Unresolved chest-like interactions: %d"):format(stats.unresolvedInteraction))
            appendLine("")

            appendLine("LIVE WORKSPACE ESP ANALYSIS:")
            appendLine(("Live candidates with root: %d"):format(stats.workspaceWithRoot))
            appendLine(("Live candidates WITHOUT root: %d"):format(stats.workspaceWithoutRoot))
            appendLine(("Selected by chest filter: %d"):format(stats.workspaceSelected))
            appendLine(("Rejected by chest filter: %d"):format(stats.workspaceRejected))
            appendLine(("Pass current configured distance: %d"):format(stats.workspacePassDistance))
            appendLine(("Fail current configured distance: %d"):format(stats.workspaceFailDistance))
            appendLine(("ESP eligible IGNORING distance: %d"):format(
                stats.workspaceEspEligibleIgnoringDistance
            ))
            appendLine(("ESP eligible WITH current distance: %d"):format(
                stats.workspaceEspEligibleWithDistance
            ))
            appendLine(("Opened: %d"):format(stats.workspaceOpened))
            appendLine("")

            appendLine("DISTANCE BUCKETS (diagnostic only):")
            appendLine(("0-500: %d"):format(distanceBuckets["0-500"]))
            appendLine(("500-2000: %d"):format(distanceBuckets["500-2000"]))
            appendLine(("2000-5000: %d"):format(distanceBuckets["2000-5000"]))
            appendLine(("5000-10000: %d"):format(distanceBuckets["5000-10000"]))
            appendLine(("10000+: %d"):format(distanceBuckets["10000+"]))
            appendLine(("UNKNOWN: %d"):format(distanceBuckets.UNKNOWN))
            appendLine("")

            appendLine("DISCOVERY SOURCE COUNTS:")
            local sortedSources = {}

            for key, count in pairs(sourceCounts) do
                sortedSources[#sortedSources + 1] = {
                    key = key,
                    count = count,
                }
            end

            table.sort(sortedSources, function(a, b)
                if a.count == b.count then
                    return a.key < b.key
                end

                return a.count > b.count
            end)

            for index = 1, math.min(#sortedSources, 80) do
                local item = sortedSources[index]
                appendLine(("%s = %d"):format(item.key, item.count))
            end

            appendLine("")
            appendLine("CHEST TYPE COUNTS:")
            local sortedTypes = {}

            for key, count in pairs(typeCounts) do
                sortedTypes[#sortedTypes + 1] = {
                    key = key,
                    count = count,
                }
            end

            table.sort(sortedTypes, function(a, b)
                if a.count == b.count then
                    return a.key < b.key
                end

                return a.count > b.count
            end)

            for index = 1, math.min(#sortedTypes, 60) do
                local item = sortedTypes[index]
                appendLine(("%s = %d"):format(item.key, item.count))
            end

            appendLine("")
            appendLine("LIVE WORKSPACE CHESTS (max 600, NO DISTANCE FILTER):")
            if #workspaceSamples == 0 then
                appendLine("<none>")
            else
                for _, line in ipairs(workspaceSamples) do
                    appendLine(line)
                end
            end

            appendLine("")
            appendLine("REPLICATED/TEMPLATE CHESTS (max 600, NO DISTANCE FILTER):")
            if #templateSamples == 0 then
                appendLine("<none>")
            else
                for _, line in ipairs(templateSamples) do
                    appendLine(line)
                end
            end

            appendLine("")
            appendLine("UNRESOLVED CHEST-LIKE OBJECTS (max 250):")
            if #unresolvedSamples == 0 then
                appendLine("<none>")
            else
                for _, line in ipairs(unresolvedSamples) do
                    appendLine(line)
                end
            end

            appendLine("")
            appendLine("INTERPRETATION:")
            appendLine("1) This debug NEVER hides a chest because of distance.")
            appendLine("2) Compare LIVE Workspace vs Replicated/template counts.")
            appendLine("3) 'ESP eligible IGNORING distance' is the important count for the intended global ESP.")
            appendLine("4) If LIVE is high and ESP-eligible is high, the renderer/update loop is the remaining issue.")
            appendLine("5) If templates are high but LIVE is low, the game stores future chest locations in ReplicatedStorage and the ESP should use those static positions.")
            appendLine("6) ATTR/VALUES entries show extra position/location data when the game exposes it.")

            local finalText = table.concat(out, "\n")
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

            print("[Arcane] Chest DEBUG v6 finished.")
            print(finalText)
        end, debug.traceback)

        if not ok then
            setText("CHEST DEBUG v6 ERROR\n" .. tostring(err))
            warn("[SolarHub] Chest DEBUG v6 error:", err)
        end
    end)
end
-------------------------------------------------
-- ESP
-------------------------------------------------

function ArcaneMisc.Init(Shared, UI, Context)
    local function markSolarHubVisual(instance)
        if not instance then
            return
        end

        pcall(function()
            if type(getgenv) == "function" then
                instance:SetAttribute(
                    "SolarHubSessionToken",
                    tostring(getgenv().SolarHubLoaderSession or "")
                )
            end
        end)
    end

    local isArcaneSessionActive = Context.isSessionActive
    local Config = Shared.Config
    local tabs = UI.tabs or {}
    local tabButtons = UI.tabButtons or {}

    Config.ArcaneBossESP = Config.ArcaneBossESP == true
    Config.ArcaneBossDebug = Config.ArcaneBossDebug == true
    Config.ArcaneChestESP = Config.ArcaneChestESP == true
    Config.ArcaneTreasureChartESP = Config.ArcaneTreasureChartESP == true
    Config.ArcaneTreasureChartDebug = Config.ArcaneTreasureChartDebug == true
    Config.ArcaneSideQuestESP = Config.ArcaneSideQuestESP == true
    -- Chest filters start OFF. The user selects the chest types they want.
    if type(Config.ArcaneChestFilter) ~= "table" then
        Config.ArcaneChestFilter = {}
    end

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        Config.ArcaneChestFilter[chestType] = false
    end

    -- Chest scanning:
    -- Infinite Distance Scan is deliberately OFF by default so a weaker PC
    -- does not immediately have to process every cached chest location.
    Config.ArcaneInfiniteDistanceScan = Config.ArcaneInfiniteDistanceScan == true
    Config.ArcaneChestScanDistanceLimitEnabled =
        Config.ArcaneChestScanDistanceLimitEnabled == true

    local configuredChestScanDistance = tonumber(Config.ArcaneChestScanDistance)
    Config.ArcaneChestScanDistance = math.clamp(
        math.floor(configuredChestScanDistance or 30000),
        1,
        100000
    )

    local miscTab = tabs["Misc"]
    if not miscTab then
        error("[ArcaneMisc] Misc tab is missing.")
    end

    miscTab.CanvasPosition = Vector2.zero

    -------------------------------------------------
    -- BOSS RESPAWN NOTIFICATIONS
    -------------------------------------------------

    local bossNotificationGui = Instance.new("ScreenGui")
    bossNotificationGui.Name = "SolarArcaneBossNotifications"
    markSolarHubVisual(bossNotificationGui)
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
        "Structure Scan",
        "Scans bosses, chests, side quest NPCs/locations, templates and remotes.",
        "ArcaneBossDebug",
        80
    )

    local scanButton = Instance.new("TextButton")
    scanButton.Size = UDim2.new(1, -16, 0, 34)
    scanButton.Position = UDim2.fromOffset(8, 124)
    scanButton.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    scanButton.BorderSizePixel = 0
    scanButton.Text = "CHEST DEBUG v6"
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
        runChestDebug(setDebugText, Config)

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

    
    local scanSelectedChests

    -------------------------------------------------
    -- CHEST ESP / SCAN CONTROL UI
    -------------------------------------------------

    local chestSection = UI.createSection(
        miscTab,
        "Chest ESP",
        620
    )

    UI.createToggle(
        chestSection,
        "Chest ESP",
        "Shows selected chest types with name, rarity and distance.",
        "ArcaneChestESP",
        34
    )

    local chestHeader = Instance.new("TextLabel")
    chestHeader.Size = UDim2.new(1, -20, 0, 28)
    chestHeader.Position = UDim2.fromOffset(10, 80)
    chestHeader.BackgroundTransparency = 1
    chestHeader.Text = "CHEST TYPES"
    chestHeader.TextColor3 = Color3.fromRGB(220, 220, 230)
    chestHeader.Font = Enum.Font.GothamBold
    chestHeader.TextSize = 10
    chestHeader.TextXAlignment = Enum.TextXAlignment.Left
    chestHeader.Parent = chestSection

    local chestHeaderLine = Instance.new("Frame")
    chestHeaderLine.Size = UDim2.new(1, -20, 0, 1)
    chestHeaderLine.Position = UDim2.fromOffset(10, 106)
    chestHeaderLine.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    chestHeaderLine.BorderSizePixel = 0
    chestHeaderLine.Parent = chestSection

    local chestFilterButtons = {}

    local function updateChestFilterButton(chestType)
        local buttonData = chestFilterButtons[chestType]
        if not buttonData then
            return
        end

        local enabled = Config.ArcaneChestFilter[chestType] == true

        buttonData.indicator.BackgroundColor3 = enabled
            and CHEST_COLORS[chestType]
            or Color3.fromRGB(48, 48, 58)

        buttonData.text.TextColor3 = enabled
            and Color3.fromRGB(245, 245, 248)
            or Color3.fromRGB(135, 135, 145)

        buttonData.check.Text = enabled and "✓" or ""
    end

    -- Compact 2-column filter grid: much easier to scan visually than a
    -- separate slider for every chest rarity.
    local gridStartY = 114
    local cardWidth = 0.5
    local cardHeight = 40
    local cardGap = 6

    for index, chestType in ipairs(CHEST_TYPE_ORDER) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)

        local card = Instance.new("TextButton")
        card.Size = UDim2.new(
            cardWidth,
            -13,
            0,
            cardHeight
        )
        card.Position = UDim2.new(
            column * 0.5,
            column == 0 and 8 or 5,
            0,
            gridStartY + row * (cardHeight + cardGap)
        )
        card.BackgroundColor3 = Color3.fromRGB(31, 31, 40)
        card.BorderSizePixel = 0
        card.Text = ""
        card.Parent = chestSection
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.fromOffset(18, 18)
        indicator.Position = UDim2.fromOffset(9, 11)
        indicator.BorderSizePixel = 0
        indicator.Parent = card
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 5)

        local check = Instance.new("TextLabel")
        check.Size = UDim2.fromScale(1, 1)
        check.BackgroundTransparency = 1
        check.Font = Enum.Font.GothamBold
        check.TextSize = 11
        check.TextColor3 = Color3.fromRGB(255, 255, 255)
        check.Parent = indicator

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, -38, 1, 0)
        textLabel.Position = UDim2.fromOffset(34, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.Text = CHEST_DISPLAY_NAMES[chestType]
        textLabel.TextSize = 9
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextXAlignment = Enum.TextXAlignment.Left
        textLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
        textLabel.Parent = card

        chestFilterButtons[chestType] = {
            button = card,
            indicator = indicator,
            check = check,
            text = textLabel,
        }

        updateChestFilterButton(chestType)

        card.Activated:Connect(function()
            Config.ArcaneChestFilter[chestType] = not (
                Config.ArcaneChestFilter[chestType] == true
            )

            updateChestFilterButton(chestType)
            scanSelectedChests()
        end)
    end

    local filterRows = math.ceil(#CHEST_TYPE_ORDER / 2)
    local controlsY = gridStartY + filterRows * (cardHeight + cardGap) + 12

    local selectAllButton = Instance.new("TextButton")
    selectAllButton.Size = UDim2.new(0.5, -13, 0, 28)
    selectAllButton.Position = UDim2.fromOffset(8, controlsY)
    selectAllButton.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
    selectAllButton.BorderSizePixel = 0
    selectAllButton.Text = "SELECT ALL"
    selectAllButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    selectAllButton.Font = Enum.Font.GothamBold
    selectAllButton.TextSize = 9
    selectAllButton.Parent = chestSection
    Instance.new("UICorner", selectAllButton).CornerRadius = UDim.new(0, 7)

    local clearAllButton = Instance.new("TextButton")
    clearAllButton.Size = UDim2.new(0.5, -13, 0, 28)
    clearAllButton.Position = UDim2.new(0.5, 5, 0, controlsY)
    clearAllButton.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
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
        scanSelectedChests()
    end)

    clearAllButton.Activated:Connect(function()
        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            Config.ArcaneChestFilter[chestType] = false
            updateChestFilterButton(chestType)
        end
        scanSelectedChests()
    end)

    local scanControlsTitle = Instance.new("TextLabel")
    scanControlsTitle.Size = UDim2.new(1, -20, 0, 24)
    scanControlsTitle.Position = UDim2.fromOffset(10, controlsY + 40)
    scanControlsTitle.BackgroundTransparency = 1
    scanControlsTitle.Text = "SCAN RANGE"
    scanControlsTitle.TextColor3 = Color3.fromRGB(220, 220, 230)
    scanControlsTitle.Font = Enum.Font.GothamBold
    scanControlsTitle.TextSize = 10
    scanControlsTitle.TextXAlignment = Enum.TextXAlignment.Left
    scanControlsTitle.Parent = chestSection

    UI.createToggle(
        chestSection,
        "Infinite Distance Scan",
        "OFF = use a bounded scan. ON = scan every cached chest location regardless of distance.",
        "ArcaneInfiniteDistanceScan",
        controlsY + 66
    )

    UI.createToggle(
        chestSection,
        "Scan Distance Limit",
        "When enabled, only chest locations inside the selected radius are processed/displayed.",
        "ArcaneChestScanDistanceLimitEnabled",
        controlsY + 108
    )

    local scanSlider = UI.createSlider(
        chestSection,
        "Scan Distance (1 - 100,000)",
        "ArcaneChestScanDistance",
        1,
        100000,
        10,
        controlsY + 151,
        330,
        function(value)
            Config.ArcaneChestScanDistance = math.clamp(
                math.floor(tonumber(value) or 30000),
                1,
                100000
            )
            scanSelectedChests()
        end
    )

    scanSlider.setValue(Config.ArcaneChestScanDistance)

    local scanHint = Instance.new("TextLabel")
    scanHint.Size = UDim2.new(1, -20, 0, 32)
    scanHint.Position = UDim2.fromOffset(10, controlsY + 200)
    scanHint.BackgroundTransparency = 1
    scanHint.Text = "Tip: type a number in the slider box (example: 30000) instead of dragging."
    scanHint.TextColor3 = Color3.fromRGB(130, 130, 140)
    scanHint.Font = Enum.Font.Gotham
    scanHint.TextSize = 8
    scanHint.TextWrapped = true
    scanHint.TextXAlignment = Enum.TextXAlignment.Left
    scanHint.Parent = chestSection

    -------------------------------------------------
    -- TREASURE CHART FINDER
    -------------------------------------------------

    local treasureChartSection = UI.createSection(
        miscTab,
        "Treasure Chart Finder",
        280
    )

    UI.createToggle(
        treasureChartSection,
        "Treasure Chart Finder",
        "Only activates while a Treasure Chart is equipped; shows the destination, STUDS remaining, then highlights every matching physical dig part within 30 studs.",
        "ArcaneTreasureChartESP",
        32
    )

    local treasureChartStatus = Instance.new("TextLabel")
    treasureChartStatus.Size = UDim2.new(1, -16, 0, 54)
    treasureChartStatus.Position = UDim2.fromOffset(8, 78)
    treasureChartStatus.BackgroundTransparency = 1
    treasureChartStatus.Text = "Treasure Chart Finder: equip a Treasure Chart to activate."
    treasureChartStatus.TextColor3 = Color3.fromRGB(150, 150, 160)
    treasureChartStatus.Font = Enum.Font.Gotham
    treasureChartStatus.TextSize = 9
    treasureChartStatus.TextWrapped = true
    treasureChartStatus.TextXAlignment = Enum.TextXAlignment.Left
    treasureChartStatus.TextYAlignment = Enum.TextYAlignment.Top
    treasureChartStatus.Parent = treasureChartSection

    UI.createToggle(
        treasureChartSection,
        "Treasure Chart Debug",
        "Logs chart detection, clue parsing, island detection, candidates, STUDS and green-area state.",
        "ArcaneTreasureChartDebug",
        140
    )

    local destroyTreasureChartESP
    local treasureDebugLog
    local treasureChartLastKey
    local treasureChartCurrentObject
    local treasureChartNeedsScan
    local treasureChartLastScanAttempt

    Config.ArcaneTreasureChartClueSlot = nil

    local treasureDebugButton = Instance.new("TextButton")
    treasureDebugButton.Size = UDim2.fromOffset(130, 28)
    treasureDebugButton.Position = UDim2.fromOffset(10, 194)
    treasureDebugButton.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
    treasureDebugButton.BorderSizePixel = 0
    treasureDebugButton.Text = "VIEW DEBUG"
    treasureDebugButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    treasureDebugButton.Font = Enum.Font.GothamBold
    treasureDebugButton.TextSize = 9
    treasureDebugButton.Parent = treasureChartSection
    Instance.new("UICorner", treasureDebugButton).CornerRadius = UDim.new(0, 7)


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

    local espObjects = {}
    local candidateModels = {}

    local chestESPObjects = {}
    local staticChestESPObjects = {}
    local staticChestLocationCache = {}
    local staticChestLocationsScanned = false
    local chestCandidates = {}
    local openedChests = {}
    local openedChestLocations = {}
    local chestLifecycleWatchers = {}
    local chestTypeCache = setmetatable({}, {__mode = "k"})
    local staticChestAnchor = nil
    local isOpenedChestLocation


    local sideQuestESPObjects = {}
    local sideQuestCandidates = {}

    local treasureChartESP = nil
    treasureChartCurrentObject = nil
    treasureChartLastKey = nil
    local treasureDebugLines = {}
    local MAX_TREASURE_DEBUG_LINES = 250
    local treasureDebugGui = nil
    local openTreasureDebugList
    local treasureChartCandidateParts = {}
    local treasureChartHighlights = {}
    local treasureChartIslandModel = nil
    local treasureChartLastObjectScan = 0
    treasureChartNeedsScan = true
    treasureChartLastScanAttempt = 0
    local treasureDeepScanning = false
    local treasureTeleportGui = nil

    -- Forward declarations: these helpers are referenced by Treasure Chart
    -- functions that are defined earlier in this module.
    local treasureNormalize
    local getLocalPlayerRoot

    local function treasureDebugValue(value)
        if value == nil then
            return "<nil>"
        end

        local valueType = typeof(value)

        if valueType == "Vector3" then
            return ("Vector3(%.2f, %.2f, %.2f)"):format(
                value.X,
                value.Y,
                value.Z
            )
        end

        if valueType == "Instance" then
            local ok, fullName = pcall(function()
                return value:GetFullName()
            end)

            return ok and fullName or tostring(value)
        end

        return tostring(value)
    end

    treasureDebugLog = function(message)
        if not Config.ArcaneTreasureChartDebug then
            return
        end

        local line = "[TreasureDebug] "
            .. ("%.3f"):format(os.clock())
            .. " | "
            .. tostring(message)

        table.insert(treasureDebugLines, line)

        if #treasureDebugLines > MAX_TREASURE_DEBUG_LINES then
            table.remove(treasureDebugLines, 1)
        end

        print(line)
    end

    local function destroyTreasureDebugGui()
        if treasureDebugGui then
            pcall(function()
                treasureDebugGui:Destroy()
            end)
            treasureDebugGui = nil
        end
    end

    local function refreshTreasureDebugGuiText(statusText)
        if not treasureDebugGui or not treasureDebugGui.Parent then
            return
        end

        local panel = treasureDebugGui:FindFirstChild("Panel")
        if not panel then
            return
        end

        local box = panel:FindFirstChild("Logs")
        if box and box:IsA("TextBox") then
            box.Text = #treasureDebugLines > 0
                and table.concat(treasureDebugLines, "\n")
                or "No treasure debug logs yet."
        end

        local status = panel:FindFirstChild("DeepStatus")
        if status and status:IsA("TextLabel") then
            status.Text = statusText or ""
        end
    end

    local function treasureDeepScan()
        if not Config.ArcaneTreasureChartDebug then
            return
        end

        treasureDeepScanning = true
        treasureDebugLog("========== DEEP SCAN BEGIN ==========")
        refreshTreasureDebugGuiText("Scanning...")

        local collectionService = game:GetService("CollectionService")
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local player = Shared.player
        local character = player and player.Character
        local chart = treasureChartCurrentObject or (
            character and character:FindFirstChildOfClass("Tool")
        )

        local function logAttributes(object, prefix)
            if not object then
                return
            end

            local ok, attrs = pcall(function()
                return object:GetAttributes()
            end)

            if ok and type(attrs) == "table" then
                local keys = {}
                for key in pairs(attrs) do
                    keys[#keys + 1] = tostring(key)
                end
                table.sort(keys)

                for _, key in ipairs(keys) do
                    local value = attrs[key]
                    treasureDebugLog(
                        ("DEEP ATTR | %s | %s=%s")
                            :format(
                                prefix,
                                tostring(key),
                                treasureDebugValue(value)
                            )
                    )
                end
            end
        end

        local function logTags(object, prefix)
            if not object then
                return
            end

            local ok, tags = pcall(function()
                return collectionService:GetTags(object)
            end)

            if ok and type(tags) == "table" and #tags > 0 then
                treasureDebugLog(
                    ("DEEP TAGS | %s | %s")
                        :format(
                            prefix,
                            table.concat(tags, ", ")
                        )
                )
            end
        end

        local function isInterestingName(value)
            local normalized = treasureNormalize(value)

            return normalized:find("treasure", 1, true) ~= nil
                or normalized:find("chart", 1, true) ~= nil
                or normalized:find("buried", 1, true) ~= nil
                or normalized:find("dig", 1, true) ~= nil
                or normalized:find("shovel", 1, true) ~= nil
                or normalized:find("spot", 1, true) ~= nil
                or normalized:find("chest", 1, true) ~= nil
        end

        -- Deep Scan used to call GetDescendants() on huge containers.
        -- GetDescendants() allocates the complete descendant array before the
        -- first yield, which can temporarily stall Roblox rendering/UI.
        -- Walk the hierarchy incrementally instead and yield frequently.
        local function walkDescendantsYielding(root, callback)
            if not root then
                return
            end

            local stack = {}
            local initialChildren = root:GetChildren()

            for index = #initialChildren, 1, -1 do
                stack[#stack + 1] = initialChildren[index]
            end

            local scanned = 0

            while #stack > 0 do
                local object = stack[#stack]
                stack[#stack] = nil

                scanned += 1

                if scanned % 12 == 0 then
                    task.wait()
                end

                local shouldContinue = callback(object, scanned)

                if shouldContinue == false then
                    break
                end

                local children = object:GetChildren()

                for index = #children, 1, -1 do
                    stack[#stack + 1] = children[index]
                end
            end

            return scanned
        end

        local function scanContainer(root, rootName, maxMatches)
            if not root then
                treasureDebugLog(
                    ("DEEP CONTAINER | %s | <nil>"):format(rootName)
                )
                return
            end

            local matches = 0
            local scanned = 0

            refreshTreasureDebugGuiText(
                ("Scanning %s..."):format(rootName)
            )

            walkDescendantsYielding(root, function(object, count)
                scanned = count

                if scanned % 60 == 0 then
                    refreshTreasureDebugGuiText(
                        ("Scanning %s... checked %d"):format(rootName, scanned)
                    )
                end

                if isInterestingName(object.Name)
                    or (
                        object:IsA("RemoteEvent")
                        or object:IsA("RemoteFunction")
                    )
                        and isInterestingName(object.Parent and object.Parent.Name) then

                    matches += 1

                    treasureDebugLog(
                        ("DEEP OBJECT | %s | Class=%s | Name=%s | FullName=%s")
                            :format(
                                rootName,
                                object.ClassName,
                                tostring(object.Name),
                                treasureDebugValue(object)
                            )
                    )

                    logAttributes(object, rootName)
                    logTags(object, rootName)

                    if matches >= maxMatches then
                        treasureDebugLog(
                            ("DEEP LIMIT | %s | MaxMatches=%d")
                                :format(rootName, maxMatches)
                        )
                        return false
                    end
                end

                return true
            end)

            treasureDebugLog(
                ("DEEP CONTAINER DONE | %s | Matches=%d")
                    :format(rootName, matches)
            )

            refreshTreasureDebugGuiText(
                ("Finished %s | Matches=%d"):format(rootName, matches)
            )
        end

        if chart then
            treasureDebugLog(
                ("DEEP CHART | Class=%s | FullName=%s")
                    :format(chart.ClassName, treasureDebugValue(chart))
            )

            logAttributes(chart, "Chart")
            logTags(chart, "Chart")

            local chartScanned = 0

            walkDescendantsYielding(chart, function(object, index)
                chartScanned = index

                if chartScanned % 60 == 0 then
                    refreshTreasureDebugGuiText(
                        ("Scanning chart contents... checked %d"):format(chartScanned)
                    )
                end

                if isInterestingName(object.Name)
                    or object:IsA("StringValue")
                    or object:IsA("IntValue")
                    or object:IsA("NumberValue")
                    or object:IsA("BoolValue") then

                    local valueText = ""

                    if object:IsA("StringValue")
                        or object:IsA("IntValue")
                        or object:IsA("NumberValue")
                        or object:IsA("BoolValue") then
                        valueText = " | Value=" .. treasureDebugValue(object.Value)
                    end

                    treasureDebugLog(
                        ("DEEP CHART CHILD | #%d | Class=%s | Name=%s | FullName=%s%s")
                            :format(
                                index,
                                object.ClassName,
                                tostring(object.Name),
                                treasureDebugValue(object),
                                valueText
                            )
                    )

                    logAttributes(object, "ChartChild")
                    logTags(object, "ChartChild")
                end

                return true
            end)
        else
            treasureDebugLog("DEEP CHART | <none equipped>")
        end

        if treasureChartIslandModel then
            treasureDebugLog(
                ("DEEP ISLAND | %s"):format(
                    treasureDebugValue(treasureChartIslandModel)
                )
            )

            logAttributes(treasureChartIslandModel, "Island")
            logTags(treasureChartIslandModel, "Island")

            local matchCount = 0
            local islandScanned = 0

            walkDescendantsYielding(treasureChartIslandModel, function(object, count)
                islandScanned = count

                if islandScanned % 60 == 0 then
                    refreshTreasureDebugGuiText(
                        ("Scanning island... checked %d"):format(islandScanned)
                    )
                end

                if isInterestingName(object.Name) then
                    matchCount += 1

                    treasureDebugLog(
                        ("DEEP ISLAND OBJECT | Class=%s | Name=%s | FullName=%s")
                            :format(
                                object.ClassName,
                                tostring(object.Name),
                                treasureDebugValue(object)
                            )
                    )

                    logAttributes(object, "IslandObject")
                    logTags(object, "IslandObject")

                    if matchCount >= 120 then
                        treasureDebugLog("DEEP ISLAND LIMIT | MaxMatches=120")
                        return false
                    end
                end

                return true
            end)

            treasureDebugLog(
                ("DEEP ISLAND DONE | Matches=%d"):format(matchCount)
            )
        end

        scanContainer(replicatedStorage, "ReplicatedStorage", 120)

        local map = workspace:FindFirstChild("Map")
        scanContainer(map, "Workspace.Map", 120)

        local playerGui = Shared.playerGui

        if playerGui then
            local guiMatches = 0
            local guiScanned = 0

            walkDescendantsYielding(playerGui, function(object, count)
                guiScanned = count

                if guiScanned % 60 == 0 then
                    refreshTreasureDebugGuiText(
                        ("Scanning PlayerGui... checked %d"):format(guiScanned)
                    )
                end

                if (object:IsA("TextLabel")
                    or object:IsA("TextButton")
                    or object:IsA("TextBox"))
                    and tostring(object.Text or "") ~= "" then

                    local text = tostring(object.Text)

                    if isInterestingName(text) then
                        guiMatches += 1

                        treasureDebugLog(
                            ("DEEP GUI | Class=%s | Text=%s | FullName=%s")
                                :format(
                                    object.ClassName,
                                    text,
                                    treasureDebugValue(object)
                                )
                        )

                        if guiMatches >= 60 then
                            treasureDebugLog("DEEP GUI LIMIT | MaxMatches=60")
                            return false
                        end
                    end
                end

                return true
            end)

            treasureDebugLog(
                ("DEEP GUI DONE | Matches=%d"):format(guiMatches)
            )
        end

        treasureDebugLog("========== DEEP SCAN END ==========")
        treasureDeepScanning = false
        refreshTreasureDebugGuiText("Deep Scan complete")
    end

    openTreasureDebugList = function()
        local playerGui = Shared.playerGui

        if not playerGui then
            return
        end

        if treasureDebugGui and treasureDebugGui.Parent then
            local panel = treasureDebugGui:FindFirstChild("Panel")
            local box = panel and panel:FindFirstChild("Logs")

            if box and box:IsA("TextBox") then
                box.Text = #treasureDebugLines > 0
                    and table.concat(treasureDebugLines, "\n")
                    or "No treasure debug logs yet. Enable Treasure Chart Debug and equip a Treasure Chart."
            end

            treasureDebugGui.Enabled = true
            return
        end

        treasureDebugGui = Instance.new("ScreenGui")
        treasureDebugGui.Name = "SolarHubTreasureDebug"
        markSolarHubVisual(treasureDebugGui)
        treasureDebugGui.ResetOnSpawn = false
        treasureDebugGui.DisplayOrder = 1000002
        treasureDebugGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        treasureDebugGui.Parent = playerGui

        local overlay = Instance.new("TextButton")
        overlay.Name = "Overlay"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 0.35
        overlay.Text = ""
        overlay.AutoButtonColor = false
        overlay.Parent = treasureDebugGui

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.Position = UDim2.fromScale(0.5, 0.5)
        panel.Size = UDim2.new(0.82, 0, 0.72, 0)
        panel.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
        panel.BorderSizePixel = 0
        panel.Parent = treasureDebugGui
        Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Position = UDim2.fromOffset(12, 8)
        title.Size = UDim2.new(1, -52, 0, 28)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 12
        title.TextColor3 = Color3.fromRGB(235, 235, 240)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Treasure Chart Debug"
        title.Parent = panel

        local close = Instance.new("TextButton")
        close.Size = UDim2.fromOffset(28, 28)
        close.Position = UDim2.new(1, -38, 0, 8)
        close.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        close.BorderSizePixel = 0
        close.Text = "X"
        close.TextColor3 = Color3.fromRGB(235, 235, 240)
        close.Font = Enum.Font.GothamBold
        close.TextSize = 10
        close.Parent = panel
        Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)

        local copyButton = Instance.new("TextButton")
        copyButton.Name = "Copy"
        copyButton.Size = UDim2.fromOffset(64, 28)
        copyButton.Position = UDim2.new(1, -110, 0, 8)
        copyButton.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        copyButton.BorderSizePixel = 0
        copyButton.Text = "COPY"
        copyButton.TextColor3 = Color3.fromRGB(235, 235, 240)
        copyButton.Font = Enum.Font.GothamBold
        copyButton.TextSize = 10
        copyButton.Parent = panel
        Instance.new("UICorner", copyButton).CornerRadius = UDim.new(0, 6)

        local deepButton = Instance.new("TextButton")
        deepButton.Name = "DeepScan"
        deepButton.Size = UDim2.fromOffset(82, 28)
        deepButton.Position = UDim2.new(1, -274, 0, 8)
        deepButton.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        deepButton.BorderSizePixel = 0
        deepButton.Text = "DEEP SCAN"
        deepButton.TextColor3 = Color3.fromRGB(235, 235, 240)
        deepButton.Font = Enum.Font.GothamBold
        deepButton.TextSize = 10
        deepButton.Parent = panel
        Instance.new("UICorner", deepButton).CornerRadius = UDim.new(0, 6)

        local deepStatus = Instance.new("TextLabel")
        deepStatus.Name = "DeepStatus"
        deepStatus.Position = UDim2.fromOffset(10, 32)
        deepStatus.Size = UDim2.new(1, -20, 0, 12)
        deepStatus.BackgroundTransparency = 1
        deepStatus.Text = ""
        deepStatus.TextColor3 = Color3.fromRGB(145, 150, 165)
        deepStatus.Font = Enum.Font.Gotham
        deepStatus.TextSize = 9
        deepStatus.TextXAlignment = Enum.TextXAlignment.Left
        deepStatus.Parent = panel

        local clearButton = Instance.new("TextButton")
        clearButton.Name = "Clear"
        clearButton.Size = UDim2.fromOffset(64, 28)
        clearButton.Position = UDim2.new(1, -182, 0, 8)
        clearButton.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        clearButton.BorderSizePixel = 0
        clearButton.Text = "CLEAR"
        clearButton.TextColor3 = Color3.fromRGB(235, 235, 240)
        clearButton.Font = Enum.Font.GothamBold
        clearButton.TextSize = 10
        clearButton.Parent = panel
        Instance.new("UICorner", clearButton).CornerRadius = UDim.new(0, 6)

        local box = Instance.new("TextBox")
        box.Name = "Logs"
        box.Position = UDim2.fromOffset(10, 56)
        box.Size = UDim2.new(1, -20, 1, -66)
        box.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        box.BorderSizePixel = 0
        box.ClearTextOnFocus = false
        box.MultiLine = true
        box.TextEditable = false
        box.TextWrapped = false
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = Enum.TextYAlignment.Top
        box.Font = Enum.Font.Code
        box.TextSize = 10
        box.TextColor3 = Color3.fromRGB(225, 225, 230)
        box.Text = #treasureDebugLines > 0
            and table.concat(treasureDebugLines, "\n")
            or "No treasure debug logs yet. Enable Treasure Chart Debug and equip a Treasure Chart."
        box.Parent = panel

        copyButton.MouseButton1Click:Connect(function()
            local textToCopy = box.Text or ""
            local copied = false

            if type(setclipboard) == "function" then
                copied = pcall(setclipboard, textToCopy)
            elseif type(toclipboard) == "function" then
                copied = pcall(toclipboard, textToCopy)
            elseif type(set_clipboard) == "function" then
                copied = pcall(set_clipboard, textToCopy)
            end

            copyButton.Text = copied and "COPIED!" or "NO CLIP"
            task.delay(1.2, function()
                if copyButton and copyButton.Parent then
                    copyButton.Text = "COPY"
                end
            end)
        end)

        deepButton.MouseButton1Click:Connect(function()
            if treasureDeepScanning then
                return
            end

            treasureDeepScanning = true
            deepButton.Text = "SCANNING..."
            deepButton.AutoButtonColor = false

            task.spawn(function()
                local ok, err = xpcall(
                    treasureDeepScan,
                    function(scanError)
                        return debug.traceback(tostring(scanError), 2)
                    end
                )

                if not ok then
                    treasureDeepScanning = false
                    treasureDebugLog(
                        ("DEEP SCAN ERROR | %s"):format(tostring(err))
                    )
                    refreshTreasureDebugGuiText("Deep Scan error")
                end

                if deepButton and deepButton.Parent then
                    deepButton.Text = "DEEP SCAN"
                    deepButton.AutoButtonColor = true
                end

                refreshTreasureDebugGuiText(
                    ok and "Deep Scan complete" or "Deep Scan error"
                )
            end)
        end)

        clearButton.MouseButton1Click:Connect(function()
            table.clear(treasureDebugLines)
            box.Text = "Debug log cleared."
        end)

        close.MouseButton1Click:Connect(function()
            destroyTreasureDebugGui()
        end)

        overlay.MouseButton1Click:Connect(function()
            destroyTreasureDebugGui()
        end)
    end

    treasureDebugButton.Activated:Connect(function()
        -- Opening the viewer should turn tracing on automatically so the
        -- window does not look broken when the separate debug toggle is off.
        Config.ArcaneTreasureChartDebug = true
        treasureDebugLog("DEBUG VIEW OPENED | Logging enabled from VIEW DEBUG button")
        openTreasureDebugList()
        refreshTreasureDebugGuiText("Debug logging enabled")
    end)

    local treasureTeleportButton = Instance.new("TextButton")
    treasureTeleportButton.Size = UDim2.new(1, -20, 0, 28)
    treasureTeleportButton.Position = UDim2.fromOffset(10, 228)
    treasureTeleportButton.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
    treasureTeleportButton.BorderSizePixel = 0
    treasureTeleportButton.Text = "TP TO TREASURE"
    treasureTeleportButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    treasureTeleportButton.Font = Enum.Font.GothamBold
    treasureTeleportButton.TextSize = 9
    treasureTeleportButton.Parent = treasureChartSection
    Instance.new("UICorner", treasureTeleportButton).CornerRadius = UDim.new(0, 7)

    treasureTeleportButton.Activated:Connect(function()
        local marker = treasureChartESP
        local position = marker and marker.position
        local character = Shared.player and Shared.player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if not marker or marker.physicalTarget ~= true then
            treasureTeleportButton.Text = "TARGET NOT READY"

            task.delay(1.2, function()
                if treasureTeleportButton and treasureTeleportButton.Parent then
                    treasureTeleportButton.Text = "TP TO TREASURE"
                end
            end)

            treasureDebugLog("TP | Blocked | Physical treasure target is not loaded")
            return
        end

        if typeof(position) ~= "Vector3" then
            treasureTeleportButton.Text = "NO TARGET"

            task.delay(1.2, function()
                if treasureTeleportButton and treasureTeleportButton.Parent then
                    treasureTeleportButton.Text = "TP TO TREASURE"
                end
            end)

            treasureDebugLog("TP | Failed | MarkerPosition=nil")
            return
        end

        if not root then
            treasureTeleportButton.Text = "NO CHARACTER"

            task.delay(1.2, function()
                if treasureTeleportButton and treasureTeleportButton.Parent then
                    treasureTeleportButton.Text = "TP TO TREASURE"
                end
            end)

            treasureDebugLog("TP | Failed | HumanoidRootPart=nil")
            return
        end

        local targetPosition = position + Vector3.new(0, 4, 0)
        local ok, err = pcall(function()
            root.CFrame = CFrame.new(targetPosition)
        end)

        if ok then
            treasureTeleportButton.Text = "TELEPORTED"
            treasureDebugLog(
                ("TP | Success | Position=%s")
                    :format(treasureDebugValue(targetPosition))
            )
        else
            treasureTeleportButton.Text = "TP FAILED"
            treasureDebugLog(
                ("TP | Failed | Error=%s")
                    :format(tostring(err))
            )
        end

        task.delay(1.2, function()
            if treasureTeleportButton and treasureTeleportButton.Parent then
                treasureTeleportButton.Text = "TP TO TREASURE"
            end
        end)
    end)

    -------------------------------------------------
    -- TREASURE CHART TRACKER
    -------------------------------------------------

    local TREASURE_CHART_DIRECTIONS = {
        "East", "East Southeast", "Southeast", "South Southeast",
        "South", "South Southwest", "Southwest", "West Southwest",
        "West", "West Northwest", "Northwest", "North Northwest",
        "North", "North Northeast", "Northeast", "East Northeast",
    }

    local TREASURE_CHART_DISTANCE_BANDS = {
        ["Few paces"] = {0, 1 / 3},
        Halfway = {1 / 3, 2 / 3},
        ["On the edge"] = {2 / 3, 1.10},
    }

    local TREASURE_CHART_ARRIVAL_DISTANCE = 30

    local TREASURE_CHART_ISLANDS = {
        "Frostmill Island", "Ravenna", "Forest of Cernunno", "Shell Island",
        "Harvest Island", "Whitesummit", "Munera Garden", "Wind-Row Island",
        "Palo Town", "Blasted Rock", "Thorin's Refuge", "Limestone Key",
        "Akursius Keep", "Blackreach Island", "Thrylos Crossing", "Cedar Arch",
        "Ierochos", "Sameria", "Shale Reef", "Drakos Arch", "Claw Island",
        "Makrinaos",
    }

    local TREASURE_CHART_DIRECTION_ANGLES = {
        East = 0,
        ["East Southeast"] = 22.5,
        Southeast = 45,
        ["South Southeast"] = 67.5,
        South = 90,
        ["South Southwest"] = 112.5,
        Southwest = 135,
        ["West Southwest"] = 157.5,
        West = 180,
        ["West Northwest"] = 202.5,
        Northwest = 225,
        ["North Northwest"] = 247.5,
        North = 270,
        ["North Northeast"] = 292.5,
        Northeast = 315,
        ["East Northeast"] = 337.5,
    }

    treasureNormalize = function(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function treasureDirectionVector(direction)
        local degrees = TREASURE_CHART_DIRECTION_ANGLES[direction]

        if degrees == nil then
            return nil
        end

        local angle = math.rad(degrees)

        -- Arcane's common chart locators use +X = East and +Z = South.
        return Vector3.new(math.cos(angle), 0, math.sin(angle))
    end

    local function destroyTreasureChartMarkerVisual()
        if not treasureChartESP then
            return
        end

        if treasureChartESP.highlight then
            pcall(function() treasureChartESP.highlight:Destroy() end)
        end

        if treasureChartESP.billboard then
            pcall(function() treasureChartESP.billboard:Destroy() end)
        end

        if treasureChartESP.anchor then
            pcall(function() treasureChartESP.anchor:Destroy() end)
        end

        treasureChartESP = nil
    end

    destroyTreasureChartESP = function()
        destroyTreasureChartMarkerVisual()

        for _, highlight in ipairs(treasureChartHighlights) do
            pcall(function() highlight:Destroy() end)
        end

        table.clear(treasureChartHighlights)
        table.clear(treasureChartCandidateParts)
        treasureChartIslandModel = nil
    end

    local function addTreasureChartObjectText(object, sources)
        if not object then
            return
        end

        table.insert(sources, tostring(object.Name))

        if object:IsA("Tool") then
            pcall(function()
                if object.ToolTip and object.ToolTip ~= "" then
                    table.insert(sources, tostring(object.ToolTip))
                end
            end)
        end

        local okAttrs, attrs = pcall(function()
            return object:GetAttributes()
        end)

        if okAttrs and type(attrs) == "table" then
            for key, value in pairs(attrs) do
                table.insert(sources, tostring(key))

                if typeof(value) == "string" then
                    table.insert(sources, value)
                end
            end
        end

        for _, child in ipairs(object:GetDescendants()) do
            if child:IsA("StringValue") then
                table.insert(sources, tostring(child.Value))
            elseif child:IsA("TextLabel") or child:IsA("TextBox") then
                table.insert(sources, tostring(child.Text))
            end
        end
    end

    local function isSolarHubGuiObject(object, playerGui)
        local current = object

        while current and current ~= playerGui do
            local name = tostring(current.Name or "")

            if name:sub(1, 8) == "SolarHub"
                or name:sub(1, 13) == "SolarTreasure"
                or name == "SolarArcaneBossNotifications" or name:sub(1, 11) == "SolarArcane" then
                return true
            end

            current = current.Parent
        end

        return false
    end

    local function collectTreasureChartGuiText()
        local playerGui = Shared.playerGui
        if not playerGui then
            return ""
        end

        local parts = {}

        for _, object in ipairs(playerGui:GetDescendants()) do
            if (object:IsA("TextLabel")
                or object:IsA("TextButton")
                or object:IsA("TextBox"))
                and not isSolarHubGuiObject(object, playerGui) then

                local text = tostring(object.Text or "")

                if text ~= "" then
                    local normalized = treasureNormalize(text)

                    if normalized:find("fewpaces", 1, true)
                        or normalized:find("halfway", 1, true)
                        or normalized:find("ontheedge", 1, true)
                        or normalized:find("buried", 1, true)
                        or normalized:find("treasure", 1, true) then
                        table.insert(parts, text)
                    end
                end
            end
        end

        return table.concat(parts, " | ")
    end

    local function parseTreasureChartText(text)
        local normalized = treasureNormalize(text)

        local island
        local islandNameLength = 0

        for _, name in ipairs(TREASURE_CHART_ISLANDS) do
            local normalizedName = treasureNormalize(name)

            if normalized:find(normalizedName, 1, true)
                and #normalizedName > islandNameLength then
                island = name
                islandNameLength = #normalizedName
            end
        end

        local direction
        local directionLength = 0

        for _, name in ipairs(TREASURE_CHART_DIRECTIONS) do
            local normalizedName = treasureNormalize(name)

            if normalized:find(normalizedName, 1, true)
                and #normalizedName > directionLength then
                direction = name
                directionLength = #normalizedName
            end
        end

        local distance

        -- Charts use several natural-language variants for the same three
        -- distance bands. Common charts often say "not too far ... from the
        -- center" instead of the literal phrase "few paces".
        if normalized:find("fewpaces", 1, true)
            or normalized:find("fewsteps", 1, true)
            or normalized:find("nottoofar", 1, true)
            or normalized:find("slightly", 1, true)
            or normalized:find("nearthecenter", 1, true)
            or (
                normalized:find("fromthecenter", 1, true)
                and not normalized:find("halfway", 1, true)
                and not normalized:find("midway", 1, true)
            ) then
            distance = "Few paces"
        elseif normalized:find("halfway", 1, true)
            or normalized:find("midway", 1, true)
            or normalized:find("roughlyhalf", 1, true) then
            distance = "Halfway"
        elseif normalized:find("ontheedge", 1, true)
            or normalized:find("boundary", 1, true)
            or normalized:find("edge", 1, true)
            or normalized:find("edges", 1, true) then
            distance = "On the edge"
        end

        local surface

        if normalized:find("snow", 1, true) then
            surface = "SNOW"
        elseif normalized:find("sand", 1, true) then
            surface = "SAND"
        elseif normalized:find("ground", 1, true)
            or normalized:find("grass", 1, true) then
            surface = "GROUND"
        end

        return {
            island = island,
            direction = direction,
            distance = distance,
            surface = surface,
            rawText = text,
        }
    end

    local function readTreasureClueStructuredData(clueSource)
        if not clueSource then
            return {}
        end

        local data = {}

        -- Arcane exposes useful normalized clue fields on TextN objects in
        -- runtime (for example ISN and DIR). Prefer those over parsing English
        -- text because island names can change/add over time.
        local okAttrs, attrs = pcall(function()
            return clueSource:GetAttributes()
        end)

        if okAttrs and type(attrs) == "table" then
            for key, value in pairs(attrs) do
                local normalizedKey = treasureNormalize(key)

                if typeof(value) == "string" then
                    if normalizedKey == "isn"
                        or normalizedKey == "island"
                        or normalizedKey == "islandname" then
                        data.island = value
                    elseif normalizedKey == "dir"
                        or normalizedKey == "direction" then
                        data.direction = value
                    elseif normalizedKey == "dist"
                        or normalizedKey == "distance"
                        or normalizedKey == "distanceband" then
                        data.distance = value
                    elseif normalizedKey == "surf"
                        or normalizedKey == "surface"
                        or normalizedKey == "material" then
                        data.surface = value
                    end
                end
            end
        end

        -- Also support StringValues/NumberValues nested under TextN in case a
        -- server version exposes the same data as child values rather than
        -- attributes.
        for _, child in ipairs(clueSource:GetDescendants()) do
            local key = treasureNormalize(child.Name)

            local value
            if child:IsA("StringValue")
                or child:IsA("IntValue")
                or child:IsA("NumberValue") then
                value = tostring(child.Value)
            end

            if value then
                if key == "isn"
                    or key == "island"
                    or key == "islandname" then
                    data.island = value
                elseif key == "dir"
                    or key == "direction" then
                    data.direction = value
                elseif key == "dist"
                    or key == "distance"
                    or key == "distanceband" then
                    data.distance = value
                elseif key == "surf"
                    or key == "surface"
                    or key == "material" then
                    data.surface = value
                end
            end
        end

        if type(data.distance) == "string" then
            local normalizedDistance = treasureNormalize(data.distance)

            if normalizedDistance == "fewpaces" then
                data.distance = "Few paces"
            elseif normalizedDistance == "halfway"
                or normalizedDistance == "midway" then
                data.distance = "Halfway"
            elseif normalizedDistance == "ontheedge"
                or normalizedDistance == "edge"
                or normalizedDistance == "boundary" then
                data.distance = "On the edge"
            end
        end

        if type(data.surface) == "string" then
            local normalizedSurface = treasureNormalize(data.surface)

            if normalizedSurface:find("snow", 1, true) then
                data.surface = "SNOW"
            elseif normalizedSurface:find("sand", 1, true) then
                data.surface = "SAND"
            elseif normalizedSurface:find("ground", 1, true)
                or normalizedSurface:find("grass", 1, true) then
                data.surface = "GROUND"
            end
        end

        return data
    end

    local function findTreasureChartActiveText(chart)
        if not chart then
            return nil, nil, nil
        end

        local clueValues = {}

        for _, child in ipairs(chart:GetDescendants()) do
            if child:IsA("StringValue") then
                local number = tostring(child.Name):match("^Text(%d+)$")
                local clueText = tostring(child.Value or "")

                if number and clueText ~= "" then
                    table.insert(clueValues, {
                        index = tonumber(number),
                        text = clueText,
                        source = child,
                    })
                end
            end
        end

        table.sort(clueValues, function(a, b)
            return a.index < b.index
        end)

        if #clueValues == 0 then
            treasureDebugLog("CLUE SOURCE FAIL | No TextN StringValues found in chart tool")
            return nil, nil, nil
        end

        local playerGui = Shared.playerGui

        local function isActuallyVisible(object)
            local current = object

            while current and current ~= playerGui do
                if current:IsA("GuiObject") and not current.Visible then
                    return false
                end

                if current:IsA("ScreenGui") and not current.Enabled then
                    return false
                end

                current = current.Parent
            end

            return true
        end

        local function belongsToTreasureChartGui(object)
            local current = object

            while current and current ~= playerGui do
                if current.Name == "TreasureChartGui" then
                    return true
                end

                current = current.Parent
            end

            return false
        end

        local function normalizedMatch(a, b)
            local na = treasureNormalize(a)
            local nb = treasureNormalize(b)

            return na ~= ""
                and nb ~= ""
                and (
                    na == nb
                    or na:find(nb, 1, true) ~= nil
                    or nb:find(na, 1, true) ~= nil
                )
        end

        if playerGui then
            local exactMatches = {}
            local chartUiTexts = {}

            for _, guiObject in ipairs(playerGui:GetDescendants()) do
                if (guiObject:IsA("TextLabel")
                    or guiObject:IsA("TextButton")
                    or guiObject:IsA("TextBox"))
                    and isActuallyVisible(guiObject)
                    and not isSolarHubGuiObject(guiObject, playerGui) then

                    local guiText = tostring(guiObject.Text or "")

                    if guiText ~= "" then
                        local inChartGui = belongsToTreasureChartGui(guiObject)

                        if inChartGui then
                            table.insert(chartUiTexts, {
                                object = guiObject,
                                text = guiText,
                            })
                        end

                        for _, clue in ipairs(clueValues) do
                            if normalizedMatch(guiText, clue.text) then
                                table.insert(exactMatches, {
                                    clue = clue,
                                    object = guiObject,
                                    inChartGui = inChartGui,
                                    exact = treasureNormalize(guiText)
                                        == treasureNormalize(clue.text),
                                })
                                break
                            end
                        end
                    end
                end
            end

            -- The rendered game clue determines the current stage. Text1,
            -- Text2 and Text3 are sequential stages, not user-selectable modes.
            table.sort(exactMatches, function(a, b)
                if a.inChartGui ~= b.inChartGui then
                    return a.inChartGui
                end

                if a.exact ~= b.exact then
                    return a.exact
                end

                return a.clue.index < b.clue.index
            end)

            if #exactMatches > 0 then
                local match = exactMatches[1]

                treasureDebugLog(
                    ("ACTIVE CLUE | Source=PlayerGui | Text%d | GUI=%s | AutoStage=true")
                        :format(
                            match.clue.index,
                            treasureDebugValue(match.object)
                        )
                )

                return match.clue.text, "Text" .. tostring(match.clue.index), match.clue.source
            end

            -- If the active clue is reformatted by the game UI, parse only the
            -- currently rendered clue text instead of merging hidden future stages.
            for _, entry in ipairs(chartUiTexts) do
                local normalized = treasureNormalize(entry.text)
                local looksLikeClue =
                    normalized:find("halfway", 1, true) ~= nil
                    or normalized:find("midway", 1, true) ~= nil
                    or normalized:find("fewpaces", 1, true) ~= nil
                    or normalized:find("ontheedge", 1, true) ~= nil
                    or normalized:find("buried", 1, true) ~= nil
                    or normalized:find("fromthecenter", 1, true) ~= nil

                if looksLikeClue then
                    treasureDebugLog(
                        ("ACTIVE CLUE | Source=PlayerGuiText | GUI=%s | Text=%s | AutoStage=true")
                            :format(
                                treasureDebugValue(entry.object),
                                entry.text
                            )
                    )

                    return entry.text, "PlayerGuiText", nil
                end
            end
        end

        -- Use the first clue only while the game's chart UI has not appeared.
        -- Once it is rendered, never regress to Text1 if the stage has changed.
        local first = clueValues[1]

        treasureDebugLog(
            ("ACTIVE CLUE | Source=ToolFallback | Text%d | UIUnavailable=true")
                :format(first.index)
        )

        return first.text, "Text" .. tostring(first.index), first.source
    end

    local function parseTreasureChartText(text)
        local normalized = treasureNormalize(text)

        local island
        local islandNameLength = 0
        local islandNames = {}

        for _, name in ipairs(TREASURE_CHART_ISLANDS) do
            islandNames[name] = true
        end

        local map = workspace:FindFirstChild("Map")
        if map then
            for _, object in ipairs(map:GetChildren()) do
                if object:IsA("Model") or object:IsA("Folder") then
                    islandNames[object.Name] = true
                end
            end
        end

        for name in pairs(islandNames) do
            local normalizedName = treasureNormalize(name)
            local shortName = normalizedName:gsub("island$", "")

            if normalizedName ~= ""
                and (
                    normalized:find(normalizedName, 1, true)
                    or (#shortName >= 4 and normalized:find(shortName, 1, true))
                ) then
                local candidateLength = math.max(#normalizedName, #shortName)
                if candidateLength > islandNameLength then
                    island = name
                    islandNameLength = candidateLength
                end
            end
        end

        local direction
        local directionLength = 0
        for _, name in ipairs(TREASURE_CHART_DIRECTIONS) do
            local normalizedName = treasureNormalize(name)
            if normalized:find(normalizedName, 1, true)
                and #normalizedName > directionLength then
                direction = name
                directionLength = #normalizedName
            end
        end

        local distance
        if normalized:find("fewpaces", 1, true)
            or normalized:find("fewsteps", 1, true)
            or normalized:find("nottoofar", 1, true)
            or normalized:find("nearthecenter", 1, true)
            or (
                normalized:find("fromthecenter", 1, true)
                and not normalized:find("halfway", 1, true)
                and not normalized:find("midway", 1, true)
            ) then
            distance = "Few paces"
        elseif normalized:find("halfway", 1, true)
            or normalized:find("midway", 1, true)
            or normalized:find("roughlyhalf", 1, true)
            or normalized:find("aboutmidway", 1, true) then
            distance = "Halfway"
        elseif normalized:find("ontheedge", 1, true)
            or normalized:find("edge", 1, true)
            or normalized:find("boundary", 1, true) then
            distance = "On the edge"
        end

        local surface
        if normalized:find("snow", 1, true) then
            surface = "SNOW"
        elseif normalized:find("sand", 1, true) then
            surface = "SAND"
        elseif normalized:find("ground", 1, true)
            or normalized:find("grass", 1, true) then
            surface = "GROUND"
        end

        local elevation
        if normalized:find("abovetheclouds", 1, true)
            or normalized:find("skyisland", 1, true)
            or normalized:find("abovetheworld", 1, true) then
            elevation = "SKY"
        elseif normalized:find("sealevel", 1, true)
            or normalized:find("atwaterlevel", 1, true)
            or normalized:find("nearwaterlevel", 1, true) then
            elevation = "SEA_LEVEL"
        elseif normalized:find("highvantage", 1, true)
            or normalized:find("highcliff", 1, true)
            or normalized:find("greatheight", 1, true)
            or normalized:find("decentheight", 1, true)
            or normalized:find("higherground", 1, true)
            or normalized:find("highground", 1, true)
            or normalized:find("highabove", 1, true)
            or normalized:find("atopacliff", 1, true)
            or normalized:find("higherearth", 1, true)
            or normalized:find("highaltitude", 1, true) then
            elevation = "HIGH"
        end

        local coastal =
            normalized:find("coastal", 1, true) ~= nil
            or normalized:find("overlookingthesea", 1, true) ~= nil
            or normalized:find("neartheocean", 1, true) ~= nil
            or normalized:find("bythesea", 1, true) ~= nil

        return {
            island = island,
            direction = direction,
            distance = distance,
            surface = surface,
            elevation = elevation,
            coastal = coastal,
            rawText = text,
        }
    end

    local function getTreasureChartInfo(chart)
        local activeText, activeSource, clueSource =
            findTreasureChartActiveText(chart)

        local text = activeText or ""
        local info = parseTreasureChartText(text)

        local structured = readTreasureClueStructuredData(clueSource)

        if structured.island and structured.island ~= "" then
            info.island = structured.island
        end

        if structured.direction and structured.direction ~= "" then
            for _, name in ipairs(TREASURE_CHART_DIRECTIONS) do
                if treasureNormalize(name) == treasureNormalize(structured.direction) then
                    info.direction = name
                    break
                end
            end
        end

        if structured.distance then
            info.distance = structured.distance
        end

        if structured.surface then
            info.surface = structured.surface
        end

        treasureDebugLog(
            ("CLUE PARSE | Chart=%s | Source=%s | Island=%s | Direction=%s | Distance=%s | Surface=%s | Elevation=%s | Coastal=%s | StructuredIsland=%s | StructuredDirection=%s | Raw=%s")
                :format(
                    treasureDebugValue(chart),
                    tostring(activeSource),
                    tostring(info.island),
                    tostring(info.direction),
                    tostring(info.distance),
                    tostring(info.surface),
                    tostring(info.elevation),
                    tostring(info.coastal),
                    tostring(structured.island),
                    tostring(structured.direction),
                    tostring(info.rawText)
                )
        )

        if not info.island or not info.direction or not info.distance then
            treasureDebugLog(
                ("CLUE INCOMPLETE | Source=%s | Island=%s | Direction=%s | Distance=%s | Raw=%s")
                    :format(
                        tostring(activeSource),
                        tostring(info.island),
                        tostring(info.direction),
                        tostring(info.distance),
                        tostring(text)
                    )
            )
        end

        info.stage = tonumber(tostring(activeSource):match("Text(%d+)"))
        info.rawText = text
        return info
    end

    local function findTreasureIslandModel(islandName)
        local map = workspace:FindFirstChild("Map")
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local rs = replicatedStorage:FindFirstChild("RS")
        local unloadIslands = rs and rs:FindFirstChild("UnloadIslands")

        if (not map and not unloadIslands) or not islandName then
            treasureDebugLog(
                ("ISLAND LOOKUP FAIL | Map=%s | UnloadIslands=%s | Island=%s")
                    :format(
                        tostring(map ~= nil),
                        tostring(unloadIslands ~= nil),
                        tostring(islandName)
                    )
            )
            return nil
        end

        -- Workspace.Map can contain empty name-only folders (for example,
        -- Map.Ierochos). The actual walkable terrain may be in a sibling
        -- named "Ierochos_Surrounding" or in RS.UnloadIslands.
        -- Search likely container names directly instead of walking every
        -- descendant of the entire map (100k+ objects in live diagnostics).
        local aliases = {
            tostring(islandName),
            tostring(islandName) .. "_Surrounding",
            tostring(islandName) .. "-Surrounding",
            tostring(islandName) .. " Surrounding",
            tostring(islandName) .. "_Island",
            tostring(islandName) .. " Island",
        }

        local function getPhysicalStats(container)
            local minX, minY, minZ = math.huge, math.huge, math.huge
            local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
            local partCount = 0

            local ok, descendants = pcall(function()
                return container:GetDescendants()
            end)

            if not ok or not descendants then
                return 0, Vector3.new(0, 0, 0), 0
            end

            for index, object in ipairs(descendants) do
                if index % 2500 == 0 then
                    task.wait()
                end

                if object:IsA("BasePart")
                    and object.Transparency < 0.98
                    and math.max(object.Size.X, object.Size.Z) >= 1 then

                    local p = object.Position
                    local half = object.Size * 0.5

                    minX = math.min(minX, p.X - math.abs(half.X))
                    minY = math.min(minY, p.Y - math.abs(half.Y))
                    minZ = math.min(minZ, p.Z - math.abs(half.Z))
                    maxX = math.max(maxX, p.X + math.abs(half.X))
                    maxY = math.max(maxY, p.Y + math.abs(half.Y))
                    maxZ = math.max(maxZ, p.Z + math.abs(half.Z))
                    partCount += 1
                end
            end

            if partCount == 0 then
                return 0, Vector3.new(0, 0, 0), 0
            end

            local size = Vector3.new(
                maxX - minX,
                maxY - minY,
                maxZ - minZ
            )
            local area = math.max(size.X, 0) * math.max(size.Z, 0)
            return partCount, size, area
        end

        local function tryRoot(root, sourceName, allowRecursiveFallback)
            if not root then
                return nil
            end

            local candidates = {}
            local seen = {}

            local function consider(object)
                if not object
                    or seen[object]
                    or not (object:IsA("Model") or object:IsA("Folder"))
                    or treasureNormalize(object.Name) ~= treasureNormalize(islandName)
                        and not treasureNormalize(object.Name):find(
                            treasureNormalize(islandName) .. "surrounding",
                            1,
                            true
                        )
                        and not treasureNormalize(object.Name):find(
                            treasureNormalize(islandName) .. "island",
                            1,
                            true
                        ) then
                    return
                end

                seen[object] = true
                local partCount, size, area = getPhysicalStats(object)

                treasureDebugLog(
                    ("ISLAND CANDIDATE | Source=%s | Container=%s | Parts=%d | Footprint=%.1fx%.1f")
                        :format(
                            sourceName,
                            treasureDebugValue(object),
                            partCount,
                            size.X,
                            size.Z
                        )
                )

                if partCount >= 8 and size.X >= 40 and size.Z >= 40 then
                    table.insert(candidates, {
                        object = object,
                        partCount = partCount,
                        size = size,
                        area = area,
                    })
                else
                    treasureDebugLog(
                        ("ISLAND CANDIDATE REJECTED | Source=%s | Container=%s | Reason=NoMeaningfulWorldGeometry")
                            :format(sourceName, treasureDebugValue(object))
                    )
                end
            end

            -- First do O(number-of-aliases) direct-child lookups. This quickly
            -- handles the normal layout without scanning the whole hierarchy.
            for _, alias in ipairs(aliases) do
                local ok, found = pcall(function()
                    return root:FindFirstChild(alias)
                end)

                if ok and found then
                    consider(found)
                end
            end

            -- Unloaded island templates can be nested in folders. Only the
            -- unloaded-template source gets a recursive name lookup fallback;
            -- do not run a Lua GetDescendants loop over Workspace.Map.
            if #candidates == 0 and allowRecursiveFallback then
                local recursiveAliases = {
                    tostring(islandName) .. "_Surrounding",
                    tostring(islandName),
                    tostring(islandName) .. "_Island",
                }

                for _, alias in ipairs(recursiveAliases) do
                    local ok, found = pcall(function()
                        return root:FindFirstChild(alias, true)
                    end)

                    if ok and found then
                        consider(found)
                        if #candidates > 0 then
                            break
                        end
                    end
                end
            end

            table.sort(candidates, function(a, b)
                if a.area == b.area then
                    return a.partCount > b.partCount
                end
                return a.area > b.area
            end)

            local best = candidates[1]
            if best then
                treasureDebugLog(
                    ("ISLAND FOUND | Method=NamedPhysicalContainer | Source=%s | Wanted=%s | Container=%s | Parts=%d | Footprint=%.1fx%.1f")
                        :format(
                            sourceName,
                            tostring(islandName),
                            treasureDebugValue(best.object),
                            best.partCount,
                            best.size.X,
                            best.size.Z
                        )
                )
                return best.object
            end

            treasureDebugLog(
                ("ISLAND LOOKUP NO NAMED GEOMETRY | Wanted=%s | Source=%s | Recursive=%s")
                    :format(tostring(islandName), sourceName, tostring(allowRecursiveFallback))
            )
            return nil
        end

        local live = tryRoot(map, "Workspace.Map", false)
        if live then
            return live
        end

        local unloaded = tryRoot(unloadIslands, "RS.UnloadIslands", true)
        if unloaded then
            return unloaded
        end

        treasureDebugLog(
            ("ISLAND NOT FOUND | Wanted=%s | Reason=NoPhysicalContainer | Map=%s | UnloadIslands=%s")
                :format(
                    tostring(islandName),
                    treasureDebugValue(map),
                    treasureDebugValue(unloadIslands)
                )
        )

        return nil
    end

    local function treasurePartHasNoTreasureSpot(part)
        if not part or not part:IsA("BasePart") then
            return true
        end

        -- Runtime diagnostics showed the map contains BoolValues named
        -- "NoTreasureSpot" directly under Fragmentable parts. Treat those parts
        -- as explicitly ineligible for buried treasure.
        local marker = part:FindFirstChild("NoTreasureSpot")

        if marker and marker:IsA("BoolValue") then
            return marker.Value ~= false
        end

        -- Also allow the marker to be attached slightly deeper in the part's
        -- immediate descendant tree for streamed variants.
        local nested = part:FindFirstChild("NoTreasureSpot", true)

        if nested and nested:IsA("BoolValue") then
            return nested.Value ~= false
        end

        return false
    end

    local function treasurePartMatchesSurface(part, surface)
        if not surface then
            return true
        end

        local material = part.Material
        local name = treasureNormalize(part.Name)
        local parentName = part.Parent and treasureNormalize(part.Parent.Name) or ""

        if surface == "SAND" then
            return material == Enum.Material.Sand
                or name:find("sand", 1, true) ~= nil
                or parentName:find("sand", 1, true) ~= nil
        end

        if surface == "SNOW" then
            return material == Enum.Material.Snow
                or material == Enum.Material.Glacier
                or name:find("snow", 1, true) ~= nil
                or parentName:find("snow", 1, true) ~= nil
        end

        if surface == "GROUND" then
            return material == Enum.Material.Ground
                or material == Enum.Material.Grass
                or material == Enum.Material.LeafyGrass
                or material == Enum.Material.Mud
                or name:find("ground", 1, true) ~= nil
                or name:find("grass", 1, true) ~= nil
                or parentName:find("ground", 1, true) ~= nil
                or parentName:find("grass", 1, true) ~= nil
        end

        return true
    end

    local function getTreasureDigSurfacePosition(part)
        if not part or not part:IsA("BasePart") then
            return nil
        end

        -- Highlight/target the top surface rather than the BasePart center.
        local halfHeight = math.abs(part.Size.Y) * 0.5

        return part.Position
            + part.CFrame.UpVector * (halfHeight + 0.15)
    end

    local function getTreasureIslandBounds(root)
        if not root then
            return nil
        end

        if root:IsA("Model") then
            local okBounds, cf, size = pcall(function()
                return root:GetBoundingBox()
            end)

            if okBounds and cf and size then
                -- Treasure chart directions are based on the visible island
                -- footprint. Use the bounding-box center, not Model:GetPivot(),
                -- because streamed Fragmentable models may have authored pivots
                -- that are nowhere near the whole island.
                return cf.Position, size
            end
        end

        -- Some Arcane islands are folders containing the actual Fragmentable
        -- terrain model. Calculate a world-space footprint from their BaseParts.
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        local found = 0

        local ok = pcall(function()
            for _, object in ipairs(root:GetDescendants()) do
                if object:IsA("BasePart") then
                    local p = object.Position
                    local half = object.Size * 0.5

                    minX = math.min(minX, p.X - math.abs(half.X))
                    minY = math.min(minY, p.Y - math.abs(half.Y))
                    minZ = math.min(minZ, p.Z - math.abs(half.Z))
                    maxX = math.max(maxX, p.X + math.abs(half.X))
                    maxY = math.max(maxY, p.Y + math.abs(half.Y))
                    maxZ = math.max(maxZ, p.Z + math.abs(half.Z))
                    found += 1
                end
            end
        end)

        if not ok or found == 0 then
            return nil
        end

        local size = Vector3.new(
            maxX - minX,
            maxY - minY,
            maxZ - minZ
        )

        local center = Vector3.new(
            (minX + maxX) * 0.5,
            (minY + maxY) * 0.5,
            (minZ + maxZ) * 0.5
        )

        return center, size
    end

    local function getTreasureChartExplicitSpot(islandModel)
        if not islandModel then
            return nil
        end

        local collectionService = game:GetService("CollectionService")

        local wantedTags = {
            "TreasureSpot",
            "TreasureSpots",
            "BuriedChests",
        }

        for _, tagName in ipairs(wantedTags) do
            local ok, tagged = pcall(function()
                return collectionService:GetTagged(tagName)
            end)

            if ok and type(tagged) == "table" then
                for _, object in ipairs(tagged) do
                    if object
                        and object.Parent
                        and object:IsDescendantOf(islandModel) then

                        local root = nil

                        if object:IsA("BasePart") then
                            root = object
                        elseif object:IsA("Model") then
                            root = object.PrimaryPart
                                or object:FindFirstChild("Base", true)
                                or object:FindFirstChildWhichIsA("BasePart", true)
                        end

                        if root and root:IsA("BasePart") then
                            return root, "TAG:" .. tagName
                        end
                    end
                end
            end
        end

        -- Some versions may expose the target by an explicit object name.
        for _, object in ipairs(islandModel:GetDescendants()) do
            local normalized = treasureNormalize(object.Name)

            if (object:IsA("BasePart") or object:IsA("Model"))
                and (
                    normalized:find("treasurespot", 1, true)
                    or normalized:find("buriedtreasure", 1, true)
                    or normalized:find("buriedchest", 1, true)
                ) then

                local root = object:IsA("BasePart")
                    and object
                    or (
                        object.PrimaryPart
                            or object:FindFirstChild("Base", true)
                            or object:FindFirstChildWhichIsA("BasePart", true)
                    )

                if root and root:IsA("BasePart") then
                    return root, "NAME"
                end
            end
        end

        return nil, nil
    end

    local function findTreasureChartDiggableContainer(islandModel)
        if not islandModel then
            return nil
        end

        if treasureNormalize(islandModel.Name) == "fragmentable" then
            return islandModel
        end

        local fragmentable = islandModel:FindFirstChild("Fragmentable", true)
        if fragmentable
            and (fragmentable:IsA("Folder") or fragmentable:IsA("Model")) then
            return fragmentable
        end

        return nil
    end

    local function buildTreasureChartCandidates(islandModel, info)
        -- Only score the game's actual destructible/diggable terrain hierarchy.
        -- Scanning the entire island also finds decorative rocks/buildings that
        -- satisfy the geometric clue but cannot be dug.
        local fragmentable = findTreasureChartDiggableContainer(islandModel)

        if not fragmentable then
            treasureDebugLog(
                ("CANDIDATES FAIL | NoFragmentableDigTerrain | Island=%s | Container=%s")
                    :format(tostring(info.island), treasureDebugValue(islandModel))
            )
            return {}
        end

        local center, size = getTreasureIslandBounds(fragmentable)

        if not center or not size or not info.direction or not info.distance then
            treasureDebugLog(
                ("CANDIDATES FAIL | MissingBoundsOrClue | Center=%s | Size=%s | Direction=%s | Distance=%s")
                    :format(
                        treasureDebugValue(center),
                        treasureDebugValue(size),
                        tostring(info.direction),
                        tostring(info.distance)
                    )
            )
            return {}
        end

        local directionVector = treasureDirectionVector(info.direction)
        local band = TREASURE_CHART_DISTANCE_BANDS[info.distance]

        if not directionVector or not band then
            treasureDebugLog(
                ("CANDIDATES FAIL | Direction=%s | Band=%s")
                    :format(tostring(info.direction), tostring(band))
            )
            return {}
        end

        local halfX = math.max(math.abs(size.X) * 0.5, 1)
        local halfZ = math.max(math.abs(size.Z) * 0.5, 1)

        local targetAngle = math.atan2(directionVector.Z, directionVector.X)
        local candidates = {}
        local scanned = 0
        local surfaceMatched = 0
        local rejectedNoSpot = 0

        -- Model the chart's search zone relative to the island footprint.
        -- This is closer to the actual 16-direction / 3-distance-band chart
        -- locator than using one circular radius based only on max(X, Z).
        local function getNormalizedPolar(offsetX, offsetZ)
            local radial = math.sqrt(offsetX * offsetX + offsetZ * offsetZ)

            if radial <= 0.001 then
                return 0, 0
            end

            local angle = math.atan2(offsetZ, offsetX)
            local difference = math.abs(angle - targetAngle)

            while difference > math.pi do
                difference = math.abs(difference - (math.pi * 2))
            end

            -- Estimate the island edge in this exact direction using the
            -- model's X/Z footprint, then express the part distance as a
            -- fraction of that directional edge.
            local dx = math.cos(angle)
            local dz = math.sin(angle)

            local denominator =
                (dx * dx) / (halfX * halfX)
                + (dz * dz) / (halfZ * halfZ)

            local edgeRadius = denominator > 0
                and (1 / math.sqrt(denominator))
                or math.max(halfX, halfZ)

            local normalizedRadius = radial / math.max(edgeRadius, 1)

            return normalizedRadius, difference
        end

        treasureDebugLog(
            ("CANDIDATE SOURCE | IslandContainer=%s | Class=%s | Fragmentable=%s")
                :format(
                    treasureDebugValue(islandModel),
                    islandModel.ClassName,
                    treasureDebugValue(fragmentable)
                )
        )

        for _, part in ipairs(fragmentable:GetDescendants()) do
            scanned += 1

            if scanned % 700 == 0 then
                task.wait()
            end

            if part:IsA("BasePart")
                and part.Transparency < 0.85
                and math.max(part.Size.X, part.Size.Z) >= 1
                and not treasurePartHasNoTreasureSpot(part)
                and treasurePartMatchesSurface(part, info.surface) then

                surfaceMatched += 1

                local offsetX = part.Position.X - center.X
                local offsetZ = part.Position.Z - center.Z
                local normalizedRadius, angularDifference =
                    getNormalizedPolar(offsetX, offsetZ)

                local minRadius = band[1]
                local maxRadius = band[2]

                if normalizedRadius >= minRadius
                    and normalizedRadius <= maxRadius + 0.08
                    and angularDifference <= math.rad(15) then

                    local radialMid = (minRadius + maxRadius) * 0.5
                    local radialScore =
                        math.abs(normalizedRadius - radialMid)

                    local angularScore =
                        angularDifference / math.rad(11.25)

                    local surfacePosition =
                        getTreasureDigSurfacePosition(part)

                    if surfacePosition then
                        local heightRange = math.max(math.abs(size.Y), 1)
                        local normalizedHeight = math.clamp(
                            (part.Position.Y - (center.Y - heightRange * 0.5))
                                / heightRange,
                            0,
                            1
                        )
                        local elevationPenalty = 0

                        if info.elevation == "HIGH" then
                            elevationPenalty = (1 - normalizedHeight) * 0.65
                        elseif info.elevation == "SEA_LEVEL" then
                            elevationPenalty = normalizedHeight * 0.65
                        end

                        table.insert(candidates, {
                            part = part,
                            score = radialScore + angularScore * 0.45 + elevationPenalty,
                            position = surfacePosition,
                            normalizedRadius = normalizedRadius,
                            angularDifference = angularDifference,
                            normalizedHeight = normalizedHeight,
                            elevationPenalty = elevationPenalty,
                        })
                    end
                end
            elseif part:IsA("BasePart")
                and part:FindFirstChild("NoTreasureSpot") then
                rejectedNoSpot += 1
            end
        end

        table.sort(candidates, function(a, b)
            return a.score < b.score
        end)

        local result = {}

        -- Keep all physical candidates. The green area will cover every part
        -- inside the chart's clue zone instead of hiding the true terrain part.
        for index = 1, #candidates do
            result[index] = candidates[index].part
        end

        treasureDebugLog(
            ("CANDIDATES DONE | Island=%s | Direction=%s | Distance=%s | Surface=%s | Elevation=%s | Count=%d | ALL_MATCHING_PARTS=true | Scanned=%d | SurfaceMatched=%d | NoTreasureRejected=%d | Footprint=%.1fx%.1f")
                :format(
                    tostring(info.island),
                    tostring(info.direction),
                    tostring(info.distance),
                    tostring(info.surface),
                    tostring(info.elevation),
                    #result,
                    scanned,
                    surfaceMatched,
                    rejectedNoSpot,
                    size.X,
                    size.Z
                )
        )

        for index = 1, math.min(#candidates, 8) do
            local candidate = candidates[index]
            local part = candidate.part

            treasureDebugLog(
                ("CANDIDATE[%d] | %s | Score=%.4f | R=%.3f | Angle=%.2fdeg | SurfacePos=%s | Size=%s | Material=%s")
                    :format(
                        index,
                        treasureDebugValue(part),
                        candidate.score,
                        candidate.normalizedRadius,
                        math.deg(candidate.angularDifference),
                        treasureDebugValue(candidate.position),
                        treasureDebugValue(part.Size),
                        tostring(part.Material)
                    )
            )
        end

        return result
    end

    local function findTreasureFallbackPhysicalPart(islandModel, info)
        if not islandModel or not info or not info.direction or not info.distance then
            return nil
        end

        local fragmentable = findTreasureChartDiggableContainer(islandModel)
        if not fragmentable then
            treasureDebugLog(
                ("FALLBACK PHYSICAL FAIL | NoFragmentableDigTerrain | Island=%s")
                    :format(tostring(info.island))
            )
            return nil
        end

        local center, size = getTreasureIslandBounds(fragmentable)
        local directionVector = treasureDirectionVector(info.direction)
        local band = TREASURE_CHART_DISTANCE_BANDS[info.distance]

        if not center or not size or not directionVector or not band then
            return nil
        end

        local halfX = math.max(math.abs(size.X) * 0.5, 1)
        local halfZ = math.max(math.abs(size.Z) * 0.5, 1)
        local targetAngle = math.atan2(directionVector.Z, directionVector.X)
        local targetRadius = (band[1] + band[2]) * 0.5
        local bestPart
        local bestScore = math.huge
        local scanned = 0

        for _, part in ipairs(fragmentable:GetDescendants()) do
            scanned += 1

            if scanned % 800 == 0 then
                task.wait()
            end

            if part:IsA("BasePart")
                and part.Transparency < 0.85
                and math.max(part.Size.X, part.Size.Z) >= 1
                and not treasurePartHasNoTreasureSpot(part)
                and treasurePartMatchesSurface(part, info.surface) then

                local dx = part.Position.X - center.X
                local dz = part.Position.Z - center.Z
                local radial = math.sqrt(dx * dx + dz * dz)

                if radial > 0.001 then
                    local angle = math.atan2(dz, dx)
                    local difference = math.abs(angle - targetAngle)

                    while difference > math.pi do
                        difference = math.abs(difference - (math.pi * 2))
                    end

                    local denominator =
                        (math.cos(angle) * math.cos(angle)) / (halfX * halfX)
                        + (math.sin(angle) * math.sin(angle)) / (halfZ * halfZ)

                    local edgeRadius = denominator > 0
                        and (1 / math.sqrt(denominator))
                        or math.max(halfX, halfZ)

                    local normalizedRadius =
                        radial / math.max(edgeRadius, 1)

                    local heightRange = math.max(math.abs(size.Y), 1)
                    local normalizedHeight = math.clamp(
                        (part.Position.Y - (center.Y - heightRange * 0.5))
                            / heightRange,
                        0,
                        1
                    )
                    local elevationPenalty = 0

                    if info.elevation == "HIGH" then
                        elevationPenalty = (1 - normalizedHeight) * 0.45
                    elseif info.elevation == "SEA_LEVEL" then
                        elevationPenalty = normalizedHeight * 0.45
                    end

                    local score =
                        math.abs(normalizedRadius - targetRadius)
                        + (difference / math.pi) * 0.65
                        + elevationPenalty

                    if normalizedRadius >= band[1] - 0.28
                        and normalizedRadius <= band[2] + 0.28
                        and difference <= math.rad(38)
                        and score < bestScore then
                        bestScore = score
                        bestPart = part
                    end
                end
            end
        end

        treasureDebugLog(
            ("FALLBACK PHYSICAL | Part=%s | Score=%s | Scanned=%d | SurfaceFilter=Enforced")
                :format(
                    treasureDebugValue(bestPart),
                    bestPart and ("%.4f"):format(bestScore) or "<nil>",
                    scanned
                )
        )

        return bestPart
    end

    local function createTreasureChartMarker(position, info, isEstimated)
        if not position then
            treasureDebugLog("MARKER FAIL | Position=nil")
            return
        end

        -- Replacing an approximate target with a physical candidate must not
        -- clear the candidate array that the caller just built.
        destroyTreasureChartMarkerVisual()

        treasureDebugLog(
            ("MARKER CREATE | Position=%s | Estimated=%s | Island=%s | Direction=%s | Distance=%s")
                :format(
                    treasureDebugValue(position),
                    tostring(isEstimated == true),
                    tostring(info.island),
                    tostring(info.direction),
                    tostring(info.distance)
                )
        )

        local anchor = Instance.new("Part")
        anchor.Name = "SolarTreasureChartMarker"
        markSolarHubVisual(anchor)
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(2, 2, 2)
        anchor.CFrame = CFrame.new(position)
        anchor.Parent = workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarTreasureChartInfo"
        markSolarHubVisual(billboard)
        billboard.Adornee = anchor
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0
        billboard.Size = UDim2.fromOffset(320, 54)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.Parent = Shared.playerGui

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(255, 205, 80)
        label.TextStrokeTransparency = 0.15
        label.TextSize = 12
        label.TextWrapped = true
        label.Text = "TREASURE CHART | "
            .. tostring(info.island or "?")
            .. "\n"
            .. tostring(info.direction or "?")
            .. (isEstimated and " | APPROXIMATE AREA" or " | DIG AREA")
        label.Parent = billboard

        treasureChartESP = {
            anchor = anchor,
            billboard = billboard,
            label = label,
            position = position,
            island = info.island,
            direction = info.direction,
            distanceClue = info.distance,
            greenShown = false,
            estimated = isEstimated == true,
            physicalTarget = isEstimated ~= true,
        }
    end

    local function setTreasureChartGreenArea(visible)
        if not visible then
            for _, highlight in ipairs(treasureChartHighlights) do
                pcall(function() highlight:Destroy() end)
            end

            table.clear(treasureChartHighlights)

            if treasureChartESP and treasureChartESP.fallbackArea then
                pcall(function()
                    treasureChartESP.fallbackArea:Destroy()
                end)

                treasureChartESP.fallbackArea = nil
            end

            if treasureChartESP then
                treasureChartESP.greenShown = false
            end

            treasureDebugLog("GREEN AREA | Hidden")
            return
        end

        if not treasureChartESP or treasureChartESP.greenShown then
            return
        end

        -- Never create a guessed midpoint square. Green must correspond to
        -- actual Fragmentable terrain that passed the chart filters.
        if #treasureChartCandidateParts == 0 then
            treasureDebugLog("GREEN AREA | NoPhysicalCandidates | NothingHighlighted")
            return
        end

        treasureChartESP.greenShown = true

        local parts = table.clone(treasureChartCandidateParts)

        task.spawn(function()
            local created = 0

            for index, part in ipairs(parts) do
                if part and part.Parent then
                    local highlight = Instance.new("Highlight")
                    highlight.Name = "SolarTreasureDigArea"
                    markSolarHubVisual(highlight)
                    highlight.Adornee = part
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.FillColor = Color3.fromRGB(35, 255, 80)
                    highlight.OutlineColor = Color3.fromRGB(35, 255, 80)
                    highlight.FillTransparency = 0.82
                    highlight.OutlineTransparency = 0
                    highlight.Parent = part

                    treasureChartHighlights[#treasureChartHighlights + 1] = highlight
                    created += 1
                end

                if index % 25 == 0 then
                    refreshTreasureDebugGuiText(
                        ("Highlighting dig area... %d / %d"):format(
                            index,
                            #parts
                        )
                    )
                    task.wait()
                end
            end

            treasureDebugLog(
                ("GREEN AREA | AllPhysicalCandidatesHighlighted=%d"):format(created)
            )

            refreshTreasureDebugGuiText(
                ("Green dig area ready | %d matching terrain parts"):format(created)
            )
        end)
    end

    local function isTreasureChartTool(object)
        if not object or not object:IsA("Tool") then
            return false
        end

        local normalized = treasureNormalize(object.Name)

        if normalized:find("treasurechart", 1, true) ~= nil
            or normalized:find("treasuremap", 1, true) ~= nil
            or normalized == "chart"
            or normalized:find("mystictreasure", 1, true) ~= nil then
            return true
        end

        local okTooltip, tooltip = pcall(function()
            return object.ToolTip
        end)

        if okTooltip
            and treasureNormalize(tooltip):find("treasurechart", 1, true) ~= nil then
            return true
        end

        for _, child in ipairs(object:GetDescendants()) do
            if child:IsA("StringValue") then
                local text = treasureNormalize(child.Value)

                if text:find("treasurechart", 1, true) ~= nil
                    or text:find("mystictreasure", 1, true) ~= nil then
                    return true
                end
            end
        end

        return false
    end

    local function findTreasureChartObject()
        -- IMPORTANT: do not inspect the Backpack. The Finder becomes active
        -- only when the chart is actually equipped in Character.
        local character = Shared.player.Character

        if not character then
            return nil
        end

        for _, child in ipairs(character:GetChildren()) do
            if isTreasureChartTool(child) then
                return child
            end
        end

        return nil
    end

    local function refreshTreasureChart()
        if not Config.ArcaneTreasureChartESP then
            destroyTreasureChartESP()
            treasureChartCurrentObject = nil
            treasureChartLastKey = nil
            treasureChartNeedsScan = true

            if treasureChartStatus then
                treasureChartStatus.Text = "Treasure Chart Finder: OFF"
            end

            return
        end

        local chart = findTreasureChartObject()

        treasureDebugLog(
            ("REFRESH | Enabled=%s | Chart=%s")
                :format(
                    tostring(Config.ArcaneTreasureChartESP),
                    treasureDebugValue(chart)
                )
        )

        if not chart then
            destroyTreasureChartESP()
            treasureChartCurrentObject = nil
            treasureChartLastKey = nil
            treasureChartNeedsScan = true

            if treasureChartStatus then
                treasureChartStatus.Text =
                    "Treasure Chart Finder: equip a Treasure Chart to activate."
            end

            return
        end

        local info = getTreasureChartInfo(chart)

        treasureDebugLog(
            ("REFRESH INFO | Stage=%s | Island=%s | Direction=%s | Distance=%s | Surface=%s")
                :format(
                    tostring(info.stage or info.rawText),
                    tostring(info.island),
                    tostring(info.direction),
                    tostring(info.distance),
                    tostring(info.surface)
                )
        )

        if not info.island or not info.direction or not info.distance then
            if treasureChartStatus then
                treasureChartStatus.Text =
                    "Chart detected, but its clue text is not readable yet."
            end

            return
        end

        local chartKey = table.concat({
            tostring(chart:GetFullName()),
            tostring(info.island),
            tostring(info.direction),
            tostring(info.distance),
            tostring(info.surface),
            tostring(info.stage or info.rawText),
        }, "|")

        if chartKey ~= treasureChartLastKey then
            destroyTreasureChartESP()
            treasureChartLastKey = chartKey
            treasureChartCurrentObject = chart
            treasureChartNeedsScan = true
        end

        if treasureChartNeedsScan
            and (os.clock() - treasureChartLastScanAttempt) >= 3.0 then

            -- The island may not exist yet because Arcane streams Map content
            -- after the chart GUI/tool becomes available. The old code marked
            -- the scan complete even when the island lookup failed, leaving
            -- the Finder permanently stuck at Candidates=0 / no ESP until rejoin.
            treasureChartLastScanAttempt = os.clock()
            treasureDebugLog(
                ("SCAN ATTEMPT | Island=%s")
                    :format(tostring(info.island))
            )

            local islandModel = findTreasureIslandModel(info.island)

            treasureDebugLog(
                ("SCAN | Island=%s | Found=%s")
                    :format(tostring(info.island), tostring(islandModel ~= nil))
            )

            if islandModel then
                treasureChartIslandModel = islandModel
                treasureChartCandidateParts =
                    buildTreasureChartCandidates(islandModel, info)

                local markerPart = treasureChartCandidateParts[1]
                local markerPosition

                if markerPart then
                    markerPosition = getTreasureDigSurfacePosition(markerPart)

                    treasureDebugLog(
                        ("MARKER SOURCE | PhysicalCandidate[1]=%s | SurfacePosition=%s")
                            :format(
                                treasureDebugValue(markerPart),
                                treasureDebugValue(markerPosition)
                            )
                    )

                    if markerPosition then
                        createTreasureChartMarker(markerPosition, info)

                        if treasureChartESP then
                            treasureChartESP.physicalTarget = true
                        end
                    end

                    treasureDebugLog(
                        ("TARGET TYPE | Physical=%s | Candidates=%d")
                            :format(
                                tostring(markerPart ~= nil),
                                #treasureChartCandidateParts
                            )
                    )
                    treasureDebugLog("STEP | AfterPhysicalMarkerCreate")
                    treasureChartNeedsScan = false
                else
                    -- The strict clue filter can be empty on a streamed/variant
                    -- island. First search wider for a REAL Fragmentable part.
                    local fallbackPart =
                        findTreasureFallbackPhysicalPart(islandModel, info)

                    if fallbackPart then
                        markerPart = fallbackPart
                        markerPosition =
                            getTreasureDigSurfacePosition(fallbackPart)

                        treasureChartCandidateParts = {fallbackPart}

                        treasureDebugLog(
                            ("MARKER SOURCE | FallbackPhysicalPart=%s | SurfacePosition=%s")
                                :format(
                                    treasureDebugValue(fallbackPart),
                                    treasureDebugValue(markerPosition)
                                )
                        )

                        if markerPosition then
                            createTreasureChartMarker(markerPosition, info)

                            if treasureChartESP then
                                treasureChartESP.physicalTarget = true
                            end
                        end

                        treasureDebugLog(
                            "TARGET TYPE | Physical=true | Source=FallbackPhysicalPart"
                        )

                        treasureChartNeedsScan = false
                    else
                        local center, size =
                            getTreasureIslandBounds(islandModel)
                        local directionVector =
                            treasureDirectionVector(info.direction)
                        local band =
                            TREASURE_CHART_DISTANCE_BANDS[info.distance]
                        local streamPosition

                        if center and size and directionVector and band then
                            -- Match the same directional island-edge calculation
                            -- used by the candidate filter instead of a circular
                            -- radius, which is inaccurate on long/narrow islands.
                            local halfX = math.max(math.abs(size.X) * 0.5, 1)
                            local halfZ = math.max(math.abs(size.Z) * 0.5, 1)
                            local dx = directionVector.X
                            local dz = directionVector.Z
                            local denominator =
                                (dx * dx) / (halfX * halfX)
                                + (dz * dz) / (halfZ * halfZ)
                            local edgeRadius = denominator > 0
                                and (1 / math.sqrt(denominator))
                                or math.max(halfX, halfZ)
                            local middleRadius =
                                edgeRadius * ((band[1] + band[2]) * 0.5)

                            streamPosition =
                                center + directionVector * middleRadius

                            -- Snap the estimated X/Z to the real island surface,
                            -- so STUDS measures distance to the ground instead
                            -- of to the island bounding-box center's height.
                            pcall(function()
                                local rayParams = RaycastParams.new()
                                rayParams.FilterType = Enum.RaycastFilterType.Include
                                rayParams.FilterDescendantsInstances = {islandModel}
                                rayParams.IgnoreWater = true

                                local rayStart = Vector3.new(
                                    streamPosition.X,
                                    center.Y + math.abs(size.Y) * 0.5 + 150,
                                    streamPosition.Z
                                )
                                local rayDirection = Vector3.new(
                                    0,
                                    -(math.abs(size.Y) + 650),
                                    0
                                )
                                local hit = workspace:Raycast(
                                    rayStart,
                                    rayDirection,
                                    rayParams
                                )

                                if hit then
                                    streamPosition = Vector3.new(
                                        streamPosition.X,
                                        hit.Position.Y + 2,
                                        streamPosition.Z
                                    )
                                end
                            end)

                            treasureDebugLog(
                                ("NO PHYSICAL CANDIDATE | ApproxPosition=%s | SurfaceSnapped=%s")
                                    :format(
                                        treasureDebugValue(streamPosition),
                                        tostring(streamPosition.Y ~= center.Y)
                                    )
                            )
                        end

                        if streamPosition then
                            -- Use the estimate only as a streaming hint. Never display
                            -- an estimated point as a real dig target: it can land on
                            -- a rock/building or non-diggable surface.
                            if treasureChartESP and treasureChartESP.estimated then
                                destroyTreasureChartESP()
                            end

                            treasureDebugLog(
                                ("APPROXIMATE POSITION | StreamRequestOnly=true | Position=%s | NoMarker=true")
                                    :format(treasureDebugValue(streamPosition))
                            )

                            pcall(function()
                                if type(workspace.RequestStreamAroundAsync)
                                    == "function" then
                                    workspace:RequestStreamAroundAsync(
                                        streamPosition,
                                        2
                                    )
                                end
                            end)
                        else
                            treasureDebugLog(
                                "ESTIMATED MARKER SKIPPED | Island bounds or clue band unavailable"
                            )
                        end

                        treasureChartNeedsScan = true

                        if treasureChartStatus then
                            treasureChartStatus.Text =
                                "Treasure Chart Finder: waiting for matching dig terrain to stream..."
                        end
                    end
                end
            else
                -- Keep the scan pending so the next retry can catch the island
                -- once its streamed model/parts have appeared in Workspace.Map.
                treasureChartNeedsScan = true

                treasureDebugLog(
                    ("SCAN RETRY QUEUED | Island=%s | NextRetry=3s")
                        :format(tostring(info.island))
                )
            end
        end

        treasureDebugLog("STEP | BeforePlayerRoot")
        local playerRoot = getLocalPlayerRoot()
        treasureDebugLog(
            ("STEP | AfterPlayerRoot | Root=%s")
                :format(treasureDebugValue(playerRoot))
        )
        local nearest
        local nearestDistance = math.huge

        if playerRoot then
            for _, part in ipairs(treasureChartCandidateParts) do
                if part and part.Parent then
                    local distance =
                        (playerRoot.Position - part.Position).Magnitude

                    if distance < nearestDistance then
                        nearestDistance = distance
                        nearest = part
                    end
                end
            end

            if not nearest and treasureChartESP and treasureChartESP.position then
                nearestDistance =
                    (playerRoot.Position - treasureChartESP.position).Magnitude
                treasureDebugLog(
                    ("DISTANCE FALLBACK | MarkerPosition=%s | Distance=%.2f")
                        :format(
                            treasureDebugValue(treasureChartESP.position),
                            nearestDistance
                        )
                )
            end
        end

        treasureDebugLog(
            ("DISTANCE | Root=%s | Nearest=%s | Distance=%.2f | Candidates=%d | GreenThreshold=%d")
                :format(
                    treasureDebugValue(playerRoot),
                    treasureDebugValue(nearest),
                    nearestDistance,
                    #treasureChartCandidateParts,
                    TREASURE_CHART_ARRIVAL_DISTANCE
                )
        )

        if treasureChartESP and playerRoot and treasureChartESP.position then
            -- Keep the displayed distance tied to the visible marker itself.
            -- Candidate parts are optional; the chart must still show STUDS
            -- when the island has no matching physical candidates.
            local targetPosition = treasureChartESP.position

            if nearest then
                targetPosition = nearest.Position
            end

            treasureChartESP.position = targetPosition
            treasureChartESP.anchor.CFrame = CFrame.new(targetPosition)

            local displayDistance =
                (playerRoot.Position - targetPosition).Magnitude

            local arrived = displayDistance <= TREASURE_CHART_ARRIVAL_DISTANCE

            treasureDebugLog(
                ("ARRIVAL | Arrived=%s | Distance=%.2f | Target=%s | Marker=%s")
                    :format(
                        tostring(arrived),
                        displayDistance,
                        treasureDebugValue(targetPosition),
                        treasureDebugValue(treasureChartESP.anchor)
                    )
            )

            -- Update the text BEFORE the optional green-area work so a highlight
            -- error can never prevent the STUDS text from appearing.
            local targetLabel
            if treasureChartESP.estimated then
                targetLabel = "APPROXIMATE AREA | WAITING FOR TERRAIN"
            else
                targetLabel = arrived and "GREEN DIG AREA" or "GO TO AREA"
            end

            treasureChartESP.label.Text =
                "TREASURE CHART | "
                .. tostring(info.island)
                .. "\n"
                .. tostring(math.floor(displayDistance))
                .. " STUDS | "
                .. targetLabel

            pcall(function()
                setTreasureChartGreenArea(
                    arrived and not treasureChartESP.estimated
                )
            end)
        elseif treasureChartESP then
            treasureDebugLog(
                ("DISTANCE WAIT | PlayerRoot=%s | MarkerPosition=%s")
                    :format(
                        treasureDebugValue(playerRoot),
                        treasureDebugValue(treasureChartESP.position)
                    )
            )
        end

        if treasureChartStatus then
            local statusStuds = "STUDS: ?"

            if playerRoot and treasureChartESP and treasureChartESP.position then
                statusStuds = ("STUDS: %d"):format(
                    math.floor(
                        (playerRoot.Position - treasureChartESP.position).Magnitude
                    )
                )
            end

            treasureChartStatus.Text =
                (info.stage and ("Stage: " .. tostring(info.stage) .. " | ") or "Stage: AUTO | ")
                .. "Chart: "
                .. tostring(info.island)
                .. " | "
                .. tostring(info.direction)
                .. " | "
                .. tostring(info.distance)
                .. "\n"
                .. statusStuds
                .. " | Candidates: "
                .. tostring(#treasureChartCandidateParts)
                .. (info.surface and (" | " .. info.surface) or "")
                .. (info.elevation and (" | " .. info.elevation) or "")
                .. (info.coastal and " | COASTAL" or "")
                .. (treasureChartESP and treasureChartESP.estimated
                    and " | APPROXIMATE (waiting for physical terrain)"
                    or "")
        end
    end

    local function destroyTreasureTeleportGui()
        if treasureTeleportGui then
            pcall(function()
                treasureTeleportGui:Destroy()
            end)
            treasureTeleportGui = nil
        end
    end

    local function createTreasureTeleportGui()
        if treasureTeleportGui and treasureTeleportGui.Parent then
            return
        end

        local playerGui = Shared.playerGui

        if not playerGui then
            return
        end

        treasureTeleportGui = Instance.new("ScreenGui")
        treasureTeleportGui.Name = "SolarHubTreasureTeleport"
        markSolarHubVisual(treasureTeleportGui)
        treasureTeleportGui.ResetOnSpawn = false
        treasureTeleportGui.DisplayOrder = 1000001
        treasureTeleportGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        treasureTeleportGui.Parent = playerGui

        local button = Instance.new("TextButton")
        button.Name = "Teleport"
        button.AnchorPoint = Vector2.new(1, 0)
        button.Position = UDim2.new(1, -18, 0, 72)
        button.Size = UDim2.fromOffset(160, 38)
        button.BackgroundColor3 = Color3.fromRGB(43, 43, 54)
        button.BorderSizePixel = 0
        button.Text = "TP TO TREASURE"
        button.TextColor3 = Color3.fromRGB(235, 235, 240)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 10
        button.AutoButtonColor = true
        button.Parent = treasureTeleportGui
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

        button.Activated:Connect(function()
            local marker = treasureChartESP
            local position = marker and marker.position
            local character = Shared.player and Shared.player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")

            if not marker
                or marker.physicalTarget ~= true
                or typeof(position) ~= "Vector3" then
                button.Text = "NO TARGET"

                task.delay(1.1, function()
                    if button and button.Parent then
                        button.Text = "TP TO TREASURE"
                    end
                end)

                treasureDebugLog(
                    ("TP | Failed | Marker=%s | Physical=%s | Position=%s | Root=%s")
                        :format(
                            treasureDebugValue(marker),
                            tostring(marker and marker.physicalTarget),
                            treasureDebugValue(position),
                            treasureDebugValue(root)
                        )
                )
                return
            end

            if not root then
                button.Text = "NO CHARACTER"

                task.delay(1.1, function()
                    if button and button.Parent then
                        button.Text = "TP TO TREASURE"
                    end
                end)

                treasureDebugLog(
                    ("TP | Failed | CharacterRootMissing | Position=%s")
                        :format(treasureDebugValue(position))
                )
                return
            end

            local targetPosition = position + Vector3.new(0, 5, 0)
            local ok, err = pcall(function()
                root.CFrame = CFrame.new(targetPosition)
            end)

            button.Text = ok and "TELEPORTED" or "TP FAILED"

            treasureDebugLog(
                ("TP | %s | Position=%s%s")
                    :format(
                        ok and "Success" or "Failed",
                        treasureDebugValue(targetPosition),
                        ok and "" or (" | Error=" .. tostring(err))
                    )
            )

            task.delay(1.1, function()
                if button and button.Parent then
                    button.Text = "TP TO TREASURE"
                end
            end)
        end)
    end

    createTreasureTeleportGui()

    Context.registerCleanup(destroyTreasureTeleportGui)

    task.spawn(function()
        task.wait(1)

        while isArcaneSessionActive() do
            task.wait(0.5)

            if Config.ArcaneTreasureChartESP then
                local ok, err = pcall(refreshTreasureChart)

                if not ok then
                    treasureDebugLog(
                        ("REFRESH ERROR | %s"):format(tostring(err))
                    )
                end
            else
                destroyTreasureChartESP()
            end
        end
    end)

    -- Distance/label updates are intentionally independent from the heavier
    -- chart discovery scan. This keeps STUDS and the visible marker alive even
    -- while a Deep Scan is running or while the chart's candidate list is empty.
    task.spawn(function()
        while isArcaneSessionActive() do
            task.wait(0.15)

            if not Config.ArcaneTreasureChartESP then
                continue
            end

            local marker = treasureChartESP
            local playerRoot = getLocalPlayerRoot()

            if marker and marker.position and playerRoot then
                local distance = (playerRoot.Position - marker.position).Magnitude
                local arrived = distance <= TREASURE_CHART_ARRIVAL_DISTANCE

                if marker.label and marker.label.Parent then
                    marker.label.Text =
                        "TREASURE CHART | "
                        .. tostring(marker.island or "?")
                        .. "\n"
                        .. tostring(math.floor(distance))
                        .. " STUDS | "
                        .. (arrived and "GREEN DIG AREA" or "GO TO AREA")
                end

                if treasureChartStatus then
                    treasureChartStatus.Text =
                        "Chart: "
                        .. tostring(marker.island or "?")
                        .. " | "
                        .. tostring(marker.direction or "?")
                        .. " | "
                        .. tostring(marker.distanceClue or "?")
                        .. "\nSTUDS: "
                        .. tostring(math.floor(distance))
                        .. " | Candidates: "
                        .. tostring(#treasureChartCandidateParts)
                end

                pcall(function()
                    setTreasureChartGreenArea(arrived)
                end)
            end
        end
    end)

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

        chestTypeCache[target] = nil
        if not target.Parent then
            chestRootCache[target] = nil
        end
    end

    local DEFAULT_CHEST_SCAN_DISTANCE = 30000

    local function getChestScanDistance()
        local distance = tonumber(Config.ArcaneChestScanDistance)

        if distance == nil then
            distance = 30000
        end

        return math.clamp(
            math.floor(distance + 0.5),
            1,
            100000
        )
    end

    getLocalPlayerRoot = function()
        local character = Shared.player.Character

        return character
            and character:FindFirstChild("HumanoidRootPart")
    end

    local function isChestWithinScanDistance(targetOrPosition)
        if Config.ArcaneInfiniteDistanceScan == true then
            return true
        end

        local playerRoot = getLocalPlayerRoot()

        if not playerRoot then
            return true
        end

        local position = targetOrPosition

        if typeof(targetOrPosition) == "Instance" then
            local root = getChestRoot(targetOrPosition)
            position = root and root.Position
        elseif typeof(targetOrPosition) == "Vector3" then
            position = targetOrPosition
        end

        if typeof(position) ~= "Vector3" then
            return false
        end

        local limit = Config.ArcaneChestScanDistanceLimitEnabled == true
            and getChestScanDistance()
            or DEFAULT_CHEST_SCAN_DISTANCE

        return (playerRoot.Position - position).Magnitude <= limit
    end

    local function hasLiveChestInteraction(chest)
    if not chest or not chest:IsDescendantOf(workspace) then
        return false
    end

    local root = getChestRoot(chest)
    if not root or not root:IsDescendantOf(workspace) then
        return false
    end

    -- A live chest only needs a valid world root. Different chest variants
    -- can use PrimaryPart or another BasePart instead of a direct "Base".
    -- Prompt/ClickDetector are not required for ESP discovery.
    return true
end

local function createChestESP(target)
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        local chestType = chestTypeCache[target]

        if not chestType then
            chestType = getChestTypeFast(target) or getChestType(target)
            chestTypeCache[target] = chestType
        end

        if not chestType or not isChestFilterEnabled(Config, chestType) then
            destroyChestESP(target)
            return
        end

        if not hasLiveChestInteraction(target) then
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

        if not isChestWithinScanDistance(root.Position) then
            destroyChestESP(target)
            return
        end

        local chestColor = CHEST_COLORS[chestType] or CHEST_COLORS.OTHER
        local chestDisplayName = CHEST_DISPLAY_NAMES[chestType] or "Other Chest"

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarChestESP"
        markSolarHubVisual(highlight)
        highlight.Adornee = target
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = chestColor
        highlight.OutlineColor = chestColor
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = target:IsA("Model") and target or Workspace

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarChestESPInfo"
        markSolarHubVisual(billboard)
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

    local function getStaticChestPosition(entry)
        if not entry then
            return nil
        end

        if entry:IsA("BasePart") then
            return entry.Position
        end

        if entry:IsA("Model") then
            local root = entry.PrimaryPart
                or entry:FindFirstChild("Base", true)
                or entry:FindFirstChildWhichIsA("BasePart", true)

            if root and root:IsA("BasePart") then
                return root.Position
            end

            local okPivot, pivot = pcall(function()
                return entry:GetPivot()
            end)

            if okPivot then
                return pivot.Position
            end
        end

        return nil
    end

    local function getStaticChestAnchor()
        if staticChestAnchor and staticChestAnchor.Parent then
            return staticChestAnchor
        end

        local anchor = Instance.new("Part")
        anchor.Name = "SolarChestStaticAnchor"
        markSolarHubVisual(anchor)
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanTouch = false
        anchor.CanQuery = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(0.1, 0.1, 0.1)
        anchor.CFrame = CFrame.new()
        anchor.Parent = workspace

        staticChestAnchor = anchor
        return anchor
    end

    local function destroyStaticChestESP(key)
        local data = staticChestESPObjects[key]

        if not data then
            return
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

        staticChestESPObjects[key] = nil

        if next(staticChestESPObjects) == nil and staticChestAnchor then
            pcall(function()
                staticChestAnchor:Destroy()
            end)
            staticChestAnchor = nil
        end
    end

    local function createStaticChestESP(entry, chestType, cachedPosition, cachedKey)
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        -- Static entries may come from Workspace or ReplicatedStorage. The
        -- cached world position is what matters, not whether the source is
        -- currently parented to Workspace.
        if entry
            and not (entry:IsA("Model") or entry:IsA("BasePart")) then
            return
        end

        chestType = chestType or (entry and getChestType(entry)) or "OTHER"

        if not isChestFilterEnabled(Config, chestType) then
            return
        end

        local position = cachedPosition
            or getStaticChestPosition(entry)

        if not position then
            return
        end

        -- Keep the location in the global cache, but only create the actual
        -- BillboardGui when it is inside the active scan radius. This keeps
        -- the expensive global location database while protecting weaker PCs
        -- from thousands of simultaneous marker instances.
        if not isChestWithinScanDistance(position) then
            return
        end

        -- Only hide locations confirmed as consumed.
        if isOpenedChestLocation(position) then
            return
        end
        local key = cachedKey
            or (entry and entry:GetFullName())
            or ("STATIC|" .. tostring(position.X) .. "|" .. tostring(position.Y) .. "|" .. tostring(position.Z))

        if staticChestESPObjects[key] then
            return
        end

        local anchor = Instance.new("Attachment")
        anchor.Name = "SolarChestStaticAttachment"
        markSolarHubVisual(anchor)
        anchor.Position = position
        anchor.Parent = getStaticChestAnchor()

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarChestStaticESPInfo"
        markSolarHubVisual(billboard)
        billboard.Adornee = anchor
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 0
        billboard.Size = UDim2.fromOffset(270, 32)
        billboard.StudsOffset = Vector3.new(0, 2.8, 0)
        billboard.Parent = Shared.playerGui

        local chestColor = CHEST_COLORS[chestType] or CHEST_COLORS.OTHER
        local chestDisplayName = CHEST_DISPLAY_NAMES[chestType] or "Chest Location"

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = chestColor
        label.TextStrokeTransparency = 0.15
        label.TextSize = 11
        label.Text = chestDisplayName .. " | STUDS: ?"
        label.Parent = billboard

        staticChestESPObjects[key] = {
            source = entry,
            anchor = anchor,
            billboard = billboard,
            label = label,
            position = position,
            chestType = chestType,
        }
    end

    local function getStaticChestLocationKey(position, chestType)
        local function snap(value)
            return math.floor((value / 2) + 0.5) * 2
        end

        return ("STATIC|%s|%d|%d|%d"):format(
            tostring(chestType or "OTHER"),
            snap(position.X),
            snap(position.Y),
            snap(position.Z)
        )
    end

    local function getOpenedChestLocationKey(position)
        if not position then
            return nil
        end

        local function snap(value)
            return math.floor((value / 2) + 0.5) * 2
        end

        return ("OPENED|%d|%d|%d"):format(
            snap(position.X),
            snap(position.Y),
            snap(position.Z)
        )
    end

    isOpenedChestLocation = function(position)
        local key = getOpenedChestLocationKey(position)
        return key ~= nil and openedChestLocations[key] == true
    end

    local function clearOpenedChestLocation(position)
        local key = getOpenedChestLocationKey(position)

        if key then
            openedChestLocations[key] = nil
        end
    end

    local function cacheStaticChestLocation(entry, chestType)
        if not entry then
            return
        end

        local position = getStaticChestPosition(entry)

        if not position then
            return
        end

        local key = getStaticChestLocationKey(
            position,
            chestType or "OTHER"
        )

        if not staticChestLocationCache[key] then
            staticChestLocationCache[key] = {
                source = entry,
                position = position,
                chestType = chestType or "OTHER",
            }
        end
    end

    local function refreshStaticChestESP()
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        for key, data in pairs(staticChestLocationCache) do
            if isChestWithinScanDistance(data.position) then
                createStaticChestESP(
                    data.source,
                    data.chestType,
                    data.position,
                    key
                )
            else
                destroyStaticChestESP(key)
            end
        end
    end

    local function scanStaticChestLocations(root)
        if staticChestLocationsScanned then
            refreshStaticChestESP()
            return
        end

        staticChestLocationsScanned = true

        local function scanRoot(scanRoot)
            if not scanRoot then
                return
            end

            local descendants = scanRoot:GetDescendants()

            for index, object in ipairs(descendants) do
                if index % 750 == 0 then
                    task.wait()
                end

                if (object:IsA("Folder") or object:IsA("Model"))
                    and (
                        normalizeName(object.Name) == "chests"
                        or normalizeName(object.Name) == "tempchests"
                    ) then

                    for _, entry in ipairs(object:GetChildren()) do
                        if entry:IsA("Model") or entry:IsA("BasePart") then
                            local chestType = getChestTypeFast(entry)
                                or getChestType(entry)
                                or "OTHER"

                            cacheStaticChestLocation(entry, chestType)
                        end
                    end
                end
            end
        end

        -- Workspace contains the currently loaded chests. ReplicatedStorage
        -- contains Arcane Odyssey's unloaded-island chest locations, allowing
        -- the ESP to remain visible even after the game removes the live model.
        scanRoot(root or workspace:FindFirstChild("Map"))

        local rs = game:GetService("ReplicatedStorage")
        local unloadIslands = rs:FindFirstChild("RS")
            and rs.RS:FindFirstChild("UnloadIslands")

        scanRoot(unloadIslands)

        refreshStaticChestESP()
    end

    local function destroyStaticChestESPNearPosition(position, chestType, radius)
        if not position then
            return
        end

        radius = radius or 24

        for key, data in pairs(staticChestESPObjects) do
            if data.position
                and (not chestType or data.chestType == chestType)
                and (data.position - position).Magnitude <= radius then
                destroyStaticChestESP(key)
            end
        end
    end

    local function markChestOpened(chest)
        if not chest then
            return
        end

        openedChests[chest] = true
        chestCandidates[chest] = nil

        local root = getChestRoot(chest)

        if root then
            local locationKey = getOpenedChestLocationKey(root.Position)

            if locationKey then
                openedChestLocations[locationKey] = true
            end

            destroyStaticChestESPNearPosition(
                root.Position,
                chestTypeCache[chest]
                    or getChestTypeFast(chest)
                    or getChestType(chest)
            )
        end

        destroyChestESP(chest)
    end



    local function cleanupChestLifecycleWatcher(chest)
        local watcher = chestLifecycleWatchers[chest]

        if not watcher then
            return
        end

        for _, connection in ipairs(watcher.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        chestLifecycleWatchers[chest] = nil
    end

    local function watchChestLifecycle(chest)
        if not chest
            or chestLifecycleWatchers[chest] then
            return
        end

        local watcher = {
            connections = {},
            baseConnected = false,
            lidConnected = false,
        }

        chestLifecycleWatchers[chest] = watcher

        local function connect(signal, callback)
            local ok, connection = pcall(function()
                return signal:Connect(callback)
            end)

            if ok and connection then
                table.insert(watcher.connections, connection)
            end

            return connection
        end

        local base = chest:FindFirstChild("Base", true)
        local lid = chest:FindFirstChild("Lid", true)
        local consumed = false

        local function isFullyVisible()
            return base
                and lid
                and base:IsA("BasePart")
                and lid:IsA("BasePart")
                and base.Transparency < 0.999
                and lid.Transparency < 0.999
        end

        local function isFullyInvisible()
            return base
                and lid
                and base:IsA("BasePart")
                and lid:IsA("BasePart")
                and base.Transparency >= 0.999
                and lid.Transparency >= 0.999
        end

        local function onConsumed()
            if consumed or not isArcaneSessionActive() then
                return
            end

            consumed = true
            markChestOpened(chest)
        end

        local function onRespawned()
            if not consumed or not isArcaneSessionActive() then
                return
            end

            consumed = false

            local root = getChestRoot(chest)

            if root then
                clearOpenedChestLocation(root.Position)
            end

            openedChests[chest] = nil

            if Config.ArcaneChestESP
                and hasAnyChestFilterEnabled(Config)
                and chest.Parent then

                local chestType =
                    chestTypeCache[chest]
                    or getChestTypeFast(chest)
                    or getChestType(chest)

                chestTypeCache[chest] = chestType

                if chestType
                    and isChestFilterEnabled(Config, chestType) then

                    chestCandidates[chest] = true
                    createChestESP(chest)

                    if root then
                        destroyStaticChestESPNearPosition(
                            root.Position,
                            chestType
                        )
                    end
                end
            end
        end

        local function checkVisualState()
            if not isArcaneSessionActive() then
                return
            end

            if not chest.Parent then
                cleanupChestLifecycleWatcher(chest)
                return
            end

            if isFullyInvisible() then
                onConsumed()
            elseif isFullyVisible() then
                onRespawned()
            end
        end

        local function hookPartSignals()
            if base and base.Parent and base:IsA("BasePart")
                and not watcher.baseConnected then

                watcher.baseConnected = true

                connect(
                    base:GetPropertyChangedSignal("Transparency"),
                    function()
                        if base.Transparency >= 0.999
                            or base.Transparency <= 0.001 then
                            checkVisualState()
                        end
                    end
                )
            end

            if lid and lid.Parent and lid:IsA("BasePart")
                and not watcher.lidConnected then

                watcher.lidConnected = true

                connect(
                    lid:GetPropertyChangedSignal("Transparency"),
                    function()
                        if lid.Transparency >= 0.999
                            or lid.Transparency <= 0.001 then
                            checkVisualState()
                        end
                    end
                )
            end
        end

        connect(
            chest.AncestryChanged,
            function(_, parent)
                if not parent then
                    cleanupChestLifecycleWatcher(chest)
                    chestTypeCache[chest] = nil
                    chestRootCache[chest] = nil
                end
            end
        )

        connect(
            chest.DescendantAdded,
            function(descendant)
                if not isArcaneSessionActive() then
                    return
                end

                if descendant:IsA("BoolValue") then
                    local normalized = normalizeChestText(descendant.Name)

                    if normalized == "open"
                        or normalized == "opened"
                        or normalized == "chestopened"
                        or normalized == "openedchest" then
                        onConsumed()
                    end
                end

                if descendant:IsA("BasePart") then
                    if (not base or not base.Parent)
                        and descendant.Name == "Base" then
                        base = descendant
                        watcher.baseConnected = false
                    end

                    if (not lid or not lid.Parent)
                        and descendant.Name == "Lid" then
                        lid = descendant
                        watcher.lidConnected = false
                    end

                    hookPartSignals()
                    checkVisualState()
                end
            end
        )

        hookPartSignals()
        checkVisualState()
    end

    local function hasChestOpenedMarker(chest)
    if not chest then
        return false
    end

    local function isTruthyOpenValue(name, value)
        local normalizedName = normalizeChestText(name)

        return value == true
            and (
                normalizedName == "opened"
                or normalizedName == "open"
                or normalizedName == "isopen"
                or normalizedName == "chestopened"
                or normalizedName == "openedchest"
            )
    end

    -- Only trust explicit boolean open-state markers.
    local okAttrs, attrs = pcall(function()
        return chest:GetAttributes()
    end)

    if okAttrs and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            if isTruthyOpenValue(key, value) then
                return true
            end
        end
    end

    for _, descendant in ipairs(chest:GetDescendants()) do
        if descendant:IsA("BoolValue")
            and isTruthyOpenValue(descendant.Name, descendant.Value) then
            return true
        end
    end

    return false
end

local proximityPromptService = game:GetService("ProximityPromptService")

    proximityPromptService.PromptTriggered:Connect(function(prompt, player)
        if not isArcaneSessionActive() then
            return
        end

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

    -- Resolve the real chest first. Do not reject a candidate using only the
    -- scanned object's name, because the live rarity may exist in prompts,
    -- values, attributes, or tags inside the chest.
    local chest = getChestTarget(target)
    if not chest then
        return
    end

    if not hasLiveChestInteraction(chest) then
        chestCandidates[chest] = nil
        destroyChestESP(chest)
        return
    end

    local chestType = getChestType(chest)

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

    local chestRoot = getChestRoot(chest)

    if chestRoot and isOpenedChestLocation(chestRoot.Position) then
        chestCandidates[chest] = nil
        destroyChestESP(chest)
        return
    end

    watchChestLifecycle(chest)

    if not isChestWithinScanDistance(chest, chestType) then
        chestCandidates[chest] = nil
        destroyChestESP(chest)
        return
    end

    localChestTagObjects[chest] = true
    chestCandidates[chest] = true

    createChestESP(chest)

    -- Prefer the live chest marker while the actual chest model is loaded.
    if chestRoot then
        destroyStaticChestESPNearPosition(
            chestRoot.Position,
            chestType
        )
    end
end

local function scanAllWorkspaceChests()
        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        -- Initial discovery pass. We do NOT rely only on chest/model names:
        -- hidden chests can use generic names or live inside other structures.
        -- The game's actual interaction objects (ProximityPrompt/ClickDetector)
        -- are much stronger discovery signals.
        local seen = {}
        local resolvedChests = {}

        local function inspectOnce(object)
            if not object
                or not object:IsDescendantOf(workspace)
                or seen[object] then
                return
            end

            -- Skip live chest work outside the active radius. Static location
            -- caching remains global so moving later can reveal cached markers.
            if object:IsA("Model") or object:IsA("BasePart") then
                local root = getChestRoot(object)
                if root and not isChestWithinScanDistance(root.Position) then
                    return
                end
            end

            seen[object] = true
            inspectChest(object)
        end

        local function inspectInteraction(object)
            if not object or not object:IsDescendantOf(workspace) then
                return
            end

            -- Avoid repeatedly resolving the same chest from multiple prompts.
            local chest = getChestTarget(object)

            if chest then
                if not resolvedChests[chest] then
                    resolvedChests[chest] = true
                    inspectChest(chest)
                end
            else
                -- Keep the generic fallback for unusual chest structures that
                -- are recognized only after their interaction appears.
                inspectOnce(object)
            end
        end

        -- First use the game's known chest-related tags.
        local collectionService = game:GetService("CollectionService")

        for _, tag in ipairs({
            "Chests",
            "Prompt_Chest",
            "BuriedChests",
        }) do
            for _, object in ipairs(collectionService:GetTagged(tag)) do
                inspectOnce(object)
            end
        end

        local map = workspace:FindFirstChild("Map")

        if map then
            -- Keep the existing static cache for known chest-location folders.
            scanStaticChestLocations(map)

            for index, object in ipairs(map:GetDescendants()) do
                if index % 500 == 0 then
                    task.wait()
                end

                -- Strongest generic discovery path. This catches chests that:
                --   * have a generic/non-chest model name
                --   * are hidden inside another model/folder
                --   * are not covered by the known chest tags
                if object:IsA("ProximityPrompt")
                    or object:IsA("ClickDetector") then
                    inspectInteraction(object)

                elseif object:IsA("Model") then
                    -- Keep named-model discovery as a fallback for chest models
                    -- that do not expose their interaction immediately.
                    local normalized = normalizeName(object.Name)

                    if normalized:find("chest", 1, true)
                        or normalized:find("treasure", 1, true)
                        or normalized:find("sealed", 1, true)
                        or normalized == "rare"
                        or normalized == "uncommon"
                        or normalized == "legendary"
                        or normalized == "mystic" then
                        inspectOnce(object)
                    end
                end
            end
        end
    end

    -- Filter changes use the location cache instead of rescanning the map.
    scanSelectedChests = function()
        if not staticChestLocationsScanned then
            scanStaticChestLocations()
        else
            refreshStaticChestESP()
        end
    end
    local collectionService = game:GetService("CollectionService")

    for _, tag in ipairs({
        "Chests",
        "Prompt_Chest",
        "BuriedChests",
    }) do
        collectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
            if not isArcaneSessionActive() then
                return
            end

            if Config.ArcaneChestESP and hasAnyChestFilterEnabled(Config) then
                inspectChest(instance)
            end
        end)
    end

    -- Arcane can stream/create chest models after the initial scan. Do not
    -- depend on model names or tags in that case: an interaction appearing
    -- inside a generic hidden chest is enough to discover its real parent.
    workspace.DescendantAdded:Connect(function(instance)
        if not isArcaneSessionActive() then
            return
        end

        if not Config.ArcaneChestESP
            or not hasAnyChestFilterEnabled(Config) then
            return
        end

        if instance:IsA("ProximityPrompt")
            or instance:IsA("ClickDetector") then
            task.defer(function()
                if instance.Parent and instance:IsDescendantOf(workspace) then
                    inspectChest(instance)
                end
            end)
        elseif instance:IsA("Model") then
            local normalized = normalizeName(instance.Name)

            if normalized:find("chest", 1, true)
                or normalized:find("treasure", 1, true)
                or normalized:find("sealed", 1, true)
                or normalized == "rare"
                or normalized == "uncommon"
                or normalized == "legendary"
                or normalized == "mystic" then
                task.defer(function()
                    if instance.Parent and instance:IsDescendantOf(workspace) then
                        inspectChest(instance)
                    end
                end)
            end
        end
    end)

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
        markSolarHubVisual(highlight)
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = Color3.fromRGB(220, 140, 40)
        highlight.OutlineColor = Color3.fromRGB(220, 140, 40)
        highlight.FillTransparency = 0.84
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarSideQuestESPInfo"
        markSolarHubVisual(billboard)
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
        markSolarHubVisual(anchor)
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
        markSolarHubVisual(billboard)
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
        markSolarHubVisual(highlight)
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
        markSolarHubVisual(anchor)
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
        markSolarHubVisual(billboard)
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
        markSolarHubVisual(highlight)
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

    local function scanWorkspaceNPCRecords()
        if not Config.ArcaneSideQuestESP then
            return
        end

        local npcFolder = workspace:FindFirstChild("NPCs")

        if not npcFolder then
            return
        end

        for _, record in ipairs(npcFolder:GetChildren()) do
            if record:IsA("Model") then
                local knownName = NORMALIZED_SIDE_QUEST_NPCS[normalizeName(record.Name)]

                if knownName then
                    local cfValue = record:FindFirstChild("CF")

                    if cfValue and cfValue:IsA("CFrameValue") then
                        local position = cfValue.Value.Position
                        local key = "NPCRECORD|" .. record:GetFullName()

                        -- If the live visual NPC exists, let the normal model ESP
                        -- handle it. Otherwise use the game's own CF record.
                        local modelValue = record:FindFirstChild("Model")
                        local liveModel = modelValue
                            and modelValue:IsA("ObjectValue")
                            and modelValue.Value
                            or nil

                        local hasLiveModel = liveModel
                            and liveModel:IsA("Model")
                            and liveModel:IsDescendantOf(workspace)
                            and liveModel:FindFirstChildOfClass("Humanoid") ~= nil

                        if hasLiveModel then
                            destroySideQuestVirtualESP(key)
                        else
                            createSideQuestLocationVirtualESP(
                                knownName,
                                position,
                                key,
                                record
                            )
                        end
                    end
                end
            end
        end
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

        -- Use the game's persistent Workspace.NPCs records first. Their CF
        -- values are the actual NPC spawn CFrames, even without a Humanoid.
        scanWorkspaceNPCRecords()

        -- Keep the older registry scan as a secondary source.
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
        markSolarHubVisual(highlight)
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarBossESPInfo"
        markSolarHubVisual(billboard)
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

    do
        local map = workspace:FindFirstChild("Map")
        local seaContent = map and map:FindFirstChild("SeaContent")
        local npcLocations = seaContent and seaContent:FindFirstChild("NPCLocations")

        if npcLocations then
            npcLocations.DescendantAdded:Connect(function()
                if Config.ArcaneSideQuestESP then
                    task.defer(scanSideQuestLocationRegistry)
                end
            end)

            npcLocations.DescendantRemoving:Connect(function(instance)
                if instance:IsA("BasePart")
                    and Config.ArcaneSideQuestESP then
                    task.defer(scanSideQuestLocationRegistry)
                end
            end)
        end
    end

    workspace.DescendantAdded:Connect(function(instance)
        if not isArcaneSessionActive() then
            return
        end

        local model = instance:IsA("Model")
            and instance
            or instance:FindFirstAncestorOfClass("Model")

        local parent = instance.Parent

        if parent
            and (parent:IsA("Folder") or parent:IsA("Model"))
            and normalizeName(parent.Name) == "chests"
            and (instance:IsA("Model") or instance:IsA("BasePart")) then
            task.defer(function()
                if instance.Parent then
                    local chestType = getChestTypeFast(instance)
                        or getChestType(instance)
                        or "OTHER"

                    cacheStaticChestLocation(instance, chestType)

                    if Config.ArcaneChestESP
                        and hasAnyChestFilterEnabled(Config) then
                        createStaticChestESP(instance, chestType)
                    end
                end
            end)
        end

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
        if not isArcaneSessionActive() then
            return
        end

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
            scanAllWorkspaceChests()

            -- Lifecycle monitoring starts AFTER the global scanner finishes,
            -- so it cannot slow down or gate initial static chest discovery.
            for chest in pairs(chestESPObjects) do
                watchChestLifecycle(chest)
            end
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
    local chestScanAccumulator = 0

    local function getChestFilterSignature()
        local parts = {}

        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            parts[#parts + 1] = Config.ArcaneChestFilter[chestType] == true
                and "1"
                or "0"

            parts[#parts + 1] = ";"
        end

        return table.concat(parts, "")
    end

    task.spawn(function()
        while isArcaneSessionActive() do
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

                    for key in pairs(staticChestESPObjects) do
                        destroyStaticChestESP(key)
                    end
                end
            end

            targetedScanAccumulator += 0.25
            chestScanAccumulator += 0.25

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

            -- Chest discovery is event-driven after the initial scan.
            -- Workspace.DescendantAdded + CollectionService tag signals catch
            -- streamed/spawned chests without repeatedly walking the whole Map.
            chestScanAccumulator = 0
        end
    end)

    task.spawn(function()
        while isArcaneSessionActive() do
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
        while isArcaneSessionActive() do
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
        while isArcaneSessionActive() do
            task.wait(0.5)

            if Config.ArcaneChestESP
                and hasAnyChestFilterEnabled(Config) then
                for target in pairs(chestCandidates) do
                    if not target.Parent then
                        chestCandidates[target] = nil
                        destroyChestESP(target)
                    else
                        watchChestLifecycle(target)

                        if openedChests[target] then
                            markChestOpened(target)
                        elseif not hasLiveChestInteraction(target) then
                            chestCandidates[target] = nil
                            destroyChestESP(target)
                        else
                            local chestType = chestTypeCache[target]

        if not chestType then
            chestType = getChestTypeFast(target) or getChestType(target)
            chestTypeCache[target] = chestType
        end

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

                for key in pairs(staticChestESPObjects) do
                    destroyStaticChestESP(key)
                end

                -- Keep openedChests intact while ESP is OFF or filters are cleared.
                -- This prevents already-opened chests from returning after re-enable.

            end
        end
    end)

    task.spawn(function()
        while isArcaneSessionActive() do
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
        while isArcaneSessionActive() do
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
        while isArcaneSessionActive() do
            task.wait(1)

            if not Config.ArcaneChestESP
                or not hasAnyChestFilterEnabled(Config)
                or next(staticChestESPObjects) == nil then
                continue
            end

            local playerRoot = getLocalPlayerRoot()

            if playerRoot then
                for key, location in pairs(staticChestLocationCache) do
                    if not isChestFilterEnabled(Config, location.chestType) then
                        destroyStaticChestESP(key)
                    elseif isChestWithinScanDistance(location.position) then
                        createStaticChestESP(
                            location.source,
                            location.chestType,
                            location.position,
                            key
                        )

                        local data = staticChestESPObjects[key]
                        if data then
                            local distance = math.floor(
                                (playerRoot.Position - location.position).Magnitude
                            )

                            if data.lastDistance ~= distance then
                                data.lastDistance = distance
                                data.label.Text =
                                    (CHEST_DISPLAY_NAMES[data.chestType] or "Chest Location")
                                    .. " | STUDS: "
                                    .. tostring(distance)
                            end
                        end
                    else
                        destroyStaticChestESP(key)
                    end
                end
            end
        end
    end)


    task.spawn(function()
        while isArcaneSessionActive() do
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
                        or not hasLiveChestInteraction(target) then

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
        while isArcaneSessionActive() do
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


    local function cleanupArcaneSession()
        -- Remove chart marker, all green Highlights, and debug UI on re-execute.
        pcall(destroyTreasureChartESP)
        pcall(destroyTreasureDebugGui)
        pcall(destroyTreasureTeleportGui)

        for chest in pairs(chestLifecycleWatchers) do
            cleanupChestLifecycleWatcher(chest)
        end

        for target in pairs(chestESPObjects) do
            destroyChestESP(target)
        end

        for key in pairs(staticChestESPObjects) do
            destroyStaticChestESP(key)
        end

        for model in pairs(espObjects) do
            destroyESP(model)
        end

        for model in pairs(sideQuestESPObjects) do
            destroySideQuestESP(model)
        end

        for key in pairs(sideQuestVirtualESPObjects) do
            destroySideQuestVirtualESP(key)
        end

        if staticChestAnchor then
            pcall(function()
                staticChestAnchor:Destroy()
            end)
            staticChestAnchor = nil
        end

        if bossNotificationGui then
            pcall(function()
                bossNotificationGui:Destroy()
            end)
        end

    end

    Context.registerCleanup(cleanupArcaneSession)

    return true
end

return ArcaneMisc