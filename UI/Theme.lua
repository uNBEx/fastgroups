-- Colors, fonts and textures.
local _, ns = ...

local T = {}
ns.T = T

local MEDIA = "Interface\\AddOns\\" .. ns.name .. "\\Media\\"
T.MEDIA = MEDIA
T.ICON = MEDIA .. "Icons\\"
T.TEX = {
    round = MEDIA .. "round6",
    ring = MEDIA .. "ring6",
    round3 = MEDIA .. "round3",
    circle = MEDIA .. "circle",
    square = MEDIA .. "square",
    ring0 = MEDIA .. "ring0",
    white = "Interface\\Buttons\\WHITE8X8",
}

T.C = {
    win = { 0.067, 0.075, 0.094 },
    side = { 0.051, 0.059, 0.075 },
    panel = { 0.090, 0.102, 0.125 },
    panel2 = { 0.114, 0.129, 0.161 },
    panel3 = { 0.145, 0.165, 0.200 },
    line = { 0.153, 0.173, 0.208 },
    line2 = { 0.196, 0.220, 0.267 },
    text = { 0.906, 0.914, 0.933 },
    muted = { 0.541, 0.573, 0.635 },
    dim = { 0.365, 0.396, 0.459 },
    warn = { 0.961, 0.647, 0.141 },
    danger = { 0.949, 0.333, 0.353 },
    ok = { 0.243, 0.812, 0.557 },
    tank = { 0.424, 0.714, 1.000 },
    heal = { 0.341, 0.851, 0.541 },
    dps = { 1.000, 0.439, 0.439 },
    ink = { 0.024, 0.063, 0.094 },   -- text on accent
}

T.ACCENTS = {
    { 0.353, 0.784, 0.980 },
    { 0.545, 0.486, 0.965 },
    { 0.243, 0.812, 0.557 },
    { 0.961, 0.647, 0.141 },
    { 1.000, 0.420, 0.545 },
    { 0.902, 0.910, 0.925 },
}

do
    local locale = GetLocale()
    if locale == "koKR" or locale == "zhCN" or locale == "zhTW" then
        local f = STANDARD_TEXT_FONT
        T.FONT = { regular = f, semibold = f, bold = f }
    else
        T.FONT = {
            regular = MEDIA .. "Fonts\\Inter-Regular.ttf",
            semibold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
            bold = MEDIA .. "Fonts\\Inter-Bold.ttf",
        }
        -- Touch the font files at load time so the client has them ready before the
        -- window is built. On a cold start an unloaded font measures as 0 wide, and
        -- everything sized by GetUnboundedStringWidth comes out too narrow.
        for _, path in pairs(T.FONT) do
            local fs = UIParent:CreateFontString(nil, "BACKGROUND")
            fs:SetFont(path, 12, "")
            fs:SetText("Aa")
        end
    end
end

function T.Color(name)
    local c = T.C[name]
    return c[1], c[2], c[3]
end

function T.Accent()
    local a = ns.settings.accent
    return a[1], a[2], a[3]
end

-- Hex for chat / FontString escapes.
function T.Hex(r, g, b)
    return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function T.ClassHex(class)
    return T.Hex(ns.Data.ClassColor(class))
end

-- Things that follow the accent color register a callback here.
local accentHooks = {}
function T.OnAccent(fn)
    accentHooks[#accentHooks + 1] = fn
    fn(T.Accent())
end

function T.SetAccent(r, g, b)
    ns.settings.accent = { r, g, b }
    for i = 1, #accentHooks do accentHooks[i](r, g, b) end
    ns.Fire("SETTINGS_CHANGED", "accent")
end

T.ROLE_ICON = { T = "role_tank", H = "role_healer", D = "role_dps" }
T.ROLE_COLOR = { T = "tank", H = "heal", D = "dps" }
T.POS_ICON = { M = "pos_melee", R = "pos_ranged", ["?"] = "pos_unknown" }
T.ROLE_KEY = { TANK = "T", HEALER = "H", DAMAGER = "D" }
