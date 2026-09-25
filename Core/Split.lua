-- Auto-split: balance tanks, healers, melee, ranged and classes between the
-- two halves while moving as few players as possible.
local _, ns = ...

local Data = ns.Data

local Split = {}
ns.Split = Split

local GROUP_SIZE = 5
local BUCKETS = { "T", "H", "M", "R", "?" }

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
  Returns key -> group (0 when both halves are full).
]]
function Split.Compute(opts)
    local keys, info, current, L, R = opts.keys, opts.info, opts.current, opts.L, opts.R
    local sideOfGroup = {}
    for _, g in ipairs(L) do sideOfGroup[g] = "L" end
    for _, g in ipairs(R) do sideOfGroup[g] = "R" end
    local cap = { L = #L * GROUP_SIZE, R = #R * GROUP_SIZE }

    local bucket, class, cur = {}, {}, {}
    local freq = {}
    for _, key in ipairs(keys) do
        local i = info(key)
        bucket[key] = i.bucket
        class[key] = i.class or "?"
        cur[key] = sideOfGroup[current[key] or 0]
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

    local cnt = { L = { n = 0, b = {}, c = {} }, R = { n = 0, b = {}, c = {} } }
    for _, s in pairs(cnt) do
        for _, b in ipairs(BUCKETS) do s.b[b] = 0 end
    end

    local side = {}
    for _, key in ipairs(order) do
        local b, c = bucket[key], class[key]
        local best, bestScore
        for _, s in ipairs({ "L", "R" }) do
            local t = cnt[s]
            if t.n < cap[s] then
                -- lexicographic: bucket count, class count, stay on current side, size
                local score = t.b[b] * 1000000 + (t.c[c] or 0) * 10000
                    + ((cur[key] == s) and 0 or 100) + t.n
                if not bestScore or score < bestScore then best, bestScore = s, score end
            end
        end
        if best then
            side[key] = best
            local t = cnt[best]
            t.n = t.n + 1
            t.b[b] = t.b[b] + 1
            t.c[c] = (t.c[c] or 0) + 1
        end
    end

    -- Local search: swap same-bucket pairs across halves when it lowers
    -- class imbalance, or keeps it and saves moves.
    local function moves()
        local m = 0
        for _, key in ipairs(keys) do
            if side[key] and side[key] ~= cur[key] then m = m + 1 end
        end
        return m
    end
    local cost = classCost(cnt) * 100 + moves()
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
                        local newCost = classCost(cnt) * 100 + moves()
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

    -- Placement inside each half: keep the current group when it is on the
    -- right side and has room, then fill groups in order.
    local result = {}
    for _, s in ipairs({ "L", "R" }) do
        local groups = s == "L" and L or R
        local fill = {}
        for _, g in ipairs(groups) do fill[g] = 0 end
        local rest = {}
        for _, key in ipairs(order) do
            if side[key] == s then
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
    return result
end

-- Split the board. Bench groups (beyond the halves) are left alone.
function Split.Run(board)
    board = board or ns.Board
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
    local result = Split.Compute({
        keys = keys, info = ns.Players.Get, current = board.draft, L = L, R = R,
    })
    for key, g in pairs(result) do board.draft[key] = g end
    board:Changed()
    return board:Pending()
end
