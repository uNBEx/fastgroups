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
    sides = {},         -- key -> "L" | "R", the own side of players in the shared group
    ghosts = {},        -- array of { key, group, side } for absent loadout players
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
    if self.source == "demo" then return ns.Demo.mythic end
    if self.source == "live" then return ns.Raid:IsMythic() end
    return false
end

-- Shared odd group layout (opt-in). When the players fill an odd number of
-- groups (11-15 or 21-25 players), the groups before the last one form the
-- halves and the last one is shared: each of its players has an own side.
-- An odd K stands for this layout; the shared group is group K.
function Board:SharedK()
    if not settings().sharedGroup or self:IsMythic() then return nil end
    local m = math.ceil(#self.members / GROUP_SIZE)
    if m == 3 or m == 5 then return m end
    return nil
end

-- Number of groups the halves use, the shared group included.
function Board:K()
    local lo = self.source == "loadout" and ns.Loadouts.Find(self.sourceId)
    if lo and lo.k and lo.k % 2 == 1 then return lo.k end
    if not lo then
        local sk = self:SharedK()
        if sk then return sk end
    end
    local mode = settings().groupsMode
    if mode == 4 or mode == 6 then return mode end
    if lo and lo.k then return lo.k end
    if self:IsMythic() then return 4 end
    local n = #self.members
    if n == 0 then return 4 end
    local k = 2 * math.ceil(n / 10)
    if k < 2 then k = 2 elseif k > 6 then k = 6 end
    return k
end

local halvesCache = {}

-- Returns two arrays of group numbers for the left and right half. An odd
-- k leaves out its last group, which is shared.
function Board.HalvesFor(conv, k)
    local id = conv .. k
    local h = halvesCache[id]
    if h then return h.L, h.R end
    h = { L = {}, R = {} }
    local n = k - k % 2
    for g = 1, n do
        if conv == "oddeven" then
            if g % 2 == 1 then tinsert(h.L, g) else tinsert(h.R, g) end
        else
            if g <= n / 2 then tinsert(h.L, g) else tinsert(h.R, g) end
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

-- The shared group of a layout with k groups, or nil.
function Board.SharedOf(k)
    if k % 2 == 1 then return k end
    return nil
end

function Board:Shared()
    return Board.SharedOf(self:K())
end

-- Side of a player: the half of their group, or their own side in the shared group.
function Board:PlayerSide(key)
    local g = self.draft[key]
    if not g or g == 0 then return nil end
    local k = self:K()
    if g == Board.SharedOf(k) then return self.sides[key] end
    return Board.SideOfFor(g, settings().conv, k)
end

function Board:GhostSide(gh)
    if gh.group == self:Shared() then return gh.side end
    return self:SideOf(gh.group)
end

-- Map a group from one layout to another, keeping the side. pside is the
-- player's own side when g is the shared group. Returns the new group (0 when
-- the target layout has no matching group) and, when that is the shared
-- group, the side the player has there. Players past the end of a half go
-- to the shared group; shared players go to the last group of their half.
function Board.Remap(g, fromConv, fromK, toConv, toK, pside)
    if not g or g == 0 then return 0 end
    local toShared = Board.SharedOf(toK)
    local side, idx = Board.SideOfFor(g, fromConv, fromK)
    local L, R = Board.HalvesFor(toConv, toK)
    if not side then
        if g ~= Board.SharedOf(fromK) then
            if g > toK then return g end
            return 0
        end
        if toShared then return toShared, pside end
        if not pside then return 0 end
        local list = pside == "L" and L or R
        return list[#list] or 0
    end
    local list = side == "L" and L or R
    if list[idx] then return list[idx] end
    if toShared then return toShared, side end
    return 0
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
    local conv, k = settings().conv, self:K()
    local shared = Board.SharedOf(k)
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        local ps
        if g == shared then
            ps = self.sides[key]
        elseif g and g > 0 then
            ps = Board.SideOfFor(g, conv, k)
        end
        if ps == side then
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
-- Everyone in the shared group needs a side: newcomers get the half with
-- fewer of their role, then fewer players.
function Board:FixSides()
    local shared = self:Shared()
    if not shared then return end
    for _, key in ipairs(self.members) do
        if self.draft[key] == shared and not self.sides[key] then
            local b = Players.Get(key).bucket
            if b == "?" then b = "U" end
            local cl, cr = self:Counts("L"), self:Counts("R")
            local l, r = cl[b], cr[b]
            if l == r then l, r = cl.n, cr.n end
            self.sides[key] = l <= r and "L" or "R"
        end
    end
end

function Board:Changed()
    self:FixSides()
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
    wipe(self.sides)
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
    self.sides[key] = nil
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
            local memory = lo.memory or {}
            for key, g in pairs(lo.groups) do
                local g2, side = Board.Remap(g, lo.conv or conv, k, conv, k, memory[key])
                self:AddMember(key, g2)
                if side then self.sides[key] = side end
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
            local g, side = self.draft[key], self.sides[key]
            local lo = self.loaded and self.loaded.lo
            self:RemoveMember(key)
            if lo and lo.groups[key] and g and g > 0 then
                tinsert(self.ghosts, { key = key, group = g, side = side })
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

-- Move a player to group g (0 = tray). Fails when the group is full. side
-- sets the player's own side when g is the shared group.
function Board:Move(key, g, side)
    local shared = side and g ~= 0 and g == self:Shared()
    if self.draft[key] == g then
        if shared and self.sides[key] ~= side then
            self.sides[key] = side
            self:Changed()
        end
        return true
    end
    if g ~= 0 and self:Occupancy(g) >= GROUP_SIZE then
        return false, "full"
    end
    self.draft[key] = g
    if shared then self.sides[key] = side end
    self:Changed()
    return true
end

-- Swap two players, their sides in the shared group included.
function Board:Swap(a, b)
    local ga, gb = self.draft[a], self.draft[b]
    self.draft[a], self.draft[b] = gb, ga
    self.sides[a], self.sides[b] = self.sides[b], self.sides[a]
    self:Changed()
end

-- Put `key` into the slot of an absent player.
function Board:Substitute(key, ghostKey)
    for i, gh in ipairs(self.ghosts) do
        if gh.key == ghostKey then
            self.draft[key] = gh.group
            if gh.side then self.sides[key] = gh.side end
            self.subs[key] = ghostKey
            tremove(self.ghosts, i)
            self:Changed()
            return true
        end
    end
    return false
end

-- First group of a half with a free slot, else the shared group. Move the
-- player there with the side passed here.
function Board:FreeGroupIn(side)
    local L, R = self:Halves()
    local list = side == "L" and L or R
    for _, g in ipairs(list) do
        if self:Occupancy(g) < GROUP_SIZE then return g end
    end
    local shared = self:Shared()
    if shared and self:Occupancy(shared) < GROUP_SIZE then return shared end
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

-- Remapping can put more than five into a group (a half's last group, or
-- the shared group). Absent players who moved there leave first, then moved
-- players go to the tray.
local function settleOverflow(self, moved)
    for g = 1, MAX_GROUPS do
        local over = self:Occupancy(g) - GROUP_SIZE
        for i = #self.ghosts, 1, -1 do
            local gh = self.ghosts[i]
            if over > 0 and gh.group == g and moved[gh] then
                tremove(self.ghosts, i)
                over = over - 1
            end
        end
        for i = #self.members, 1, -1 do
            local key = self.members[i]
            if over > 0 and self.draft[key] == g and moved[key] then
                self.draft[key] = 0
                over = over - 1
            end
        end
    end
end

-- Move everyone from one layout to another, keeping their side.
local movedTmp = {}
local function remapAll(self, fromConv, fromK, toConv, toK)
    wipe(movedTmp)
    for _, key in ipairs(self.members) do
        local g = self.draft[key]
        if g and g > 0 and g <= fromK then
            local g2, side = Board.Remap(g, fromConv, fromK, toConv, toK, self.sides[key])
            self.draft[key] = g2
            if side then self.sides[key] = side end
            if g2 ~= g then movedTmp[key] = true end
        end
    end
    for i = #self.ghosts, 1, -1 do
        local gh = self.ghosts[i]
        if gh.group <= fromK then
            local g2, side = Board.Remap(gh.group, fromConv, fromK, toConv, toK, gh.side)
            if g2 ~= gh.group then movedTmp[gh] = true end
            gh.group, gh.side = g2, side
            if g2 == 0 then tremove(self.ghosts, i) end
        end
    end
    settleOverflow(self, movedTmp)
end

-- Change a layout setting; everyone keeps their side.
local function relayout(self, change)
    local s = settings()
    local oldConv, oldK = s.conv, self:K()
    change(s)
    local newK = self:K()
    if oldConv ~= s.conv or oldK ~= newK then remapAll(self, oldConv, oldK, s.conv, newK) end
    self:Changed()
end

-- Switch split convention.
function Board:SetConvention(conv)
    if settings().conv == conv then return end
    relayout(self, function(s) s.conv = conv end)
end

-- Change how many groups the halves use.
function Board:SetGroupsMode(mode)
    relayout(self, function(s) s.groupsMode = mode end)
end

-- Turn the shared odd group layout on or off.
function Board:SetShared(on)
    relayout(self, function(s) s.sharedGroup = on and true or false end)
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
    local memory = lo.memory or {}
    wipe(movedTmp)
    for key, g in pairs(lo.groups) do
        local target, side = Board.Remap(g, lo.conv or conv, lo.k or k, conv, k, memory[key])
        if self.isMember[key] then
            present = present + 1
            self.draft[key] = target
            if side then self.sides[key] = side end
            movedTmp[key] = true
        elseif target > 0 then
            absent = absent + 1
            local gh = { key = key, group = target, side = side }
            tinsert(self.ghosts, gh)
            movedTmp[gh] = true
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
    settleOverflow(self, movedTmp)
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
                if want and self:GhostSide(gh) == want then score = score + 40 end
                if not bestScore or score > bestScore then best, bestScore = gh, score end
            end
        end
        if best then
            self.draft[key] = best.group
            if best.side then self.sides[key] = best.side end
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
            local side = first
            local g = self:FreeGroupIn(first)
            if not g then
                side = first == "L" and "R" or "L"
                g = self:FreeGroupIn(side)
            end
            if g then
                self.draft[key] = g
                if g == self:Shared() then self.sides[key] = side end
                placed = placed + 1
            end
        end
    end
    self:Changed()
    return placed
end
