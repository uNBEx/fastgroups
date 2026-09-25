-- Minimal WoW API stub so the Core modules can load and run under plain Lua 5.1.
local stub = {}

stub.sent = {}          -- addon messages sent: { prefix, msg, chatType, target }
stub.inRaid = false
stub.time = 1700000000

local function noop() end

-- string / table helpers WoW provides as globals
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
strupper = string.upper
tinsert = table.insert
tremove = table.remove
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function time() return stub.time end
math.randomseed(42)

-- frames: only the event frame in Init.lua is created at load time
stub.frames = {}
function CreateFrame()
    local f = { events = {}, scripts = {} }
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    table.insert(stub.frames, f)
    return f
end

function stub.fire(event, ...)
    for _, f in ipairs(stub.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) stub.lastPrint = msg end }
GameTooltip = { SetOwner = noop, AddLine = noop, Show = noop, Hide = noop }
SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, a, b, data) stub.popup = { which = which, a = a, b = b, data = data } end
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
stub.timers = {}        -- pending C_Timer.After callbacks: { delay, fn }
C_Timer = { After = function(delay, fn) table.insert(stub.timers, { delay, fn }) end }
-- run the timers queued so far (not the ones they queue)
function stub.runTimers()
    local list = stub.timers
    stub.timers = {}
    for _, t in ipairs(list) do t[2]() end
end
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
LOCALIZED_CLASS_NAMES_MALE = {}
MAX_RAID_MEMBERS = 40
Enum = { CompressionMethod = { Deflate = 0 } }

function GetSpecializationInfoByID(id) return id, "Spec" .. id, "", 12345, "DAMAGER" end
function GetNormalizedRealmName() return "Silvermoon" end
function GetRealmName() return "Silvermoon" end
function UnitName() return "Tester" end
function IsInRaid() return stub.inRaid end
function IsInGuild() return true end
function IsInGroup(category) return stub.inRaid and category ~= 2 end
stub.inspected = {}     -- units passed to NotifyInspect
function NotifyInspect(u) table.insert(stub.inspected, u) end
function ClearInspectPlayer() end
function CanInspect() return true end
function UnitIsConnected() return true end
function UnitIsVisible(u) return not (stub.farAway and stub.farAway[u]) end
function UnitGUID(u) return "GUID-" .. tostring(u) end
function InCombatLockdown() return false end
function UnitIsGroupLeader() return true end
function UnitIsGroupAssistant() return false end
function IsEveryoneAssistant() return false end
function HasLFGRestrictions() return false end
stub.uninvited = {}     -- names passed to UninviteUnit
C_PartyInfo = {
    UninviteUnit = function(name) table.insert(stub.uninvited, name) end,
    PromoteToLeader = function(name) stub.promoted = { name, 2 } end,
    PromoteToAssistant = function(name) stub.promoted = { name, 1 } end,
    DemoteAssistant = function(name) stub.promoted = { name, 0 } end,
}
function UnitAffectingCombat() return false end
function UnitIsUnit(a, b) return a == b end
function UnitGroupRolesAssigned() return "NONE" end
function GetInstanceInfo() return "Test", "none", 0 end
function GetRaidDifficultyID() return 14 end
function GetRaidRosterInfo() return nil end
function GetNumGuildMembers() return 0 end

C_SpecializationInfo = {
    GetSpecialization = function() return nil end,
    GetSpecializationInfo = function() return nil end,
    GetInspectSpecialization = function() return 0 end,
}

stub.chat = {}          -- chat lines sent: { msg, chatType }
C_ChatInfo = {
    RegisterAddonMessagePrefix = noop,
    SendChatMessage = function(msg, chatType) table.insert(stub.chat, { msg, chatType }) end,
    InChatMessagingLockdown = function() return false end,
    SendAddonMessage = function(prefix, msg, chatType, target)
        table.insert(stub.sent, { prefix, msg, chatType, target })
        return 0
    end,
}

-- Encoding: a readable serializer, identity compression and real base64.
local function ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(val) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64enc(data)
    return ((data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return B64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end
local function b64dec(data)
    data = data:gsub("[^" .. B64 .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (B64:find(x, 1, true) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

C_EncodingUtil = {
    SerializeCBOR = function(v) return ser(v) end,
    DeserializeCBOR = function(s)
        local fn = loadstring("return " .. s)
        if not fn then error("bad data") end
        setfenv(fn, {})
        return fn()
    end,
    CompressString = function(s) return "Z" .. s end,
    DecompressString = function(s)
        if s:sub(1, 1) ~= "Z" then error("bad stream") end
        return s:sub(2)
    end,
    EncodeBase64 = b64enc,
    DecodeBase64 = b64dec,
}

return stub
