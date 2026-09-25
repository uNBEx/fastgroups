-- UI smoke test: builds every page against the mock frame API, drives the
-- main flows and then clicks / hovers every widget. Run: lua tests/ui_smoke.lua
package.path = "./tests/?.lua;" .. package.path
local stub = require("wow_stub")
local M = require("ui_mock")

local ns = {}
local FILES = {
    "Core/Init.lua", "Core/Data.lua", "Core/Players.lua", "Core/Raid.lua", "Core/Board.lua",
    "Core/Split.lua", "Core/Loadouts.lua", "Core/Rosters.lua", "Core/Apply.lua", "Core/Demo.lua",
    "Core/Inspect.lua", "Core/SpecComm.lua", "Core/Serialize.lua", "Core/Comm.lua",
    "UI/Theme.lua", "UI/Widgets.lua", "UI/Main.lua", "UI/GroupsPage.lua", "UI/RostersPage.lua",
    "UI/SharePage.lua", "UI/OptionsPage.lua", "UI/Minimap.lua",
}
for _, path in ipairs(FILES) do
    assert(loadfile(path))("FastGroups", ns)
end
stub.fire("ADDON_LOADED", "FastGroups")
stub.fire("PLAYER_LOGIN")

local failures = 0
local function step(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function check(cond, msg) if not cond then error(msg, 2) end end

local UI, Board = ns.UI, ns.Board
local groups = UI.pages.groups

step("open window without a raid", function()
    SlashCmdList.FASTGROUPS("")
    check(UI.Frame():IsShown(), "window shown")
    check(Board.source == "none", "source none")
    check(groups.empty:IsShown(), "empty state shown")
end)

step("demo raid renders 20 cards", function()
    SlashCmdList.FASTGROUPS("demo")
    check(Board.source == "demo", "demo source")
    check(#groups.activeCards == 20, "cards: " .. #groups.activeCards)
end)

local function cardFor(key)
    for _, c in ipairs(groups.activeCards) do
        if c.key == key and not c.ghost then return c end
    end
end

step("drag onto a card swaps", function()
    local a, b = "Thalric-Silvermoon", "Solenne-Silvermoon"
    local ga, gb = Board.draft[a], Board.draft[b]
    check(ga ~= gb, "different groups")
    local ca, cb = cardFor(a), cardFor(b)
    ca.scripts.OnDragStart(ca)
    cb._mouseOver = true
    ca.scripts.OnDragStop(ca)
    cb._mouseOver = false
    check(Board.draft[a] == gb and Board.draft[b] == ga, "swapped")
    check(Board:Pending() == 2, "two pending")
end)

step("drag onto a full column is refused", function()
    local a = "Thalric-Silvermoon"
    local ca = cardFor(a)
    local target = Board.draft[a] == 1 and 3 or 1
    ca.scripts.OnDragStart(ca)
    groups.columns[target]._mouseOver = true
    ca.scripts.OnDragStop(ca)
    groups.columns[target]._mouseOver = false
    check(Board.draft[a] ~= target, "not moved into full group")
end)

step("drag into the tray and back", function()
    local a = "Arrowyn-Silvermoon"
    local g = Board.draft[a]
    Board:Move(a, 0)
    check(groups.tray:IsShown(), "tray visible")
    local ca = cardFor(a)
    ca.scripts.OnDragStart(ca)
    groups.columns[g]._mouseOver = true
    ca.scripts.OnDragStop(ca)
    groups.columns[g]._mouseOver = false
    check(Board.draft[a] == g, "moved back")
end)

-- Every callback in a menu description, submenus included.
local function menuCalls(d, out)
    out = out or {}
    for _, e in ipairs(d.children or {}) do
        if e.isSelected then e.isSelected() end
        if e.fn then out[#out + 1] = e.fn end
        menuCalls(e, out)
    end
    return out
end

step("card context menus", function()
    for _, c in ipairs(groups.activeCards) do
        ns.W.menuRoot = nil
        c.scripts.OnClick(c, "RightButton")
        check(ns.W.menuRoot and #ns.W.menuRoot.children > 0, "menu built")
    end
    -- run every entry of one menu
    local c = cardFor("Vexmora-Silvermoon")
    c.scripts.OnClick(c, "RightButton")
    for _, fn in ipairs(menuCalls(ns.W.menuRoot)) do fn() end
end)

step("source dropdown toggles and opens submenus", function()
    local b = groups.sourceBtn
    b.scripts.OnClick(b, "LeftButton")
    check(#ns.W.menuRoot.children > 0, "dropdown built")
    b.scripts.OnClick(b, "LeftButton")
    -- hover every row of a card menu so submenus render
    local c = cardFor("Vexmora-Silvermoon")
    c.scripts.OnClick(c, "RightButton")
    local before = #M.objects
    for i = 1, before do
        local o = M.objects[i]
        if o.desc and o:IsVisible() and o.scripts.OnEnter then
            o.scripts.OnEnter(o)
            o.scripts.OnLeave(o)
        end
    end
    ns.W.CloseMenu()
end)

step("auto-split, apply (demo) and revert", function()
    groups.split.scripts.OnClick(groups.split, "LeftButton")
    check(#Board:Imbalances() == 0, "balanced")
    groups.apply.scripts.OnClick(groups.apply, "LeftButton")
    check(Board:Pending() == 0, "demo applied")
    Board:Move("Thalric-Silvermoon", 0)
    groups.revert.scripts.OnClick(groups.revert, "LeftButton")
    check(Board.draft["Thalric-Silvermoon"] ~= 0, "reverted")
end)

step("save dialog and load loadout", function()
    groups.save.scripts.OnClick(groups.save, "LeftButton")
    local modalButtons = {}
    for _, o in ipairs(M.objects) do
        if o._kind == "Button" and o.label and (o.label._text == "Save") and o.scripts.OnClick and o ~= groups.save then
            modalButtons[#modalButtons + 1] = o
        end
    end
    check(#modalButtons > 0, "modal save button")
    modalButtons[#modalButtons].scripts.OnClick(modalButtons[#modalButtons])
    check(ns.Loadouts.List()[1].name == "Untitled", "saved as Untitled: " .. tostring(ns.Loadouts.List()[1].name))
end)

step("load sample with absentees, auto-fill", function()
    local sample
    for _, lo in ipairs(ns.Loadouts.List()) do
        if lo.name == "[Demo] Last week" then sample = lo end
    end
    UI.LoadLoadout(sample.id)
    check(groups.banner:IsShown(), "banner")
    check(#Board.ghosts == 3, "ghosts")
    local ghosts = 0
    for _, c in ipairs(groups.activeCards) do if c.ghost then ghosts = ghosts + 1 end end
    check(ghosts == 3, "ghost cards " .. ghosts)
    groups.banner.b1.scripts.OnClick(groups.banner.b1)
    check(#Board.ghosts == 0, "filled")
end)

step("layout variants", function()
    ns.settings.arrangeByHalf = false
    ns.settings.cardStyle = "subtle"
    ns.settings.showSpec = false
    ns.settings.benchOpen = true
    Board:SetGroupsMode(6)
    Board:SetConvention("split")
    groups:Refresh()
    ns.settings.arrangeByHalf = true
    ns.settings.cardStyle = "filled"
    ns.settings.showSpec = true
    Board:SetGroupsMode("auto")
    Board:SetConvention("oddeven")
end)

step("rosters page", function()
    local r = ns.Rosters.Create("Core")
    for key in pairs(ns.Demo.members) do ns.Rosters.Add(r.id, key) end
    UI.ShowPage("rosters")
    local page = UI.pages.rosters
    page.selected = r.id
    page:Refresh()
    page.detail.addGuild.scripts.OnClick(page.detail.addGuild)
    page.detail.plan.scripts.OnClick(page.detail.plan)
    check(Board.source == "roster", "planning source")
    check(UI.current == "groups", "switched to groups")
    groups.split.scripts.OnClick(groups.split)
end)

step("share page export / import round trip", function()
    UI.ShowPage("share")
    local page = UI.pages.share
    page:Select(ns.Loadouts.List()[1].id)
    page:Generate()
    local str = page.export:GetText()
    check(str:sub(1, 5) == "!FG1!", "export string")
    page.import:SetText(str)
    page:Preview()
    check(page.preview and not page.preview.error, "preview ok")
    local before = #ns.Loadouts.List()
    page:Import()
    check(#ns.Loadouts.List() == before + 1, "imported")
    page.target = "WHISPER"
    page.send.name:SetText("Friend")
    page:Send()
end)

step("options page", function()
    UI.ShowPage("options")
    UI.pages.options:Refresh()
end)

step("corner style switches in place", function()
    local shaped, dots = {}, {}
    local function walk(f)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.fgShape then shaped[#shaped + 1] = r end
            local tex = r:GetTexture()
            if type(tex) == "string" and tex:find("circle$") and not r.fgShape then dots[#dots + 1] = r end
        end
        for _, c in ipairs({ f:GetChildren() }) do walk(c) end
    end
    walk(UI.Frame())
    check(#shaped > 50 and #dots > 0, "shaped " .. #shaped .. ", dots " .. #dots)
    check(ns.settings.squareCorners == true, "square by default")
    for _, r in ipairs(shaped) do
        check(r:GetTexture():find("square$") or r:GetTexture():find("ring0$"), "square: " .. r.fgShape)
    end
    ns.settings.squareCorners = false
    ns.W.RefreshShapes()
    for _, r in ipairs(shaped) do
        local tex = r:GetTexture()
        check(not tex:find("square$") and not tex:find("ring0$"), "rounded: " .. r.fgShape)
    end
    for _, r in ipairs(dots) do check(r:GetTexture():find("circle$"), "dots stay circles") end
    ns.settings.squareCorners = true
    ns.W.RefreshShapes()
    for _, r in ipairs(shaped) do
        check(r:GetTexture():find("square$") or r:GetTexture():find("ring0$"), "square again: " .. r.fgShape)
    end
end)

step("incoming offer popup", function()
    ns.Comm.OnMessage("FastGroups", "O\tab12\t2\t1 loadout", "RAID", "Stranger-Silvermoon")
    check(stub.popup and stub.popup.which == "FASTGROUPS_OFFER", "popup shown")
    StaticPopupDialogs.FASTGROUPS_OFFER.OnAccept(nil, stub.popup.data)
end)

-- Fuzz: hover and click everything on every page.
local fuzzErrors = {}
local function fuzz(pageName)
    UI.ShowPage(pageName)
    local snapshot = {}
    for i, o in ipairs(M.objects) do snapshot[i] = o end
    for _, o in ipairs(snapshot) do
        for _, script in ipairs({ "OnEnter", "OnLeave", "OnClick" }) do
            local fn = o.scripts[script]
            if fn and o:IsVisible() then
                local ok, err = pcall(fn, o, "LeftButton")
                if not ok then fuzzErrors[pageName .. " " .. script .. ": " .. tostring(err)] = true end
                UI.CloseModal()
                if UI.current ~= pageName then UI.ShowPage(pageName) end
            end
        end
    end
end
step("fuzz", function()
    Board:SetSource("demo")
    for _, p in ipairs({ "groups", "rosters", "share", "options" }) do fuzz(p) end
    for msg in pairs(fuzzErrors) do print("FUZZ " .. msg) failures = failures + 1 end
end)

step("close window unregisters events", function()
    UI.Frame():Hide()
    local listening = {}
    for _, o in ipairs(stub.frames) do
        for e in pairs(o.events) do listening[e] = true end
    end
    check(not listening.GROUP_ROSTER_UPDATE, "roster events off when closed")
    check(not listening.INSPECT_READY, "inspect off when closed")
    check(not listening.PLAYER_SPECIALIZATION_CHANGED, "spec changes off when closed")
end)

print(failures == 0 and "ui smoke: ok" or ("ui smoke: " .. failures .. " failure(s)"))
if failures > 0 then os.exit(1) end
