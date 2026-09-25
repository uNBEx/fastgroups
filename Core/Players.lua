-- Player model: resolves class, role, spec and melee/ranged for a "Name-Realm" key.
local _, ns = ...

local Data = ns.Data

local Players = {}
ns.Players = Players

Players.temp = {}   -- demo players, never saved
Players.hints = {}  -- class/spec carried by loadouts and imports: key -> { c = class, s = specID }
-- Specs confirmed this session, key -> "inspect" | "comm" (LibSpecialization),
-- or false when the player is known to have changed spec since.
Players.checked = {}

local cache = {}    -- key -> info table, reused between calls

local function records()
    return ns.db and ns.db.players or {}
end

function Players.ShortName(key)
    return (key:match("^(.-)%-") or key)
end

function Players.Realm(key)
    return key:match("%-(.+)$")
end

local homeRealm
function Players.HomeRealm()
    if not homeRealm or homeRealm == "" then
        homeRealm = GetNormalizedRealmName and GetNormalizedRealmName()
        if not homeRealm or homeRealm == "" then
            homeRealm = (GetRealmName() or ""):gsub("[%s%-]", "")
        end
    end
    return homeRealm
end

-- "Name" or "Name-Realm" -> "Name-Realm"
function Players.Key(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. Players.HomeRealm()
end

-- Name to show: realm hidden for players from our own realm.
function Players.DisplayName(key)
    local realm = Players.Realm(key)
    if realm and realm ~= Players.HomeRealm() then
        return Players.ShortName(key), realm
    end
    return Players.ShortName(key), nil
end

function Players.Record(key, create)
    local recs = records()
    local rec = recs[key]
    if not rec and create then
        rec = {}
        recs[key] = rec
    end
    return rec
end

-- Called for every raid member on roster refresh.
function Players.Seen(key, class)
    local rec = Players.Record(key, true)
    if class then rec.class = class end
    rec.seen = time()
end

function Players.SetSpec(key, specID, manual)
    local sd = Data.SPECS[specID]
    if not sd then return end
    local rec = Players.Record(key, true)
    rec.class = sd[1]
    rec.spec = specID
    rec.manual = manual or nil
    rec.stale = nil
end

-- A spec the player really has (inspected or broadcast). Returns true when
-- anything shown on the card may change.
function Players.Confirm(key, specID, source)
    if not Data.SPECS[specID] then return false end
    local rec = Players.Record(key)
    local changed = not rec or rec.spec ~= specID or rec.manual or not Players.checked[key]
    Players.Seen(key)
    Players.SetSpec(key, specID)
    Players.checked[key] = source
    return changed and true or false
end

-- The player changed spec (or role): the spec on record needs a new check.
function Players.Unconfirm(key)
    Players.checked[key] = false
end

-- Drop confirmations from one source (inspects are redone per window opening).
function Players.ForgetChecked(source)
    for key, v in pairs(Players.checked) do
        if v == source then Players.checked[key] = nil end
    end
end

-- Manual melee/ranged override, nil to go back to the spec default.
function Players.SetPos(key, pos)
    local rec = Players.Record(key, true)
    rec.pos = pos
end

function Players.SetClass(key, class)
    local rec = Players.Record(key, true)
    if rec.class ~= class then
        rec.class = class
        rec.spec = nil
        Players.checked[key] = nil
    end
end

local function liveMember(key)
    local board = ns.Board
    local live = board and board:Live()
    return live and live[key]
end

--[[ Returns a reused table:
  key, name, class, spec, role ("TANK"|"HEALER"|"DAMAGER"), roleKnown,
  pos ("M"|"R"|nil), posManual, bucket ("T"|"H"|"M"|"R"|"?"),
  needsInspect (spec unknown, contradicted or changed), recheck (a saved spec
  the raid role cannot vouch for, not confirmed this session)
]]
function Players.Get(key)
    local info = cache[key]
    if not info then
        info = { key = key, name = Players.ShortName(key) }
        cache[key] = info
    end
    local rec = Players.temp[key] or records()[key]
    local hint = Players.hints[key]
    local live = liveMember(key)

    local class = (rec and rec.class) or (live and live.class) or (hint and hint.c)
    local spec = (rec and rec.spec) or (hint and hint.s)
    local sd = spec and Data.SPECS[spec]
    if sd and class and sd[1] ~= class then
        sd, spec = nil, nil
    end

    local assigned = live and live.role
    if assigned ~= "TANK" and assigned ~= "HEALER" and assigned ~= "DAMAGER" then assigned = nil end

    local checked = Players.checked[key]
    local role
    local stale = false
    if sd then
        role = sd[2]
        -- the raid role says otherwise: the spec we remember is out of date
        -- (unless we just saw it; a role change clears that, see Raid:Refresh)
        if assigned and assigned ~= role and not (rec and rec.manual) and not checked then
            role, sd, spec, stale = assigned, nil, nil, true
        end
    else
        role = assigned or (class and Data.DPS_ONLY[class] and "DAMAGER") or nil
    end

    info.class = class
    info.spec = spec
    info.roleKnown = role ~= nil
    info.role = role or "DAMAGER"

    local pos = rec and rec.pos
    info.posManual = pos ~= nil
    if not pos then
        if info.role == "TANK" then
            pos = "M"
        elseif info.role == "HEALER" then
            pos = nil
        elseif sd then
            pos = sd[3] and "M" or "R"
        elseif class then
            pos = Data.CLASS_DEFAULT_POS[class]
        end
    end
    info.pos = pos

    if info.role == "TANK" then
        info.bucket = "T"
    elseif info.role == "HEALER" then
        info.bucket = "H"
    else
        info.bucket = pos or "?"
    end
    info.needsInspect = stale or spec == nil or checked == false
    -- the real raid role, whatever the board shows (roster / loadout sources)
    local raidRole = assigned
    if not raidRole then
        local m = ns.Raid and ns.Raid.members[key]
        raidRole = m and (m.role == "TANK" or m.role == "HEALER" or m.role == "DAMAGER") and m.role
    end
    info.recheck = not info.needsInspect and not checked
        and (Data.SHARED_ROLE[spec] or not raidRole) and true or false
    return info
end

-- Sort key helpers used by the board.
function Players.RoleOrder(key)
    return Data.ROLE_ORDER[Players.Get(key).bucket]
end
