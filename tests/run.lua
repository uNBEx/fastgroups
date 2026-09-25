-- Unit tests for the Core modules. Run from the repo root:  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local stub = require("wow_stub")

local ns = {}
local CORE = {
    "Core/Init.lua", "Core/Data.lua", "Core/Players.lua", "Core/Raid.lua", "Core/Board.lua",
    "Core/Split.lua", "Core/Loadouts.lua", "Core/Rosters.lua", "Core/Apply.lua", "Core/Demo.lua",
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

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
