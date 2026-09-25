-- Planning rosters: hand-picked lists of players to plan groups with before
-- the raid forms. Stored in FastGroupsDB.rosters as { id, name, members = { key, ... } }.
local _, ns = ...

local Rosters = {}
ns.Rosters = Rosters

local function list() return ns.db.rosters end

function Rosters.List() return list() end

function Rosters.Find(id)
    if not id then return nil end
    for i, r in ipairs(list()) do
        if r.id == id then return r, i end
    end
    return nil
end

function Rosters.Create(name)
    local r = { id = ns.NewId(), name = name or "New roster", members = {} }
    tinsert(list(), r)
    ns.Fire("ROSTERS_CHANGED")
    return r
end

function Rosters.Rename(id, name)
    local r = Rosters.Find(id)
    if not r then return end
    name = strtrim(tostring(name or "")):gsub("[%c|]", "")
    if name ~= "" then r.name = name:sub(1, 48) end
    ns.Fire("ROSTERS_CHANGED")
end

function Rosters.Delete(id)
    local _, i = Rosters.Find(id)
    if i then
        tremove(list(), i)
        ns.Fire("ROSTERS_CHANGED")
    end
end

function Rosters.Has(r, key)
    for _, k in ipairs(r.members) do
        if k == key then return true end
    end
    return false
end

-- Add a player; class is optional (guild roster and raid provide it).
function Rosters.Add(id, key, class)
    local r = Rosters.Find(id)
    if not r or not key or Rosters.Has(r, key) then return false end
    tinsert(r.members, key)
    if class then
        local rec = ns.Players.Record(key, true)
        rec.class = rec.class or class
        rec.seen = rec.seen or time()
    end
    ns.Fire("ROSTERS_CHANGED")
    return true
end

function Rosters.Remove(id, key)
    local r = Rosters.Find(id)
    if not r then return end
    for i, k in ipairs(r.members) do
        if k == key then
            tremove(r.members, i)
            break
        end
    end
    ns.Fire("ROSTERS_CHANGED")
end

function Rosters.AddCurrentRaid(id)
    ns.Raid:Refresh()
    local n = 0
    for key, m in pairs(ns.Raid.members) do
        if Rosters.Add(id, key, m.class) then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Guild roster access. GUILD_ROSTER_UPDATE is only registered while the
-- guild picker is open (StartGuildScan / StopGuildScan).
---------------------------------------------------------------------------
Rosters.guild = {}   -- array of { key, class, rank, rankIndex, level, online }

local function readGuild()
    local out = Rosters.guild
    wipe(out)
    local n = GetNumGuildMembers()
    for i = 1, n do
        local name, rank, rankIndex, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            out[#out + 1] = {
                key = ns.Players.Key(name), class = classFile, rank = rank,
                rankIndex = rankIndex, level = level, online = online,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        return a.key < b.key
    end)
    ns.Fire("GUILD_LIST_CHANGED")
end

function Rosters.StartGuildScan()
    if not IsInGuild() then
        wipe(Rosters.guild)
        ns.Fire("GUILD_LIST_CHANGED")
        return false
    end
    ns.RegisterEvent(Rosters, "GUILD_ROSTER_UPDATE", readGuild)
    C_GuildInfo.GuildRoster()
    readGuild()
    return true
end

function Rosters.StopGuildScan()
    ns.UnregisterEvent(Rosters, "GUILD_ROSTER_UPDATE")
end
