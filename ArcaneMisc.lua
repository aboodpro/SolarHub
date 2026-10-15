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

-- Selectable filters: seven Treasure Chest variants and three Sealed Chest variants.
local CHEST_TYPE_ORDER = {
    "COMMON",
    "UNCOMMON",
    "RARE",
    "MYSTIC",
    "LEGENDARY",
    "PRIVATE_STORAGE",
    "SKY",
    "BRONZE_SEALED",
    "NIMBUS_SEALED",
    "DARK_SEALED",
}

local CHEST_DISPLAY_NAMES = {
    COMMON = "Common Chest",
    UNCOMMON = "Uncommon Chest",
    RARE = "Rare Chest",
    MYSTIC = "Mystic Chest",
    LEGENDARY = "Legendary Chest",
    PRIVATE_STORAGE = "Private Storage Chest",
    SKY = "Sky Chest",
    SEALED = "Sealed Chest (Type Unknown)",
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
    SEALED = Color3.fromRGB(80, 205, 190),
    STEEL = Color3.fromRGB(175, 175, 185),
    BRONZE_SEALED = Color3.fromRGB(220, 150, 75),
    NIMBUS_SEALED = Color3.fromRGB(75, 190, 255),
    DARK_SEALED = Color3.fromRGB(185, 85, 255),
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

    -- One toggle controls all sealed types; keep the specific type as metadata for labels.
    if text:find("sealed", 1, true) then
        if text:find("dark", 1, true) or text:find("atlantean", 1, true) then
            return "DARK_SEALED"
        end
        if text:find("nimbus", 1, true) then
            return "NIMBUS_SEALED"
        end
        if text:find("bronze", 1, true) then
            return "BRONZE_SEALED"
        end
        return "SEALED"
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

    -- Some chest variants expose their name on a nearby parent/container.
    -- Check a few ancestor names individually; don't combine the whole island
    -- path, since that can misclassify every chest on an island named "Sky...".
    local ancestor = target.Parent
    local ancestorDepth = 0
    while ancestor and ancestor ~= workspace and ancestorDepth < 5 do
        table.insert(sources, ancestor.Name)
        ancestor = ancestor.Parent
        ancestorDepth += 1
    end

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
            local childName = normalizeChestText(child.Name)
            if childName:find("sealed", 1, true)
                or childName:find("privatestorage", 1, true)
                or childName:find("skychest", 1, true)
                or childName:find("skyhall", 1, true)
                or childName:find("bronze", 1, true)
                or childName:find("nimbus", 1, true)
                or childName:find("dark", 1, true)
                or childName:find("legendary", 1, true)
                or childName:find("mystic", 1, true)
                or childName:find("uncommon", 1, true)
                or childName:find("rare", 1, true)
                or childName:find("common", 1, true) then
                table.insert(sources, child.Name)
            end

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

    -- Some exact variants are exposed as a short model name without "Chest".
    if target:IsA("Model") then
        local targetName = normalizeChestText(target.Name)
        if targetName == "sky" then return "SKY" end
        if targetName == "privatestorage" then return "PRIVATE_STORAGE" end
    end

    -- Buried treasure found through Treasure Charts is not a separate chest type;
    -- classify it by its actual rarity (or as Sealed if the object is sealed).

    -- Prefer specific rarity/type data over the generic "Treasure Chest"
    -- name. A live Rare Chest can still be named Treasure Chest while its
    -- actual rarity is exposed by a value, attribute, prompt, or child.
    local genericCommon = false
    local genericSealed = false
    local sources = collectChestTextSources(target)

    -- First determine whether this object is sealed at all. Some games expose
    -- "SealedChest" on the model and "Bronze"/"Nimbus"/"Dark" on a parent or
    -- metadata value; sealed classification must take priority over rarity words.
    local hasSealed, hasBronze, hasNimbus, hasDark, hasSkyhall =
        false, false, false, false, false
    local hasPrivateStorage, hasSkyType, hasChestIdentity = false, false, false
    for _, source in ipairs(sources) do
        local normalized = normalizeChestText(source)
        hasSealed = hasSealed or normalized:find("sealed", 1, true) ~= nil
        hasBronze = hasBronze or normalized:find("bronze", 1, true) ~= nil
        hasNimbus = hasNimbus or normalized:find("nimbus", 1, true) ~= nil
        hasDark = hasDark or normalized:find("dark", 1, true) ~= nil
            or normalized:find("atlantean", 1, true) ~= nil
        hasSkyhall = hasSkyhall or normalized:find("skyhall", 1, true) ~= nil
        hasPrivateStorage = hasPrivateStorage
            or normalized:find("privatestorage", 1, true) ~= nil
        hasSkyType = hasSkyType
            or normalized == "sky"
            or normalized:find("skychest", 1, true) ~= nil
        hasChestIdentity = hasChestIdentity
            or normalized:find("chest", 1, true) ~= nil
            or normalized:find("buriedtreasure", 1, true) ~= nil

        local chestType = classifyChestText(source)
        if chestType == "COMMON" then
            genericCommon = true
        elseif chestType == "SEALED" then
            genericSealed = true
        end
    end

    if hasSealed then
        if hasDark then return "DARK_SEALED" end
        if hasNimbus then return "NIMBUS_SEALED" end
        if hasBronze then return "BRONZE_SEALED" end
        return "SEALED"
    elseif genericSealed then
        return "SEALED"
    end

    -- These are chest variants, not separate ESP systems. Give explicit
    -- Private Storage metadata priority over generic common/rarity text.
    if hasPrivateStorage and hasChestIdentity then
        return "PRIVATE_STORAGE"
    end
    if hasSkyType and hasChestIdentity and not hasPrivateStorage then
        return "SKY"
    end

    -- No sealed chest found: prefer a specific Treasure Chest type (rare,
    -- mystic, legendary) before falling back to generic Common.
    for _, source in ipairs(sources) do
        local chestType = classifyChestText(source)
        if chestType and chestType ~= "COMMON" and chestType ~= "SEALED"
            and chestType ~= "BRONZE_SEALED"
            and chestType ~= "NIMBUS_SEALED"
            and chestType ~= "DARK_SEALED" then
            return chestType
        end
    end

    -- Sky Chests are tied to Skyhall and nearby sky islands. The game may
    -- name those objects generically, so use the location only when the chest
    -- itself has no more specific exposed type.
    if hasSkyhall and hasChestIdentity then return "SKY" end
    if genericCommon then return "COMMON" end
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
    if chestType and chestType ~= "COMMON" and chestType ~= "SEALED" then
        return chestType
    end

    local model = target:IsA("Model")
        and target
        or target:FindFirstAncestorOfClass("Model")

    if model then
        chestType = classifyChestText(model.Name)
        if chestType and chestType ~= "COMMON" and chestType ~= "SEALED" then
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

    if chestType == "SEALED" then
        -- If the game hides the subtype in its instance data, show a generic
        -- sealed marker whenever the user has selected at least one sealed type.
        return filter.BRONZE_SEALED == true
            or filter.NIMBUS_SEALED == true
            or filter.DARK_SEALED == true
    end

    if chestType == "BRONZE_SEALED"
        or chestType == "NIMBUS_SEALED"
        or chestType == "DARK_SEALED" then
        return filter[chestType] == true
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
        or normalized:find("buriedtreasure", 1, true)
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

local function findSealedChestTarget(container)
    if not container
        or not (container:IsA("Folder") or container:IsA("Model")) then
        return nil
    end

    local normalizedName = normalizeChestText(container.Name)
    if not normalizedName:find("sealed", 1, true)
        or normalizedName == "sealedchests"
        or normalizedName:find("chestcontainer", 1, true) then
        return nil
    end

    -- Some sealed chest objects are folders instead of Models. Resolve a
    -- renderable descendant, preferring a real chest model with a Base/prompt.
    local bestModel = nil
    local bestScore = -1

    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("Model") and looksLikeChestModel(descendant) then
            local descendantName = normalizeChestText(descendant.Name)
            local score = 0

            if descendantName:find("sealed", 1, true) then
                score += 100
            end
            if descendantName:find("chest", 1, true) then
                score += 80
            end
            if descendant:FindFirstChild("Base", true) then
                score += 20
            end
            if descendant:FindFirstChildWhichIsA("ProximityPrompt", true)
                or descendant:FindFirstChildWhichIsA("ClickDetector", true) then
                score += 15
            end

            if score > bestScore then
                bestModel = descendant
                bestScore = score
            end
        end
    end

    if bestModel then
        return bestModel
    end

    local fallbackPart = nil
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if normalizeChestText(descendant.Name) == "base" then
                return descendant
            end

            if not fallbackPart then
                fallbackPart = descendant
            end

            if descendant:FindFirstChildWhichIsA("ProximityPrompt", true)
                or descendant:FindFirstChildWhichIsA("ClickDetector", true) then
                return descendant
            end
        end
    end

    return fallbackPart
end

local function getChestTarget(object)
    if not object or not object.Parent then
        return nil
    end

    -- Resolve the nearest actual chest model above the scanned object.
    -- Sealed chest folders are a special case in Arcane: use their contained
    -- Model/BasePart so ESP APIs receive a renderable target, not a Folder.
    local current = object

    while current and current ~= workspace do
        if current:IsA("Model") and looksLikeChestModel(current) then
            return current
        end

        if (current:IsA("Folder") or current:IsA("Model"))
            and normalizeChestText(current.Name):find("sealed", 1, true) then
            local sealedTarget = findSealedChestTarget(current)
            if sealedTarget then
                return sealedTarget
            end
        end

        current = current.Parent
    end

    -- Tagged/container objects may be the thing reported by CollectionService.
    -- Find a concrete chest model inside rather than targeting the container.
    if object:IsA("Model") or object:IsA("Folder") then
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
                or normalized:find("buriedtreasure", 1, true) ~= nil
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

            setText("CHEST DEBUG v7 | GLOBAL + INFINITE RANGE | SCANNING...")

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
                    or normalized:find("buriedtreasure", 1, true) ~= nil
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
                "SOLARHUB CHEST DEBUG v7",
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

            appendLine("")
            appendLine("UNLOADED ISLAND / SEA CHEST TREE:")
            appendLine("Lists every island folder plus all Chests/TempChests/SealedChests containers and their direct entries.")

            local rsFolder = rs and rs:FindFirstChild("RS")
            local unloadDarkSea = rsFolder and rsFolder:FindFirstChild("UnloadDarkSea")
            local storageRoots = {
                {label = "UnloadIslands", root = unloadIslands},
                {label = "UnloadDarkSea", root = unloadDarkSea},
            }
            local treeLines = 0
            local treeLimit = 3000
            local treeContainerCount = 0
            local treeEntryCount = 0

            local function isChestContainerName(value)
                local normalized = normalizeChestText(value)
                return normalized == "chests"
                    or normalized == "tempchests"
                    or normalized == "sealedchests"
                    or normalized == "treasurechests"
                    or normalized:find("chestcontainer", 1, true) ~= nil
            end

            local function appendTreeLine(value)
                if treeLines >= treeLimit then
                    return false
                end
                appendLine(value)
                treeLines += 1
                return true
            end

            for _, storage in ipairs(storageRoots) do
                appendTreeLine("")
                appendTreeLine("ROOT " .. storage.label .. ": " .. safeString(storage.root))

                if not storage.root then
                    appendTreeLine("<missing>")
                else
                    local islandChildren = storage.root:GetChildren()
                    appendTreeLine(("DIRECT CHILDREN: %d | DESCENDANTS: %d"):format(
                        #islandChildren,
                        #storage.root:GetDescendants()
                    ))

                    for islandIndex, island in ipairs(islandChildren) do
                        if islandIndex % 50 == 0 then
                            task.wait()
                        end

                        appendTreeLine(("ISLAND/REGION %s [%s] | CHILDREN=%d"):format(
                            island:GetFullName(),
                            island.ClassName,
                            #island:GetChildren()
                        ))

                        local nodes = {island}
                        for _, descendant in ipairs(island:GetDescendants()) do
                            nodes[#nodes + 1] = descendant
                        end

                        local containers = {}
                        for _, node in ipairs(nodes) do
                            if (node:IsA("Folder") or node:IsA("Model"))
                                and isChestContainerName(node.Name) then
                                containers[#containers + 1] = node
                            end
                        end

                        table.sort(containers, function(a, b)
                            return a:GetFullName() < b:GetFullName()
                        end)

                        if #containers == 0 then
                            local immediate = {}
                            for childIndex, child in ipairs(island:GetChildren()) do
                                if childIndex > 12 then
                                    immediate[#immediate + 1] = "..."
                                    break
                                end
                                immediate[#immediate + 1] = child.Name .. "[" .. child.ClassName .. "]"
                            end
                            appendTreeLine("  NO CHEST CONTAINER FOUND; DIRECT CHILDREN: "
                                .. (#immediate > 0 and table.concat(immediate, ", ") or "<none>"))
                        end

                        for _, container in ipairs(containers) do
                            treeContainerCount += 1
                            local entries = container:GetChildren()
                            appendTreeLine(("  CONTAINER %s | CHILDREN=%d"):format(
                                container:GetFullName(),
                                #entries
                            ))

                            for entryIndex, entry in ipairs(entries) do
                                if treeLines >= treeLimit then
                                    break
                                end
                                if entryIndex % 100 == 0 then
                                    task.wait()
                                end

                                treeEntryCount += 1
                                local chestType = getType(entry)
                                local rootPart = getAnyRoot(entry)
                                local positionText = "POS=?"
                                if rootPart then
                                    local position = rootPart.Position
                                    positionText = ("POS=%.1f,%.1f,%.1f"):format(
                                        position.X, position.Y, position.Z
                                    )
                                else
                                    pcall(function()
                                        local pivot = entry:GetPivot()
                                        positionText = ("PIVOT=%.1f,%.1f,%.1f"):format(
                                            pivot.Position.X,
                                            pivot.Position.Y,
                                            pivot.Position.Z
                                        )
                                    end)
                                end

                                local childNames = {}
                                if entry:IsA("Model") or entry:IsA("Folder") then
                                    for childIndex, child in ipairs(entry:GetDescendants()) do
                                        if childIndex > 10 then
                                            childNames[#childNames + 1] = "..."
                                            break
                                        end
                                        childNames[#childNames + 1] =
                                            child.Name .. "[" .. child.ClassName .. "]"
                                    end
                                end

                                appendTreeLine(("    ENTRY %s [%s] | TYPE=%s | %s | ATTR={%s} | VALUES={%s}"):format(
                                    entry:GetFullName(),
                                    entry.ClassName,
                                    chestType,
                                    positionText,
                                    getAttributeSummary(entry),
                                    getValueObjectSummary(entry)
                                ))
                                if #childNames > 0 then
                                    appendTreeLine("      CHILDREN: " .. table.concat(childNames, ", "))
                                end
                            end
                        end
                    end
                end
            end

            appendLine(("TREE SUMMARY: containers=%d | direct entries=%d | printed lines=%d%s"):format(
                treeContainerCount,
                treeEntryCount,
                treeLines,
                treeLines >= treeLimit and " | OUTPUT TRUNCATED AT LIMIT" or ""
            ))
            appendLine("If UnloadDarkSea exists but reports no containers, send this tree section anyway; its folder layout matters.")

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
            setText("CHEST DEBUG v7 ERROR\n" .. tostring(err))
            warn("[SolarHub] Chest DEBUG v6 error:", err)
        end
    end)
end
-------------------------------------------------
-- ESP
-------------------------------------------------

function ArcaneMisc.Init(Shared, UI, Context)
    Shared.SolarHubStats = Shared.SolarHubStats or {
        chestScans = 0,
        chestsDetected = 0,
        chestMarkersCreated = 0,
        chestScanErrors = 0,
        chestRecoveries = 0,
    }
    local chestStats = Shared.SolarHubStats

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
    Config.ArcaneWantedCriminalESP = Config.ArcaneWantedCriminalESP == true
    Config.ArcaneBossDebug = Config.ArcaneBossDebug == true
    Config.ArcaneChestESP = Config.ArcaneChestESP == true
    Config.ArcaneSideQuestESP = Config.ArcaneSideQuestESP == true
    -- Chest filters start OFF. The user selects the chest types they want.
    if type(Config.ArcaneChestFilter) ~= "table" then
        Config.ArcaneChestFilter = {}
    end
    if Config.ArcaneChestFilter.SEALED == true then
        Config.ArcaneChestFilter.BRONZE_SEALED = true
        Config.ArcaneChestFilter.NIMBUS_SEALED = true
        Config.ArcaneChestFilter.DARK_SEALED = true
    end
    -- Remove the legacy single filter after migration so it cannot override
    -- the three independent subtype switches.
    Config.ArcaneChestFilter.SEALED = nil

    for _, chestType in ipairs(CHEST_TYPE_ORDER) do
        if Config.ArcaneChestFilter[chestType] == nil then
            Config.ArcaneChestFilter[chestType] = false
        end
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
    -- BOAT CONTROLS / OWNERSHIP-SAFE
    -------------------------------------------------

    Config.ArcaneBoatSpeedControl = Config.ArcaneBoatSpeedControl == true
    Config.ArcaneBoatSpeed = math.clamp(
        math.floor(tonumber(Config.ArcaneBoatSpeed) or 160),
        30,
        350
    )

    local boatPlayer = Shared.player
    local ownedBoatCache = nil
    local boatNextScanAt = 0
    local boatSpeedConnection = nil
    local boatSpeedStatus = ""

    local boatSection = UI.createSection(
        miscTab,
        "Boat Controls",
        216
    )

    local tpToBoatButton = Instance.new("TextButton")
    tpToBoatButton.Name = "TPToOwnedBoatButton"
    tpToBoatButton.Size = UDim2.new(1, -20, 0, 34)
    tpToBoatButton.Position = UDim2.fromOffset(10, 40)
    tpToBoatButton.BackgroundColor3 = Color3.fromRGB(54, 48, 35)
    tpToBoatButton.BorderSizePixel = 0
    tpToBoatButton.Text = "TP TO MY BOAT"
    tpToBoatButton.TextColor3 = Color3.fromRGB(255, 220, 150)
    tpToBoatButton.Font = Enum.Font.GothamBold
    tpToBoatButton.TextSize = 10
    tpToBoatButton.AutoButtonColor = true
    tpToBoatButton.Parent = boatSection
    Instance.new("UICorner", tpToBoatButton).CornerRadius = UDim.new(0, 8)

    UI.createToggle(
        boatSection,
        "Boat Speed Control",
        "Adjusts your verified boat's horizontal speed while it is moving.",
        "ArcaneBoatSpeedControl",
        80
    )

    local boatSpeedSlider = UI.createSlider(
        boatSection,
        "Boat Speed (studs/s)",
        "ArcaneBoatSpeed",
        30,
        350,
        10,
        134,
        330,
        function(value)
            Config.ArcaneBoatSpeed = math.clamp(
                math.floor(tonumber(value) or 160),
                30,
                350
            )
        end
    )
    boatSpeedSlider.setValue(Config.ArcaneBoatSpeed)

    local boatStatusLabel = Instance.new("TextLabel")
    boatStatusLabel.Name = "BoatControlStatus"
    boatStatusLabel.Size = UDim2.new(1, -20, 0, 28)
    boatStatusLabel.Position = UDim2.fromOffset(10, 180)
    boatStatusLabel.BackgroundTransparency = 1
    boatStatusLabel.Text = "TP only targets a boat with ownership evidence."
    boatStatusLabel.TextColor3 = Color3.fromRGB(145, 145, 155)
    boatStatusLabel.Font = Enum.Font.Gotham
    boatStatusLabel.TextSize = 8
    boatStatusLabel.TextWrapped = true
    boatStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    boatStatusLabel.Parent = boatSection

    local function setBoatStatus(message, isError)
        boatSpeedStatus = tostring(message or "")
        if boatStatusLabel and boatStatusLabel.Parent then
            boatStatusLabel.Text = boatSpeedStatus
            boatStatusLabel.TextColor3 = isError
                and Color3.fromRGB(255, 115, 105)
                or Color3.fromRGB(220, 175, 95)
        end
    end

    local function boatNormalize(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function isOwnerFieldName(value)
        local key = boatNormalize(value)
        return key == "owner"
            or key == "ownerid"
            or key == "owneruserid"
            or key == "ownername"
            or key == "boatowner"
            or key == "shipowner"
            or key == "player"
            or key == "playerid"
            or key == "playeruserid"
            or key == "playername"
            or key == "userid"
            or key == "username"
            or key == "creator"
            or key == "creatorid"
            or key == "creatoruserid"
            or key == "pilot"
            or key == "captain"
    end

    local function valueMatchesBoatPlayer(value)
        if not boatPlayer then
            return false
        end

        if typeof(value) == "Instance" then
            if value == boatPlayer or value == boatPlayer.Character then
                return true
            end

            local isPlayerObject = false
            pcall(function()
                isPlayerObject = value:IsA("Player")
            end)
            if isPlayerObject then
                return value.UserId == boatPlayer.UserId
            end

            local objectName = boatNormalize(value.Name)
            return objectName ~= ""
                and objectName == boatNormalize(boatPlayer.Name)
        end

        if type(value) == "number" then
            return value == boatPlayer.UserId
        end

        if type(value) == "string" then
            local normalized = boatNormalize(value)
            local playerName = boatNormalize(boatPlayer.Name)
            local displayName = boatNormalize(boatPlayer.DisplayName)
            local userIdText = tostring(boatPlayer.UserId)

            return normalized == playerName
                or normalized == displayName
                or normalized == userIdText
                or (#userIdText >= 5 and normalized:find(userIdText, 1, true) ~= nil)
        end

        return false
    end

    local function inspectBoatOwnerNode(node)
        if not node then
            return false, false
        end

        local hasOwnerMetadata = false
        local okAttributes, attributes = pcall(function()
            return node:GetAttributes()
        end)
        if okAttributes and type(attributes) == "table" then
            for key, value in pairs(attributes) do
                if isOwnerFieldName(key) then
                    hasOwnerMetadata = true
                    if valueMatchesBoatPlayer(value) then
                        return true, true
                    end
                end
            end
        end

        for _, child in ipairs(node:GetChildren()) do
            if isOwnerFieldName(child.Name) then
                hasOwnerMetadata = true
                local canReadValue = false
                local childValue = nil
                pcall(function()
                    if child:IsA("ObjectValue")
                        or child:IsA("StringValue")
                        or child:IsA("IntValue")
                        or child:IsA("NumberValue") then
                        childValue = child.Value
                        canReadValue = true
                    end
                end)

                if canReadValue and valueMatchesBoatPlayer(childValue) then
                    return true, true
                end
            end
        end

        return false, hasOwnerMetadata
    end

    local function getBoatOwnerEvidenceScore(model)
        if not model or not model:IsA("Model") then
            return 0
        end

        -- Explicit ownership metadata takes precedence over model-name guesses.
        -- If a model explicitly names another owner, never TP to it just because
        -- its display name happens to contain the local player's username.
        local matchedOwner, hasOwnerMetadata = inspectBoatOwnerNode(model)
        if matchedOwner then
            return 120
        end

        -- A direct Owner/UserId field is authoritative. A mismatch must not be
        -- overridden by a matching-looking model name or nested decoration.
        if hasOwnerMetadata then
            return 0
        end

        for _, descendant in ipairs(model:GetDescendants()) do
            local descendantMatched, descendantHasMetadata = inspectBoatOwnerNode(descendant)
            if descendantMatched then
                return 90
            end
            hasOwnerMetadata = hasOwnerMetadata or descendantHasMetadata
        end

        if hasOwnerMetadata then
            return 0
        end

        -- Some builds encode the owner in a boat/ship model name instead of a
        -- ValueObject. Only accept clear username/UID naming patterns as fallback.
        local normalizedName = boatNormalize(model.Name)
        local normalizedPlayerName = boatNormalize(boatPlayer and boatPlayer.Name)
        local userIdText = tostring(boatPlayer and boatPlayer.UserId or "")
        local hasVesselWord = normalizedName:find("boat", 1, true) ~= nil
            or normalizedName:find("ship", 1, true) ~= nil
            or normalizedName:find("brig", 1, true) ~= nil
            or normalizedName:find("caravel", 1, true) ~= nil
            or normalizedName:find("ketch", 1, true) ~= nil
            or normalizedName:find("sailboat", 1, true) ~= nil
            or normalizedName:find("rowboat", 1, true) ~= nil

        if hasVesselWord and normalizedName ~= ""
            and userIdText ~= ""
            and normalizedName:find(userIdText, 1, true) ~= nil then
            return 70
        end

        if hasVesselWord and #normalizedPlayerName >= 3 then
            local acceptedNamePatterns = {
                "boat" .. normalizedPlayerName,
                "ship" .. normalizedPlayerName,
                "brig" .. normalizedPlayerName,
                "caravel" .. normalizedPlayerName,
                "ketch" .. normalizedPlayerName,
                normalizedPlayerName .. "boat",
                normalizedPlayerName .. "ship",
                normalizedPlayerName .. "brig",
                normalizedPlayerName .. "caravel",
                normalizedPlayerName .. "ketch",
            }

            for _, pattern in ipairs(acceptedNamePatterns) do
                if normalizedName == pattern
                    or normalizedName:find(pattern, 1, true) ~= nil then
                    return 60
                end
            end
        end

        return 0
    end

    local function isBoatLikeModel(model)
        if not model or not model:IsA("Model") then
            return false
        end

        local name = boatNormalize(model.Name)
        if name == "boats" or name == "ships" or name == "playerboats"
            or name == "playerships" or name:find("fleet", 1, true) then
            return false
        end

        -- Fast path: ship-type names are common in Arcane Odyssey and avoid
        -- repeatedly walking every map model's descendants during discovery.
        if name:find("boat", 1, true)
            or name:find("ship", 1, true)
            or name:find("brig", 1, true)
            or name:find("caravel", 1, true)
            or name:find("ketch", 1, true)
            or name:find("vessel", 1, true) then
            return true
        end

        -- Generic model names are considered only when the name itself contains
        -- this player's username/UID; this avoids deep-searching every map model.
        local playerName = boatNormalize(boatPlayer and boatPlayer.Name)
        local userIdText = tostring(boatPlayer and boatPlayer.UserId or "")
        local nameMayIdentifyOwner = (#playerName >= 3
                and name:find(playerName, 1, true) ~= nil)
            or (userIdText ~= "" and name:find(userIdText, 1, true) ~= nil)

        if nameMayIdentifyOwner then
            for _, markerName in ipairs({
                "Hull",
                "Sails",
                "Mast",
                "Helm",
                "ShipStats",
                "ShipHealth",
                "ShipRoot",
                "BoatRoot",
                "VehicleSeat",
            }) do
                if model:FindFirstChild(markerName, true) then
                    return true
                end
            end
        end

        return false
    end

    local function getOwnedBoatRoot(model)
        if not model or not model:IsA("Model") then
            return nil
        end

        local preferredNames = {
            "ShipRoot",
            "BoatRoot",
            "PrimaryPart",
            "Root",
            "RootPart",
            "Hull",
            "Base",
            "Main",
            "Body",
            "VehicleSeat",
        }

        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
            return model.PrimaryPart
        end

        for _, preferredName in ipairs(preferredNames) do
            local part = model:FindFirstChild(preferredName, true)
            if part and part:IsA("BasePart") then
                return part
            end
        end

        local bestPart = nil
        local bestVolume = -1
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
                if volume > bestVolume then
                    bestPart = descendant
                    bestVolume = volume
                end
            end
        end

        return bestPart
    end

    local function findMyBoat()
        if not boatPlayer then
            return nil, nil
        end

        local character = boatPlayer.Character
        local characterRoot = character and character:FindFirstChild("HumanoidRootPart")
        local bestModel = nil
        local bestRoot = nil
        local bestOwnerScore = 0
        local bestDistance = math.huge

        for _, object in ipairs(workspace:GetDescendants()) do
            if object:IsA("Model") and isBoatLikeModel(object) then
                local ownerScore = getBoatOwnerEvidenceScore(object)
                if ownerScore > 0 then
                    local root = getOwnedBoatRoot(object)
                    if root and root:IsDescendantOf(workspace) then
                        local distance = characterRoot
                            and (characterRoot.Position - root.Position).Magnitude
                            or math.huge

                        local replace = ownerScore > bestOwnerScore
                            or (ownerScore == bestOwnerScore and distance < bestDistance)

                        -- Prefer the outer ship model if both it and a nested
                        -- ship-like model carry matching owner metadata.
                        if bestModel and object:IsDescendantOf(bestModel)
                            and ownerScore <= bestOwnerScore then
                            replace = false
                        elseif bestModel and bestModel:IsDescendantOf(object)
                            and ownerScore >= bestOwnerScore then
                            replace = true
                        end

                        if replace then
                            bestModel = object
                            bestRoot = root
                            bestOwnerScore = ownerScore
                            bestDistance = distance
                        end
                    end
                end
            end
        end

        return bestModel, bestRoot
    end

    tpToBoatButton.Activated:Connect(function()
        if not isArcaneSessionActive() then
            return
        end

        tpToBoatButton.Text = "FINDING YOUR BOAT..."
        local ok, boat, boatRoot = pcall(findMyBoat)
        if not ok or not boat or not boatRoot then
            ownedBoatCache = nil
            tpToBoatButton.Text = "TP TO MY BOAT"
            setBoatStatus(
                "TP cancelled: no boat with verified ownership data was found.",
                true
            )
            return
        end

        local character = boatPlayer and boatPlayer.Character
        if not character or not character.Parent then
            tpToBoatButton.Text = "TP TO MY BOAT"
            setBoatStatus("TP cancelled: your character is not available.", true)
            return
        end

        local targetPosition = boatRoot.Position
            + Vector3.new(0, math.max(boatRoot.Size.Y * 0.5 + 5, 8), 0)

        local didTeleport = pcall(function()
            character:PivotTo(CFrame.new(targetPosition))
            local characterRoot = character:FindFirstChild("HumanoidRootPart")
            if characterRoot then
                characterRoot.AssemblyLinearVelocity = Vector3.zero
            end
        end)

        if didTeleport then
            ownedBoatCache = boat
            boatNextScanAt = os.clock() + 1
            tpToBoatButton.Text = "TP TO MY BOAT"
            setBoatStatus("Teleported to ownership-verified boat: " .. boat.Name, false)
        else
            tpToBoatButton.Text = "TP TO MY BOAT"
            setBoatStatus("TP failed: Roblox rejected the character movement.", true)
        end
    end)

    -- Speed is applied to the locally simulated assembly of the verified boat.
    -- It only changes horizontal velocity while the boat is already moving, so
    -- it won't force a stationary boat to sail or choose a direction for the user.
    local boatSpeedAccumulator = 0
    local boatValidationAccumulator = 0
    local runServiceForBoat = Shared.RunService or game:GetService("RunService")

    boatSpeedConnection = runServiceForBoat.Heartbeat:Connect(function(deltaTime)
        if not isArcaneSessionActive() or not Config.ArcaneBoatSpeedControl then
            boatSpeedAccumulator = 0
            return
        end

        boatValidationAccumulator += deltaTime
        boatSpeedAccumulator += deltaTime

        if boatValidationAccumulator >= 1.25 then
            boatValidationAccumulator = 0

            if not ownedBoatCache
                or not ownedBoatCache.Parent
                or not ownedBoatCache:IsDescendantOf(workspace)
                or getBoatOwnerEvidenceScore(ownedBoatCache) == 0 then
                ownedBoatCache = nil
            end

            if not ownedBoatCache and os.clock() >= boatNextScanAt then
                boatNextScanAt = os.clock() + 4.5
                local ok, boat = pcall(function()
                    local found = findMyBoat()
                    return found
                end)

                if ok and boat then
                    ownedBoatCache = boat
                    setBoatStatus("Speed control found your boat: " .. boat.Name, false)
                else
                    setBoatStatus(
                        "Speed control ON, but no ownership-verified boat is available.",
                        true
                    )
                end
            end
        end

        if boatSpeedAccumulator < 1 / 30 then
            return
        end
        boatSpeedAccumulator = 0

        local boat = ownedBoatCache
        if not boat or not boat.Parent or not boat:IsDescendantOf(workspace) then
            return
        end

        -- Ownership is revalidated on the slower scan timer above; avoid
        -- walking every descendant of the boat 30 times per second.
        local root = getOwnedBoatRoot(boat)
        local assembly = root and (root.AssemblyRootPart or root)
        if not assembly or not assembly:IsA("BasePart") or assembly.Anchored then
            return
        end

        local currentVelocity = assembly.AssemblyLinearVelocity
        local horizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
        local currentSpeed = horizontalVelocity.Magnitude
        local targetSpeed = math.clamp(
            tonumber(Config.ArcaneBoatSpeed) or 160,
            30,
            350
        )

        if currentSpeed > 2 and math.abs(currentSpeed - targetSpeed) > 1.5 then
            local boostedVelocity = horizontalVelocity.Unit * targetSpeed
            assembly.AssemblyLinearVelocity = Vector3.new(
                boostedVelocity.X,
                currentVelocity.Y,
                boostedVelocity.Z
            )
        end
    end)

    Context.registerCleanup(function()
        if boatSpeedConnection then
            pcall(function()
                boatSpeedConnection:Disconnect()
            end)
            boatSpeedConnection = nil
        end
        ownedBoatCache = nil
    end)


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


    -------------------------------------------------
    -- RARE CHEST NOTIFICATIONS
    -------------------------------------------------

    -- Weak keys make the alert state disappear with the chest model. This
    -- prevents duplicate toasts from repeated ESP scans of the same object.
    local rareChestNotified = setmetatable({}, {__mode = "k"})

    local function showRareChestNotification(chest, chestType, detectedPosition)
        if not chest
            or rareChestNotified[chest]
            or (chestType ~= "MYSTIC" and chestType ~= "LEGENDARY") then
            return
        end

        rareChestNotified[chest] = true

        local chestColor = CHEST_COLORS[chestType]
            or Color3.fromRGB(255, 190, 70)
        local chestTitle = chestType == "LEGENDARY"
            and "LEGENDARY CHEST DETECTED"
            or "MYSTIC CHEST DETECTED"

        local frame = Instance.new("Frame")
        frame.Name = "SolarRareChestNotification"
        frame.Size = UDim2.fromOffset(320, 80)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
        frame.BackgroundTransparency = 0.04
        frame.BorderSizePixel = 0
        frame.Parent = notificationHolder
        markSolarHubVisual(frame)
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

        local stroke = Instance.new("UIStroke")
        stroke.Color = chestColor
        stroke.Thickness = 1.3
        stroke.Transparency = 0.12
        stroke.Parent = frame

        local logo = Instance.new("TextLabel")
        logo.Name = "SolarLogo"
        logo.Position = UDim2.fromOffset(10, 20)
        logo.Size = UDim2.fromOffset(36, 36)
        logo.BackgroundColor3 = Color3.fromRGB(35, 35, 44)
        logo.BorderSizePixel = 0
        logo.Font = Enum.Font.GothamBlack
        logo.Text = "☀"
        logo.TextColor3 = Color3.fromRGB(255, 194, 70)
        logo.TextSize = 27
        logo.Parent = frame
        Instance.new("UICorner", logo).CornerRadius = UDim.new(1, 0)

        local title = Instance.new("TextLabel")
        title.Name = "ChestTitle"
        title.Position = UDim2.fromOffset(54, 12)
        title.Size = UDim2.new(1, -132, 0, 21)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.Text = chestTitle
        title.TextColor3 = chestColor
        title.TextSize = 10
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextTruncate = Enum.TextTruncate.AtEnd
        title.Parent = frame

        local detail = Instance.new("TextLabel")
        detail.Name = "ChestDetail"
        detail.Position = UDim2.fromOffset(54, 34)
        detail.Size = UDim2.new(1, -136, 0, 19)
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.Text = "Rare chest found by Chest ESP"
        detail.TextColor3 = Color3.fromRGB(175, 178, 190)
        detail.TextSize = 9
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.Parent = frame

        local timerLabel = Instance.new("TextLabel")
        timerLabel.Name = "ExpiresIn"
        timerLabel.Position = UDim2.new(1, -45, 0, 7)
        timerLabel.Size = UDim2.fromOffset(36, 14)
        timerLabel.BackgroundTransparency = 1
        timerLabel.Font = Enum.Font.GothamBold
        timerLabel.Text = "20s"
        timerLabel.TextColor3 = Color3.fromRGB(175, 178, 190)
        timerLabel.TextSize = 9
        timerLabel.TextXAlignment = Enum.TextXAlignment.Right
        timerLabel.Parent = frame

        local tpButton = Instance.new("TextButton")
        tpButton.Name = "TeleportButton"
        tpButton.Position = UDim2.new(1, -72, 0, 34)
        tpButton.Size = UDim2.fromOffset(60, 30)
        tpButton.BackgroundColor3 = chestColor
        tpButton.BorderSizePixel = 0
        tpButton.Font = Enum.Font.GothamBlack
        tpButton.Text = "TP"
        tpButton.TextColor3 = Color3.fromRGB(18, 18, 22)
        tpButton.TextSize = 12
        tpButton.AutoButtonColor = true
        tpButton.Parent = frame
        Instance.new("UICorner", tpButton).CornerRadius = UDim.new(0, 7)

        local teleporting = false
        tpButton.Activated:Connect(function()
            if teleporting or not frame.Parent or not isArcaneSessionActive() then
                return
            end
            teleporting = true

            local character = Shared.player and Shared.player.Character
            local targetPosition = detectedPosition

            -- Use the chest's live position if it still exists; otherwise use
            -- the position captured at discovery so the toast can still TP.
            if chest and chest.Parent then
                local liveRoot = getChestRoot(chest)
                if liveRoot and liveRoot:IsDescendantOf(workspace) then
                    targetPosition = liveRoot.Position
                end
            end

            local ok = pcall(function()
                if not character or not character.Parent
                    or typeof(targetPosition) ~= "Vector3" then
                    error("Character or chest position is unavailable")
                end

                character:PivotTo(CFrame.new(targetPosition + Vector3.new(0, 5, 0)))
            end)

            tpButton.Text = ok and "TP ✓" or "NO TARGET"
            if not ok then
                tpButton.BackgroundColor3 = Color3.fromRGB(95, 95, 105)
            end
            teleporting = false
        end)

        task.spawn(function()
            for remaining = 20, 1, -1 do
                if not frame.Parent then
                    return
                end
                timerLabel.Text = tostring(remaining) .. "s"
                task.wait(1)
            end

            if frame and frame.Parent then
                frame:Destroy()
            end
        end)
    end

    local section = UI.createSection(
        miscTab,
        "Arcane Odyssey",
        408
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
        "Wanted Criminal ESP",
        "Highlights NPCs marked Wanted Criminal.",
        "ArcaneWantedCriminalESP",
        80
    )

    UI.createToggle(
        section,
        "Structure Scan",
        "Scans bosses, chests, side quest NPCs/locations, templates and remotes.",
        "ArcaneBossDebug",
        132
    )

    local scanButton = Instance.new("TextButton")
    scanButton.Size = UDim2.new(1, -16, 0, 34)
    scanButton.Position = UDim2.fromOffset(8, 176)
    scanButton.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    scanButton.BorderSizePixel = 0
    scanButton.Text = "CHEST DEBUG v7"
    scanButton.TextColor3 = Color3.fromRGB(235, 235, 240)
    scanButton.Font = Enum.Font.GothamBold
    scanButton.TextSize = 10
    scanButton.Parent = section
    Instance.new("UICorner", scanButton).CornerRadius = UDim.new(0, 8)

    local copyButton = Instance.new("TextButton")
    copyButton.Size = UDim2.fromOffset(70, 24)
    copyButton.Position = UDim2.new(1, -78, 0, 239)
    copyButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    copyButton.BorderSizePixel = 0
    copyButton.Text = "COPY"
    copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    copyButton.Font = Enum.Font.GothamBold
    copyButton.TextSize = 9
    copyButton.Parent = section
    Instance.new("UICorner", copyButton).CornerRadius = UDim.new(0, 6)

    local debugBox = Instance.new("TextBox")
    debugBox.Position = UDim2.fromOffset(8, 267)
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
    local DEBUG_BOX_MAX_CHARS = 180000
    local DEBUG_BOX_HEAD_CHARS = 24000

    local function setDebugText(text)
        -- Keep the full report for the Copy button, but never assign more than
        -- Roblox TextBox's supported text length to the visible Text property.
        lastScanText = tostring(text)

        if #lastScanText <= DEBUG_BOX_MAX_CHARS then
            debugBox.Text = lastScanText
            return
        end

        local tailChars = DEBUG_BOX_MAX_CHARS - DEBUG_BOX_HEAD_CHARS - 180
        local head = string.sub(lastScanText, 1, DEBUG_BOX_HEAD_CHARS)
        local tail = string.sub(lastScanText, -tailChars)

        debugBox.Text = head
            .. "\n\n[DISPLAY SHORTENED: full report remains available with COPY]\n"
            .. "[Showing report start and end so the unloaded-island tree stays visible.]\n\n"
            .. tail
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
    statusLabel.Size = UDim2.new(1, -16, 0, 22)
    statusLabel.Position = UDim2.fromOffset(8, 212)
    statusLabel.TextWrapped = true
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "ESP: waiting for boss models..."
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 9
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = section

    
    local scanSelectedChests, scanAllWorkspaceChests

    -------------------------------------------------
    -- CHEST ESP / SCAN CONTROL UI
    -------------------------------------------------

    local chestSection = UI.createSection(
        miscTab,
        "Chest ESP",
        680
    )

    UI.createToggle(
        chestSection,
        "Chest ESP",
        "Highlights the selected chest types and shows their distance.",
        "ArcaneChestESP",
        34
    )

    local chestHeader = Instance.new("TextLabel")
    chestHeader.Size = UDim2.new(1, -20, 0, 28)
    chestHeader.Position = UDim2.fromOffset(10, 80)
    chestHeader.BackgroundTransparency = 1
    chestHeader.Text = "TREASURE CHESTS"
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
        local data = chestFilterButtons[chestType]
        if not data then return end
        local enabled = Config.ArcaneChestFilter[chestType] == true

        data.indicator.BackgroundColor3 = enabled
            and CHEST_COLORS[chestType]
            or Color3.fromRGB(48, 48, 58)
        data.check.Text = enabled and "✓" or ""
        data.text.TextColor3 = enabled
            and Color3.fromRGB(245, 245, 248)
            or Color3.fromRGB(135, 135, 145)
        data.button.BackgroundColor3 = enabled
            and Color3.fromRGB(39, 38, 39)
            or Color3.fromRGB(31, 31, 40)
    end

    local function createChestFilterButton(chestType, position, size)
        local card = Instance.new("TextButton")
        card.Size = size
        card.Position = position
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
            Config.ArcaneChestFilter[chestType] = not (Config.ArcaneChestFilter[chestType] == true)
            updateChestFilterButton(chestType)
            scanSelectedChests()
        end)
    end

    -- Treasure Chests use independent rarity/type filters.
    local TREASURE_CHEST_FILTERS = {
        "COMMON", "UNCOMMON", "RARE", "MYSTIC",
        "LEGENDARY", "PRIVATE_STORAGE", "SKY",
    }
    local gridStartY = 114
    local cardHeight = 40
    local cardGap = 6

    for index, chestType in ipairs(TREASURE_CHEST_FILTERS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        createChestFilterButton(
            chestType,
            UDim2.new(
                column * 0.5,
                column == 0 and 8 or 5,
                0,
                gridStartY + row * (cardHeight + cardGap)
            ),
            UDim2.new(0.5, -13, 0, cardHeight)
        )
    end

    local sealedHeader = Instance.new("TextLabel")
    sealedHeader.Size = UDim2.new(1, -20, 0, 18)
    sealedHeader.Position = UDim2.fromOffset(10, 302)
    sealedHeader.BackgroundTransparency = 1
    sealedHeader.Text = "SEALED CHESTS"
    sealedHeader.TextColor3 = Color3.fromRGB(220, 220, 230)
    sealedHeader.Font = Enum.Font.GothamBold
    sealedHeader.TextSize = 10
    sealedHeader.TextXAlignment = Enum.TextXAlignment.Left
    sealedHeader.Parent = chestSection

    -- Three subtype filters live under this single Sealed Chests group;
    -- the main Chest ESP toggle above is the only master ESP switch.
    local SEALED_CHEST_FILTERS = {
        "BRONZE_SEALED",
        "NIMBUS_SEALED",
        "DARK_SEALED",
    }
    local sealedGridStartY = 322
    for index, chestType in ipairs(SEALED_CHEST_FILTERS) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        createChestFilterButton(
            chestType,
            UDim2.new(
                column * 0.5,
                column == 0 and 8 or 5,
                0,
                sealedGridStartY + row * (cardHeight + cardGap)
            ),
            UDim2.new(0.5, -13, 0, cardHeight)
        )
    end

    local controlsY = 416

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

    -- Let the diagnostics/profile module restore saved category toggles and repaint this UI.
    Shared.refreshArcaneChestFilters = function()
        for _, chestType in ipairs(CHEST_TYPE_ORDER) do
            updateChestFilterButton(chestType)
        end
        scanSelectedChests()
    end

    local scanControlsTitle = Instance.new("TextLabel")
    scanControlsTitle.Size = UDim2.new(1, -20, 0, 24)
    scanControlsTitle.Position = UDim2.fromOffset(10, controlsY + 38)
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
        controlsY + 68
    )

    UI.createToggle(
        chestSection,
        "Scan Distance Limit",
        "When enabled, only chest locations inside the selected radius are processed/displayed.",
        "ArcaneChestScanDistanceLimitEnabled",
        controlsY + 114
    )

    local scanSlider = UI.createSlider(
        chestSection,
        "Scan Distance (1 - 100,000)",
        "ArcaneChestScanDistance",
        1,
        100000,
        10,
        controlsY + 160,
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
    scanHint.Position = UDim2.fromOffset(10, controlsY + 207)
    scanHint.BackgroundTransparency = 1
    scanHint.Text = "Tip: type a number in the slider box (example: 30000) instead of dragging."
    scanHint.TextColor3 = Color3.fromRGB(130, 130, 140)
    scanHint.Font = Enum.Font.Gotham
    scanHint.TextSize = 8
    scanHint.TextWrapped = true
    scanHint.TextXAlignment = Enum.TextXAlignment.Left
    scanHint.Parent = chestSection

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
    local wantedCriminalESPObjects = {}
    local wantedCriminalCandidates = setmetatable({}, {__mode = "k"})
    local wantedCriminalDetectionCache = setmetatable({}, {__mode = "k"})

    local chestESPObjects = {}
    local staticChestESPObjects = {}
    local staticChestLocationCache = {}
    local staticChestLocationsScanned = false
    local staticChestRootsScanned = setmetatable({}, {__mode = "k"})
    local chestCandidates = {}
    local openedChests = {}
    local openedChestLocations = {}
    local chestLifecycleWatchers = {}
    local chestTypeCache = setmetatable({}, {__mode = "k"})
    local staticChestAnchor = nil
    local isOpenedChestLocation


    local sideQuestESPObjects = {}
    local sideQuestCandidates = {}

    local getLocalPlayerRoot

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

    local function destroyWantedCriminalESP(model)
        local data = wantedCriminalESPObjects[model]

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

        wantedCriminalESPObjects[model] = nil
    end

    local function hasWantedCriminalText(value)
        local normalized = normalizeName(value)
        return normalized:find("wantedcriminal", 1, true) ~= nil
            or normalized:find("notoriouscriminal", 1, true) ~= nil
            or normalized:find("wantednpc", 1, true) ~= nil
            or normalized:find("bountynpc", 1, true) ~= nil
            or normalized:find("bountycriminal", 1, true) ~= nil
            or (normalized:find("wanted", 1, true) ~= nil
                and normalized:find("criminal", 1, true) ~= nil)
    end

    local function isWantedCriminalModel(model)
        if not model or not model.Parent or not model:IsA("Model") then
            return false
        end

        local now = os.clock()
        local cached = wantedCriminalDetectionCache[model]
        if cached then
            -- A negative check is much more expensive than reading the cached
            -- result. Recheck unknown NPCs every few seconds, while positive
            -- matches refresh sooner in case the game changes their status.
            local cacheWindow = cached.isWanted and 1 or 8
            if now - cached.checkedAt < cacheWindow then
                return cached.isWanted
            end
        end

        local function isTruthy(value)
            if value == true then
                return true
            end
            if type(value) == "number" then
                return value ~= 0
            end
            if type(value) == "string" then
                local normalized = normalizeName(value)
                return normalized == "true"
                    or normalized == "wanted"
                    or normalized == "criminal"
                    or normalized == "wantedcriminal"
                    or normalized == "notoriouscriminal"
            end
            return false
        end

        local wanted = hasWantedCriminalText(model.Name)
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid and hasWantedCriminalText(humanoid.DisplayName) then
            wanted = true
        end

        -- Read explicit game metadata from the model, rig parts, and value objects.
        -- Wanted NPCs have randomized names, so name matching alone is insufficient.
        local objectsToCheck = {model}
        local allModelText = {tostring(model.Name)}
        if humanoid then
            allModelText[#allModelText + 1] = tostring(humanoid.DisplayName)
        end

        for _, descendant in ipairs(model:GetDescendants()) do
            objectsToCheck[#objectsToCheck + 1] = descendant
            if descendant:IsA("TextLabel")
                or descendant:IsA("TextButton")
                or descendant:IsA("TextBox") then
                allModelText[#allModelText + 1] = tostring(descendant.Text)
            end
        end

        if not wanted and hasWantedCriminalText(table.concat(allModelText, " ")) then
            wanted = true
        end

        for _, object in ipairs(objectsToCheck) do
            if wanted then
                break
            end

            local normalizedObjectName = normalizeName(object.Name)
            local objectValue

            if object:IsA("BoolValue")
                or object:IsA("StringValue")
                or object:IsA("IntValue")
                or object:IsA("NumberValue") then
                objectValue = object.Value
            end

            if (normalizedObjectName == "wanted"
                or normalizedObjectName == "iswanted"
                or normalizedObjectName == "wantedcriminal"
                or normalizedObjectName == "iswantedcriminal"
                or normalizedObjectName == "criminal"
                or normalizedObjectName == "iscriminal"
                or normalizedObjectName == "notoriouscriminal")
                and isTruthy(objectValue) then
                wanted = true
                break
            end

            if objectValue ~= nil and hasWantedCriminalText(objectValue) then
                wanted = true
                break
            end

            if object:IsA("TextLabel")
                or object:IsA("TextButton")
                or object:IsA("TextBox") then
                if hasWantedCriminalText(object.Text) then
                    wanted = true
                    break
                end
            end

            local okAttributes, attributes = pcall(function()
                return object:GetAttributes()
            end)
            if okAttributes and type(attributes) == "table" then
                for key, value in pairs(attributes) do
                    local normalizedKey = normalizeName(key)
                    local metadataKey = normalizedKey:find("type", 1, true) ~= nil
                        or normalizedKey:find("status", 1, true) ~= nil
                        or normalizedKey:find("role", 1, true) ~= nil
                        or normalizedKey:find("faction", 1, true) ~= nil
                        or normalizedKey:find("alignment", 1, true) ~= nil
                    local metadataValue = normalizeName(value)

                    if hasWantedCriminalText(value)
                        or ((normalizedKey:find("wanted", 1, true) ~= nil
                            or normalizedKey:find("criminal", 1, true) ~= nil
                            or normalizedKey:find("bounty", 1, true) ~= nil)
                            and isTruthy(value))
                        or (metadataKey and (
                            metadataValue == "wanted"
                            or metadataValue == "criminal"
                            or metadataValue == "bounty"
                            or metadataValue == "bountyhunter"
                            or metadataValue == "wantednpc"
                            or metadataValue == "notorious"
                            or metadataValue == "villain"
                        )) then
                        wanted = true
                        break
                    end
                end
            end

            if not wanted and (object == model or object:IsA("Model")) then
                local okTags, tags = pcall(function()
                    return game:GetService("CollectionService"):GetTags(object)
                end)
                if okTags and type(tags) == "table" then
                    for _, tag in ipairs(tags) do
                        local normalizedTag = normalizeName(tag)
                        if hasWantedCriminalText(tag)
                            or normalizedTag == "wanted"
                            or normalizedTag == "criminal"
                            or normalizedTag == "bounty" then
                            wanted = true
                            break
                        end
                    end
                end
            end
        end

        -- Some overhead tags are parented to PlayerGui and point at the NPC via Adornee.
        -- Check those GUIs too; this avoids missing a wanted title outside the Model tree.
        if not wanted and Shared.playerGui then
            for _, gui in ipairs(Shared.playerGui:GetDescendants()) do
                if gui:IsA("BillboardGui") and gui.Adornee then
                    local adornee = gui.Adornee
                    local adorneeModel = adornee:IsA("Model")
                        and adornee
                        or adornee:FindFirstAncestorOfClass("Model")

                    if adorneeModel == model then
                        local parts = {}
                        for _, descendant in ipairs(gui:GetDescendants()) do
                            if descendant:IsA("TextLabel")
                                or descendant:IsA("TextButton")
                                or descendant:IsA("TextBox") then
                                parts[#parts + 1] = tostring(descendant.Text)
                            end
                        end
                        if hasWantedCriminalText(table.concat(parts, " ")) then
                            wanted = true
                            break
                        end
                    end
                end
            end
        end

        -- A spawned NPC can be grouped below a folder named for bounties/criminals.
        if not wanted then
            local parent = model.Parent
            while parent and parent ~= workspace do
                local parentName = normalizeName(parent.Name)
                if parentName:find("wantedcriminal", 1, true)
                    or parentName:find("wantednpc", 1, true)
                    or parentName:find("bountynpc", 1, true)
                    or parentName == "criminals" then
                    wanted = true
                    break
                end
                parent = parent.Parent
            end
        end

        wantedCriminalDetectionCache[model] = {
            isWanted = wanted,
            checkedAt = now,
        }

        return wanted
    end

    local function createWantedCriminalESP(model)
        if not Config.ArcaneWantedCriminalESP
            or not isWantedCriminalModel(model)
            or wantedCriminalESPObjects[model] then
            return
        end

        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = getRoot(model)
        if not humanoid or not root then
            return
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "SolarWantedCriminalESP"
        markSolarHubVisual(highlight)
        highlight.Adornee = model
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = Color3.fromRGB(210, 45, 78)
        highlight.OutlineColor = Color3.fromRGB(255, 105, 135)
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SolarWantedCriminalESPInfo"
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
        label.TextColor3 = Color3.fromRGB(255, 105, 135)
        label.TextStrokeTransparency = 0.2
        label.TextSize = 13
        label.TextWrapped = true
        label.Text = "WANTED CRIMINAL"
        label.Parent = billboard

        wantedCriminalESPObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
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
        chestStats.chestMarkersCreated = (chestStats.chestMarkersCreated or 0) + 1
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
        chestStats.chestMarkersCreated = (chestStats.chestMarkersCreated or 0) + 1
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
        for key, data in pairs(staticChestLocationCache) do
            if not Config.ArcaneChestESP
                or not hasAnyChestFilterEnabled(Config)
                or not isChestFilterEnabled(Config, data.chestType) then
                destroyStaticChestESP(key)
            elseif isChestWithinScanDistance(data.position) then
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
        local function scanRoot(scanRoot)
            if not scanRoot or staticChestRootsScanned[scanRoot] then
                return
            end

            local descendants = scanRoot:GetDescendants()

            for index, object in ipairs(descendants) do
                if index % 750 == 0 then
                    task.wait()
                end

                local normalizedObjectName = normalizeChestText(object.Name)
                local normalizedObjectShortName = normalizeName(object.Name)
                local isChestContainer = (object:IsA("Folder") or object:IsA("Model"))
                    and (
                        normalizedObjectShortName == "chests"
                        or normalizedObjectShortName == "tempchests"
                        or normalizedObjectShortName == "sealedchests"
                        or normalizedObjectShortName == "treasurechests"
                        or normalizedObjectShortName:find("chestcontainer", 1, true) ~= nil
                    )

                if isChestContainer then
                    for _, entry in ipairs(object:GetChildren()) do
                        if entry:IsA("Model") or entry:IsA("BasePart") then
                            local chestType = getChestTypeFast(entry)
                                or getChestType(entry)
                                or "OTHER"

                            cacheStaticChestLocation(entry, chestType)
                        end
                    end
                elseif (object:IsA("Model") or object:IsA("BasePart"))
                    and normalizedObjectName:find("sealed", 1, true) then
                    -- Cache named sealed models even when they are not inside
                    -- a conventional Chests/TempChests folder.
                    local chestType = getChestType(object)
                        or getChestTypeFast(object)
                        or "SEALED"
                    cacheStaticChestLocation(object, chestType)
                elseif object:IsA("Folder")
                    and normalizedObjectName:find("sealed", 1, true)
                    and normalizedObjectShortName ~= "sealedchests"
                    and not normalizedObjectShortName:find("chestcontainer", 1, true) then
                    -- Folder-backed sealed chests do not themselves provide a
                    -- world position; cache a concrete descendant instead.
                    local sealedTarget = getChestTarget(object)
                    if sealedTarget and (sealedTarget:IsA("Model") or sealedTarget:IsA("BasePart")) then
                        local chestType = getChestType(object)
                            or getChestType(sealedTarget)
                            or getChestTypeFast(sealedTarget)
                            or "SEALED"
                        cacheStaticChestLocation(sealedTarget, chestType)
                    end
                end
            end

            staticChestRootsScanned[scanRoot] = true
        end

        -- Workspace contains live chests. UnloadIslands and UnloadDarkSea can
        -- retain world-space chest placements for regions that are not loaded.
        local mapRoot = root or workspace:FindFirstChild("Map")
        local rs = game:GetService("ReplicatedStorage")
        local rsRoot = rs:FindFirstChild("RS")
        local unloadIslands = rsRoot and rsRoot:FindFirstChild("UnloadIslands")
        local unloadDarkSea = rsRoot and rsRoot:FindFirstChild("UnloadDarkSea")

        if not mapRoot and not unloadIslands and not unloadDarkSea then
            return
        end

        scanRoot(mapRoot)
        scanRoot(unloadIslands)
        scanRoot(unloadDarkSea)
        local function rootWasScannedOrMissing(scanRoot)
            return scanRoot == nil or staticChestRootsScanned[scanRoot] == true
        end
        staticChestLocationsScanned = rootWasScannedOrMissing(mapRoot)
            and rootWasScannedOrMissing(unloadIslands)
            and rootWasScannedOrMissing(unloadDarkSea)

        refreshStaticChestESP()
    end

    -- ReplicatedStorage can finish populating unloaded-island templates after
    -- the initial scan. Keep their static chest cache incremental instead of
    -- assuming each root is permanently complete after one GetDescendants pass.
    local function isStaticChestContainerName(value)
        local normalized = normalizeName(value)
        return normalized == "chests"
            or normalized == "tempchests"
            or normalized == "sealedchests"
            or normalized == "treasurechests"
            or normalized:find("chestcontainer", 1, true) ~= nil
    end

    local function findStaticChestEntry(instance, sourceRoot)
        local current = instance

        -- Most island templates place actual chest models directly under a
        -- Chests/TempChests/SealedChests folder or model. Walk up from the
        -- added descendant so late-added parts also resolve to their chest.
        while current and current ~= sourceRoot do
            local parent = current.Parent
            if (current:IsA("Model") or current:IsA("BasePart"))
                and parent
                and isStaticChestContainerName(parent.Name) then
                return current, parent
            end
            current = parent
        end

        -- Some sealed chests are stored outside the regular container folders.
        current = instance
        while current and current ~= sourceRoot do
            if (current:IsA("Model") or current:IsA("BasePart"))
                and normalizeChestText(current.Name):find("sealed", 1, true) then
                return current, nil
            end
            current = current.Parent
        end

        return nil, nil
    end

    local staticChestRefreshPending = false
    local function queueStaticChestESPRefresh()
        if staticChestRefreshPending then
            return
        end

        staticChestRefreshPending = true
        task.delay(0.2, function()
            staticChestRefreshPending = false
            if type(isArcaneSessionActive) == "function"
                and not isArcaneSessionActive() then
                return
            end
            refreshStaticChestESP()
        end)
    end

    local replicatedStorageForStaticChests = game:GetService("ReplicatedStorage")
    replicatedStorageForStaticChests.DescendantAdded:Connect(function(instance)
        task.defer(function()
            if not instance or not instance.Parent then
                return
            end

            local rsRoot = replicatedStorageForStaticChests:FindFirstChild("RS")
            local unloadIslands = rsRoot and rsRoot:FindFirstChild("UnloadIslands")
            local unloadDarkSea = rsRoot and rsRoot:FindFirstChild("UnloadDarkSea")

            local sourceRoot = nil
            if unloadIslands and instance:IsDescendantOf(unloadIslands) then
                sourceRoot = unloadIslands
            elseif unloadDarkSea and instance:IsDescendantOf(unloadDarkSea) then
                sourceRoot = unloadDarkSea
            else
                return
            end

            local entry, container = findStaticChestEntry(instance, sourceRoot)
            if not entry then
                return
            end

            -- A chest model may be parented before all its BaseParts arrive.
            -- Re-run position/type resolution on each relevant descendant
            -- addition; the position-keyed cache safely deduplicates repeats.
            local chestType = getChestTypeFast(entry) or getChestType(entry)
            if not chestType and container
                and normalizeName(container.Name) == "chests"
                and normalizeChestText(entry.Name):find("chest", 1, true) then
                chestType = "COMMON"
            end
            if not chestType
                and normalizeChestText(entry.Name):find("sealed", 1, true) then
                chestType = "SEALED"
            end

            cacheStaticChestLocation(entry, chestType or "OTHER")
            queueStaticChestESPRefresh()
        end)
    end)

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

    -- Only notify for live, classified Mystic/Legendary chests. Static cached
    -- island entries are deliberately excluded because they may be unloaded.
    if chestType == "MYSTIC" or chestType == "LEGENDARY" then
        showRareChestNotification(
            chest,
            chestType,
            chestRoot and chestRoot.Position or nil
        )
    end

    localChestTagObjects[chest] = true
    if not chestCandidates[chest] then
        chestStats.chestsDetected = (chestStats.chestsDetected or 0) + 1
    end
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

scanAllWorkspaceChests = function()
        chestStats.chestScans = (chestStats.chestScans or 0) + 1
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
            -- Retain static chest anchors for cached/unloaded island locations.
            scanStaticChestLocations(map)
        end

        -- Scan all live Workspace roots, not only Map. Sealed chests can be on
        -- defeated NPC ships and in underwater structures outside the Map tree.
        -- This is a one-shot, yielding discovery pass; later updates are event-driven.
        for index, object in ipairs(workspace:GetDescendants()) do
            if index % 500 == 0 then
                task.wait()
            end

            if object:IsA("ProximityPrompt")
                or object:IsA("ClickDetector") then
                inspectInteraction(object)

            elseif object:IsA("Model") then
                local normalized = normalizeName(object.Name)
                if normalized:find("chest", 1, true)
                    or normalized:find("buriedtreasure", 1, true)
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

    -- Filter changes refresh cached locations and re-inspect live chests.
    -- Guard against overlapping yielding workspace scans when users click quickly.
    local workspaceChestScanRunning = false
    scanSelectedChests = function()
        -- scanStaticChestLocations skips roots it has already scanned, but
        -- still discovers roots that appeared later (e.g. UnloadIslands).
        -- DescendantAdded above handles new entries inside previously seen roots.
        scanStaticChestLocations()

        -- Remove live markers whose category has just been turned off.
        for target, data in pairs(chestESPObjects) do
            local chestType = data.chestType or chestTypeCache[target] or getChestType(target)
            if not Config.ArcaneChestESP
                or not isChestFilterEnabled(Config, chestType) then
                destroyChestESP(target)
            end
        end

        if Config.ArcaneChestESP
            and hasAnyChestFilterEnabled(Config)
            and type(scanAllWorkspaceChests) == "function"
            and not workspaceChestScanRunning then
            workspaceChestScanRunning = true
            task.spawn(function()
                local function attemptScan(attempt)
                    if not isArcaneSessionActive() then
                        workspaceChestScanRunning = false
                        return
                    end

                    local ok, err = xpcall(scanAllWorkspaceChests, debug.traceback)
                    if ok then
                        workspaceChestScanRunning = false
                        return
                    end

                    chestStats.chestScanErrors = (chestStats.chestScanErrors or 0) + 1
                    warn("[SolarHub] Chest ESP scan failed (attempt "
                        .. tostring(attempt) .. "): " .. tostring(err))

                    if Config.SolarRecoveryEnabled ~= false and attempt < 3 then
                        chestStats.chestRecoveries = (chestStats.chestRecoveries or 0) + 1
                        task.delay(0.35 * attempt, function()
                            attemptScan(attempt + 1)
                        end)
                    else
                        workspaceChestScanRunning = false
                    end
                end
                attemptScan(1)
            end)
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
                or normalized:find("buriedtreasure", 1, true)
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
        destroyWantedCriminalESP(model)
        wantedCriminalDetectionCache[model] = nil

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

        if Config.ArcaneWantedCriminalESP then
            wantedCriminalCandidates[model] = true
            createWantedCriminalESP(model)
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
    local lastWantedCriminalESPEnabled = Config.ArcaneWantedCriminalESP == true
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
            local loopStep = Config.SolarPerformanceMode == true and 0.75 or 0.25
            task.wait(loopStep)

            local wantedCriminalEnabled = Config.ArcaneWantedCriminalESP == true
            if wantedCriminalEnabled and not lastWantedCriminalESPEnabled then
                -- Perform one yielding full-world pass when the user enables the
                -- feature. Bounty NPCs can live outside Workspace.NPCs/Enemies.
                task.spawn(function()
                    local ok, err = xpcall(function()
                        local descendants = workspace:GetDescendants()
                        for index, instance in ipairs(descendants) do
                            if not isArcaneSessionActive() then
                                break
                            end

                            if instance:IsA("Model")
                                and instance:FindFirstChildOfClass("Humanoid") then
                                wantedCriminalCandidates[instance] = true
                                createWantedCriminalESP(instance)
                            end

                            if index % 350 == 0 then
                                task.wait()
                            end
                        end
                    end, debug.traceback)

                    if not ok then
                        warn("[SolarHub] Wanted Criminal scan failed: " .. tostring(err))
                    end
                end)
            elseif not wantedCriminalEnabled and lastWantedCriminalESPEnabled then
                for model in pairs(wantedCriminalESPObjects) do
                    destroyWantedCriminalESP(model)
                end
                table.clear(wantedCriminalCandidates)
                table.clear(wantedCriminalDetectionCache)
            end
            lastWantedCriminalESPEnabled = wantedCriminalEnabled

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

            targetedScanAccumulator += loopStep
            chestScanAccumulator += loopStep

            local targetedScanInterval = Config.SolarPerformanceMode == true and 3 or 1.5
            if targetedScanAccumulator >= targetedScanInterval then
                targetedScanAccumulator = 0

                if Config.ArcaneBossESP
                    or Config.ArcaneWantedCriminalESP
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

            local wantedCriminalDetected = 0

            if Config.ArcaneWantedCriminalESP then
                for model in pairs(wantedCriminalCandidates) do
                    if not model.Parent then
                        wantedCriminalCandidates[model] = nil
                        wantedCriminalDetectionCache[model] = nil
                        destroyWantedCriminalESP(model)
                    else
                        -- Retry unknown/late-added titles without rescanning the
                        -- whole Workspace every frame.
                        createWantedCriminalESP(model)
                    end
                end

                for model in pairs(wantedCriminalESPObjects) do
                    if model.Parent then
                        wantedCriminalDetected += 1
                    else
                        destroyWantedCriminalESP(model)
                    end
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

            statusLabel.Text = ("Boss: %d | Wanted: %d | Chests: %d | Side NPC: %d"):format(
                detected,
                wantedCriminalDetected,
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
            task.wait(0.25)

            if Config.ArcaneWantedCriminalESP then
                local character = Shared.player.Character
                local playerRoot = character
                    and character:FindFirstChild("HumanoidRootPart")

                for model, data in pairs(wantedCriminalESPObjects) do
                    if not model.Parent then
                        destroyWantedCriminalESP(model)
                    elseif not isWantedCriminalModel(model) then
                        destroyWantedCriminalESP(model)
                    else
                        local root = getRoot(model)
                        local humanoid = model:FindFirstChildOfClass("Humanoid")

                        if not root or not humanoid or humanoid.Health <= 0 then
                            destroyWantedCriminalESP(model)
                        else
                            local distanceText = "STUDS: ?"

                            if playerRoot then
                                distanceText = ("STUDS: %d"):format(
                                    math.floor((playerRoot.Position - root.Position).Magnitude)
                                )
                            end

                            data.label.Text = string.format(
                                "WANTED CRIMINAL\n%s\nHP: %d/%d | %s",
                                tostring(humanoid.DisplayName ~= "" and humanoid.DisplayName or model.Name),
                                math.floor(math.max(0, humanoid.Health)),
                                math.floor(math.max(0, humanoid.MaxHealth)),
                                distanceText
                            )
                        end
                    end
                end
            else
                for model in pairs(wantedCriminalESPObjects) do
                    destroyWantedCriminalESP(model)
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

        for model in pairs(wantedCriminalESPObjects) do
            destroyWantedCriminalESP(model)
        end
        table.clear(wantedCriminalCandidates)
        table.clear(wantedCriminalDetectionCache)

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

        table.clear(rareChestNotified)

    end

    Context.registerCleanup(cleanupArcaneSession)

    return true
end

return ArcaneMisc