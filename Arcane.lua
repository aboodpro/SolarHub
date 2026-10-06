--!strict
local Arcane = {}

function Arcane.Init(Shared, UI, Modules)
    if type(Modules) ~= "table" then
        error("[Arcane] Feature modules are missing.")
    end

    local arcaneSessionId =
        tostring(os.clock()) .. "_" .. tostring(math.random(100000000, 999999999))
    local arcaneSessionActive = true
    local cleanups = {}

    if type(getgenv) == "function" then
        local env = getgenv()
        local previousCleanup = env.SolarHubArcaneCleanup

        if type(previousCleanup) == "function" then
            pcall(previousCleanup)
        end

        env.SolarHubArcaneSession = arcaneSessionId
    end

    local function isSessionActive()
        if not arcaneSessionActive then
            return false
        end

        if type(getgenv) ~= "function" then
            return true
        end

        return getgenv().SolarHubArcaneSession == arcaneSessionId
    end

    local function registerCleanup(fn)
        if type(fn) == "function" then
            table.insert(cleanups, fn)
        end
    end

    local function cleanupArcane()
        if not arcaneSessionActive then
            return
        end

        arcaneSessionActive = false

        for index = #cleanups, 1, -1 do
            pcall(cleanups[index])
        end

        table.clear(cleanups)

        if type(getgenv) == "function" then
            local env = getgenv()

            if env.SolarHubArcaneSession == arcaneSessionId then
                env.SolarHubArcaneSession = nil
            end

            if env.SolarHubArcaneCleanup == cleanupArcane then
                env.SolarHubArcaneCleanup = nil
            end
        end
    end

    local Context = {
        sessionId = arcaneSessionId,
        isSessionActive = isSessionActive,
        registerCleanup = registerCleanup,
    }

    if type(getgenv) == "function" then
        getgenv().SolarHubArcaneCleanup = cleanupArcane
    end

    if not Modules.Misc or type(Modules.Misc.Init) ~= "function" then
        cleanupArcane()
        error("[Arcane] ArcaneMisc module is missing or invalid.")
    end

    if not Modules.Farming or type(Modules.Farming.Init) ~= "function" then
        cleanupArcane()
        error("[Arcane] ArcaneFarming module is missing or invalid.")
    end

    Modules.Misc.Init(Shared, UI, Context)
    Modules.Farming.Init(Shared, UI, Context)

    return true
end

return Arcane
