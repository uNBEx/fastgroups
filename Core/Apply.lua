-- Push the draft to the real raid. One SetRaidSubgroup / SwapRaidSubgroup at
-- a time; the next move is chosen when GROUP_ROSTER_UPDATE confirms the last.
-- Events are only registered while an apply is running.
local _, ns = ...

local Apply = {
    running = false,
    total = 0,
    done = 0,
    expect = nil,       -- { key, group } the last move should produce
    waiting = false,
}
ns.Apply = Apply

local GROUP_SIZE = 5
local MAX_GROUPS = 8

--[[ Pure planner.
  members: array of { key, index, group, busy }  (busy = cannot be moved now)
  target:  key -> wanted group (0 or nil = leave alone)
  Returns an op { kind = "set", a = member, group = g } or
  { kind = "swap", a = member, b = member }, or nil plus a reason:
  nil when everything is in place, "busy" when only busy players are left,
  "stuck" when no legal move exists (target overfills a group).
]]
local count, byGroup, wrong = {}, {}, {}
for g = 1, MAX_GROUPS do byGroup[g] = {} end

function Apply.NextMove(members, target)
    for g = 1, MAX_GROUPS do
        count[g] = 0
        wipe(byGroup[g])
    end
    wipe(wrong)
    for _, m in ipairs(members) do
        count[m.group] = count[m.group] + 1
        tinsert(byGroup[m.group], m)
        local t = target[m.key]
        if t and t > 0 and t ~= m.group then tinsert(wrong, m) end
    end
    if #wrong == 0 then return nil end

    -- 1. two players who want each other's group
    for _, a in ipairs(wrong) do
        if not a.busy then
            local ta = target[a.key]
            for _, b in ipairs(wrong) do
                if not b.busy and b.group == ta and target[b.key] == a.group then
                    return { kind = "swap", a = a, b = b }
                end
            end
        end
    end
    -- 2. a free slot in the wanted group
    for _, a in ipairs(wrong) do
        local ta = target[a.key]
        if not a.busy and count[ta] < GROUP_SIZE then
            return { kind = "set", a = a, group = ta }
        end
    end
    -- 3. swap with someone in the wanted group who does not want to stay there
    for _, a in ipairs(wrong) do
        if not a.busy then
            for _, b in ipairs(byGroup[target[a.key]]) do
                local tb = target[b.key]
                if not b.busy and tb ~= b.group then
                    return { kind = "swap", a = a, b = b }
                end
            end
        end
    end
    for _, a in ipairs(wrong) do
        if not a.busy then return nil, "stuck" end
    end
    return nil, "busy"
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
local memberPool, memberList = {}, {}

local function snapshot()
    wipe(memberList)
    local i = 0
    for key, m in pairs(ns.Raid.members) do
        i = i + 1
        local t = memberPool[i]
        if not t then
            t = {}
            memberPool[i] = t
        end
        t.key, t.index, t.group = key, m.index, m.group
        t.busy = UnitAffectingCombat(m.unit) and true or false
        memberList[i] = t
    end
    return memberList
end

local function finish(ok, reason)
    Apply.running = false
    Apply.expect = nil
    Apply.waiting = false
    ns.UnregisterEvent(Apply, "GROUP_ROSTER_UPDATE")
    ns.UnregisterEvent(Apply, "PLAYER_REGEN_DISABLED")
    ns.Board:Sync()
    ns.Fire("APPLY_STATE", ok, reason)
end

function Apply:Stop(reason)
    if self.running then finish(false, reason or "stopped") end
end

-- Can the current board be applied? Returns ok, reason.
function Apply:CanApply()
    local board = ns.Board
    if board.source == "demo" then return true end
    if board.source ~= "live" then return false, "Only the live raid can be applied." end
    if not IsInRaid() then return false, "You are not in a raid." end
    if not ns.Raid:CanManage() then return false, "Only the raid leader or an assistant can move players." end
    if InCombatLockdown() then return false, "Groups cannot be changed in combat." end
    return true
end

function Apply:Step(force)
    if not self.running then return end
    ns.Raid:Refresh()
    if self.expect and not force then
        local m = ns.Raid.members[self.expect.key]
        if m and m.group ~= self.expect.group then
            self.waiting = true
            ns.Fire("APPLY_PROGRESS")
            return
        end
    end
    self.expect = nil
    self.waiting = false
    local op, why = Apply.NextMove(snapshot(), ns.Board.draft)
    if not op then
        if why then
            finish(false, why)
        else
            finish(true)
        end
        return
    end
    if op.kind == "set" then
        SetRaidSubgroup(op.a.index, op.group)
        self.expect = { key = op.a.key, group = op.group }
    else
        SwapRaidSubgroup(op.a.index, op.b.index)
        self.expect = { key = op.a.key, group = op.b.group }
    end
    self.lastKey = op.a.key
    self.lastGroup = self.expect.group
    self.done = math.max(0, self.total - ns.Board:Pending())
    ns.Fire("APPLY_PROGRESS")
end

local function onRoster() Apply:Step() end
local function onCombat() Apply:Stop("combat") end

-- Start, or nudge a running apply that waits for a lost server reply.
function Apply:Start()
    if self.running then
        self:Step(true)
        return true
    end
    local ok, reason = self:CanApply()
    if not ok then return false, reason end
    if ns.Board.source == "demo" then
        return self:RunDemo()
    end
    self.total = ns.Board:Pending()
    if self.total == 0 then return false, "Nothing to apply." end
    self.done = 0
    self.running = true
    ns.RegisterEvent(Apply, "GROUP_ROSTER_UPDATE", onRoster)
    ns.RegisterEvent(Apply, "PLAYER_REGEN_DISABLED", onCombat)
    ns.Fire("APPLY_STATE", nil)
    self:Step()
    return true
end

-- Demo raid: run the same planner against the fake roster, instantly.
function Apply:RunDemo()
    local demo = ns.Demo
    local list = {}
    for key, m in pairs(demo.members) do
        tinsert(list, { key = key, index = m.index, group = m.group, ref = m })
    end
    local moves = 0
    for _ = 1, 200 do
        local op = Apply.NextMove(list, ns.Board.draft)
        if not op then break end
        moves = moves + 1
        if op.kind == "set" then
            op.a.group = op.group
        else
            op.a.group, op.b.group = op.b.group, op.a.group
        end
    end
    for _, m in ipairs(list) do m.ref.group = m.group end
    ns.Board:Sync()
    ns.Fire("APPLY_STATE", true, nil, moves)
    return true
end
