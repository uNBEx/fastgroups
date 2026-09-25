-- Specs broadcast by LibSpecialization, which BigWigs and other addons embed.
-- Its users announce their spec on the "LibSpec" prefix when anyone in the
-- group asks ("R", sent by the library on login and on joining a group) and
-- whenever they change spec or talents. The library keeps no cache, so we
-- listen from login while spec detection is on, and changes made while the
-- window is closed are not missed. We send one request per group ourselves,
-- only when no loaded copy of the library does it for us. Players without
-- the library are left to the inspect queue.
local _, ns = ...

local Data, Players = ns.Data, ns.Players

local PREFIX = "LibSpec"
local CHANNELS = { RAID = true, INSTANCE_CHAT = true }

local SpecComm = {
    enabled = false,
    registered = false,
    requested = false,   -- asked this group already
}
ns.SpecComm = SpecComm

-- "<specID>,<talent string>"; a bare "R" is a request.
function SpecComm.OnMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not CHANNELS[channel] or not IsInRaid() then return end
    local specID = tonumber(msg:match("^(%d+),"))
    if not specID or not Data.SPECS[specID] then return end
    local key = Players.Key(sender)
    if key and Players.Confirm(key, specID, "comm") then
        ns.Fire("PLAYER_INFO_CHANGED", key)
    end
end

local function onAddonMessage(_, _, ...) SpecComm.OnMessage(...) end

local function onGroupFormed() SpecComm.requested = false end

function SpecComm.SetEnabled(on)
    on = on and true or false
    if on == SpecComm.enabled then return end
    SpecComm.enabled = on
    if on then
        if not SpecComm.registered then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
            SpecComm.registered = true
        end
        ns.RegisterEvent(SpecComm, "CHAT_MSG_ADDON", onAddonMessage)
        ns.RegisterEvent(SpecComm, "GROUP_FORMED", onGroupFormed)
    else
        ns.UnregisterEvent(SpecComm, "CHAT_MSG_ADDON")
        ns.UnregisterEvent(SpecComm, "GROUP_FORMED")
    end
end

-- Ask the raid once per group, so specs announced before we started
-- listening (login, /reload) are heard again.
function SpecComm.Request()
    if not SpecComm.enabled or SpecComm.requested or not IsInRaid() then return end
    if LibStub and LibStub("LibSpecialization", true) then
        SpecComm.requested = true   -- the loaded library asks on its own
        return
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    SpecComm.requested = true
    if IsInGroup(2) then C_ChatInfo.SendAddonMessage(PREFIX, "R", "INSTANCE_CHAT") end
    if IsInGroup(1) then C_ChatInfo.SendAddonMessage(PREFIX, "R", "RAID") end
end

ns.On("LOGIN", SpecComm, function()
    SpecComm.SetEnabled(ns.settings.autoInspect)
end)
