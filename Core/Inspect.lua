-- Learn raid members' specs by inspecting them, one at a time. Only runs
-- while the window is open, the option is on and we are in a raid. The queue
-- is driven by events (window open, roster update, INSPECT_READY, hovering a
-- card); a request the server drops is simply retried on the next event.
local _, ns = ...

local Players = ns.Players

local Inspect = {
    active = false,
    pendingGUID = nil,
    tried = {},       -- key -> true, attempted this session
}
ns.Inspect = Inspect

local function inspectFrameBusy()
    return InspectFrame and InspectFrame:IsShown()
end

local function onReady(_, _, guid)
    Inspect:OnReady(guid)
end

function Inspect:SetActive(on)
    on = on and ns.settings.autoInspect and IsInRaid() and true or false
    if on == self.active then
        if on then self:Kick() end
        return
    end
    self.active = on
    if on then
        ns.RegisterEvent(Inspect, "INSPECT_READY", onReady)
        self:Kick()
    else
        ns.UnregisterEvent(Inspect, "INSPECT_READY")
        self.pendingGUID = nil
    end
end

local function canInspect(unit)
    return UnitIsConnected(unit) and UnitIsVisible(unit) and CanInspect(unit)
end

local function request(key, unit)
    Inspect.tried[key] = true
    Inspect.pendingGUID = UnitGUID(unit)
    NotifyInspect(unit)
end

-- Ask about the next player whose spec is unknown. `preferKey` jumps the queue.
function Inspect:Kick(preferKey)
    if not self.active or InCombatLockdown() or inspectFrameBusy() then return end
    local members = ns.Raid.members
    if preferKey then
        local m = members[preferKey]
        if m and not UnitIsUnit(m.unit, "player") and Players.Get(preferKey).needsInspect and canInspect(m.unit) then
            request(preferKey, m.unit)
            return
        end
    end
    for key, m in pairs(members) do
        if not self.tried[key] and not UnitIsUnit(m.unit, "player")
            and Players.Get(key).needsInspect and canInspect(m.unit) then
            request(key, m.unit)
            return
        end
    end
    self.pendingGUID = nil
end

function Inspect:OnReady(guid)
    -- use any inspect result for a raid member, ours or another addon's
    for key, m in pairs(ns.Raid.members) do
        if UnitGUID(m.unit) == guid then
            local specID = C_SpecializationInfo.GetInspectSpecialization(m.unit)
            if specID and specID > 0 then
                Players.SetSpec(key, specID)
                ns.Fire("PLAYER_INFO_CHANGED", key)
            end
            break
        end
    end
    if guid == self.pendingGUID then
        self.pendingGUID = nil
        if not inspectFrameBusy() then ClearInspectPlayer() end
        self:Kick()
    end
end

-- New session for a player (e.g. they changed spec): allow another try.
function Inspect:Forget(key)
    self.tried[key] = nil
end
