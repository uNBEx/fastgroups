-- UI smoke test: builds every page against the mock frame API, drives the
-- main flows and then clicks / hovers every widget. Run: lua tests/ui_smoke.lua
package.path = "./tests/?.lua;" .. package.path
local stub = require("wow_stub")
local M = require("ui_mock")

local ns = {}
-- cold start: the window is built before the fonts have loaded (see "fonts arrive late")
M.fontsLoaded = false
local FILES = {
    "Core/Init.lua", "Core/Data.lua", "Core/Players.lua", "Core/Raid.lua", "Core/Board.lua",
    "Core/Split.lua", "Core/Loadouts.lua", "Core/Rosters.lua", "Core/Invite.lua", "Core/Apply.lua", "Core/Announce.lua", "Core/Demo.lua",
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
    local listening = false
    for _, o in ipairs(stub.frames) do
        if o.events.GROUP_ROSTER_UPDATE then listening = true end
    end
    check(listening, "first open runs OnShow and listens to the roster")
end)

step("demo raid renders 20 cards", function()
    SlashCmdList.FASTGROUPS("demo")
    check(Board.source == "demo", "demo source")
    check(#groups.activeCards == 20, "cards: " .. #groups.activeCards)
end)

step("fonts arrive late: text is measured again", function()
    local function textWidth(text)
        for _, o in ipairs(M.objects) do
            if o._kind == "FontString" and o._text == text then return o:GetParent():GetWidth() end
        end
    end
    local pill = textWidth("Mythic  -  20 players")
    local save = groups.save:GetWidth()
    check(not ns.T.fontsReady, "fonts not ready yet")
    M.fontsLoaded = true
    -- the font probes in Theme.lua see their strings grow
    for _, o in ipairs(M.objects) do
        local p = o._parent
        if o.scripts.OnSizeChanged and p and p ~= UI.Frame() and p._parent == UIParent then
            o.scripts.OnSizeChanged(o, 12, 14)
        end
    end
    check(ns.T.fontsReady, "fonts ready")
    check(textWidth("Mythic  -  20 players") > pill + 60, "status pill resized: " .. pill)
    check(groups.save:GetWidth() > save + 20, "button resized: " .. save)
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
    -- the last entry removed her from the raid
    check(not ns.Demo.members["Vexmora-Silvermoon"], "removed from demo raid")
    check(not Board.isMember["Vexmora-Silvermoon"], "removed from board")
    Board:SetSource("demo")
    check(#groups.activeCards == 20, "demo restored")
end)

local function modalButton(label, except)
    for _, o in ipairs(M.objects) do
        if o._kind == "Button" and o ~= except and o.label and o.label._text == label and o:IsVisible() then return o end
    end
end

step("offline player is marked", function()
    local c = cardFor("Stormjaw-Silvermoon")
    check(c.tag:IsShown() and c.tag.text._text == "OFFLINE", "offline tag")
    check(not cardFor("Thalric-Silvermoon").tag:IsShown(), "online has no tag")
end)

step("remove the bench from the raid", function()
    ns.settings.benchOpen = true
    groups:Refresh()
    check(not groups.bench.remove:IsShown(), "no button for an empty bench")
    Board:Move("Stormjaw-Silvermoon", 5)
    Board:Move("Arrowyn-Silvermoon", 6)
    check(groups.bench.meta._text:find("1 offline"), "bench meta counts offline: " .. groups.bench.meta._text)
    local b = groups.bench.remove
    check(b:IsShown() and not b.disabled, "button enabled")
    b.scripts.OnClick(b, "LeftButton")
    check(ns.Demo.members["Arrowyn-Silvermoon"], "nothing removed before confirming")
    modalButton("Cancel").scripts.OnClick(modalButton("Cancel"))
    check(ns.Demo.members["Arrowyn-Silvermoon"], "cancel keeps them")
    b.scripts.OnClick(b, "LeftButton")
    local ok = modalButton("Remove 2")
    check(ok, "confirm button")
    ok.scripts.OnClick(ok)
    check(not ns.Demo.members["Arrowyn-Silvermoon"] and not ns.Demo.members["Stormjaw-Silvermoon"], "bench removed")
    check(not b:IsShown(), "button hidden again")
    Board:SetSource("demo")
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

step("apply confirm with don't ask again", function()
    local Apply = ns.Apply
    local start, starts = Apply.Start, 0
    Apply.Start = function() starts = starts + 1; return true end
    Board.source = "live"
    Board:Move("Thalric-Silvermoon", 0)
    groups:OnApply()
    check(starts == 0, "dialog shown first")
    modalButton("Cancel").scripts.OnClick(modalButton("Cancel"))
    check(starts == 0 and ns.settings.confirmApply, "cancel keeps the setting")
    groups:OnApply()
    local skip = groups.skipConfirm.check
    check(skip:IsVisible() and not groups.skipConfirm.on, "check shown, off")
    skip.scripts.OnClick(skip)
    modalButton("Cancel").scripts.OnClick(modalButton("Cancel"))
    check(ns.settings.confirmApply, "cancel ignores the check")
    groups:OnApply()
    check(not groups.skipConfirm.on, "check resets per dialog")
    skip.scripts.OnClick(skip)
    for _, o in ipairs(M.objects) do
        if o ~= groups.apply and o._kind == "Button" and o.label and o.label._text == "Apply" and o:IsVisible() then
            o.scripts.OnClick(o)
            break
        end
    end
    check(starts == 1 and ns.settings.confirmApply == false, "applied and stopped asking")
    groups:OnApply()
    check(starts == 2 and not modalButton("Cancel"), "no dialog after opting out")
    ns.settings.confirmApply = true
    Apply.Start = start
    Board:SetSource("demo")
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

step("invite a loadout opened for editing", function()
    local source = Board.source
    Board:SetSource("none")
    UI.LoadLoadout(ns.Loadouts.List()[1].id)
    check(Board.source == "loadout", "opened for editing")
    local inv = groups.banner.b2
    check(inv:IsVisible() and inv.label._text == "Invite", "editing banner invites")
    local before = #stub.invited
    inv.scripts.OnClick(inv)
    local ok = modalButton("Invite", inv)
    check(ok, "invite asks first")
    ok.scripts.OnClick(ok)
    check(#stub.invited == before + 4 and ns.Invite.running, "solo: 4 invites, then waits")
    groups:Refresh()
    check(inv.label._text == "Cancel invites", "cancel while waiting")
    inv.scripts.OnClick(inv)
    check(not ns.Invite.running, "cancelled")
    Board:SetSource(source)
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
    check(not groups.banner.b3:IsShown(), "the demo invites nobody")
    -- the same board as a live raid (stand-in: the stub has no raid roster)
    Board.source = "live"
    groups:Refresh()
    local inv = groups.banner.b3
    check(inv:IsVisible() and inv.label._text == "Invite absent", "invite absent on a live raid")
    inv.scripts.OnClick(inv)
    check(modalButton("Invite"), "invite absent asks first")
    UI.CloseModal()
    Board.source = "demo"
    groups:Refresh()
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
    ns.W.CloseMenu()
    page.detail.add.scripts.OnClick(page.detail.add)
    local entries = ns.W.menuRoot.children
    check(#entries == 3 and entries[1].text == "From guild...", "add players menu")
    entries[1].fn()
    ns.W.CloseMenu()
    UI.CloseModal()
    local invite = page.detail.invite
    check(invite:IsVisible() and not invite.disabled, "invite button enabled")
    invite.scripts.OnClick(invite)
    local ok = modalButton("Invite")
    check(ok, "invite asks first")
    local before = #stub.invited
    ok.scripts.OnClick(ok)
    check(#stub.invited == before + 4 and ns.Invite.running, "solo: 4 invites, then waits")
    check(invite.label._text == "Cancel", "button cancels while waiting")
    invite.scripts.OnClick(invite)
    check(not ns.Invite.running and invite.label._text == "Invite", "cancelled")
    page.detail.plan.scripts.OnClick(page.detail.plan)
    check(Board.source == "roster", "planning source")
    check(UI.current == "groups", "switched to groups")
    check(groups.banner.b2:IsVisible() and groups.banner.b2.label._text == "Invite roster", "banner invites the roster")
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
    Board:SetConvention("oddeven")
end)

step("shared odd group board", function()
    UI.ShowPage("groups")
    Board:SetShared(true)
    SlashCmdList.FASTGROUPS("demo 13")
    check(#Board.members == 13, "13 player demo")
    groups.split.scripts.OnClick(groups.split, "LeftButton")
    check(Board:Shared() == 3, "group 3 shared")
    check(#groups.activeCards == 13, "cards: " .. #groups.activeCards)
    local sl, sr = groups.sharedCols.L, groups.sharedCols.R
    check(sl:IsVisible() and sr:IsVisible(), "both parts of the shared group shown")
    check(not groups.groups:IsShown() and groups.sharedBtn:IsShown(), "shared button replaces the groups control")
    check(groups.announce:IsShown(), "announce button")
    -- drag a shared player to the other half's part: only the side changes
    local key
    for _, k in ipairs(Board.members) do
        if Board.draft[k] == 3 and Board.sides[k] == "L" then key = k end
    end
    check(key, "someone on the left in the shared group")
    local c = cardFor(key)
    c.scripts.OnDragStart(c)
    sr._mouseOver = true
    c.scripts.OnDragStop(c)
    sr._mouseOver = false
    check(Board.draft[key] == 3 and Board.sides[key] == "R", "side changed")
    -- the card menu moves them back without a group move
    c = cardFor(key)
    c.scripts.OnClick(c, "RightButton")
    for _, e in ipairs(ns.W.menuRoot.children) do
        if e.text == "Move to Left" then e.fn() end
    end
    check(Board.draft[key] == 3 and Board.sides[key] == "L", "side changed back")
    stub.lastPrint = nil
    groups.announce.scripts.OnClick(groups.announce, "LeftButton")
    check(stub.lastPrint and stub.lastPrint:find("Group 3 is split"), "announced: " .. tostring(stub.lastPrint))
    -- columns in group order: side tags on the shared cards
    ns.settings.arrangeByHalf = false
    groups:Refresh()
    c = cardFor(key)
    check(c.tag:IsShown() and c.tag.text._text == "LEFT", "side tag on shared card")
    fuzz("groups")
    ns.settings.arrangeByHalf = true
    fuzz("groups")
    for msg in pairs(fuzzErrors) do print("FUZZ " .. msg) failures = failures + 1 end
    Board:SetShared(false)
    SlashCmdList.FASTGROUPS("demo")
    check(#Board.members == 20 and Board:K() == 4, "back to the Mythic demo")
end)

step("simple mode board", function()
    UI.ShowPage("groups")
    SlashCmdList.FASTGROUPS("demo")
    Board:SetConvention("oddeven")
    groups:Refresh()
    check(groups.split:IsShown() and groups.chip:IsShown(), "split mode toolbar")
    Board:SetConvention("none")
    check(not groups.split:IsShown(), "no Auto-split")
    check(not groups.chip:IsShown(), "no balance chip")
    check(not groups.announce:IsShown(), "no announce button")
    check(groups.single:IsVisible(), "one panel")
    check(not groups.halves.L:IsVisible() and not groups.halves.R:IsVisible(), "no halves")
    local p = groups.single
    check(p.counters.A:IsShown() and not p.counters.L:IsShown() and not p.counters.R:IsShown(), "one counter row")
    check(p.counters.A.lbl._text == "GROUPS 1-4", "counter label: " .. tostring(p.counters.A.lbl._text))
    for _, c in ipairs(groups.activeCards) do
        local t = c.tag:IsShown() and c.tag.text._text
        check(t ~= "LEFT" and t ~= "RIGHT", "no side tags: " .. tostring(t))
    end
    for g = 1, 4 do check(not groups.columns[g].sideTag:IsShown(), "no column side tag") end
    local c = cardFor("Thalric-Silvermoon")
    c.scripts.OnClick(c, "RightButton")
    for _, e in ipairs(ns.W.menuRoot.children) do
        check(not (e.text or ""):find("^Move to "), "no half move in the menu")
    end
    fuzz("groups")
    Board:SetConvention("none")
    fuzz("options")
    for msg in pairs(fuzzErrors) do print("FUZZ " .. msg) failures = failures + 1 end
    Board:SetConvention("oddeven")
    ns.settings.arrangeByHalf = true   -- the options fuzz flips toggles
    UI.ShowPage("groups")
    check(groups.halves.L:IsShown() and not groups.single:IsShown(), "halves back")
end)

step("narrow and wide windows fit", function()
    local frame = UI.Frame()
    local w0, h0 = frame:GetSize()
    Board:SetSource("demo")
    local function toolbarFits()
        local tb = groups.toolbar
        local sum, n = 0, 0
        for _, c in ipairs({ groups.sourceBtn, groups.conv, groups.groups, groups.sharedBtn, groups.chip,
            groups.split, groups.announce, groups.revert, groups.save, groups.stop, groups.apply }) do
            if c:IsShown() then sum, n = sum + c:GetWidth(), n + 1 end
        end
        return sum + 6 * (n - 1) + 8 + 2 * 14 <= tb:GetWidth()
    end
    local function countersFit(f)
        local x = 0
        for _, c in ipairs(f.roles) do
            if c:IsShown() then x = x + c:GetWidth() + 5 end
        end
        return x - 5 <= f:GetWidth()
    end
    -- the mock gives a page the window's width, so 755 is the real minimum page width
    frame:SetSize(755, 560)
    UI.ShowPage("groups")
    groups:Refresh()
    check(groups.toolbarRows == 2 or toolbarFits(), "narrow toolbar overlaps")
    for _, side in ipairs({ "L", "R" }) do
        check(countersFit(groups.halves[side].counters), "narrow counters overflow on " .. side)
    end
    UI.ShowPage("options")
    check(UI.pages.options.columns == 1, "one options column when narrow")
    UI.ShowPage("rosters")
    -- the mock font is narrower than the game's: go tighter so the wrap and the
    -- numbers-only counters run too
    frame:SetSize(560, 560)
    UI.ShowPage("groups")
    groups:Refresh()
    check(groups.toolbarRows == 2, "toolbar wraps")
    check(not groups.halves.L.counters.roles[1].label:IsShown(), "counters drop labels")
    check(countersFit(groups.halves.L.counters), "tight counters overflow")

    frame:SetSize(1600, 800)
    UI.ShowPage("groups")
    groups:Refresh()
    check(groups.toolbarRows == 1 and toolbarFits(), "wide toolbar on one row")
    check(groups.split.label:GetText() == "Auto-split", "wide toolbar keeps labels")
    UI.ShowPage("options")
    check(UI.pages.options.columns == 2, "two options columns when wide")
    frame:SetSize(w0, h0)
    UI.ShowPage("groups")
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
