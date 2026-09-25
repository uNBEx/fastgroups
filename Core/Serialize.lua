-- Export strings: "!FG1!" .. Base64(Deflate(CBOR(payload))).
local _, ns = ...

local Serialize = {}
ns.Serialize = Serialize

Serialize.PREFIX = "!FG1!"
local MAX_INPUT = 200000

local function deflate() return (Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate) or 0 end

function Serialize.Encode(payload)
    local cbor = C_EncodingUtil.SerializeCBOR(payload)
    local packed = C_EncodingUtil.CompressString(cbor, deflate())
    return Serialize.PREFIX .. C_EncodingUtil.EncodeBase64(packed)
end

-- Returns payload or nil, error message.
function Serialize.Decode(str)
    if type(str) ~= "string" then return nil, "No text." end
    if #str > MAX_INPUT then return nil, "The text is too long." end
    str = str:gsub("%s+", "")
    if str:sub(1, #Serialize.PREFIX) ~= Serialize.PREFIX then
        return nil, "Not a FastGroups string (it should start with " .. Serialize.PREFIX .. ")."
    end
    local body = str:sub(#Serialize.PREFIX + 1)
    local ok, packed = pcall(C_EncodingUtil.DecodeBase64, body)
    if not ok or not packed or packed == "" then return nil, "The string is damaged (base64)." end
    local ok2, cbor = pcall(C_EncodingUtil.DecompressString, packed, deflate())
    if not ok2 or not cbor then return nil, "The string is damaged (compression)." end
    local ok3, payload = pcall(C_EncodingUtil.DeserializeCBOR, cbor)
    if not ok3 or type(payload) ~= "table" then return nil, "The string is damaged (data)." end
    if payload.v ~= 1 then return nil, "Made by a newer FastGroups version." end
    return payload
end

-- Settings that may travel with an export (never window position etc.).
local SHARED_SETTINGS = { "accent", "cardStyle", "showSpec", "conv", "halfNames", "groupsMode", "arrangeByHalf", "sortMode" }

function Serialize.BuildPayload(loadouts, includeSettings)
    local payload = { v = 1, l = {} }
    for _, lo in ipairs(loadouts) do
        tinsert(payload.l, ns.Loadouts.ToExport(lo))
    end
    if includeSettings then
        payload.s = {}
        for _, k in ipairs(SHARED_SETTINGS) do payload.s[k] = ns.CopyTable(ns.settings[k]) end
    end
    return payload
end

-- Validate a decoded payload. Returns { loadouts = {...}, settings = table|nil }.
function Serialize.ReadPayload(payload)
    local out = { loadouts = {} }
    if type(payload.l) == "table" then
        for i = 1, math.min(#payload.l, 100) do
            local lo = ns.Loadouts.FromExport(payload.l[i])
            if lo then tinsert(out.loadouts, lo) end
        end
    end
    if type(payload.s) == "table" then
        local s = {}
        local d = ns.defaults.settings
        for _, k in ipairs(SHARED_SETTINGS) do
            local v = payload.s[k]
            if type(v) == type(d[k]) then s[k] = v end
        end
        if type(s.accent) == "table" then
            local a = s.accent
            if type(a[1]) ~= "number" or type(a[2]) ~= "number" or type(a[3]) ~= "number" then s.accent = nil end
        end
        if s.conv ~= nil and s.conv ~= "oddeven" and s.conv ~= "split" then s.conv = nil end
        if s.cardStyle ~= nil and s.cardStyle ~= "filled" and s.cardStyle ~= "subtle" then s.cardStyle = nil end
        if s.sortMode ~= nil and s.sortMode ~= "role" and s.sortMode ~= "class" then s.sortMode = nil end
        if type(s.halfNames) == "table" then
            if type(s.halfNames.L) ~= "string" or type(s.halfNames.R) ~= "string" then s.halfNames = nil end
        end
        local gm = payload.s.groupsMode
        if gm == "auto" or gm == 4 or gm == 6 then s.groupsMode = gm else s.groupsMode = nil end
        out.settings = s
    end
    return out
end

function Serialize.ApplySettings(s)
    for k, v in pairs(s) do ns.settings[k] = ns.CopyTable(v) end
    ns.Fire("SETTINGS_CHANGED")
end
