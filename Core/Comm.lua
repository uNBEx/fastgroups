-- In-game sharing over the hidden addon channel.
--[[ Protocol (fields separated by TAB):
  O id chunks summary   offer (RAID / GUILD broadcast or WHISPER)
  A id                  accept, whispered to the sender
  D id                  decline
  C id seq data         one chunk, whispered to each accepting player
  The data is an export string (see Core/Serialize.lua), split in chunks.
]]
local _, ns = ...

local Comm = {
    registered = false,
    listening = false,
    outgoing = {},   -- id -> { data, chunks, created, summary }
    inbox = {},      -- sender .. id -> { total, parts, got, sender }
}
ns.Comm = Comm

Comm.PREFIX = "FastGroups"
local CHUNK = 230
local MAX_CHUNKS = 400
local MAX_OUTGOING = 5
local SEP = "\t"

local RESULT_OK = 0
local RESULT_THROTTLE = { [3] = true, [8] = true }

---------------------------------------------------------------------------
-- Pure helpers (tested)
---------------------------------------------------------------------------
function Comm.Chunk(str, size)
    local out = {}
    size = size or CHUNK
    for i = 1, #str, size do
        out[#out + 1] = str:sub(i, i + size - 1)
    end
    return out
end

function Comm.Split(msg)
    local parts = {}
    local start = 1
    while true do
        local i = msg:find(SEP, start, true)
        if not i then
            parts[#parts + 1] = msg:sub(start)
            break
        end
        parts[#parts + 1] = msg:sub(start, i - 1)
        start = i + 1
        if #parts == 3 then
            parts[4] = msg:sub(start)
            break
        end
    end
    return parts
end

---------------------------------------------------------------------------
-- Send queue. Blizzard throttles each prefix; when it says so we wait a
-- second and continue. Only runs while there is something to send.
---------------------------------------------------------------------------
local queue = {}
local pumping = false

local function pump()
    pumping = false
    while #queue > 0 do
        local q = queue[1]
        local res = C_ChatInfo.SendAddonMessage(Comm.PREFIX, q[1], q[2], q[3])
        if res == true then res = RESULT_OK end
        if RESULT_THROTTLE[res] then
            pumping = true
            C_Timer.After(1, pump)
            return
        end
        tremove(queue, 1)
        if res ~= RESULT_OK and res ~= nil and q.onError then q.onError(res) end
    end
end

local function send(msg, chatType, target, onError)
    tinsert(queue, { msg, chatType, target, onError = onError })
    if not pumping then pump() end
end

local function ensurePrefix()
    if not Comm.registered then
        C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
        Comm.registered = true
    end
end

function Comm.Locked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function myName()
    return ns.Players.Key(UnitName("player"))
end

local function sanitize(s)
    return (tostring(s or ""):gsub("[%c]", " "):sub(1, 120))
end

-- channel: "RAID" | "GUILD" | "WHISPER". Returns ok, error.
function Comm.Offer(channel, target, data, summary)
    if Comm.Locked() then
        return false, "Addon messages are blocked right now (boss encounter or Mythic+)."
    end
    if channel == "RAID" and not IsInRaid() then return false, "You are not in a raid." end
    if channel == "GUILD" and not IsInGuild() then return false, "You are not in a guild." end
    if channel == "WHISPER" then
        target = ns.Players.Key(strtrim(target or ""))
        if not target then return false, "Enter a player name." end
    end
    ensurePrefix()
    Comm.Listen(true)
    local id = string.format("%04x", math.random(0, 65535))
    local chunks = Comm.Chunk(data)
    if #chunks > MAX_CHUNKS then return false, "Too much data for one transfer." end
    Comm.outgoing[id] = { chunks = chunks, created = time(), summary = summary }
    -- keep only the last few offers
    local n, oldestId, oldest = 0, nil, nil
    for oid, o in pairs(Comm.outgoing) do
        n = n + 1
        if not oldest or o.created < oldest then oldestId, oldest = oid, o.created end
    end
    if n > MAX_OUTGOING and oldestId then Comm.outgoing[oldestId] = nil end
    send(table.concat({ "O", id, #chunks, sanitize(summary) }, SEP), channel, target, function()
        ns.Fire("COMM_STATUS", "error", "Could not send the offer.")
    end)
    return true
end

local function sendChunks(id, to)
    local o = Comm.outgoing[id]
    if not o then return end
    for i, part in ipairs(o.chunks) do
        send(table.concat({ "C", id, i, part }, SEP), "WHISPER", to)
    end
    ns.Fire("COMM_STATUS", "sent", to, o.summary)
end

---------------------------------------------------------------------------
-- Receiving. CHAT_MSG_ADDON is registered while sharing is not set to
-- "Ignore" (see Listen).
---------------------------------------------------------------------------
local function acceptOffer(sender, id, total)
    Comm.inbox[sender .. id] = { total = total, parts = {}, got = 0, sender = sender }
    send(table.concat({ "A", id }, SEP), "WHISPER", sender)
    ns.Fire("COMM_STATUS", "receiving", sender)
end

local function declineOffer(sender, id)
    send(table.concat({ "D", id }, SEP), "WHISPER", sender)
end

local function isTrusted(sender)
    if ns.db.trusted[sender] then return true end
    if ns.settings.acceptFrom == "leader" then
        local short = ns.Players.ShortName(sender)
        return UnitIsGroupLeader(sender) or UnitIsGroupLeader(short)
    end
    return false
end

local popupReady = false
local function ensurePopup()
    if popupReady then return end
    popupReady = true
    StaticPopupDialogs.FASTGROUPS_OFFER = {
        text = "FastGroups: %s wants to send you %s.",
        button1 = ACCEPT or "Accept",
        button2 = DECLINE or "Decline",
        button3 = "Always accept",
        OnAccept = function(_, data) acceptOffer(data.sender, data.id, data.total) end,
        OnCancel = function(_, data, reason)
            if reason == "clicked" then declineOffer(data.sender, data.id) end
        end,
        OnAlt = function(_, data)
            ns.db.trusted[data.sender] = true
            acceptOffer(data.sender, data.id, data.total)
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function finishIncoming(entry)
    local data = table.concat(entry.parts)
    local payload, err = ns.Serialize.Decode(data)
    if not payload then
        ns.Fire("COMM_STATUS", "error", err)
        return
    end
    local read = ns.Serialize.ReadPayload(payload)
    local added = ns.Loadouts.Import(read.loadouts)
    ns.Fire("COMM_STATUS", "received", entry.sender, #added)
end

function Comm.OnMessage(prefix, text, _, sender)
    if prefix ~= Comm.PREFIX or not sender then return end
    sender = ns.Players.Key(sender)
    if sender == myName() then return end
    local p = Comm.Split(text)
    local kind, id = p[1], p[2]
    if not id or #id ~= 4 then return end
    if kind == "O" then
        if ns.settings.acceptFrom == "never" then return end
        local total = tonumber(p[3])
        if not total or total < 1 or total > MAX_CHUNKS then return end
        if Comm.inbox[sender .. id] then return end
        if isTrusted(sender) then
            acceptOffer(sender, id, total)
        else
            ensurePopup()
            local who = ns.Players.DisplayName(sender)
            StaticPopup_Show("FASTGROUPS_OFFER", who, p[4] or "a loadout",
                { sender = sender, id = id, total = total })
        end
    elseif kind == "A" then
        sendChunks(id, sender)
    elseif kind == "D" then
        ns.Fire("COMM_STATUS", "declined", sender)
    elseif kind == "C" then
        local entry = Comm.inbox[sender .. id]
        local seq = tonumber(p[3])
        if not entry or not seq or seq < 1 or seq > entry.total or entry.parts[seq] then return end
        entry.parts[seq] = p[4] or ""
        entry.got = entry.got + 1
        if entry.got == entry.total then
            Comm.inbox[sender .. id] = nil
            finishIncoming(entry)
        end
    end
end

local function onAddonMessage(_, _, ...) Comm.OnMessage(...) end

-- Listen for offers unless the user chose to ignore them.
function Comm.Listen(on)
    on = on and true or false
    if on == Comm.listening then return end
    Comm.listening = on
    if on then
        ensurePrefix()
        ns.RegisterEvent(Comm, "CHAT_MSG_ADDON", onAddonMessage)
    else
        ns.UnregisterEvent(Comm, "CHAT_MSG_ADDON")
    end
end

ns.On("LOGIN", Comm, function()
    Comm.Listen(ns.settings.acceptFrom ~= "never")
end)
