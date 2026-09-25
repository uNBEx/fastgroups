-- Unit tests for the Core modules. Run from the repo root:  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local stub = require("wow_stub")

local ns = {}
local CORE = {
    "Core/Init.lua", "Core/Data.lua", "Core/Players.lua", "Core/Raid.lua", "Core/Board.lua",
    "Core/Split.lua", "Core/Loadouts.lua", "Core/Rosters.lua", "Core/Apply.lua", "Core/Demo.lua",
    "Core/Inspect.lua", "Core/Serialize.lua", "Core/Comm.lua",
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

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
