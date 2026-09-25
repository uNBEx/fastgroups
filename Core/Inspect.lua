-- Learn raid members' specs by inspecting them, one request at a time. Only
-- runs while the window is open, the option is on and we are in a raid.
-- First come players whose spec is unknown, contradicted by their raid role,
-- or changed; then saved specs the raid role cannot vouch for (a class with
-- two specs in that role), checked once per window opening. Requests are
-- paced and time out, so a dropped one never stalls the queue; a player whose
-- requests keep failing (out of range) waits for the next roster event, hover,
-- spec change or combat end.
local _, ns = ...

local Players = ns.Players

local GAP = 1.5       -- seconds between requests; the server drops faster ones
local TIMEOUT = 5     -- a request with no answer by then is lost
local MAX_FAILS = 3   -- failed requests before a player waits for an event

local Inspect = {
    active = false,
    pendingKey = nil,
    pendingGUID = nil,
    nextKey = nil,    -- hovered card, asked about next
    waiting = false,  -- the pacing / timeout timer is running
    fails = {},       -- key -> failed requests since the window opened
}
ns.Inspect = Inspect

local function inspectFrameBusy()
    return InspectFrame and InspectFrame:IsShown()
end

-- One timer at a time; starting a new wait voids the previous one.
local token = 0
local function wait(delay, fn)
    token = token + 1
    local mine = token
    Inspect.waiting = true
    C_Timer.After(delay, function()
        if mine ~= token then return end
        Inspect.waiting = false
        fn()
    end)
end

local function stopWaiting()
    token = token + 1
    Inspect.waiting = false
end

local function kickNext()
    Inspect:Kick()
end

local function onTimeout()
    local key = Inspect.pendingKey
    if key then Inspect.fails[key] = (Inspect.fails[key] or 0) + 1 end
    Inspect.pendingKey, Inspect.pendingGUID = nil, nil
    Inspect:Kick()
end

local function onReady(_, _, guid)
    Inspect:OnReady(guid)
end

local function onSpecChanged(_, _, unit)
    Inspect:OnSpecChanged(unit)
end

function Inspect:SetActive(on)
    on = on and ns.settings.autoInspect and IsInRaid() and true or false
    if on == self.active then
        if on then self:Kick() end
        return
    end
    self.active = on
    if on then
        -- a new window session: saved specs are worth another look
        Players.ForgetChecked("inspect")
        wipe(self.fails)
        ns.RegisterEvent(Inspect, "INSPECT_READY", onReady)
        ns.RegisterEvent(Inspect, "PLAYER_SPECIALIZATION_CHANGED", onSpecChanged)
        if ns.SpecComm then ns.SpecComm.Request() end
        self:Kick()
    else
        ns.UnregisterEvent(Inspect, "INSPECT_READY")
        ns.UnregisterEvent(Inspect, "PLAYER_SPECIALIZATION_CHANGED")
        self.pendingKey, self.pendingGUID, self.nextKey = nil, nil, nil
        stopWaiting()
    end
end

local function canInspect(unit)
    return UnitIsConnected(unit) and UnitIsVisible(unit) and CanInspect(unit)
end

-- 1 = must inspect, 2 = worth a re-check, nil = nothing to learn or not reachable.
local function tier(key, m)
    if UnitIsUnit(m.unit, "player") then return nil end
    local info = Players.Get(key)
    local t = info.needsInspect and 1 or info.recheck and 2 or nil
    if t and canInspect(m.unit) then return t end
end

function Inspect:Pick()
    local members = ns.Raid.members
    local want = self.nextKey
    self.nextKey = nil
    if want and members[want] and tier(want, members[want]) then
        return want, members[want].unit
    end
    local bestKey, bestScore
    for key, m in pairs(members) do
        local fails = self.fails[key] or 0
        if fails < MAX_FAILS then
            local t = tier(key, m)
            if t then
                local score = t * MAX_FAILS + fails
                if not bestScore or score < bestScore then bestKey, bestScore = key, score end
            end
        end
    end
    if bestKey then return bestKey, members[bestKey].unit end
end

-- Ask about the next player. `preferKey` (a hovered card) goes first, even
-- past the failure limit.
function Inspect:Kick(preferKey)
    if preferKey then self.nextKey = preferKey end
    if not self.active or self.pendingKey or self.waiting then return end
    if InCombatLockdown() or inspectFrameBusy() then return end
    local key, unit = self:Pick()
    if not key then return end
    self.pendingKey = key
    self.pendingGUID = UnitGUID(unit)
    NotifyInspect(unit)
    wait(TIMEOUT, onTimeout)
end

function Inspect:OnReady(guid)
    -- use any inspect result for a raid member, ours or another addon's
    for key, m in pairs(ns.Raid.members) do
        if UnitGUID(m.unit) == guid then
            local specID = C_SpecializationInfo.GetInspectSpecialization(m.unit)
            if specID and specID > 0 then
                self.fails[key] = nil
                if Players.Confirm(key, specID, "inspect") then
                    ns.Fire("PLAYER_INFO_CHANGED", key)
                end
            elseif key == self.pendingKey then
                self.fails[key] = (self.fails[key] or 0) + 1
            end
            break
        end
    end
    if self.pendingGUID and guid == self.pendingGUID then
        self.pendingKey, self.pendingGUID = nil, nil
        if not inspectFrameBusy() then ClearInspectPlayer() end
        wait(GAP, kickNext)
    end
end

-- Fires for group members too. The saved spec stays on the card until the
-- new one is read, since talent-only changes may fire this as well.
function Inspect:OnSpecChanged(unit)
    if not unit then return end
    for key, m in pairs(ns.Raid.members) do
        if UnitIsUnit(m.unit, unit) then
            if UnitIsUnit(unit, "player") then
                if ns.Raid:UpdateOwnSpec(key) then ns.Fire("PLAYER_INFO_CHANGED", key) end
            else
                Players.Unconfirm(key)
                self.fails[key] = nil
                self:Kick(key)
            end
            return
        end
    end
end
