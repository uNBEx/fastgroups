-- Static game data: specs, classes, colors.
local _, ns = ...

local Data = {}
ns.Data = Data

-- [specID] = { classFile, role, isMelee }
Data.SPECS = {
    [71] = { "WARRIOR", "DAMAGER", true }, [72] = { "WARRIOR", "DAMAGER", true }, [73] = { "WARRIOR", "TANK", true },
    [65] = { "PALADIN", "HEALER", true }, [66] = { "PALADIN", "TANK", true }, [70] = { "PALADIN", "DAMAGER", true },
    [253] = { "HUNTER", "DAMAGER", false }, [254] = { "HUNTER", "DAMAGER", false }, [255] = { "HUNTER", "DAMAGER", true },
    [259] = { "ROGUE", "DAMAGER", true }, [260] = { "ROGUE", "DAMAGER", true }, [261] = { "ROGUE", "DAMAGER", true },
    [256] = { "PRIEST", "HEALER", false }, [257] = { "PRIEST", "HEALER", false }, [258] = { "PRIEST", "DAMAGER", false },
    [250] = { "DEATHKNIGHT", "TANK", true }, [251] = { "DEATHKNIGHT", "DAMAGER", true }, [252] = { "DEATHKNIGHT", "DAMAGER", true },
    [262] = { "SHAMAN", "DAMAGER", false }, [263] = { "SHAMAN", "DAMAGER", true }, [264] = { "SHAMAN", "HEALER", false },
    [62] = { "MAGE", "DAMAGER", false }, [63] = { "MAGE", "DAMAGER", false }, [64] = { "MAGE", "DAMAGER", false },
    [265] = { "WARLOCK", "DAMAGER", false }, [266] = { "WARLOCK", "DAMAGER", false }, [267] = { "WARLOCK", "DAMAGER", false },
    [268] = { "MONK", "TANK", true }, [269] = { "MONK", "DAMAGER", true }, [270] = { "MONK", "HEALER", true },
    [102] = { "DRUID", "DAMAGER", false }, [103] = { "DRUID", "DAMAGER", true }, [104] = { "DRUID", "TANK", true }, [105] = { "DRUID", "HEALER", false },
    [577] = { "DEMONHUNTER", "DAMAGER", true }, [581] = { "DEMONHUNTER", "TANK", true }, [1480] = { "DEMONHUNTER", "DAMAGER", false },
    [1467] = { "EVOKER", "DAMAGER", false }, [1468] = { "EVOKER", "HEALER", false }, [1473] = { "EVOKER", "DAMAGER", false },
}

-- Specs that share their role with another spec of the same class. The raid
-- role cannot reveal a switch between them, so a saved one is checked again.
Data.SHARED_ROLE = {}
for id, a in pairs(Data.SPECS) do
    for other, b in pairs(Data.SPECS) do
        if other ~= id and a[1] == b[1] and a[2] == b[2] then Data.SHARED_ROLE[id] = true end
    end
end

Data.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

Data.CLASS_SPECS = {
    WARRIOR = { 71, 72, 73 },
    PALADIN = { 65, 66, 70 },
    HUNTER = { 253, 254, 255 },
    ROGUE = { 259, 260, 261 },
    PRIEST = { 256, 257, 258 },
    DEATHKNIGHT = { 250, 251, 252 },
    SHAMAN = { 262, 263, 264 },
    MAGE = { 62, 63, 64 },
    WARLOCK = { 265, 266, 267 },
    MONK = { 268, 270, 269 },
    DRUID = { 102, 103, 104, 105 },
    DEMONHUNTER = { 577, 581, 1480 },
    EVOKER = { 1467, 1468, 1473 },
}

-- Classes whose raid debuff should be spread over both halves.
Data.BUFF_CLASSES = { DEMONHUNTER = true, MONK = true }

-- Position of a damage dealer when the spec is unknown (nil = depends on spec).
Data.CLASS_DEFAULT_POS = {
    WARRIOR = "M", ROGUE = "M", DEATHKNIGHT = "M", PALADIN = "M", MONK = "M",
    MAGE = "R", WARLOCK = "R", PRIEST = "R", EVOKER = "R",
}

-- Classes that can only deal damage, so the role is known without a spec.
Data.DPS_ONLY = { MAGE = true, WARLOCK = true, ROGUE = true, HUNTER = true }

Data.ROLE_ORDER = { T = 1, H = 2, M = 3, R = 4, ["?"] = 5 }

local FALLBACK_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

function Data.ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or FALLBACK_COLOR
    return c.r, c.g, c.b
end

function Data.ClassName(class)
    if not class then return "Unknown" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

local specNames, specIcons = {}, {}

-- Localized spec name and icon, cached.
function Data.SpecInfo(specID)
    if not specID then return nil end
    local name = specNames[specID]
    if name == nil then
        local _, n, _, icon = GetSpecializationInfoByID(specID)
        name = n or false
        specNames[specID] = name
        specIcons[specID] = icon or false
    end
    return name or nil, specIcons[specID] or nil
end
