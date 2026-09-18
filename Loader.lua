--!strict
-- Loader.lua - paste ONLY this file's content (or better, host it and use
-- loadstring(game:HttpGet("https://yourdomain.com/loader.lua"))() ) in your
-- Executor. It fetches every module and wires them together.

-- ⚠️ EDIT THIS to wherever you host the other 5 files (raw text URLs).
-- Example if using GitHub raw:
--   https://raw.githubusercontent.com/YourUsername/YourRepo/main/
local BASE_URL = "https://nousigi.com/"

local function fetch(fileName)
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(BASE_URL .. fileName))()
    end)
    if not ok then
        warn("[Loader] FAILED to load " .. fileName .. ": " .. tostring(result))
        error("[Loader] Stopping - " .. fileName .. " could not be loaded.")
    end
    return result
end

print("[Loader] Fetching Shared.lua...")
local Shared = fetch("Shared.lua")

print("[Loader] Fetching UI.lua...")
local UIModule = fetch("UI.lua")
local UI = UIModule.Init(Shared)

print("[Loader] Fetching Joiner.lua...")
local JoinerModule = fetch("Joiner.lua")
JoinerModule.Init(Shared, UI)

print("[Loader] Fetching Macro.lua...")
local MacroModule = fetch("Macro.lua")
MacroModule.Init(Shared, UI)

print("[Loader] Fetching Webhook.lua...")
local WebhookModule = fetch("Webhook.lua")
WebhookModule.Init(Shared, UI)

print("☀️ Solar Hub loaded successfully (modular edition)!")
