-- FastGroups: namespace, event dispatch, saved variables, slash commands.
local ADDON, ns = ...

ns.name = ADDON
do
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    if not v or v:find("@", 1, true) then v = "dev" end
    ns.version = v
end

---------------------------------------------------------------------------
-- WoW events: several owners may listen to one event. The event is only
-- registered with the client while at least one owner listens.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for owner, fn in pairs(list) do
        fn(owner, event, ...)
    end
end)

function ns.RegisterEvent(owner, event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
    end
    if not next(list) then
        eventFrame:RegisterEvent(event)
    end
    list[owner] = fn
end

function ns.UnregisterEvent(owner, event)
    local list = handlers[event]
    if not list or list[owner] == nil then return end
    list[owner] = nil
    if not next(list) then
        eventFrame:UnregisterEvent(event)
    end
end

---------------------------------------------------------------------------
-- Internal messages (model -> UI).
---------------------------------------------------------------------------
local listeners = {}

function ns.On(msg, owner, fn)
    local list = listeners[msg]
    if not list then
        list = {}
        listeners[msg] = list
    end
    list[owner] = fn
end

function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for owner, fn in pairs(list) do
        fn(owner, ...)
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff5ac8faFastGroups|r: " .. tostring(msg))
end

local idCounter = 0
function ns.NewId()
    idCounter = idCounter + 1
    return string.format("%x%x%x", time(), idCounter, math.random(0, 4095))
end

function ns.CopyTable(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do
        t[k] = ns.CopyTable(v)
    end
    return t
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.defaults = {
    settings = {
        accent = { 0.353, 0.784, 0.980 },
        cardStyle = "filled",      -- "filled" | "subtle"
        showSpec = true,
        conv = "oddeven",          -- "oddeven" | "split"
        halfNames = { L = "Left", R = "Right" },
        groupsMode = "auto",       -- "auto" | 4 | 6
        arrangeByHalf = true,
        sortMode = "role",         -- "role" | "class"
        scale = 1,
        confirmApply = true,
        autoInspect = true,
        rememberSides = true,
        acceptFrom = "ask",        -- "ask" | "leader" | "never"
        minimap = { hide = false },
        window = { w = 1040, h = 660 },
        benchOpen = false,
    },
    players = {},   -- ["Name-Realm"] = { class = "MAGE", spec = 64, pos = "M"|"R"|nil, manual = bool, seen = time }
    loadouts = {},  -- see Core/Loadouts.lua
    rosters = {},   -- see Core/Rosters.lua
    trusted = {},   -- ["Name-Realm"] = true, auto accept shares
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            -- lists and keyed stores start empty; only merge settings recursively
            if next(v) then applyDefaults(dst[k], v) end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.ApplyDefaults = applyDefaults

local PLAYER_EXPIRY = 180 * 24 * 3600

local function initDB()
    if type(FastGroupsDB) ~= "table" then FastGroupsDB = {} end
    local db = FastGroupsDB
    applyDefaults(db, ns.defaults)
    db.version = 1
    -- forget players not seen for half a year, unless a roster or loadout still uses them
    local keep = {}
    for _, r in ipairs(db.rosters) do
        for _, key in ipairs(r.members or {}) do keep[key] = true end
    end
    for _, lo in ipairs(db.loadouts) do
        for key in pairs(lo.groups or {}) do keep[key] = true end
    end
    local now = time()
    for key, rec in pairs(db.players) do
        if not keep[key] and rec.seen and now - rec.seen > PLAYER_EXPIRY then
            db.players[key] = nil
        end
    end
    ns.db = db
    ns.settings = db.settings
end

ns.RegisterEvent(ns, "ADDON_LOADED", function(_, _, name)
    if name ~= ADDON then return end
    ns.UnregisterEvent(ns, "ADDON_LOADED")
    initDB()
    ns.Fire("DB_READY")
end)

ns.RegisterEvent(ns, "PLAYER_LOGIN", function()
    ns.UnregisterEvent(ns, "PLAYER_LOGIN")
    ns.Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Opening the window. UI/Main.lua provides ns.UI.Toggle; the UI is only
-- built the first time it is opened.
---------------------------------------------------------------------------
function ns.Toggle(page)
    if ns.UI and ns.UI.Toggle then ns.UI.Toggle(page) end
end

function ns.Show(page)
    if ns.UI and ns.UI.Show then ns.UI.Show(page) end
end

local HELP = {
    "/fg - open or close the window",
    "/fg demo - fill the board with a fake 20 player raid to try things out",
    "/fg live - leave demo / planning and show the real raid",
    "/fg reset - reset the window position and size",
}

SLASH_FASTGROUPS1 = "/fg"
SLASH_FASTGROUPS2 = "/fastgroups"
SlashCmdList.FASTGROUPS = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "" then
        ns.Toggle()
    elseif msg == "demo" then
        ns.Board:SetSource("demo")
        ns.Show("groups")
    elseif msg == "live" then
        ns.Board:AutoSource(true)
        ns.Show("groups")
    elseif msg == "reset" then
        ns.settings.window = { w = ns.defaults.settings.window.w, h = ns.defaults.settings.window.h }
        if ns.UI and ns.UI.ResetPosition then ns.UI.ResetPosition() end
    elseif msg == "options" or msg == "config" then
        ns.Show("options")
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end

-- Addon compartment (globals named in the TOC).
function FastGroups_OnAddonCompartmentClick()
    ns.Toggle()
end

function FastGroups_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("FastGroups")
    GameTooltip:AddLine("Click to open the group board.", 1, 1, 1)
    GameTooltip:Show()
end

function FastGroups_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
