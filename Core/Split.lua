-- Auto-split: balance tanks, healers, melee, ranged and classes between the
-- two halves while moving as few players as possible.
local _, ns = ...

local Data = ns.Data

local Split = {}
ns.Split = Split

local GROUP_SIZE = 5
local BUCKETS = { "T", "H", "M", "R", "?" }
-- who goes to the shared group first: damage dealers, ranged before melee
local SHARED_ORDER = { ["?"] = 1, R = 2, M = 3, H = 4, T = 5 }

-- Size and role imbalance between the halves.
local function roleCost(cnt)
    local d = cnt.L.n - cnt.R.n
    local cost = d * d
    for _, b in ipairs(BUCKETS) do
        d = cnt.L.b[b] - cnt.R.b[b]
        cost = cost + d * d
    end
    return cost
end

local function classCost(cnt)
    local cost = 0
    for _, class in ipairs(Data.CLASSES) do
        local d = (cnt.L.c[class] or 0) - (cnt.R.c[class] or 0)
        cost = cost + d * d * (Data.BUFF_CLASSES[class] and 3 or 1)
    end
    return cost
end

--[[ Pure core, used by the board and the tests.
  opts.keys     array of player keys to place
  opts.info     function(key) -> table with .bucket and .class
  opts.current  key -> current group (0 = none)
  opts.L, opts.R arrays of group numbers for each half
  opts.S        shared group, or nil. The halves fill their own groups and
                the rest of each half goes to S with a side of its own.
  opts.sides    key -> "L"|"R", the own side of players currently in S
  Returns key -> group (0 when both halves are full) and key -> side for
  the players placed in S.
]]
function Split.Compute(opts)
    local keys, info, current, L, R, S = opts.keys, opts.info, opts.current, opts.L, opts.R, opts.S
    local sides = opts.sides or {}
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

    local function newCounts()
        local cnt = { L = { n = 0, b = {}, c = {} }, R = { n = 0, b = {}, c = {} } }
        for _, t in pairs(cnt) do
            for _, b in ipairs(BUCKETS) do t.b[b] = 0 end
        end
        return cnt
    end
    local function add(cnt, s, key)
        local t = cnt[s]
        t.n = t.n + 1
        t.b[bucket[key]] = t.b[bucket[key]] + 1
        t.c[class[key]] = (t.c[class[key]] or 0) + 1
    end

    -- Local search: swap same-bucket pairs across halves when it lowers
    -- class imbalance, or keeps it and saves moves. Returns the final cost.
    local function improve(side, cnt)
        local function moves()
            local m = 0
            for _, key in ipairs(keys) do
                if side[key] and side[key] ~= cur[key] then m = m + 1 end
            end
            return m
        end
        local base = roleCost(cnt) * 1000000
        local cost = base + classCost(cnt) * 100 + moves()
        for _ = 1, 50 do
            local improved = false
            for _, a in ipairs(order) do
                if side[a] == "L" then
                    for _, b in ipairs(order) do
                        if side[b] == "R" and bucket[a] == bucket[b] and side[a] == "L" then
                            local ca, cb = class[a], class[b]
                            side[a], side[b] = "R", "L"
                            if ca ~= cb then
                                cnt.L.c[ca] = cnt.L.c[ca] - 1
                                cnt.R.c[ca] = (cnt.R.c[ca] or 0) + 1
                                cnt.R.c[cb] = cnt.R.c[cb] - 1
                                cnt.L.c[cb] = (cnt.L.c[cb] or 0) + 1
                            end
                            local newCost = base + classCost(cnt) * 100 + moves()
                            if newCost < cost then
                                cost = newCost
                                improved = true
                            else
                                side[a], side[b] = "L", "R"
                                if ca ~= cb then
                                    cnt.L.c[ca] = cnt.L.c[ca] + 1
                                    cnt.R.c[ca] = cnt.R.c[ca] - 1
                                    cnt.R.c[cb] = cnt.R.c[cb] + 1
                                    cnt.L.c[cb] = cnt.L.c[cb] - 1
                                end
                            end
                        end
                    end
                end
            end
            if not improved then break end
        end
        return cost
    end

    -- Start 1: greedy, role by role.
    local side, cnt = {}, newCounts()
    local placed = 0
    for _, key in ipairs(order) do
        local b, c = bucket[key], class[key]
        local best, bestScore
        for _, s in ipairs({ "L", "R" }) do
            local t = cnt[s]
            if t.n < cap[s] and placed < limit then
                -- lexicographic: bucket count, class count, stay on current side, size
                local score = t.b[b] * 1000000 + (t.c[c] or 0) * 10000
                    + ((cur[key] == s) and 0 or 100) + t.n
                if not bestScore or score < bestScore then best, bestScore = s, score end
            end
        end
        if best then
            side[key] = best
            placed = placed + 1
            add(cnt, best, key)
        end
    end
    local cost = improve(side, cnt)

    -- Start 2: the current sides, when everyone has one and they fit. A
    -- board that is already balanced then stays as it is.
    local cside, ccnt = {}, newCounts()
    local whole = true
    for _, key in ipairs(keys) do
        local s = cur[key]
        if not s then
            whole = false
            break
        end
        cside[key] = s
        add(ccnt, s, key)
    end
    if whole and ccnt.L.n <= cap.L and ccnt.R.n <= cap.R then
        if improve(cside, ccnt) <= cost then side = cside end
    end

    -- Placement inside each half: with a shared group, the players past the
    -- half's own groups go there (those already in it first, then damage
    -- dealers). Everyone else keeps the current group when it is on the
    -- right side and has room, then groups fill in order.
    local result, sharedSides = {}, {}
    for _, s in ipairs({ "L", "R" }) do
        local groups = s == "L" and L or R
        if S then
            local mine = {}
            for _, key in ipairs(order) do
                if side[key] == s then tinsert(mine, key) end
            end
            local over = #mine - #groups * GROUP_SIZE
            if over > 0 then
                table.sort(mine, function(a, b)
                    local sa = current[a] == S and sides[a] == s
                    local sb = current[b] == S and sides[b] == s
                    if sa ~= sb then return sa end
                    local oa, ob = SHARED_ORDER[bucket[a]] or 1, SHARED_ORDER[bucket[b]] or 1
                    if oa ~= ob then return oa < ob end
                    return a < b
                end)
                for i = 1, over do
                    result[mine[i]] = S
                    sharedSides[mine[i]] = s
                end
            end
        end
        local fill = {}
        for _, g in ipairs(groups) do fill[g] = 0 end
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

-- Split the board. Bench groups (beyond the halves) are left alone.
function Split.Run(board)
    board = board or ns.Board
    if board:IsSimple() then return 0 end
    local k = board:K()
    local keys = {}
    for _, key in ipairs(board.members) do
        local g = board.draft[key]
        if g <= k then tinsert(keys, key) end
    end
    local L, R = board:Halves()
    wipe(board.ghosts)
    wipe(board.subs)
    wipe(board.tags)
    board.loaded = nil
    local result, sides = Split.Compute({
        keys = keys, info = ns.Players.Get, current = board.draft, L = L, R = R,
        S = board:Shared(), sides = board.sides,
    })
    for key, g in pairs(result) do board.draft[key] = g end
    for key, s in pairs(sides) do board.sides[key] = s end
    board:Changed()
    return board:Pending()
end
