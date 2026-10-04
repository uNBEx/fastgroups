-- Invite a list of players (a planning roster, or a loadout's absent players).
-- In a raid everyone goes out at once. A party is turned into a raid first;
-- solo, 4 invites go out and the party becomes a raid when the first one
-- joins, then the rest follow. Roster and combat events are only registered
-- while waiting for that raid. No timer: a run nobody answers waits until it
-- is cancelled or started again.
local _, ns = ...

local Players = ns.Players

local Invite = {
    running = false,
    queue = {},         -- keys still to invite once we lead a raid
    grouped = false,    -- the party formed (so its end stops the run)
}
ns.Invite = Invite

local MAX_RAID = 40
local PARTY_SLOTS = 4

--[[ Pure planner.
  keys: roster members in roster order; inGroup: key -> true;
  guild: key -> true (online) | false (offline), unknown players are absent;
  room: free slots in the group.
  Returns reused tables: targets (known online first, otherwise roster order)
  and skipped = { inGroup, offline, full } counts.
]]
local targets, unknown = {}, {}
local skipped = { inGroup = 0, offline = 0, full = 0 }

function Invite.Plan(keys, inGroup, guild, selfKey, room)
    wipe(targets)
    wipe(unknown)
    skipped.inGroup, skipped.offline, skipped.full = 0, 0, 0
    for _, key in ipairs(keys) do
        if key == selfKey or inGroup[key] then
            skipped.inGroup = skipped.inGroup + 1
        elseif guild[key] == false then
            skipped.offline = skipped.offline + 1
        elseif guild[key] then
            targets[#targets + 1] = key
        else
            unknown[#unknown + 1] = key
        end
    end
    for _, key in ipairs(unknown) do targets[#targets + 1] = key end
    room = math.max(0, room)
    for i = #targets, room + 1, -1 do
        targets[i] = nil
        skipped.full = skipped.full + 1
    end
    return targets, skipped
end

---------------------------------------------------------------------------
-- Group state
---------------------------------------------------------------------------
local inGroup, guild = {}, {}

local function selfKey()
    return Players.Key((UnitName("player")))
end

local function readGroup()
    wipe(inGroup)
    if IsInRaid() then
        ns.Raid:Refresh()
        for key in pairs(ns.Raid.members) do inGroup[key] = true end
    else
        for i = 1, PARTY_SLOTS do
            local name, realm = UnitName("party" .. i)
            if name then
                -- UnitName gives the realm with spaces; keys use the normalized one
                realm = realm and realm:gsub("[%s%-]", "")
                inGroup[Players.Key(realm and realm ~= "" and (name .. "-" .. realm) or name)] = true
            end
        end
    end
    return inGroup
end

-- Online state of guild members from the client's cached guild roster.
local function readGuild()
    wipe(guild)
    if not IsInGuild() then return guild end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name then guild[Players.Key(name)] = online and true or false end
    end
    return guild
end

local function plan(keys)
    readGroup()
    readGuild()
    local room = MAX_RAID - math.max(1, GetNumGroupMembers())
    return Invite.Plan(keys, inGroup, guild, selfKey(), room)
end

-- Returns ok, reason.
function Invite:CanInvite()
    if IsInGroup() then
        if HasLFGRestrictions() then return false, "You cannot invite into a group finder group." end
        if IsInRaid() then
            if not ns.Raid:CanManage() then return false, "Only the raid leader or an assistant can invite." end
        elseif not UnitIsGroupLeader("player") then
            return false, "Only the party leader can invite."
        end
    end
    return true
end

-- Does inviting n players need the group turned into a raid first?
function Invite:NeedsRaid(n)
    return not IsInRaid() and n > PARTY_SLOTS + 1 - math.max(1, GetNumGroupMembers())
end

-- Plan for the confirmation; also asks the server for fresh guild online
-- states, which have usually arrived by the time Start plans again.
function Invite:Preview(keys)
    if IsInGuild() then C_GuildInfo.GuildRoster() end
    return plan(keys)
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
-- Players from our realm go by their bare name, like Blizzard's own invites.
local function send(key)
    if Players.Realm(key) == Players.HomeRealm() then key = Players.ShortName(key) end
    C_PartyInfo.InviteUnit(key)
end

-- A no-op while the group is still forming, so every roster update while we
-- lead a party asks again; combat blocks it until PLAYER_REGEN_ENABLED.
local function convert()
    if not InCombatLockdown() then C_PartyInfo.ConvertToRaid() end
end

local function finish(kind, n)
    Invite.running = false
    Invite.grouped = false
    wipe(Invite.queue)
    ns.UnregisterEvent(Invite, "GROUP_ROSTER_UPDATE")
    ns.UnregisterEvent(Invite, "PLAYER_REGEN_ENABLED")
    ns.Fire("INVITE_STATE", kind, n)
end

-- Everyone left in the queue who has not joined yet.
local function sendQueue()
    readGroup()
    local n = 0
    for _, key in ipairs(Invite.queue) do
        if not inGroup[key] then
            send(key)
            n = n + 1
        end
    end
    return n
end

local function onRoster()
    if IsInRaid() then
        if not ns.Raid:CanManage() then
            finish("lead")
            return
        end
        finish("raid", sendQueue())
    elseif IsInGroup() and GetNumGroupMembers() >= 2 then
        if not UnitIsGroupLeader("player") then
            finish("lead")
        else
            Invite.grouped = true
            convert()
        end
    elseif Invite.grouped then
        -- the party we were turning into a raid is gone
        finish("left")
    end
    -- still solo: keep waiting, declines send no roster update
end

-- Returns ok, reason. Starting again replaces a waiting run.
function Invite:Start(keys)
    local ok, reason = self:CanInvite()
    if not ok then return false, reason end
    local list = plan(keys)
    if #list == 0 then return false, "Nobody to invite." end
    if self.running then finish("replaced") end
    -- nothing to wait for
    if not self:NeedsRaid(#list) then
        for _, key in ipairs(list) do send(key) end
        ns.Fire("INVITE_STATE", "sent", #list)
        return true
    end
    local queue = self.queue
    for i, key in ipairs(list) do queue[i] = key end
    self.running = true
    self.grouped = false
    ns.RegisterEvent(Invite, "GROUP_ROSTER_UPDATE", onRoster)
    ns.RegisterEvent(Invite, "PLAYER_REGEN_ENABLED", onRoster)
    if IsInGroup() then
        self.grouped = true
        convert()
        ns.Fire("INVITE_STATE", "converting", #queue)
    else
        local n = math.min(PARTY_SLOTS, #queue)
        for _ = 1, n do send(tremove(queue, 1)) end
        ns.Fire("INVITE_STATE", "waiting", n)
    end
    return true
end

function Invite:Stop()
    if self.running then finish("stopped") end
end
