-- Unit tests for the Core modules. Run from the repo root:  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local stub = require("wow_stub")

local ns = {}
local CORE = {
    "Core/Init.lua", "Core/Data.lua", "Core/Players.lua", "Core/Raid.lua", "Core/Board.lua",
    "Core/Split.lua", "Core/Loadouts.lua", "Core/Rosters.lua", "Core/Invite.lua", "Core/Apply.lua", "Core/Announce.lua", "Core/Demo.lua",
    "Core/Inspect.lua", "Core/SpecComm.lua", "Core/Serialize.lua", "Core/Comm.lua",
}
for _, path in ipairs(CORE) do
    local chunk = assert(loadfile(path))
    chunk("FastGroups", ns)
end
stub.fire("ADDON_LOADED", "FastGroups")
stub.fire("PLAYER_LOGIN")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local Board, Players = ns.Board, ns.Players

local function occupancyOK()
    for g = 1, 8 do
        if Board:Occupancy(g) > 5 then return false, g end
    end
    return true
end

---------------------------------------------------------------------------
test("halves and remap keep sides", function()
    local L, R = Board.HalvesFor("oddeven", 6)
    eq(table.concat(L, ","), "1,3,5")
    eq(table.concat(R, ","), "2,4,6")
    L, R = Board.HalvesFor("split", 4)
    eq(table.concat(L, ","), "1,2")
    eq(table.concat(R, ","), "3,4")
    for _, k in ipairs({ 2, 4, 6 }) do
        for g = 1, k do
            local s1 = Board.SideOfFor(g, "oddeven", k)
            local g2 = Board.Remap(g, "oddeven", k, "split", k)
            eq(Board.SideOfFor(g2, "split", k), s1, "remap side")
            eq(Board.Remap(g2, "split", k, "oddeven", k), g, "remap back")
        end
    end
    eq(Board.Remap(7, "oddeven", 4, "split", 4), 7, "bench stays")
    eq(Board.Remap(5, "oddeven", 6, "oddeven", 4), 0, "no slot left")
end)

test("demo board loads", function()
    Board:SetSource("demo")
    eq(#Board.members, 20)
    eq(Board:K(), 4)
    eq(Board:Pending(), 0)
    local info = Players.Get("Vexmora-Silvermoon")
    eq(info.bucket, "R", "devourer is ranged")
    eq(Players.Get("Nyxara-Silvermoon").bucket, "T")
    eq(Players.Get("Meilin-Silvermoon").bucket, "H")
end)

test("auto split balances roles and buff classes", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    local L = Board:Counts("L")
    local lT, lH, lM, lR, ln = L.T, L.H, L.M, L.R, L.n
    local lDH, lMonk = L.cls.DEMONHUNTER or 0, L.cls.MONK or 0
    local R = Board:Counts("R")
    eq(ln, 10, "left size")
    eq(R.n, 10, "right size")
    eq(lT, 1, "tanks")
    eq(R.T, 1, "tanks")
    eq(lH, 2, "healers")
    eq(R.H, 2, "healers")
    assert(math.abs(lM - R.M) <= 1, "melee")
    assert(math.abs(lR - R.R) <= 1, "ranged")
    assert(math.abs(lDH - (R.cls.DEMONHUNTER or 0)) <= 1, "demon hunters")
    eq(lMonk, 1, "monks")
    eq(R.cls.MONK, 1, "monks")
    assert(occupancyOK(), "group over capacity")
    for _, key in ipairs(Board.members) do
        local g = Board.draft[key]
        assert(g >= 1 and g <= 4, "placed in active group")
    end
end)

test("auto split is stable", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    ns.Apply:RunDemo()
    eq(Board:Pending(), 0, "applied")
    local moves = ns.Split.Run(Board)
    eq(moves, 0, "second split moves nobody")
end)

test("split converts between conventions without moves on balance", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    local imb = #Board:Imbalances()
    Board:SetConvention("split")
    eq(#Board:Imbalances(), imb, "same balance after convention change")
    Board:SetConvention("oddeven")
end)

---------------------------------------------------------------------------
-- Split.Compute on made-up raids. rows: { key, bucket, class, group }.
local function compute(rows, settled, strict, L, R)
    local keys, info, current = {}, {}, {}
    for i, row in ipairs(rows) do
        keys[i] = row[1]
        info[row[1]] = { bucket = row[2], class = row[3] }
        current[row[1]] = row[4]
    end
    return ns.Split.Compute({
        keys = keys, info = function(k) return info[k] end, current = current,
        L = L or { 1, 3 }, R = R or { 2, 4 }, settled = settled, strictPos = strict,
    })
end

local function sideOf(g) return (g % 2 == 1) and "L" or "R" end

-- per side counts of a result: n, buckets and classes
local function tally(rows, result)
    local c = { L = { n = 0, cls = {} }, R = { n = 0, cls = {} } }
    for _, t in pairs(c) do for _, b in ipairs({ "T", "H", "M", "R" }) do t[b] = 0 end end
    for _, row in ipairs(rows) do
        local t = c[sideOf(result[row[1]])]
        t.n = t.n + 1
        t[row[2]] = t[row[2]] + 1
        t.cls[row[3]] = (t.cls[row[3]] or 0) + 1
    end
    return c.L, c.R
end

-- 20 players, all settled: tanks and healers given, damage dealers from dps
local function settledRaid(dps)
    local rows, settled = {}, {}
    local fixed = { { "T", "WARRIOR" }, { "T", "PALADIN" }, { "H", "PRIEST" }, { "H", "PRIEST" },
        { "H", "DRUID" }, { "H", "DRUID" } }
    -- tanks and healers alternate halves: L gets the odd ones
    for i, f in ipairs(fixed) do
        local key = "f" .. i
        rows[#rows + 1] = { key, f[1], f[2], (i % 2 == 1) and 1 or 2 }
        settled[key] = true
    end
    for i, d in ipairs(dps) do
        local key = "d" .. i
        rows[#rows + 1] = { key, d[1], d[2], d[3] }
        settled[key] = true
    end
    return rows, settled
end

test("pug churn: settled players keep their side", function()
    local seed = 4242
    local function rnd(n)
        seed = (seed * 16807) % 2147483647
        return seed % n + 1
    end
    -- no Monks or Demon Hunters: their coverage rule may move settled players on purpose
    local CLS = { "WARRIOR", "ROGUE", "MAGE", "WARLOCK", "HUNTER", "PRIEST", "SHAMAN", "EVOKER", "DEATHKNIGHT" }
    local rows, settled, n = {}, {}, 0
    local function newRow(bucket, g)
        n = n + 1
        return { "p" .. n, bucket, CLS[rnd(#CLS)], g }
    end
    local roles = { "T", "T", "H", "H", "H", "H" }
    for i = 1, 20 do
        rows[i] = newRow(roles[i] or (rnd(2) == 1 and "M" or "R"), math.floor((i - 1) / 5) + 1)
    end
    local function run()
        local result = compute(rows, settled)
        for _, row in ipairs(rows) do
            row[4] = result[row[1]]
            settled[row[1]] = true
        end
    end
    run()
    for pull = 1, 10 do
        local fresh = {}
        for _ = 1, 2 do
            local i
            repeat i = rnd(#rows) until rows[i][2] == "M" or rows[i][2] == "R"
            settled[rows[i][1]] = nil
            rows[i] = newRow(rnd(2) == 1 and "M" or "R", rows[i][4])
            fresh[rows[i][1]] = true
        end
        local before = {}
        for _, row in ipairs(rows) do before[row[1]] = sideOf(row[4]) end
        run()
        local L, R = tally(rows, (function()
            local r = {}
            for _, row in ipairs(rows) do r[row[1]] = row[4] end
            return r
        end)())
        eq(L.n, R.n, "pull " .. pull .. ": sizes")
        eq(L.T, R.T, "pull " .. pull .. ": tanks")
        eq(L.H, R.H, "pull " .. pull .. ": healers")
        for _, row in ipairs(rows) do
            if not fresh[row[1]] then eq(sideOf(row[4]), before[row[1]], "pull " .. pull .. ": " .. row[1]) end
        end
    end
end)

test("a forced healer crossing moves one settled healer", function()
    -- build a balanced raid by hand: L = groups 1, 3; R = groups 2, 4
    local rows, settled = settledRaid({})
    local fill = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    for _, row in ipairs(rows) do fill[row[4]] = fill[row[4]] + 1 end
    for i = 1, 14 do
        local g = (i <= 7) and ((fill[1] < 5) and 1 or 3) or ((fill[2] < 5) and 2 or 4)
        fill[g] = fill[g] + 1
        local key = "d" .. i
        rows[#rows + 1] = { key, (i % 2 == 0) and "M" or "R", "MAGE", g }
        settled[key] = true
    end
    local result = compute(rows, settled)
    for _, row in ipairs(rows) do eq(sideOf(result[row[1]]), sideOf(row[4]), "balanced raid stays: " .. row[1]) end
    -- both healers on the left leave; two new damage dealers take their slots
    local newRows = {}
    for _, row in ipairs(rows) do
        if row[2] == "H" and sideOf(row[4]) == "L" then
            newRows[#newRows + 1] = { "new" .. row[1], "R", "MAGE", row[4] }
        else
            newRows[#newRows + 1] = row
        end
    end
    result = compute(newRows, settled)
    local L, R = tally(newRows, result)
    eq(L.H, 1) eq(R.H, 1)
    eq(L.n, R.n, "sizes")
    local crossed = {}
    for _, row in ipairs(newRows) do
        if sideOf(result[row[1]]) ~= sideOf(row[4]) then crossed[#crossed + 1] = row end
    end
    eq(#crossed, 2, "a healer and a damage dealer swap")
    local settledCrossed = 0
    for _, row in ipairs(crossed) do
        if settled[row[1]] then
            settledCrossed = settledCrossed + 1
            eq(row[2], "H", "the settled one is the healer")
        end
    end
    eq(settledCrossed, 1)
end)

test("melee and ranged: soft by default, strict on request, free on a fresh split", function()
    -- L: tanks, healers and 7 melee; R: tanks, healers and 7 ranged
    local rows, settled = settledRaid({})
    local fill = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    for _, row in ipairs(rows) do fill[row[4]] = fill[row[4]] + 1 end
    for i = 1, 14 do
        local left = i <= 7
        local g = left and ((fill[1] < 5) and 1 or 3) or ((fill[2] < 5) and 2 or 4)
        fill[g] = fill[g] + 1
        rows[#rows + 1] = { "d" .. i, left and "M" or "R", "MAGE", g }
        settled["d" .. i] = true
    end
    local result = compute(rows, settled, false)
    for _, row in ipairs(rows) do eq(sideOf(result[row[1]]), sideOf(row[4]), "settled players stay: " .. row[1]) end
    for _, run in ipairs({ { settled, true }, { nil, false } }) do
        result = compute(rows, run[1], run[2])
        local L, R = tally(rows, result)
        assert(math.abs(L.M - R.M) <= 1 and math.abs(L.R - R.R) <= 1, "melee/ranged even")
        eq(L.T, R.T) eq(L.H, R.H) eq(L.n, R.n)
    end
end)

test("settled monks split over both halves", function()
    local rows, settled = settledRaid({})
    local fill = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    for _, row in ipairs(rows) do fill[row[4]] = fill[row[4]] + 1 end
    for i = 1, 14 do
        local left = i <= 7
        local g = left and ((fill[1] < 5) and 1 or 3) or ((fill[2] < 5) and 2 or 4)
        fill[g] = fill[g] + 1
        -- two monks, both on the right
        rows[#rows + 1] = { "d" .. i, (i % 2 == 0) and "M" or "R", (i == 8 or i == 9) and "MONK" or "MAGE", g }
        settled["d" .. i] = true
    end
    local result = compute(rows, settled)
    local L, R = tally(rows, result)
    eq(L.cls.MONK, 1) eq(R.cls.MONK, 1)
    eq(L.n, R.n)
end)

test("healers spread over the groups of a half", function()
    -- L (1, 3): both healers and a tank in group 1, group 3 full of damage dealers
    local rows = {
        { "t1", "T", "WARRIOR", 1 }, { "h1", "H", "PRIEST", 1 }, { "h2", "H", "DRUID", 1 },
        { "a1", "M", "ROGUE", 1 }, { "a2", "R", "MAGE", 1 },
        { "a3", "M", "ROGUE", 3 }, { "a4", "R", "MAGE", 3 }, { "a5", "M", "ROGUE", 3 },
        { "a6", "R", "MAGE", 3 }, { "a7", "R", "MAGE", 3 },
        { "t2", "T", "WARRIOR", 2 }, { "h3", "H", "PRIEST", 2 }, { "b1", "M", "ROGUE", 2 },
        { "b2", "R", "MAGE", 2 }, { "b3", "M", "ROGUE", 2 },
        { "h4", "H", "DRUID", 4 }, { "b4", "R", "MAGE", 4 }, { "b5", "M", "ROGUE", 4 },
        { "b6", "R", "MAGE", 4 }, { "b7", "R", "MAGE", 4 },
    }
    local all = {}
    for _, row in ipairs(rows) do all[row[1]] = true end
    local result = compute(rows, all)
    local inG = { [1] = 0, [3] = 0 }
    for _, h in ipairs({ "h1", "h2" }) do inG[result[h]] = (inG[result[h]] or 0) + 1 end
    eq(inG[1], 1, "one healer in group 1")
    eq(inG[3], 1, "one healer in group 3")
    local moves = 0
    for _, row in ipairs(rows) do
        eq(sideOf(result[row[1]]), sideOf(row[4]), "nobody changes side: " .. row[1])
        if result[row[1]] ~= row[4] then moves = moves + 1 end
    end
    eq(moves, 2, "a healer and a damage dealer swap groups")
    -- stable: a second split moves nobody
    for _, row in ipairs(rows) do row[4] = result[row[1]] end
    local again = compute(rows, all)
    for _, row in ipairs(rows) do eq(again[row[1]], row[4], "second split: " .. row[1]) end

    -- six groups: three healers of the left half all in group 1 end up 1/1/1
    rows = {}
    for i = 1, 30 do
        local g = math.floor((i - 1) / 5) + 1
        local bucket = (i == 1 or i == 2 or i == 3) and "H" or (i == 6 or i == 7 or i == 8) and "H" or "R"
        rows[i] = { "p" .. i, bucket, "MAGE", g }
    end
    result = compute(rows, nil, false, { 1, 3, 5 }, { 2, 4, 6 })
    local per = {}
    for _, row in ipairs(rows) do
        if row[2] == "H" then per[result[row[1]]] = (per[result[row[1]]] or 0) + 1 end
    end
    for g = 1, 6 do eq(per[g], 1, "healers in group " .. g) end
end)

test("settled players: marked by a split, dropped when they leave or the raid ends", function()
    Board:SetSource("demo")
    local settled = Board:Settled()
    assert(settled ~= ns.db.settled, "the demo does not touch the saved list")
    eq(next(settled), nil, "nobody settled on a new board")
    ns.Split.Run(Board)
    for _, key in ipairs(Board.members) do assert(settled[key], key .. " settled") end
    local gone = Board.members[5]
    ns.Demo:Remove(gone)
    eq(settled[gone], nil, "a leaver is forgotten")
    eq(next(ns.db.settled), nil, "saved list untouched")
    ns.db.settled["Someone-Silvermoon"] = true
    stub.inRaid = false
    Board:AutoSource()
    eq(next(ns.db.settled), nil, "out of a raid: saved list wiped")
end)

test("whispers for a forced crossing", function()
    local printed = {}
    local add = DEFAULT_CHAT_FRAME.AddMessage
    DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) printed[#printed + 1] = msg end
    Board:SetSource("demo")
    ns.Split.Run(Board)
    ns.Apply:RunDemo()
    eq(next(Board.flipped), nil, "the first split whispers nobody")
    -- both healers on the left leave
    local leftHealers = {}
    for _, key in ipairs(Board.members) do
        if Players.Get(key).bucket == "H" and Board:PlayerSide(key) == "L" then tinsert(leftHealers, key) end
    end
    eq(#leftHealers, 2)
    for _, key in ipairs(leftHealers) do ns.Demo:Remove(key) end
    ns.Split.Run(Board)
    local flipped = {}
    for key, was in pairs(Board.flipped) do
        flipped[#flipped + 1] = key
        eq(was, "R")
    end
    eq(#flipped, 1, "one forced crossing")
    local key = flipped[1]
    eq(Players.Get(key).bucket, "H")
    local list = ns.Announce.Whispers(Board)
    eq(#list, 1)
    eq(ns.Announce.WhisperText(list[1]), "Your group has changed to " .. Board.draft[key] .. " (Left).")
    -- dragged back before Apply: no whisper
    local g = Board.draft[key]
    Board.draft[key] = Board.lastLive[key]
    eq(#ns.Announce.Whispers(Board), 0, "dragged back")
    Board.draft[key] = g
    wipe(printed)
    ns.Apply:RunDemo()
    eq(#printed, 1)
    assert(printed[1]:find("Demo, not sent: whisper to " .. Players.ShortName(key), 1, true), printed[1])
    eq(next(Board.flipped), nil, "whispered once")
    wipe(printed)
    ns.Apply:RunDemo()
    eq(#printed, 0, "no second whisper")

    -- more than three at once: none, one local line
    for _, k in ipairs(Board.members) do
        if Board:PlayerSide(k) and not Board:IsOffline(k) then
            Board.flipped[k] = Board:PlayerSide(k) == "L" and "R" or "L"
        end
    end
    local list2, n = ns.Announce.Whispers(Board)
    eq(#list2, 0) assert(n > 3)
    wipe(printed)
    ns.Announce.SendWhispers()
    eq(#printed, 1)
    assert(printed[1]:find("switched halves; no whispers sent", 1, true), printed[1])

    -- offline players get nothing
    local off
    for _, k in ipairs(Board.members) do if Board:IsOffline(k) then off = k end end
    Board.flipped[off] = Board:PlayerSide(off) == "L" and "R" or "L"
    eq(#ns.Announce.Whispers(Board), 0, "offline")
    wipe(Board.flipped)

    -- live raid: a real whisper to Name-Realm
    stub.chat = {}
    Board.source = "live"
    local saved = ns.Raid.members
    ns.Raid.members = ns.Demo.members
    Board.flipped[key] = "R"
    ns.Announce.SendWhispers()
    eq(#stub.chat, 1)
    eq(stub.chat[1][2], "WHISPER")
    eq(stub.chat[1][3], key)
    ns.Raid.members = saved
    Board.source = "demo"

    -- a fresh split and the setting off record nothing
    Board:SetSource("demo")
    ns.Split.Run(Board)
    ns.Apply:RunDemo()
    for _, k in ipairs(leftHealers) do ns.Demo:Remove(k) end
    ns.Split.Run(Board, true)
    eq(next(Board.flipped), nil, "fresh split")
    Board:SetSource("demo")
    ns.Split.Run(Board)
    ns.Apply:RunDemo()
    for _, k in ipairs(Board.members) do
        if Players.Get(k).bucket == "H" and Board:PlayerSide(k) == "L" then ns.Demo:Remove(k) end
    end
    ns.settings.whisperSwitches = false
    ns.Split.Run(Board)
    eq(next(Board.flipped), nil, "setting off")
    ns.settings.whisperSwitches = true
    DEFAULT_CHAT_FRAME.AddMessage = add
    Board:SetSource("demo")
end)

---------------------------------------------------------------------------
local function simulate(members, target)
    local steps = 0
    while true do
        local op, why = ns.Apply.NextMove(members, target)
        if not op then return steps, why end
        steps = steps + 1
        if steps > 200 then return steps, "loop" end
        if op.kind == "set" then
            local n = 0
            for _, m in ipairs(members) do if m.group == op.group then n = n + 1 end end
            assert(n < 5, "set into full group")
            op.a.group = op.group
        else
            assert(op.a.group ~= op.b.group, "swap inside one group")
            op.a.group, op.b.group = op.b.group, op.a.group
        end
    end
end

test("apply planner converges on random raids", function()
    for trial = 1, 400 do
        local n = math.random(5, 40)
        local members, target, fill = {}, {}, {}
        for g = 1, 8 do fill[g] = 0 end
        -- random live layout respecting capacity
        for i = 1, n do
            local g
            repeat g = math.random(1, 8) until fill[g] < 5
            fill[g] = fill[g] + 1
            members[i] = { key = "p" .. i, index = i, group = g }
        end
        -- random valid target, some players left alone (0)
        local tfill = {}
        for g = 1, 8 do tfill[g] = 0 end
        for i = 1, n do
            if math.random() < 0.15 then
                target["p" .. i] = 0
            else
                local g
                repeat g = math.random(1, 8) until tfill[g] < 5
                tfill[g] = tfill[g] + 1
                target["p" .. i] = g
            end
        end
        local steps, why = simulate(members, target)
        assert(why == nil, "trial " .. trial .. " ended with " .. tostring(why))
        assert(steps <= n, "too many steps: " .. steps .. " for " .. n)
        for _, m in ipairs(members) do
            local t = target[m.key]
            if t ~= 0 then eq(m.group, t, "final group") end
        end
    end
end)

test("apply planner skips busy players", function()
    local members = {
        { key = "a", index = 1, group = 1, busy = true },
        { key = "b", index = 2, group = 2 },
    }
    local op, why = ns.Apply.NextMove(members, { a = 2, b = 2 })
    eq(op, nil)
    eq(why, "busy")
end)

---------------------------------------------------------------------------
test("loadout reconcile and auto-fill", function()
    Board:SetSource("demo")
    local sample
    for _, lo in ipairs(ns.Loadouts.List()) do
        if lo.name == "[Demo] Last week" then sample = lo end
    end
    assert(sample, "demo sample exists")
    ns.Loadouts.Load(sample.id)
    local l = Board.loaded
    eq(l.present, 17)
    eq(l.absent, 3)
    eq(l.fresh, 2)
    eq(l.returning, 1)
    eq(#Board.ghosts, 3)
    eq(Board.tags["Kaelith-Silvermoon"], "ret")
    local placed = Board:AutoFill()
    eq(placed, 3)
    eq(#Board.ghosts, 0)
    eq(Board:SideOf(Board.draft["Kaelith-Silvermoon"]), "R", "returning player keeps side")
    eq(Board.subs["Ysolde-Silvermoon"], "Selvyn-Silvermoon", "warlock replaces warlock")
    assert(occupancyOK())
end)

test("save and reload a loadout", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    local lo = ns.Loadouts.SaveCurrent("Test save")
    eq(ns.Loadouts.Count(lo), 20)
    local snapshot = {}
    for k, v in pairs(Board.draft) do snapshot[k] = v end
    Board:Revert()
    ns.Loadouts.Load(lo.id)
    for k, v in pairs(snapshot) do eq(Board.draft[k], v, k) end
    eq(#Board.ghosts, 0)
    -- loading into the other convention keeps sides
    Board:SetConvention("split")
    ns.Loadouts.Load(lo.id)
    for k, v in pairs(snapshot) do
        eq(Board:SideOf(Board.draft[k]), Board.SideOfFor(v, "oddeven", 4), k)
    end
    Board:SetConvention("oddeven")
    ns.Loadouts.Delete(lo.id)
end)

test("sync follows live moves and drops leavers", function()
    Board:SetSource("demo")
    local key = "Thalric-Silvermoon"
    Board:Move("Arrowyn-Silvermoon", 1)   -- group 1 is full: rejected
    eq(Board.draft["Arrowyn-Silvermoon"], 4)
    ns.Demo.members[key].group = 2        -- someone else moved Thalric
    ns.Demo.members["Solenne-Silvermoon"].group = 1
    Board:Sync()
    eq(Board.draft[key], 2, "unedited player follows live")
    ns.Demo.members["Aurelia-Silvermoon"] = nil
    Board:Sync()
    eq(Board.isMember["Aurelia-Silvermoon"], nil)
end)

test("live board picks up joiners and leavers on roster events", function()
    local roster = {
        { "Alpha", 1, "WARRIOR" }, { "Bravo", 1, "PRIEST" }, { "Charlie", 2, "MAGE" },
    }
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], 0, r[2], 80, r[3], r[3], "", true, false, "", false, "DAMAGER" end
    end
    stub.inRaid = true
    Board:SetSource("none")
    Board:AutoSource()
    eq(Board.source, "live")
    eq(#Board.members, 3)
    local fired = 0
    ns.On("BOARD_CHANGED", "test", function() fired = fired + 1 end)
    Board:AutoSource()
    eq(fired, 0, "unchanged roster does not redraw")
    roster[4] = { "Delta", 2, "ROGUE" }
    Board:AutoSource()
    eq(fired, 1)
    eq(Board.draft["Delta-Silvermoon"], 2, "joiner placed in live group")
    table.remove(roster, 1)
    Board:AutoSource()
    eq(Board.isMember["Alpha-Silvermoon"], nil, "leaver removed")
    eq(#Board.members, 3)
    ns.On("BOARD_CHANGED", "test", nil)
    GetRaidRosterInfo = saved
    stub.inRaid = false
    Board:AutoSource()
    eq(Board.source, "none")
end)

test("an absent loadout player who joins takes their own slot back", function()
    local roster = { { "Alpha", 1, "WARRIOR" }, { "Bravo", 1, "PRIEST" }, { "Delta", 2, "ROGUE" } }
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], 0, r[2], 80, r[3], r[3], "", true, false, "", false, "DAMAGER" end
    end
    stub.inRaid = true
    Board:SetSource("live")
    Board.draft["Delta-Silvermoon"] = 3
    local lo = ns.Loadouts.SaveCurrent("Reclaim")
    table.remove(roster, 3)
    Board:AutoSource()
    ns.Loadouts.Load(lo.id)
    eq(#Board.ghosts, 1, "Delta absent")
    eq(Board.loaded.present, 2)
    roster[3] = { "Delta", 2, "ROGUE" }
    Board:AutoSource()
    eq(#Board.ghosts, 0, "ghost gone")
    eq(Board.draft["Delta-Silvermoon"], 3, "back in the planned group, not waiting")
    eq(Board.tags["Delta-Silvermoon"], nil, "not tagged new")
    eq(Board.loaded.present, 3)
    roster[4] = { "Echo", 1, "MAGE" }
    Board:AutoSource()
    eq(Board.draft["Echo-Silvermoon"], 0, "someone else still waits")
    ns.Loadouts.Delete(lo.id)
    GetRaidRosterInfo = saved
    stub.inRaid = false
    Board:AutoSource()
end)

test("rank changes redraw and promotions use the roster name", function()
    local roster = { { "Alpha", 2 }, { "Bravo-Stormrage", 0 } }
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], r[2], 1, 80, "MAGE", "MAGE", "", true, false, "", false, "DAMAGER" end
    end
    stub.inRaid = true
    Board:SetSource("live")
    local fired = 0
    ns.On("BOARD_CHANGED", "test", function() fired = fired + 1 end)
    roster[2][2] = 1
    Board:AutoSource()
    eq(fired, 1, "rank change redraws")
    eq(ns.Raid.members["Bravo-Stormrage"].rank, 1)
    ns.Raid:SetRank("Bravo-Stormrage", 2)
    eq(stub.promoted[1], "Bravo-Stormrage")
    eq(stub.promoted[2], 2)
    ns.Raid:SetRank("Alpha-Silvermoon", 0)
    eq(stub.promoted[1], "Alpha", "same realm players go by their roster name")
    ns.On("BOARD_CHANGED", "test", nil)
    GetRaidRosterInfo = saved
    stub.inRaid = false
    Board:SetSource("none")
end)

test("offline members, remove rules and uninvite by roster name", function()
    local roster = { { "Alpha", 2, true }, { "Bravo-Stormrage", 1, true }, { "Charlie", 0, false } }
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], r[2], 6, 80, "MAGE", "MAGE", "", r[3], false, "", false, "DAMAGER" end
    end
    stub.inRaid = true
    Board:SetSource("live")
    eq(Board:IsOffline("Charlie-Silvermoon"), true)
    eq(Board:IsOffline("Alpha-Silvermoon"), false)
    local fired = 0
    ns.On("BOARD_CHANGED", "test", function() fired = fired + 1 end)
    roster[3][3] = true
    Board:AutoSource()
    eq(fired, 1, "coming back online redraws")
    eq(Board:IsOffline("Charlie-Silvermoon"), false)
    ns.On("BOARD_CHANGED", "test", nil)
    local keys = {}
    Board:BenchKeys(keys)
    eq(#keys, 3, "group 6 is bench on a 4 group board")
    local R = ns.Raid.CanRemoveRank
    eq(R("leader", 1, false), true)
    eq(R("leader", 2, true), false, "leader cannot remove themselves")
    eq(R("assist", 0, false), true)
    eq(R("assist", 1, false), false, "assistant cannot remove another assistant")
    eq(R("assist", 2, false), false)
    eq(R("member", 0, false), false)
    ns.Raid:Remove("Charlie-Silvermoon")
    eq(stub.uninvited[#stub.uninvited], "Charlie", "same realm players go by their roster name")
    GetRaidRosterInfo = saved
    stub.inRaid = false
    Board:SetSource("none")
end)

test("apply skips fighting players in instances and never waits on a refused move", function()
    local roster = { { "Alpha", 1 }, { "Bravo", 1 }, { "Charlie", 2 }, { "Delta", 3 } }
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], 0, r[2], 80, "MAGE", "MAGE", "", true, false, "", false, "DAMAGER" end
    end
    local function move(i, g) roster[i][2] = g end
    stub.inRaid = true
    Board:SetSource("live")
    Board:Move("Alpha-Silvermoon", 2)
    local Apply = ns.Apply
    local state
    ns.On("APPLY_STATE", "test", function(_, ok, reason) state = { ok, reason } end)

    stub.encounter = true
    local ok, why = Apply:Start()
    eq(ok, false)
    assert(why:find("boss encounter"), why)
    stub.encounter = nil
    stub.combat.player = true
    ok, why = Apply:Start()
    eq(ok, false)
    assert(why:find("You are in combat"), why)
    stub.instance = true
    stub.combat = { raid1 = true }
    ok, why = Apply:Start()
    eq(ok, false)
    assert(why:find("Alpha"), why)
    eq(#stub.moves, 0, "nothing moved while refused")
    eq(Apply.running, false)

    -- players who stay put may fight
    stub.combat = { raid3 = true }
    ok = Apply:Start()
    eq(ok, true)
    eq(#stub.moves, 1)
    eq(stub.moves[1][1], "set")
    -- out of combat on our side, but the server refuses: no roster update
    stub.fire("UI_ERROR_MESSAGE", 0, "Some other error")
    eq(Apply.running, true, "other errors are ignored")
    stub.fire("UI_ERROR_MESSAGE", 0, ERR_GROUP_SWAP_FAILED)
    eq(Apply.running, false, "replanned instead of waiting")
    eq(state[2], "busy")
    eq(#stub.moves, 1, "the refused move is not retried")

    -- open world: fighting players are moved
    stub.instance = nil
    stub.combat = { raid1 = true }
    Board:Move("Delta-Silvermoon", 2)
    ok = Apply:Start()
    eq(ok, true)
    eq(#stub.moves, 2)
    move(stub.moves[2][2], stub.moves[2][3])
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(#stub.moves, 3, "next move after the server confirmed")
    stub.fire("ENCOUNTER_START", 1, "Boss", 16, 20)
    eq(Apply.running, false)
    eq(state[2], "encounter")
    Board:Move("Bravo-Silvermoon", 3)
    ok = Apply:Start()
    eq(ok, true)
    eq(#stub.moves, 4)
    stub.combat.player = true
    stub.fire("PLAYER_REGEN_DISABLED")
    eq(Apply.running, false)
    eq(state[2], "combat")
    stub.fire("UI_ERROR_MESSAGE", 0, ERR_GROUP_SWAP_FAILED)
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(#stub.moves, 4, "events unregistered after stop")

    ns.On("APPLY_STATE", "test", nil)
    stub.moves, stub.combat = {}, {}
    GetRaidRosterInfo = saved
    stub.inRaid = false
    Board:SetSource("none")
end)

---------------------------------------------------------------------------
test("inspect queue paces, retries and rechecks ambiguous specs", function()
    local Inspect = ns.Inspect
    local roster = {
        { "Tanky", "WARRIOR", "TANK" },     -- raid1: spec unknown
        { "Shammy", "SHAMAN", "DAMAGER" },  -- raid2: saved Elemental, Enhancement is also dps
        { "Retty", "PALADIN", "DAMAGER" },  -- raid3: saved Retribution, the only dps spec
        { "Farry", "MAGE", "DAMAGER" },     -- raid4: spec unknown, out of range
    }
    local savedRoster, savedSpec = GetRaidRosterInfo, C_SpecializationInfo.GetInspectSpecialization
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], 0, 1, 80, r[2], r[2], "", true, false, "", false, r[3] end
    end
    local specs = { raid1 = 73, raid2 = 263, raid3 = 65 }
    C_SpecializationInfo.GetInspectSpecialization = function(u) return specs[u] or 0 end
    stub.inRaid = true
    stub.farAway = { raid4 = true }
    Players.SetSpec("Shammy-Silvermoon", 262)
    Players.SetSpec("Retty-Silvermoon", 70)
    Board:AutoSource()
    eq(Players.Get("Shammy-Silvermoon").recheck, true, "shared role is rechecked")
    eq(Players.Get("Retty-Silvermoon").recheck, false, "the role vouches for Retribution")
    stub.inspected, stub.timers = {}, {}

    Inspect:SetActive(true)
    eq(#stub.inspected, 1, "one request")
    eq(stub.inspected[1], "raid1", "unknown spec first")
    Inspect:Kick()
    eq(#stub.inspected, 1, "nothing more while one is pending")
    stub.fire("INSPECT_READY", "GUID-raid1")
    eq(Players.Get("Tanky-Silvermoon").spec, 73)
    eq(#stub.inspected, 1, "waits before the next request")
    stub.runTimers()
    eq(stub.inspected[2], "raid2", "then the saved spec worth a check")

    -- lost requests time out, are retried, then wait for an event
    stub.runTimers()
    stub.runTimers()
    stub.runTimers()
    eq(#stub.inspected, 4, "three tries")
    eq(stub.inspected[4], "raid2")
    Inspect:Kick("Shammy-Silvermoon")
    eq(#stub.inspected, 5, "hovering asks again")
    stub.fire("INSPECT_READY", "GUID-raid2")
    local info = Players.Get("Shammy-Silvermoon")
    eq(info.spec, 263)
    eq(info.pos, "M", "Enhancement is melee")
    eq(info.recheck, false)
    stub.runTimers()
    eq(#stub.inspected, 5, "nothing left to ask")
    for _, u in ipairs(stub.inspected) do
        if u == "raid3" or u == "raid4" then error("asked about " .. u) end
    end

    -- a new window session checks ambiguous saved specs again, but not the tank
    Inspect:SetActive(false)
    Inspect:SetActive(true)
    eq(#stub.inspected, 6)
    eq(stub.inspected[6], "raid2")
    eq(Players.Get("Tanky-Silvermoon").recheck, false)

    -- a spec change jumps the queue once the current request is answered
    stub.fire("PLAYER_SPECIALIZATION_CHANGED", "raid3")
    eq(Players.Get("Retty-Silvermoon").needsInspect, true)
    eq(Players.Get("Retty-Silvermoon").spec, 70, "old spec shown until read")
    stub.fire("INSPECT_READY", "GUID-raid2")
    stub.runTimers()
    eq(stub.inspected[7], "raid3")
    stub.fire("INSPECT_READY", "GUID-raid3")
    eq(Players.Get("Retty-Silvermoon").spec, 65, "a fresh inspect beats the raid role")

    -- a role change sends the player back to the queue
    roster[1][3] = "DAMAGER"
    Board:AutoSource()
    eq(Players.Get("Tanky-Silvermoon").needsInspect, true)

    Inspect:SetActive(false)
    GetRaidRosterInfo, C_SpecializationInfo.GetInspectSpecialization = savedRoster, savedSpec
    stub.inRaid, stub.farAway = false, nil
    Board:AutoSource()
    wipe(Players.checked)
end)

test("LibSpecialization broadcasts confirm specs; one request per group", function()
    stub.inRaid = true
    local key = "Demony-Silvermoon"
    stub.fire("CHAT_MSG_ADDON", "LibSpec", "577,BAAAAAAA", "RAID", key)
    eq(Players.Get(key).spec, 577, "heard while listening from login")
    eq(Players.checked[key], "comm")
    ns.SpecComm.OnMessage("LibSpec", "1480,", "PARTY", key)
    ns.SpecComm.OnMessage("LibSpec", "9999,x", "RAID", key)
    ns.SpecComm.OnMessage("LibSpec", "R", "RAID", key)
    ns.SpecComm.OnMessage("FastGroups", "1480,", "RAID", key)
    eq(Players.Get(key).spec, 577, "junk ignored")
    ns.SpecComm.OnMessage("LibSpec", "1480,", "RAID", key)
    eq(Players.Get(key).pos, "R", "Devourer is ranged")
    Players.ForgetChecked("inspect")
    eq(Players.Get(key).recheck, false, "broadcasts stay valid across window sessions")

    stub.sent = {}
    ns.SpecComm.requested = false
    ns.SpecComm.Request()
    ns.SpecComm.Request()
    eq(#stub.sent, 1, "one request")
    eq(stub.sent[1][1], "LibSpec")
    eq(stub.sent[1][2], "R")
    eq(stub.sent[1][3], "RAID")
    stub.fire("GROUP_FORMED")
    ns.SpecComm.Request()
    eq(#stub.sent, 2, "again in a new group")
    stub.inRaid = false
    wipe(Players.checked)
end)

---------------------------------------------------------------------------
test("serialize round trip and rejects junk", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    local lo = ns.Loadouts.SaveCurrent("Round trip")
    local str = ns.Serialize.Encode(ns.Serialize.BuildPayload({ lo }, true))
    assert(str:sub(1, 5) == "!FG1!")
    local payload = assert(ns.Serialize.Decode("  " .. str .. "\n"))
    local read = ns.Serialize.ReadPayload(payload)
    eq(#read.loadouts, 1)
    eq(read.loadouts[1].name, "Round trip")
    eq(read.loadouts[1].groups["Thalric-Silvermoon"], lo.groups["Thalric-Silvermoon"])
    assert(read.settings and read.settings.conv == "oddeven")
    assert(not ns.Serialize.Decode("hello"))
    assert(not ns.Serialize.Decode("!FG1!@@@@"))
    local bad = ns.Loadouts.FromExport({ n = "x", g = { ["NoRealm"] = 1, ["A-B"] = 9 } })
    eq(bad, nil, "invalid groups rejected")
    ns.Loadouts.Delete(lo.id)
end)

test("comm chunks, offer, accept and import", function()
    local parts = ns.Comm.Chunk(string.rep("x", 500), 230)
    eq(#parts, 3)
    eq(#parts[3], 40)
    local p = ns.Comm.Split("C\tab12\t3\tda\tta")
    eq(p[1], "C")
    eq(p[3], "3")
    eq(p[4], "da\tta")

    Board:SetSource("demo")
    ns.Split.Run(Board)
    local lo = ns.Loadouts.SaveCurrent("Shared")
    local data = ns.Serialize.Encode(ns.Serialize.BuildPayload({ lo }))
    ns.Loadouts.Delete(lo.id)
    local before = #ns.Loadouts.List()

    -- we are the receiver; the sender is trusted so no popup
    ns.db.trusted["Leader-Silvermoon"] = true
    local chunks = ns.Comm.Chunk(data)
    stub.sent = {}
    ns.Comm.OnMessage("FastGroups", "O\tbeef\t" .. #chunks .. "\t1 loadout", "RAID", "Leader-Silvermoon")
    eq(stub.sent[1][2], "A\tbeef", "accept whispered")
    eq(stub.sent[1][4], "Leader-Silvermoon")
    for i = #chunks, 1, -1 do   -- out of order on purpose
        ns.Comm.OnMessage("FastGroups", "C\tbeef\t" .. i .. "\t" .. chunks[i], "WHISPER", "Leader-Silvermoon")
    end
    eq(#ns.Loadouts.List(), before + 1, "imported")
    eq(ns.Loadouts.List()[1].name, "Shared")

    -- as the sender: an accept makes us whisper every chunk
    stub.sent = {}
    assert(ns.Comm.Offer("GUILD", nil, data, "1 loadout"))
    local offer = ns.Comm.Split(stub.sent[1][2])
    eq(offer[1], "O")
    ns.Comm.OnMessage("FastGroups", "A\t" .. offer[2], "WHISPER", "Friend-Silvermoon")
    eq(#stub.sent, 1 + #chunks, "chunks sent")
    eq(stub.sent[2][3], "WHISPER")
end)

---------------------------------------------------------------------------
-- Shared odd group
---------------------------------------------------------------------------
local function sharedDemo(n)
    ns.settings.sharedGroup = true
    ns.Demo:SetSize(n)
    Board:SetSource("demo")
end

local function sharedDone()
    ns.settings.sharedGroup = false
    ns.settings.announceWhat = "shared"
    ns.Demo:SetSize(nil)
    Board:SetSource("demo")
end

test("odd k leaves the last group shared", function()
    local L, R = Board.HalvesFor("oddeven", 3)
    eq(table.concat(L, ","), "1")
    eq(table.concat(R, ","), "2")
    L, R = Board.HalvesFor("split", 5)
    eq(table.concat(L, ","), "1,2")
    eq(table.concat(R, ","), "3,4")
    eq(Board.SharedOf(5), 5)
    eq(Board.SharedOf(4), nil)
    eq(Board.SideOfFor(3, "oddeven", 3), nil, "shared group has no side of its own")
    -- past the end of a half -> shared, keeping the side; and back
    local g, side = Board.Remap(3, "oddeven", 4, "oddeven", 3)
    eq(g, 3) eq(side, "L")
    g, side = Board.Remap(4, "oddeven", 4, "oddeven", 3)
    eq(g, 3) eq(side, "R")
    eq(Board.Remap(3, "oddeven", 3, "oddeven", 4, "L"), 3)
    eq(Board.Remap(3, "oddeven", 3, "oddeven", 4, "R"), 4)
    g, side = Board.Remap(5, "oddeven", 5, "split", 5, "R")
    eq(g, 5) eq(side, "R")
    eq(Board.Remap(1, "oddeven", 5, "split", 5), 1)
    eq(Board.Remap(3, "oddeven", 5, "split", 5), 2)
end)

test("shared layout only for 11-15 and 21-25 outside Mythic", function()
    sharedDemo(13)
    eq(Board:K(), 3)
    eq(Board:Shared(), 3)
    sharedDemo(17)
    eq(Board:K(), 4)
    eq(Board:Shared(), nil)
    sharedDemo(23)
    eq(Board:K(), 5)
    ns.settings.groupsMode = 6
    eq(Board:K(), 5, "shared layout wins over a fixed count")
    ns.settings.groupsMode = "auto"
    sharedDemo(nil)
    eq(#Board.members, 20)
    eq(Board:K(), 4, "never on Mythic")
    ns.settings.sharedGroup = false
    ns.Demo:SetSize(13)
    Board:SetSource("demo")
    eq(Board:K(), 4, "off by default")
    sharedDone()
end)

test("auto split fills the halves and splits the shared group", function()
    for _, n in ipairs({ 11, 13, 15, 21, 23, 25 }) do
        sharedDemo(n)
        ns.Split.Run(Board)
        local k, S = Board:K(), Board:Shared()
        local L, R = Board:Halves()
        for _, list in ipairs({ L, R }) do
            for _, g in ipairs(list) do eq(Board:Occupancy(g), 5, n .. " players: group " .. g .. " full") end
        end
        eq(Board:Occupancy(S), n - (k - 1) * 5, n .. " players: shared group")
        local cl, cr = Board:Counts("L"), Board:Counts("R")
        eq(cl.n + cr.n, n, "everyone has a side")
        assert(math.abs(cl.n - cr.n) <= 1, n .. " players: sizes " .. cl.n .. "/" .. cr.n)
        assert(math.abs(cl.T - cr.T) <= 1 and math.abs(cl.H - cr.H) <= 1, n .. " players: roles")
        for _, key in ipairs(Board.members) do
            if Board.draft[key] == S then assert(Board.sides[key], key .. " has a side") end
        end
        ns.Apply:RunDemo()
        eq(ns.Split.Run(Board), 0, n .. " players: second split moves nobody")
    end
    sharedDone()
end)

test("turning the shared group on and off keeps sides", function()
    ns.Demo:SetSize(13)
    Board:SetSource("demo")
    ns.Split.Run(Board)
    eq(Board:K(), 4)
    local before = {}
    for _, key in ipairs(Board.members) do before[key] = Board:PlayerSide(key) end
    local groups = {}
    for k, v in pairs(Board.draft) do groups[k] = v end
    local o1, o2, o34 = Board:Occupancy(1), Board:Occupancy(2), Board:Occupancy(3) + Board:Occupancy(4)
    Board:SetShared(true)
    eq(Board:K(), 3)
    -- the halves' last groups (3 and 4) merge into the shared group
    eq(Board:Occupancy(1), o1) eq(Board:Occupancy(2), o2) eq(Board:Occupancy(3), o34)
    for _, key in ipairs(Board.members) do eq(Board:PlayerSide(key), before[key], key) end
    Board:SetShared(false)
    eq(Board:K(), 4)
    for k, v in pairs(groups) do eq(Board.draft[k], v, k) end
    sharedDone()
end)

test("moves, swaps and new players in the shared group", function()
    sharedDemo(13)
    ns.Split.Run(Board)
    local inS = {}
    Board:MembersOf(3, inS)
    local a = inS[1]
    local side = Board.sides[a]
    local other = side == "L" and "R" or "L"
    Board:Move(a, 3, other)
    eq(Board.sides[a], other, "side change without a group move")
    eq(Board:Pending(), select(1, Board:Pending()))
    -- swap with someone in a full group: the newcomer takes the slot's side
    local b = "Thalric-Silvermoon"
    local gb = Board.draft[b]
    Board:Swap(a, b)
    eq(Board.draft[b], 3)
    eq(Board.sides[b], other)
    eq(Board.draft[a], gb)
    -- someone moved in without a side gets one
    Board:Move(b, 0)
    Board.sides[b] = nil
    Board:Move(b, 3)
    assert(Board.sides[b], "side assigned")
    sharedDone()
end)

test("loadouts keep the shared layout and sides", function()
    sharedDemo(13)
    ns.Split.Run(Board)
    local sides, groups = {}, {}
    for k, v in pairs(Board.sides) do if Board.draft[k] == 3 then sides[k] = v end end
    for k, v in pairs(Board.draft) do groups[k] = v end
    local lo = ns.Loadouts.SaveCurrent("Shared test")
    eq(lo.k, 3)
    for k, v in pairs(sides) do eq(lo.memory[k], v, k) end
    wipe(Board.sides)
    ns.Loadouts.Load(lo.id)
    for k, v in pairs(groups) do eq(Board.draft[k], v, k) end
    for k, v in pairs(sides) do eq(Board.sides[k], v, k) end
    -- import keeps k = 3
    local copy = ns.Loadouts.FromExport(ns.Loadouts.ToExport(lo))
    eq(copy.k, 3)
    -- loaded with the shared group off: shared players go to their half's last group
    ns.settings.sharedGroup = false
    Board:SetSource("demo")
    ns.Loadouts.Load(lo.id)
    eq(Board:K(), 4)
    for k, v in pairs(sides) do eq(Board:PlayerSide(k), v, k) end
    assert(occupancyOK())
    ns.Loadouts.Delete(lo.id)
    sharedDone()
end)

test("announce lines, demo print and raid chat after apply", function()
    sharedDemo(13)
    ns.Split.Run(Board)
    local lines = ns.Announce.Lines()
    eq(#lines, 1)
    assert(lines[1]:find("^Group 3 is split %- Left: "), lines[1])
    assert(lines[1]:find("; Right: "), lines[1])
    ns.settings.announceWhat = "all"
    lines = ns.Announce.Lines()
    eq(#lines, 2)
    eq(lines[1], "Halves - Left: group 1; Right: group 2")
    ns.settings.halfNames.L = "Star|r"
    assert(not ns.Announce.Lines()[1]:find("|", 1, true), "no escape codes")
    ns.settings.halfNames.L = "Left"
    -- demo prints instead of sending
    stub.lastPrint = nil
    ns.Apply:RunDemo()
    assert(stub.lastPrint and stub.lastPrint:find("Demo, not sent"), "demo announce printed")
    ns.settings.announceOnApply = false
    stub.lastPrint = nil
    ns.Apply:RunDemo()
    eq(stub.lastPrint, nil, "no announce when turned off")
    ns.settings.announceOnApply = true
    -- nothing to say without a shared group in "shared" mode
    ns.settings.announceWhat = "shared"
    ns.settings.sharedGroup = false
    Board:SetSource("demo")
    eq(#ns.Announce.Lines(), 0)
    eq(ns.Announce.Has(), false)
    sharedDone()
end)

test("announce goes to raid chat on a live raid", function()
    local roster = {}
    for i = 1, 12 do roster[i] = { "P" .. i, math.floor((i - 1) / 5) + 1 } end
    local saved = GetRaidRosterInfo
    GetRaidRosterInfo = function(i)
        local r = roster[i]
        if r then return r[1], 0, r[2], 80, "MAGE", "MAGE", "", true, false, "", false, "DAMAGER" end
    end
    stub.inRaid = true
    ns.settings.sharedGroup = true
    Board:SetSource("live")
    eq(Board:Shared(), 3)
    stub.chat = {}
    assert(ns.Announce.Send())
    eq(#stub.chat, 1)
    eq(stub.chat[1][2], "RAID")
    assert(stub.chat[1][1]:find("^Group 3 is split"), stub.chat[1][1])
    local lock = C_ChatInfo.InChatMessagingLockdown
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    local ok, why = ns.Announce.Send()
    eq(ok, false)
    assert(why:find("locked"), why)
    C_ChatInfo.InChatMessagingLockdown = lock
    GetRaidRosterInfo = saved
    stub.inRaid = false
    ns.settings.sharedGroup = false
    Board:SetSource("none")
end)

---------------------------------------------------------------------------
-- Simple mode: no halves
---------------------------------------------------------------------------
local function draftCopy()
    local t = {}
    for k, v in pairs(Board.draft) do t[k] = v end
    return t
end

test("simple mode has no halves and counts groups 1..K", function()
    Board:SetSource("demo")
    local before = draftCopy()
    Board:SetConvention("none")
    assert(Board:IsSimple())
    for k, v in pairs(before) do eq(Board.draft[k], v, "nobody moves: " .. k) end
    local L, R = Board:Halves()
    eq(#L + #R, 0)
    eq(Board:Shared(), nil)
    eq(Board:SideOf(1), nil)
    eq(Board:PlayerSide("Thalric-Silvermoon"), nil)
    eq(Board:K(), 4)
    local c = Board:Counts("A")
    eq(c.n, 20)
    eq(c.T + c.H + c.M + c.R + c.U, 20)
    Board:Move("Thalric-Silvermoon", 6)
    eq(Board:Counts("A").n, 19, "bench not counted")
    eq(#Board:Imbalances(), 0)
    local moved = draftCopy()
    eq(ns.Split.Run(Board), 0)
    for k, v in pairs(moved) do eq(Board.draft[k], v, "auto-split does nothing: " .. k) end
    ns.settings.announceWhat = "all"
    eq(ns.Announce.Has(), false)
    eq(#ns.Announce.Lines(), 0)
    ns.settings.announceWhat = "shared"
    Board:SetConvention("split")
    for k, v in pairs(moved) do eq(Board.draft[k], v, "back to split: " .. k) end
    Board:SetConvention("oddeven")
    Board:SetSource("demo")
end)

test("simple mode and the shared group", function()
    sharedDemo(13)
    ns.Split.Run(Board)
    local groups, sides = draftCopy(), {}
    for k, v in pairs(Board.sides) do if Board.draft[k] == 3 then sides[k] = v end end
    Board:SetConvention("none")
    eq(Board:K(), 4)
    eq(Board:Shared(), nil)
    for k, v in pairs(groups) do eq(Board.draft[k], v, k) end
    Board:SetConvention("oddeven")
    eq(Board:K(), 3)
    for k, v in pairs(groups) do eq(Board.draft[k], v, k) end
    for k, v in pairs(sides) do eq(Board.sides[k], v, k) end
    -- group 4 exists only in simple mode: its players go to the tray
    Board:SetConvention("none")
    Board:Move("Thalric-Silvermoon", 4)
    Board:SetConvention("oddeven")
    eq(Board.draft["Thalric-Silvermoon"], 0)
    assert(occupancyOK())
    sharedDone()
end)

test("loadouts bring their mode", function()
    Board:SetSource("demo")
    ns.Split.Run(Board)
    local split = ns.Loadouts.SaveCurrent("Split test")
    eq(split.conv, "oddeven")
    Board:SetConvention("none")
    local simple = ns.Loadouts.SaveCurrent("Simple test")
    eq(simple.conv, "none")
    eq(ns.Loadouts.FromExport(ns.Loadouts.ToExport(simple)).conv, "none", "export keeps simple mode")
    local groups = draftCopy()
    -- a split loadout turns simple mode off
    Board.switched = nil
    ns.Loadouts.Load(split.id)
    eq(ns.settings.conv, "oddeven")
    eq(Board.switched, "split")
    -- a simple loadout turns it on
    Board.switched = nil
    ns.Loadouts.Load(simple.id)
    eq(ns.settings.conv, "none")
    eq(Board.switched, "simple")
    for k, v in pairs(groups) do eq(Board.draft[k], v, k) end
    -- between split conventions the current one stays
    Board:SetConvention("split")
    Board.switched = nil
    ns.Loadouts.Load(split.id)
    eq(ns.settings.conv, "split")
    eq(Board.switched, nil)
    -- editing a loadout without a raid switches too
    Board:SetSource("none")
    ns.Loadouts.Load(simple.id)
    eq(Board.source, "loadout")
    eq(ns.settings.conv, "none")
    ns.Loadouts.Delete(split.id)
    ns.Loadouts.Delete(simple.id)
    Board.switched = nil
    Board:SetConvention("oddeven")
    Board:SetSource("demo")
end)

test("loadouts bring their groups used setting", function()
    Board:SetSource("demo")
    Board:SetGroupsMode(6)
    local six = ns.Loadouts.SaveCurrent("Six test")
    eq(six.mode, 6)
    Board:SetGroupsMode("auto")
    local auto = ns.Loadouts.SaveCurrent("Auto test")
    eq(auto.mode, "auto")
    eq(ns.Loadouts.FromExport(ns.Loadouts.ToExport(six)).mode, 6, "export keeps the setting")
    eq(ns.Loadouts.FromExport({ n = "x", gm = 5, g = { ["A-B"] = 1 } }).mode, nil, "bad value dropped")
    ns.Loadouts.Load(six.id)
    eq(ns.settings.groupsMode, 6)
    eq(Board:K(), 6)
    ns.Loadouts.Load(auto.id)
    eq(ns.settings.groupsMode, "auto")
    -- editing without a raid too
    Board:SetSource("none")
    ns.Loadouts.Load(six.id)
    eq(ns.settings.groupsMode, 6)
    -- older loadouts without the field leave the setting alone
    six.mode = nil
    Board:SetGroupsMode(4)
    ns.Loadouts.Load(six.id)
    eq(ns.settings.groupsMode, 4)
    ns.Loadouts.Delete(six.id)
    ns.Loadouts.Delete(auto.id)
    Board:SetGroupsMode("auto")
    Board:SetSource("demo")
end)

test("auto-fill in simple mode", function()
    Board:SetSource("demo")
    Board:SetConvention("none")
    local lo = ns.Loadouts.SaveCurrent("Simple fill")
    local a, b = "Thalric-Silvermoon", "Arrowyn-Silvermoon"
    local ga = lo.groups[a]
    lo.groups[a], lo.groups[b] = nil, nil
    lo.groups["Ghosty-Silvermoon"] = ga
    lo.info["Ghosty-Silvermoon"] = { c = lo.info[a].c, s = lo.info[a].s }
    ns.Loadouts.Load(lo.id)
    eq(Board.loaded.absent, 1)
    eq(Board.loaded.fresh, 2)
    eq(Board:AutoFill(), 2)
    eq(Board.draft[a], ga, "same spec takes the absent slot")
    eq(Board.subs[a], "Ghosty-Silvermoon")
    assert(Board.draft[b] >= 1 and Board.draft[b] <= Board:K(), "leftover in a free group")
    assert(occupancyOK())
    ns.Loadouts.Delete(lo.id)
    Board:SetConvention("oddeven")
    Board:SetSource("demo")
end)

test("invite plan skips members, offline guildies and the raid cap", function()
    local keys = { "Me-Silvermoon", "In-Silvermoon", "Off-Silvermoon", "Pug-Stormrage", "On-Silvermoon", "Late-Silvermoon" }
    local inGroup = { ["In-Silvermoon"] = true }
    local guild = { ["Off-Silvermoon"] = false, ["On-Silvermoon"] = true, ["Late-Silvermoon"] = true }
    local targets, skipped = ns.Invite.Plan(keys, inGroup, guild, "Me-Silvermoon", 39)
    eq(table.concat(targets, ","), "On-Silvermoon,Late-Silvermoon,Pug-Stormrage", "online guildies first")
    eq(skipped.inGroup, 2, "self and members")
    eq(skipped.offline, 1)
    eq(skipped.full, 0)
    targets, skipped = ns.Invite.Plan(keys, inGroup, guild, "Me-Silvermoon", 2)
    eq(table.concat(targets, ","), "On-Silvermoon,Late-Silvermoon")
    eq(skipped.full, 1)
end)

local function listening(event)
    for _, f in ipairs(stub.frames) do
        if f.events[event] then return true end
    end
    return false
end

test("invite from solo: 4, a raid on the first join, then the rest", function()
    local r = ns.Rosters.Create("Invites")
    for _, n in ipairs({ "A", "B", "C", "D", "E", "F-Stormrage", "Off" }) do ns.Rosters.Add(r.id, Players.Key(n)) end
    stub.guild = { { "Off-Silvermoon", false }, { "E-Silvermoon", true } }
    stub.invited, stub.converted = {}, 0
    local states = {}
    ns.On("INVITE_STATE", "test", function(_, kind, n) states[#states + 1] = kind .. ":" .. tostring(n) end)
    local Invite = ns.Invite
    assert(Invite:Start(r.members))
    eq(table.concat(stub.invited, ","), "E,A,B,C", "known online first, our realm by bare name")
    eq(states[1], "waiting:4")
    assert(listening("GROUP_ROSTER_UPDATE"), "waits for the party")
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(stub.converted, 0, "nobody joined yet")
    stub.party = { "A" }
    stub.combat.player = true
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(stub.converted, 0, "not in combat")
    stub.combat.player = nil
    stub.fire("PLAYER_REGEN_ENABLED")
    eq(stub.converted, 1, "after combat")
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(stub.converted, 2, "asks again while the group forms")
    stub.party = {}
    stub.inRaid = true
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(table.concat(stub.invited, ",", 5), "D,F-Stormrage", "the rest once in a raid")
    eq(states[#states], "raid:2")
    assert(not Invite.running and not listening("GROUP_ROSTER_UPDATE") and not listening("PLAYER_REGEN_ENABLED"),
        "done and unregistered")

    -- in a raid: everyone at once, nothing to wait for
    stub.invited = {}
    assert(Invite:Start(r.members))
    eq(#stub.invited, 6)
    assert(not Invite.running and not listening("GROUP_ROSTER_UPDATE"))
    stub.notLeader = true
    local ok, why = Invite:Start(r.members)
    assert(not ok and why:find("assistant"), "assistants and the leader only")
    stub.notLeader, stub.inRaid = nil, false

    -- a party member who is not the leader cannot invite; the leader converts first
    stub.party = { "A", "B-Stormrage" }
    stub.notLeader = true
    eq(Invite:CanInvite(), false)
    stub.notLeader = nil
    stub.invited, stub.converted = {}, 0
    assert(Invite:Start(r.members))
    eq(stub.converted, 1)
    eq(#stub.invited, 0, "waits for the raid")
    stub.party = {}
    stub.fire("GROUP_ROSTER_UPDATE")
    eq(states[#states], "left:nil", "the party broke up")
    assert(not listening("GROUP_ROSTER_UPDATE"))

    -- solo again, then cancelled
    assert(Invite:Start(r.members))
    Invite:Stop()
    eq(states[#states], "stopped:nil")
    assert(not listening("GROUP_ROSTER_UPDATE"))

    -- few enough for a party: invite and done
    local small = ns.Rosters.Create("Small")
    ns.Rosters.Add(small.id, "A-Silvermoon")
    ns.Rosters.Add(small.id, "B-Silvermoon")
    stub.invited = {}
    assert(Invite:Start(small.members))
    eq(#stub.invited, 2)
    eq(states[#states], "sent:2")
    assert(not Invite.running and not listening("GROUP_ROSTER_UPDATE"))
    stub.party = { "A" }
    stub.invited = {}
    assert(Invite:Start(small.members))
    eq(table.concat(stub.invited, ","), "B", "room in the party: no raid needed")
    eq(stub.converted, 1)
    assert(not Invite.running)
    assert(Invite:Start(r.members))
    assert(Invite.running and stub.converted == 2, "5 more do not fit the party")
    Invite:Stop()
    stub.party = {}
    ns.Rosters.Delete(small.id)

    ns.On("INVITE_STATE", "test", nil)
    stub.guild, stub.invited = {}, {}
    ns.Rosters.Delete(r.id)
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
