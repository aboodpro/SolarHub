-- RemoteCapture.lua
-- Temporary helper for converting SolarHub automation from game UI clicks to direct remotes.
-- Run this script, perform ONE game action manually within the capture window,
-- then paste the clipboard contents back into chat.

local CAPTURE_SECONDS = 8

local records = {}
local seen = {}
local started = os.clock()

local function simpleValue(v, depth)
    depth = depth or 0
    if depth > 2 then
        return "<table>"
    end

    local t = typeof(v)

    if t == "Instance" then
        return v:GetFullName()
    elseif t == "CFrame" then
        return string.format("CFrame.new(%s)",
            table.concat({v:GetComponents()}, ", "))
    elseif t == "Vector3" then
        return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)",
            math.floor(v.R * 255 + 0.5),
            math.floor(v.G * 255 + 0.5),
            math.floor(v.B * 255 + 0.5))
    elseif t == "boolean" or t == "number" or t == "string" or t == "nil" then
        return v
    elseif t == "table" then
        local out = {}
        local count = 0
        for k, x in pairs(v) do
            count = count + 1
            if count > 40 then
                out["..."] = "<truncated>"
                break
            end
            out[k] = simpleValue(x, depth + 1)
        end
        return out
    end

    return "<" .. t .. ">"
end

local function encodeValue(v)
    local ok, result = pcall(function()
        return game:GetService("HttpService"):JSONEncode(simpleValue(v))
    end)

    if ok then
        return result
    end

    return tostring(v)
end

local function addRecord(self, method, args)
    local path = "?"
    pcall(function()
        path = self:GetFullName()
    end)

    local values = {}
    local parts = {}

    for i = 1, args.n or #args do
        values[i] = simpleValue(args[i])
        parts[i] = encodeValue(args[i])
    end

    local signature = path .. "|" .. method .. "|" .. table.concat(parts, "|")

    -- Deduplicate identical spam calls during the capture window.
    if seen[signature] then
        return
    end

    seen[signature] = true

    table.insert(records, {
        remotePath = path,
        remoteName = self.Name,
        remoteClass = self.ClassName,
        method = method,
        args = values,
    })
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()

    if not checkcaller()
        and (method == "FireServer" or method == "InvokeServer")
        and os.clock() - started <= CAPTURE_SECONDS then

        local lower = tostring(self.Name):lower()

        -- Ignore obvious high-frequency noise.
        if not lower:find("chat")
            and not lower:find("ping")
            and not lower:find("analytics")
            and not lower:find("camera")
            and not lower:find("mouse") then

            pcall(function()
                addRecord(self, method, table.pack(...))
            end)
        end
    end

    return oldNamecall(self, ...)
end)

print("========================================")
print("[RemoteCapture] READY")
print("[RemoteCapture] Perform ONE game action now.")
print("[RemoteCapture] Capture duration: " .. CAPTURE_SECONDS .. " seconds")
print("========================================")

task.wait(CAPTURE_SECONDS)

local lines = {}
table.insert(lines, "-- ===== CAPTURED REMOTES =====")
table.insert(lines, "-- Records: " .. tostring(#records))
table.insert(lines, "")

for index, record in ipairs(records) do
    table.insert(lines, "-- [" .. index .. "] " .. record.method .. " " .. record.remotePath)
    table.insert(lines, "local args = {}")

    for argIndex = 1, #record.args do
        local value = record.args[argIndex]
        local encoded = game:GetService("HttpService"):JSONEncode(value)
        table.insert(lines, "args[" .. argIndex .. "] = " .. encoded)
    end

    table.insert(lines, "")
    table.insert(lines, "-- Remote class: " .. tostring(record.remoteClass))
    table.insert(lines, "-- Remote name: " .. tostring(record.remoteName))
    table.insert(lines, "")
end

if #records == 0 then
    table.insert(lines, "-- NO REMOTE CALLS CAPTURED")
end

local output = table.concat(lines, "\n")

local copied = false
if setclipboard then
    copied = pcall(function()
        setclipboard(output)
    end)
elseif toclipboard then
    copied = pcall(function()
        toclipboard(output)
    end)
end

print("========================================")
print("[RemoteCapture] DONE")
print("[RemoteCapture] Records: " .. tostring(#records))
print("[RemoteCapture] Clipboard copied: " .. tostring(copied))
print("========================================")
