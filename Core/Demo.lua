-- /fg demo: a fake 20 player Mythic raid to try the UI without a group.
local _, ns = ...

local Demo = { members = {} }
ns.Demo = Demo

local REALM = "Silvermoon"

-- name, specID
local ROSTER = {
    { "Thalric", 66 }, { "Nyxara", 581 }, { "Brenwyn", 105 }, { "Meilin", 270 }, { "Kaelith", 577 },
    { "Tovrin", 72 }, { "Frostvey", 64 }, { "Vexmora", 1480 }, { "Solenne", 257 }, { "Grimholt", 252 },
    { "Lianfei", 269 }, { "Seryth", 1467 }, { "Duskmire", 258 }, { "Shadewhisper", 261 }, { "Ysolde", 265 },
    { "Aurelia", 70 }, { "Arrowyn", 254 }, { "Vaelis", 1468 }, { "Stormjaw", 263 }, { "Moonbrook", 102 },
}

-- Known from last week but not here today.
local ABSENT = { { "Brakka", 71 }, { "Selvyn", 267 }, { "Morvash", 251 } }

-- roster index -> raid rank (2 = leader, 1 = assistant)
local RANKS = { [1] = 2, [2] = 1, [11] = 1 }

local SAMPLE_NAME = "[Demo] Last week"

local function key(name) return name .. "-" .. REALM end

local function addTemp(name, spec)
    local sd = ns.Data.SPECS[spec]
    ns.Players.temp[key(name)] = { class = sd[1], spec = spec }
end

function Demo:Start()
    wipe(self.members)
    for i, row in ipairs(ROSTER) do
        addTemp(row[1], row[2])
        local sd = ns.Data.SPECS[row[2]]
        self.members[key(row[1])] = {
            index = i, group = math.floor((i - 1) / 5) + 1, rank = RANKS[i] or 0,
            online = true, class = sd[1], role = sd[2], unit = "player",
        }
    end
    for _, row in ipairs(ABSENT) do addTemp(row[1], row[2]) end
    self:EnsureSample()
end

-- Stand-in for Raid:SetRank. Passing lead leaves the old leader an assistant.
function Demo:SetRank(k, rank)
    local m = self.members[k]
    if not m then return end
    if rank == 2 then
        for _, o in pairs(self.members) do
            if o.rank == 2 then o.rank = 1 end
        end
    end
    m.rank = rank
    ns.Board:Changed()
end

-- A loadout that misses three of today's players and has three absentees,
-- to show reconcile and Auto-fill.
function Demo:EnsureSample()
    for _, lo in ipairs(ns.Loadouts.List()) do
        if lo.name == SAMPLE_NAME then return end
    end
    local groups, memory, info = {}, {}, {}
    local skip = { Tovrin = true, Ysolde = true, Kaelith = true }
    local names = {}
    for _, row in ipairs(ROSTER) do
        if not skip[row[1]] then tinsert(names, row) end
    end
    for _, row in ipairs(ABSENT) do tinsert(names, row) end
    -- simple alternating layout; players that were here get a side each
    local L, R = ns.Board.HalvesFor("oddeven", 4)
    local fill = {}
    local keys = {}
    for i, row in ipairs(names) do keys[i] = key(row[1]) end
    local result = ns.Split.Compute({
        keys = keys,
        info = function(k)
            local name = k:match("^(.-)%-")
            for _, row in ipairs(names) do
                if row[1] == name then
                    local sd = ns.Data.SPECS[row[2]]
                    local b = sd[2] == "TANK" and "T" or sd[2] == "HEALER" and "H" or (sd[3] and "M" or "R")
                    return { bucket = b, class = sd[1] }
                end
            end
        end,
        current = fill, L = L, R = R,
    })
    for i, row in ipairs(names) do
        local k = keys[i]
        groups[k] = result[k]
        memory[k] = (result[k] % 2 == 1) and "L" or "R"
        info[k] = { c = ns.Data.SPECS[row[2]][1], s = row[2] }
    end
    memory[key("Kaelith")] = "R"
    info[key("Kaelith")] = { c = "DEMONHUNTER", s = 577 }
    tinsert(ns.Loadouts.List(), 1, {
        id = ns.NewId(), name = SAMPLE_NAME, conv = "oddeven", k = 4,
        groups = groups, memory = memory, info = info, updated = time() - 6 * 86400,
    })
    ns.Fire("LOADOUTS_CHANGED")
end
