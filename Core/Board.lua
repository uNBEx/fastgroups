-- The draft board: who sits in which group. Nothing here touches the real
-- raid; Core/Apply.lua pushes the draft to the server.
local _, ns = ...

local Players = ns.Players
local Data = ns.Data

local Board = {
    source = "none",    -- "none" | "live" | "demo" | "roster" | "loadout"
    sourceId = nil,     -- roster id or loadout id for those sources
    members = {},       -- array of keys on the board
    isMember = {},      -- key -> true
    draft = {},         -- key -> group (0 = unassigned tray)
    ghosts = {},        -- array of { key, group } for absent loadout players
    subs = {},          -- key -> absent key this player replaces
    tags = {},          -- key -> "new" | "ret"
    lastLive = {},      -- key -> live group at the previous sync
    liveVersion = nil,  -- ns.Raid.version the board last synced with
    loaded = nil,       -- reconcile summary of the loaded loadout
    activeLoadout = nil,
}
ns.Board = Board

local MAX_GROUPS = 8
local GROUP_SIZE = 5

local function settings() return ns.settings end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
function Board:IsLiveLike()
    return self.source == "live" or self.source == "demo"
end

function Board:Live()
    if self.source == "live" then return ns.Raid.members end
    if self.source == "demo" then return ns.Demo.members end
    return nil
end

function Board:IsMythic()
    if self.source == "demo" then return true end
    if self.source == "live" then return ns.Raid:IsMythic() end
    return false
end

-- Number of groups the halves use.
function Board:K()
    local mode = settings().groupsMode
    if mode == 4 or mode == 6 then return mode end
    if self.source == "loadout" then
        local lo = ns.Loadouts.Find(self.sourceId)
        if lo and lo.k then return lo.k end
    end
    if self:IsMythic() then return 4 end
    local n = #self.members
    if n == 0 then return 4 end
    local k = 2 * math.ceil(n / 10)
    if k < 2 then k = 2 elseif k > 6 then k = 6 end
    return k
end

local halvesCache = {}

-- Returns two arrays of group numbers for the left and right half.
function Board.HalvesFor(conv, k)
    local id = conv .. k
    local h = halvesCache[id]
    if h then return h.L, h.R end
    h = { L = {}, R = {} }
    for g = 1, k do
        if conv == "oddeven" then
            if g % 2 == 1 then tinsert(h.L, g) else tinsert(h.R, g) end
        else
            if g <= k / 2 then tinsert(h.L, g) else tinsert(h.R, g) end
        end
    end
    halvesCache[id] = h
    return h.L, h.R
end

function Board:Halves()
    return Board.HalvesFor(settings().conv, self:K())
end

function Board.SideOfFor(g, conv, k)
    local L, R = Board.HalvesFor(conv, k)
    for i = 1, #L do if L[i] == g then return "L", i end end
    for i = 1, #R do if R[i] == g then return "R", i end end
    return nil
end

function Board:SideOf(g)
    return Board.SideOfFor(g, settings().conv, self:K())
end

-- Map a group from one convention / size to another, keeping the side.
-- Returns 0 when the target layout has no matching group.
function Board.Remap(g, fromConv, fromK, toConv, toK)
    if not g or g == 0 then return 0 end
    local side, idx = Board.SideOfFor(g, fromConv, fromK)
    if not side then
        if g > toK then return g end
        return 0
    end
    local L, R = Board.HalvesFor(toConv, toK)
    local list = side == "L" and L or R
    return list[idx] or 0
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function Board:Occupancy(g)
    local n = 0
    for _, key in ipairs(self.members) do
        if self.draft[key] == g then n = n + 1 end
    end
    for _, gh in ipairs(self.ghosts) do
        if gh.group == g then n = n + 1 end
    end
    return n
end

local function compareKeys(a, b)
    local ia, ib = Players.Get(a), Players.Get(b)
    local oa, ob = Data.ROLE_ORDER[ia.bucket], Data.ROLE_ORDER[ib.bucket]
    if oa ~= ob then return oa < ob end
    if settings().sortMode == "class" and ia.class ~= ib.class then
        return (ia.class or "") < (ib.class or "")
    end
    return ia.name < ib.name
end

function Board.SortKeys(list)
    table.sort(list, compareKeys)
    return list
end

-- Fills `out` with the keys drafted into group g, sorted.
function Board:MembersOf(g, out)
    wipe(out)
    for _, key in ipairs(self.members) do
        if self.draft[key] == g then out[#out + 1] = key end
    end
    return Board.SortKeys(out)
end

function Board:GhostsOf(g, out)
    wipe(out)
    for _, gh in ipairs(self.ghosts) do
        if gh.group == g then out[#out + 1] = gh.key end
    end
    return Board.SortKeys(out)
end

function Board:IsGhost(key)
    for _, gh in ipairs(self.ghosts) do
        if gh.key == key then return gh end
    end
    return nil
end

-- True for a raid member who is logged out (for example switching to an alt).
function Board:IsOffline(key)
    local live = self:Live()
    local m = live and live[key]
    return m ~= nil and not m.online
end

-- Fills `out` with the keys drafted into bench groups (above K), sorted.
function Board:BenchKeys(out)
    wipe(out)
    local k = self:K()
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        if g and g > k then out[#out + 1] = key end
    end
    return Board.SortKeys(out)
end

-- Keys whose draft group differs from their live group.
function Board:Pending(out)
    local n = 0
    local live = self:Live()
    if not live then return 0 end
    if out then wipe(out) end
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        local m = live[key]
        if m and g and g ~= 0 and g ~= m.group then
            n = n + 1
            if out then out[n] = key end
        end
    end
    return n
end

-- True when the draft differs from the live raid in any way (moves, the
-- tray, absent players), i.e. there is something to revert.
function Board:Dirty()
    local live = self:Live()
    if not live then return false end
    if #self.ghosts > 0 or self.loaded then return true end
    for _, key in ipairs(self.members) do
        local m = live[key]
        if m and self.draft[key] ~= m.group then return true end
    end
    return false
end

local countTables = { L = { cls = {} }, R = { cls = {} } }

-- Per-half counts: T, H, M, R, U (unknown position), n, off (offline), cls[class].
function Board:Counts(side)
    local c = countTables[side]
    c.T, c.H, c.M, c.R, c.U, c.n, c.off = 0, 0, 0, 0, 0, 0, 0
    wipe(c.cls)
    local live = self:Live()
    local L, R = self:Halves()
    local groups = side == "L" and L or R
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        local inSide = false
        for i = 1, #groups do
            if groups[i] == g then inSide = true break end
        end
        if inSide then
            local info = Players.Get(key)
            local b = info.bucket
            if b == "?" then c.U = c.U + 1 else c[b] = c[b] + 1 end
            c.n = c.n + 1
            local m = live and live[key]
            if m and not m.online then c.off = c.off + 1 end
            if info.class then c.cls[info.class] = (c.cls[info.class] or 0) + 1 end
        end
    end
    return c
end

-- True when two counts are further apart than their parity allows.
function Board.Uneven(a, b)
    return math.abs(a - b) > (a + b) % 2
end

local imbalanceList = {}
local BUCKET_KEYS = { "T", "H", "M", "R" }

-- Returns an array of uneven categories: "T", "H", "M", "R" and class files.
function Board:Imbalances()
    wipe(imbalanceList)
    local L, R = self:Counts("L"), self:Counts("R")
    for _, b in ipairs(BUCKET_KEYS) do
        if Board.Uneven(L[b], R[b]) then tinsert(imbalanceList, b) end
    end
    for _, class in ipairs(Data.CLASSES) do
        if Board.Uneven(L.cls[class] or 0, R.cls[class] or 0) then tinsert(imbalanceList, class) end
    end
    return imbalanceList
end

---------------------------------------------------------------------------
-- Mutations
---------------------------------------------------------------------------
function Board:Changed()
    ns.Fire("BOARD_CHANGED")
end

local function clearLoadState(self)
    wipe(self.ghosts)
    wipe(self.subs)
    wipe(self.tags)
    self.loaded = nil
end

function Board:Clear()
    wipe(self.members)
    wipe(self.isMember)
    wipe(self.draft)
    wipe(self.lastLive)
    clearLoadState(self)
end

function Board:AddMember(key, g)
    if not self.isMember[key] then
        self.isMember[key] = true
        tinsert(self.members, key)
    end
    self.draft[key] = g or 0
end

function Board:RemoveMember(key)
    if not self.isMember[key] then return end
    self.isMember[key] = nil
    for i = #self.members, 1, -1 do
        if self.members[i] == key then tremove(self.members, i) break end
    end
    self.draft[key] = nil
    self.lastLive[key] = nil
    self.tags[key] = nil
    self.subs[key] = nil
end

function Board:SetSource(src, id)
    self:Clear()
    self.source = src
    self.sourceId = id
    if src == "live" or src == "demo" then
        if src == "live" then
            ns.Raid:Refresh()
            self.liveVersion = ns.Raid.version
        else
            ns.Demo:Start()
        end
        for key, m in pairs(self:Live()) do
            self:AddMember(key, m.group)
            self.lastLive[key] = m.group
        end
        self.activeLoadout = nil
    elseif src == "roster" then
        local r = ns.Rosters.Find(id)
        if r then
            for _, key in ipairs(r.members) do self:AddMember(key, 0) end
        end
        self.activeLoadout = nil
    elseif src == "loadout" then
        local lo = ns.Loadouts.Find(id)
        if lo then
            ns.Loadouts.SetHints(lo)
            local conv, k = settings().conv, lo.k or 4
            for key, g in pairs(lo.groups) do
                self:AddMember(key, Board.Remap(g, lo.conv or conv, lo.k or k, conv, k))
            end
            self.activeLoadout = lo.id
        end
    else
        self.source = "none"
        self.activeLoadout = nil
    end
    self:Changed()
end

-- Pick the natural source: the real raid when in one.
function Board:AutoSource(force)
    if IsInRaid() then
        if self.source == "live" then
            -- roster events come in bursts; only merge when something changed
            ns.Raid:Refresh()
            if self.liveVersion ~= ns.Raid.version then self:Sync() end
        elseif force or self.source == "none" then
            self:SetSource("live")
        end
    elseif self.source == "live" or (force and self.source ~= "none") then
        self:SetSource("none")
    end
end

-- Merge live roster changes into the draft. Players the user has not moved
-- follow their live group; joiners and leavers are added / removed.
function Board:Sync()
    if not self:IsLiveLike() then return end
    local live = self:Live()
    local applying = ns.Apply and ns.Apply.running
    if self.source == "live" then self.liveVersion = ns.Raid.version end
    for key, m in pairs(live) do
        if not self.isMember[key] then
            if self.loaded then
                self:AddMember(key, 0)
                local lo = self.loaded.lo
                self.tags[key] = (lo.memory and lo.memory[key]) and "ret" or "new"
            elseif self:Occupancy(m.group) < GROUP_SIZE then
                self:AddMember(key, m.group)
            else
                self:AddMember(key, 0)
            end
        elseif not applying and self.draft[key] == self.lastLive[key] and self.draft[key] ~= m.group then
            self.draft[key] = m.group
        end
        self.lastLive[key] = m.group
    end
    for i = #self.members, 1, -1 do
        local key = self.members[i]
        if not live[key] then
            local g = self.draft[key]
            local lo = self.loaded and self.loaded.lo
            self:RemoveMember(key)
            if lo and lo.groups[key] and g and g > 0 then
                tinsert(self.ghosts, { key = key, group = g })
            end
        end
    end
    -- someone followed a live move into a group the draft had already filled
    for g = 1, MAX_GROUPS do
        local over = self:Occupancy(g) - GROUP_SIZE
        if over > 0 then
            for i = #self.members, 1, -1 do
                local key = self.members[i]
                if over > 0 and self.draft[key] == g and self.lastLive[key] == g then
                    self.draft[key] = 0
                    over = over - 1
                end
            end
        end
    end
    self:Changed()
end

-- Move a player to group g (0 = tray). Fails when the group is full.
function Board:Move(key, g)
    if self.draft[key] == g then return true end
    if g ~= 0 and self:Occupancy(g) >= GROUP_SIZE then
        return false, "full"
    end
    self.draft[key] = g
    self:Changed()
    return true
end

function Board:Swap(a, b)
    local ga, gb = self.draft[a], self.draft[b]
    self.draft[a], self.draft[b] = gb, ga
    self:Changed()
end

-- Put `key` into the slot of an absent player.
function Board:Substitute(key, ghostKey)
    for i, gh in ipairs(self.ghosts) do
        if gh.key == ghostKey then
            self.draft[key] = gh.group
            self.subs[key] = ghostKey
            tremove(self.ghosts, i)
            self:Changed()
            return true
        end
    end
    return false
end

-- First group of a half with a free slot.
function Board:FreeGroupIn(side)
    local L, R = self:Halves()
    local list = side == "L" and L or R
    for _, g in ipairs(list) do
        if self:Occupancy(g) < GROUP_SIZE then return g end
    end
    return nil
end

function Board:FreeBenchGroup()
    for g = self:K() + 1, MAX_GROUPS do
        if self:Occupancy(g) < GROUP_SIZE then return g end
    end
    return nil
end

function Board:ClearGhosts()
    wipe(self.ghosts)
    self:Changed()
end

function Board:DismissLoaded()
    clearLoadState(self)
    self:Changed()
end

-- Throw away draft edits and show the live raid again.
function Board:Revert()
    if not self:IsLiveLike() then return end
    local live = self:Live()
    clearLoadState(self)
    self.activeLoadout = nil
    for _, key in ipairs(self.members) do
        local m = live[key]
        self.draft[key] = m and m.group or 0
    end
    self:Changed()
end

-- Switch split convention; everyone keeps their side.
function Board:SetConvention(conv)
    local s = settings()
    if s.conv == conv then return end
    local k = self:K()
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        if g and g > 0 and g <= k then self.draft[key] = Board.Remap(g, s.conv, k, conv, k) end
    end
    for _, gh in ipairs(self.ghosts) do
        if gh.group <= k then gh.group = Board.Remap(gh.group, s.conv, k, conv, k) end
    end
    s.conv = conv
    self:Changed()
end

-- Change how many groups the halves use; players keep their side.
function Board:SetGroupsMode(mode)
    local s = settings()
    local oldK = self:K()
    s.groupsMode = mode
    local newK = self:K()
    if oldK ~= newK then
        local conv = s.conv
        for _, key in ipairs(self.members) do
            local g = self.draft[key]
            if g and g > 0 and g <= oldK then self.draft[key] = Board.Remap(g, conv, oldK, conv, newK) end
        end
        for i = #self.ghosts, 1, -1 do
            local gh = self.ghosts[i]
            if gh.group <= oldK then
                gh.group = Board.Remap(gh.group, conv, oldK, conv, newK)
                if gh.group == 0 then tremove(self.ghosts, i) end
            end
        end
    end
    self:Changed()
end

---------------------------------------------------------------------------
-- Loadouts on the board
---------------------------------------------------------------------------

-- Load a loadout. On a live raid, roster or demo this reconciles who is
-- present, absent, new or returning. Otherwise the loadout is opened for
-- editing.
function Board:ApplyLoadout(lo)
    if self.source == "none" or self.source == "loadout" then
        self:SetSource("loadout", lo.id)
        return
    end
    ns.Loadouts.SetHints(lo)
    local conv, k = settings().conv, self:K()
    clearLoadState(self)
    local present, absent, fresh, returning = 0, 0, 0, 0
    for key, g in pairs(lo.groups) do
        local target = Board.Remap(g, lo.conv or conv, lo.k or k, conv, k)
        if self.isMember[key] then
            present = present + 1
            self.draft[key] = target
        elseif target > 0 then
            absent = absent + 1
            tinsert(self.ghosts, { key = key, group = target })
        end
    end
    for _, key in ipairs(self.members) do
        if not lo.groups[key] then
            self.draft[key] = 0
            if lo.memory and lo.memory[key] then
                self.tags[key] = "ret"
                returning = returning + 1
            else
                self.tags[key] = "new"
                fresh = fresh + 1
            end
        end
    end
    self.loaded = { lo = lo, name = lo.name, present = present, absent = absent, fresh = fresh, returning = returning }
    self.activeLoadout = lo.id
    self:Changed()
end

-- Put waiting players into absent players' slots: same role first, then same
-- melee/ranged, then same class; returning players prefer their old side.
-- Leftovers go to free slots on the half that needs their role most.
function Board:AutoFill()
    local lo = self.loaded and self.loaded.lo
    local memory = lo and settings().rememberSides and lo.memory or nil
    local waiting = {}
    for _, key in ipairs(self.members) do
        if self.draft[key] == 0 then tinsert(waiting, key) end
    end
    table.sort(waiting, function(a, b)
        local ra, rb = self.tags[a] == "ret", self.tags[b] == "ret"
        if ra ~= rb then return ra end
        return compareKeys(a, b)
    end)
    local placed = 0
    for _, key in ipairs(waiting) do
        local info = Players.Get(key)
        local role, bucket, class = info.role, info.bucket, info.class
        local want = memory and memory[key]
        local best, bestScore
        for _, gh in ipairs(self.ghosts) do
            local ginfo = Players.Get(gh.key)
            if ginfo.role == role then
                local score = 10
                if ginfo.bucket == bucket then score = score + 20 end
                if class and ginfo.class == class then score = score + 8 end
                if want and self:SideOf(gh.group) == want then score = score + 40 end
                if not bestScore or score > bestScore then best, bestScore = gh, score end
            end
        end
        if best then
            self.draft[key] = best.group
            self.subs[key] = best.key
            for i, gh in ipairs(self.ghosts) do
                if gh == best then tremove(self.ghosts, i) break end
            end
            placed = placed + 1
        end
    end
    for _, key in ipairs(waiting) do
        if self.draft[key] == 0 then
            local info = Players.Get(key)
            local b = info.bucket == "?" and "U" or info.bucket
            local L, R = self:Counts("L")[b], self:Counts("R")[b]
            local first = (memory and memory[key]) or (L <= R and "L" or "R")
            local g = self:FreeGroupIn(first) or self:FreeGroupIn(first == "L" and "R" or "L")
            if g then
                self.draft[key] = g
                placed = placed + 1
            end
        end
    end
    self:Changed()
    return placed
end
