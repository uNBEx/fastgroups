-- Auto-split: balance the two halves in strict order of priority.
--   1. must: half sizes, tanks, healers, and a Monk / Demon Hunter on each
--      half once there are two (with strict positions also melee, ranged and
--      unknown)
--   2. side changes of settled players (placed by an earlier split)
--   3. melee, ranged and unknown (when not strict)
--   4. classes
--   5. moves of everyone else
-- A fresh raid has nobody settled, so the first split balances everything.
-- Later splits keep earlier players on their side unless tier 1 needs them,
-- and newcomers even out the rest.
local _, ns = ...

local Data = ns.Data

local Split = {}
ns.Split = Split

local GROUP_SIZE = 5
local BUCKETS = { "T", "H", "M", "R", "?" }
local SIDES = { "L", "R" }
-- who goes to the shared group first: damage dealers, ranged before melee
local SHARED_ORDER = { ["?"] = 1, R = 2, M = 3, H = 4, T = 5 }

local function sq(a, b)
    local d = a - b
    return d * d
end

local function classCost(L, R)
    local cost = 0
    for _, class in ipairs(Data.CLASSES) do
        cost = cost + sq(L.c[class] or 0, R.c[class] or 0) * (Data.BUFF_CLASSES[class] and 3 or 1)
    end
    return cost
end

-- Is cost a lower than cost b? Both are arrays of the five tiers.
local function less(a, b)
    for i = 1, 5 do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end

--[[ Pure core, used by the board and the tests.
  opts.keys      array of player keys to place
  opts.info      function(key) -> table with .bucket and .class
  opts.current   key -> current group (0 = none)
  opts.L, opts.R arrays of group numbers for each half
  opts.S         shared group, or nil. The halves fill their own groups and
                 the rest of each half goes to S with a side of its own.
  opts.sides     key -> "L"|"R", the own side of players currently in S
  opts.settled   key -> true for players an earlier split placed
  opts.strictPos true: melee, ranged and unknown count as much as tanks
  Returns key -> group (0 when both halves are full) and key -> side for
  the players placed in S.
]]
function Split.Compute(opts)
    local keys, info, current, L, R, S = opts.keys, opts.info, opts.current, opts.L, opts.R, opts.S
    local sides = opts.sides or {}
    local settled = opts.settled or {}
    local strict = opts.strictPos
    local sideOfGroup = {}
    for _, g in ipairs(L) do sideOfGroup[g] = "L" end
    for _, g in ipairs(R) do sideOfGroup[g] = "R" end
    local cap = { L = #L * GROUP_SIZE, R = #R * GROUP_SIZE }
    local limit = #keys
    if S then
        -- halves of equal size, each at most its groups plus the shared one
        limit = math.min(#keys, (#L + #R + 1) * GROUP_SIZE)
        local half = math.ceil(limit / 2)
        cap.L = math.min(half, cap.L + GROUP_SIZE)
        cap.R = math.min(half, cap.R + GROUP_SIZE)
    end

    local bucket, class, cur = {}, {}, {}
    local freq = {}
    for _, key in ipairs(keys) do
        local i = info(key)
        bucket[key] = i.bucket
        class[key] = i.class or "?"
        local g = current[key] or 0
        if S and g == S then
            cur[key] = sides[key]
        else
            cur[key] = sideOfGroup[g]
        end
        freq[class[key]] = (freq[class[key]] or 0) + 1
    end

    local order = {}
    for i, key in ipairs(keys) do order[i] = key end
    table.sort(order, function(a, b)
        local oa, ob = Data.ROLE_ORDER[bucket[a]], Data.ROLE_ORDER[bucket[b]]
        if oa ~= ob then return oa < ob end
        local fa, fb = freq[class[a]], freq[class[b]]
        if fa ~= fb then return fa > fb end
        if class[a] ~= class[b] then return class[a] < class[b] end
        return a < b
    end)

    -- A state: who is on which side, the counts per half and how many
    -- settled (sm) and other (fm) players left their current side.
    local function newState()
        local st = { side = {}, sm = 0, fm = 0, cost = {} }
        for _, s in ipairs(SIDES) do
            st[s] = { n = 0, b = {}, c = {} }
            for _, b in ipairs(BUCKETS) do st[s].b[b] = 0 end
        end
        -- nobody is placed yet: everyone with a side has left it
        for _, key in ipairs(keys) do
            if cur[key] then
                if settled[key] then st.sm = st.sm + 1 else st.fm = st.fm + 1 end
            end
        end
        return st
    end
    -- Put key on side s (nil = off the halves).
    local function put(st, key, s)
        local old = st.side[key]
        if old == s then return end
        local b, c = bucket[key], class[key]
        if old then
            local t = st[old]
            t.n = t.n - 1
            t.b[b] = t.b[b] - 1
            t.c[c] = t.c[c] - 1
        end
        if s then
            local t = st[s]
            t.n = t.n + 1
            t.b[b] = t.b[b] + 1
            t.c[c] = (t.c[c] or 0) + 1
        end
        local was = cur[key] ~= nil and old ~= cur[key]
        local now = cur[key] ~= nil and s ~= cur[key]
        if was ~= now then
            local d = now and 1 or -1
            if settled[key] then st.sm = st.sm + d else st.fm = st.fm + d end
        end
        st.side[key] = s
    end
    -- The five tiers of the state's cost, written into out.
    local function cost(st, out)
        local l, r = st.L, st.R
        local must = sq(l.n, r.n) + sq(l.b.T, r.b.T) + sq(l.b.H, r.b.H)
        local pos = sq(l.b.M, r.b.M) + sq(l.b.R, r.b.R) + sq(l.b["?"], r.b["?"])
        for c in pairs(Data.BUFF_CLASSES) do
            local a, b = l.c[c] or 0, r.c[c] or 0
            if a + b >= 2 and (a == 0 or b == 0) then must = must + 1 end
        end
        if strict then must, pos = must + pos, 0 end
        out[1], out[2], out[3], out[4], out[5] = must, st.sm, pos, classCost(l, r), st.fm
        return out
    end

    -- Place one player on the side that needs their role and class most.
    local function greedy(st, key)
        if st.L.n + st.R.n >= limit then return end
        local b, c = bucket[key], class[key]
        local best, bestScore
        for _, s in ipairs(SIDES) do
            local t = st[s]
            if t.n < cap[s] then
                -- lexicographic: bucket count, class count, stay on current side, size
                local score = t.b[b] * 1000000 + (t.c[c] or 0) * 10000
                    + ((cur[key] == s) and 0 or 100) + t.n
                if not bestScore or score < bestScore then best, bestScore = s, score end
            end
        end
        if best then put(st, key, best) end
    end

    -- Local search: move single players and swap any pair across the halves
    -- while that lowers the cost. Leaves the final cost in st.cost.
    local try = {}
    local function improve(st)
        local side = st.side
        cost(st, st.cost)
        local function keep()
            if less(cost(st, try), st.cost) then
                for i = 1, 5 do st.cost[i] = try[i] end
                return true
            end
            return false
        end
        for _ = 1, 50 do
            local improved = false
            for _, a in ipairs(order) do
                local sa = side[a]
                if sa then
                    local other = sa == "L" and "R" or "L"
                    if st[other].n < cap[other] then
                        put(st, a, other)
                        if keep() then improved = true else put(st, a, sa) end
                    end
                    for _, b in ipairs(order) do
                        sa = side[a]
                        local sb = side[b]
                        if sb and sb ~= sa then
                            put(st, a, sb)
                            put(st, b, sa)
                            if keep() then
                                improved = true
                            else
                                put(st, a, sa)
                                put(st, b, sb)
                            end
                        end
                    end
                end
            end
            if not improved then break end
        end
    end

    -- Start A: everyone on their current side, newcomers placed greedily.
    local a = newState()
    for _, key in ipairs(order) do
        if cur[key] then put(a, key, cur[key]) end
    end
    -- a half over its cap (possible with the shared group) gives players
    -- away, newcomers and damage dealers first
    for pass = 1, 2 do
        for i = #order, 1, -1 do
            local key = order[i]
            local s = a.side[key]
            if s and a[s].n > cap[s] and (pass == 2 or not settled[key]) then
                put(a, key, s == "L" and "R" or "L")
            end
        end
    end
    for _, key in ipairs(order) do
        if not cur[key] then greedy(a, key) end
    end
    improve(a)

    -- Start B: greedy from scratch, role by role.
    local b = newState()
    for _, key in ipairs(order) do greedy(b, key) end
    improve(b)

    local side = less(b.cost, a.cost) and b.side or a.side

    -- Placement inside each half: with a shared group, the players past the
    -- half's own groups go there (those already in it first, then damage
    -- dealers). Healers spread over the half's groups. Everyone else keeps
    -- the current group when it is on the right side and has room, then
    -- groups fill in order.
    local result, sharedSides = {}, {}
    for _, s in ipairs(SIDES) do
        local groups = s == "L" and L or R
        if S then
            local mine = {}
            for _, key in ipairs(order) do
                if side[key] == s then tinsert(mine, key) end
            end
            local over = #mine - #groups * GROUP_SIZE
            if over > 0 then
                table.sort(mine, function(x, y)
                    local sx = current[x] == S and sides[x] == s
                    local sy = current[y] == S and sides[y] == s
                    if sx ~= sy then return sx end
                    local ox, oy = SHARED_ORDER[bucket[x]] or 1, SHARED_ORDER[bucket[y]] or 1
                    if ox ~= oy then return ox < oy end
                    return x < y
                end)
                for i = 1, over do
                    result[mine[i]] = S
                    sharedSides[mine[i]] = s
                end
            end
        end
        local fill, held, idx = {}, {}, {}
        for i, g in ipairs(groups) do
            fill[g], held[g], idx[g] = 0, 0, i
        end

        -- Healers: an even share per group. The groups that already hold the
        -- most get the extra ones, so as few healers as possible move.
        local healers = {}
        for _, key in ipairs(order) do
            if side[key] == s and not result[key] and bucket[key] == "H" then
                tinsert(healers, key)
                local g = current[key]
                if held[g] then held[g] = held[g] + 1 end
            end
        end
        if #healers > 0 and #groups > 0 then
            local byHeld = {}
            for i, g in ipairs(groups) do byHeld[i] = g end
            table.sort(byHeld, function(x, y)
                if held[x] ~= held[y] then return held[x] > held[y] end
                return idx[x] < idx[y]
            end)
            local base, extra = math.floor(#healers / #groups), #healers % #groups
            local quota = {}
            for i, g in ipairs(byHeld) do quota[g] = base + (i <= extra and 1 or 0) end
            local rest = {}
            for _, key in ipairs(healers) do
                local g = current[key]
                if quota[g] and fill[g] < quota[g] then
                    fill[g] = fill[g] + 1
                    result[key] = g
                else
                    tinsert(rest, key)
                end
            end
            for _, key in ipairs(rest) do
                for _, g in ipairs(groups) do
                    if fill[g] < quota[g] then
                        fill[g] = fill[g] + 1
                        result[key] = g
                        break
                    end
                end
            end
        end

        local rest = {}
        for _, key in ipairs(order) do
            if side[key] == s and not result[key] then
                local g = current[key]
                if g and fill[g] and fill[g] < GROUP_SIZE then
                    fill[g] = fill[g] + 1
                    result[key] = g
                else
                    tinsert(rest, key)
                end
            end
        end
        for _, key in ipairs(rest) do
            for _, g in ipairs(groups) do
                if fill[g] < GROUP_SIZE then
                    fill[g] = fill[g] + 1
                    result[key] = g
                    break
                end
            end
        end
    end
    for _, key in ipairs(keys) do
        if not result[key] then result[key] = 0 end
    end
    return result, sharedSides
end

-- Split the board. Bench groups (beyond the halves) are left alone. fresh
-- ignores who earlier splits placed and rebalances everyone.
function Split.Run(board, fresh)
    board = board or ns.Board
    if board:IsSimple() then return 0 end
    local k = board:K()
    local keys = {}
    for _, key in ipairs(board.members) do
        local g = board.draft[key]
        if g <= k then tinsert(keys, key) end
    end
    local L, R = board:Halves()
    local S = board:Shared()
    local settled = board:Settled()
    -- the live side of settled players, to whisper the ones sent across
    local before = {}
    local live = board:Live()
    wipe(board.flipped)
    if live and not fresh and ns.settings.whisperSwitches then
        for _, key in ipairs(keys) do
            local m = live[key]
            if settled[key] and m then
                if m.group == S then
                    before[key] = board.sides[key]
                else
                    before[key] = board:SideOf(m.group)
                end
            end
        end
    end
    wipe(board.ghosts)
    wipe(board.subs)
    wipe(board.tags)
    board.loaded = nil
    local result, sides = Split.Compute({
        keys = keys, info = ns.Players.Get, current = board.draft, L = L, R = R,
        S = S, sides = board.sides, settled = not fresh and settled or nil,
        strictPos = ns.settings.strictPositions,
    })
    for key, g in pairs(result) do board.draft[key] = g end
    for key, s in pairs(sides) do board.sides[key] = s end
    for _, key in ipairs(keys) do
        if board.draft[key] > 0 then settled[key] = true end
        local was = before[key]
        if was then
            local now = board:PlayerSide(key)
            if now and now ~= was then board.flipped[key] = was end
        end
    end
    board:Changed()
    return board:Pending()
end
