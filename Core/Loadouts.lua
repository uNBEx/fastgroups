-- Saved loadouts.
--[[ Stored in FastGroupsDB.loadouts as an array, most recently used first:
  {
    id, name, updated,
    conv = "oddeven" | "split",   -- convention the groups were saved with
    k = 4 | 6,                    -- groups used by the halves when saved
    groups = { [key] = group },   -- everyone in the setup, absent players included
    memory = { [key] = "L"|"R" }, -- last known side of everyone who ever was in it
    info = { [key] = { c = class, s = specID } }, -- so others can show absent players
  }
]]
local _, ns = ...

local Players = ns.Players

local Loadouts = {}
ns.Loadouts = Loadouts

local MAX_NAME = 48

local function list() return ns.db.loadouts end

function Loadouts.List() return list() end

function Loadouts.Find(id)
    if not id then return nil end
    for i, lo in ipairs(list()) do
        if lo.id == id then return lo, i end
    end
    return nil
end

local function cleanName(name)
    name = strtrim(tostring(name or ""))
    name = name:gsub("[%c|]", "")
    if name == "" then name = "Untitled" end
    if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
    return name
end

function Loadouts.UniqueName(name)
    name = cleanName(name)
    local taken = {}
    for _, lo in ipairs(list()) do taken[lo.name] = true end
    if not taken[name] then return name end
    local i = 2
    while taken[name .. " (" .. i .. ")"] do i = i + 1 end
    return name .. " (" .. i .. ")"
end

-- Move a loadout to the top of the list.
local function touch(lo)
    local _, i = Loadouts.Find(lo.id)
    if i and i > 1 then
        tremove(list(), i)
        tinsert(list(), 1, lo)
    end
    lo.updated = time()
end

-- Make the class/spec of a loadout's players known to the board.
function Loadouts.SetHints(lo)
    if not lo.info then return end
    for key, i in pairs(lo.info) do
        if type(i) == "table" and not Players.Record(key) then
            Players.hints[key] = { c = i.c, s = i.s }
        end
    end
end

-- Snapshot the board. When overwriteId is given that loadout is replaced
-- (its side memory is kept and extended).
function Loadouts.SaveCurrent(name, overwriteId)
    local board = ns.Board
    local s = ns.settings
    local k = board:K()
    local lo = overwriteId and Loadouts.Find(overwriteId)
    local memory = {}
    if lo and lo.memory then
        for key, side in pairs(lo.memory) do memory[key] = side end
    end
    local groups, info = {}, {}
    local function add(key, g)
        groups[key] = g
        local side = board.SideOfFor(g, s.conv, k)
        if side then memory[key] = side end
        local p = Players.Get(key)
        if p.class then info[key] = { c = p.class, s = p.spec } end
    end
    for _, key in ipairs(board.members) do
        local g = board.draft[key]
        if g and g > 0 then add(key, g) end
    end
    for _, gh in ipairs(board.ghosts) do add(gh.key, gh.group) end

    if lo then
        lo.name = cleanName(name or lo.name)
        lo.conv, lo.k, lo.groups, lo.memory, lo.info = s.conv, k, groups, memory, info
        touch(lo)
    else
        lo = {
            id = ns.NewId(), name = Loadouts.UniqueName(name),
            conv = s.conv, k = k, groups = groups, memory = memory, info = info,
            updated = time(),
        }
        tinsert(list(), 1, lo)
    end
    board.activeLoadout = lo.id
    -- tags and substitute marks are about the loaded state; saving settles them
    wipe(board.tags)
    wipe(board.subs)
    board.loaded = nil
    ns.Fire("LOADOUTS_CHANGED")
    board:Changed()
    return lo
end

function Loadouts.Load(id)
    local lo = Loadouts.Find(id)
    if not lo then return end
    touch(lo)
    ns.Board:ApplyLoadout(lo)
    ns.Fire("LOADOUTS_CHANGED")
    return lo
end

function Loadouts.Rename(id, name)
    local lo = Loadouts.Find(id)
    if not lo then return end
    lo.name = cleanName(name)
    ns.Fire("LOADOUTS_CHANGED")
end

function Loadouts.Duplicate(id)
    local lo, i = Loadouts.Find(id)
    if not lo then return end
    local copy = ns.CopyTable(lo)
    copy.id = ns.NewId()
    copy.name = Loadouts.UniqueName(lo.name .. " copy")
    copy.updated = time()
    tinsert(list(), i + 1, copy)
    ns.Fire("LOADOUTS_CHANGED")
    return copy
end

function Loadouts.Delete(id)
    local _, i = Loadouts.Find(id)
    if not i then return end
    tremove(list(), i)
    if ns.Board.activeLoadout == id then ns.Board.activeLoadout = nil end
    ns.Fire("LOADOUTS_CHANGED")
end

function Loadouts.Count(lo)
    local n = 0
    for _ in pairs(lo.groups) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Export format (compact keys), validated on import.
---------------------------------------------------------------------------
function Loadouts.ToExport(lo)
    return { n = lo.name, c = lo.conv, k = lo.k, g = lo.groups, m = lo.memory, i = lo.info }
end

local MAX_PLAYERS = 60

-- Returns a clean loadout table or nil. Never trusts the input.
function Loadouts.FromExport(t)
    if type(t) ~= "table" or type(t.g) ~= "table" then return nil end
    local lo = {
        name = cleanName(type(t.n) == "string" and t.n or "Imported"),
        conv = (t.c == "split") and "split" or "oddeven",
        k = (t.k == 2 or t.k == 4 or t.k == 6 or t.k == 8) and t.k or 4,
        groups = {}, memory = {}, info = {},
    }
    local n = 0
    for key, g in pairs(t.g) do
        if type(key) == "string" and #key <= 64 and key:find("-", 1, true)
            and type(g) == "number" and g >= 1 and g <= 8 and g == math.floor(g) then
            n = n + 1
            if n > MAX_PLAYERS then return nil end
            lo.groups[key] = g
        end
    end
    if n == 0 then return nil end
    if type(t.m) == "table" then
        for key, side in pairs(t.m) do
            if type(key) == "string" and #key <= 64 and (side == "L" or side == "R") then
                lo.memory[key] = side
            end
        end
    end
    if type(t.i) == "table" then
        for key, i in pairs(t.i) do
            if lo.groups[key] and type(i) == "table" and type(i.c) == "string" and ns.Data.CLASS_SPECS[i.c] then
                local spec = type(i.s) == "number" and ns.Data.SPECS[i.s] and i.s or nil
                lo.info[key] = { c = i.c, s = spec }
            end
        end
    end
    return lo
end

-- Add imported loadouts; names are made unique. Returns the new loadouts.
function Loadouts.Import(los)
    local added = {}
    for _, lo in ipairs(los) do
        lo.id = ns.NewId()
        lo.name = Loadouts.UniqueName(lo.name)
        lo.updated = time()
        tinsert(list(), 1, lo)
        tinsert(added, lo)
    end
    if #added > 0 then ns.Fire("LOADOUTS_CHANGED") end
    return added
end
