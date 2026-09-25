-- Main window: title bar, sidebar (navigation + loadouts), page host, modal,
-- toasts. Built the first time the window opens.
local _, ns = ...

local T, W = ns.T, ns.W
local Board, Loadouts = ns.Board, ns.Loadouts

local UI = { pages = {}, order = {} }
ns.UI = UI

local SIDEBAR_W = 204
local TITLE_H = 38
local frame -- main window

function UI.RegisterPage(name, page)
    UI.pages[name] = page
    tinsert(UI.order, name)
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------
local toastPool, toastActive = {}, {}

local function layoutToasts()
    local y = 14
    for i = #toastActive, 1, -1 do
        local t = toastActive[i]
        t:ClearAllPoints()
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, y)
        y = y + t:GetHeight() + 8
    end
end

local function releaseToast(t)
    for i, x in ipairs(toastActive) do
        if x == t then tremove(toastActive, i) break end
    end
    t:Hide()
    tinsert(toastPool, t)
    layoutToasts()
end

local TOAST_COLOR = { info = nil, ok = "ok", warn = "warn", error = "danger" }

local function newToast()
    local t = CreateFrame("Frame", nil, frame)
    t:SetFrameStrata("DIALOG")
    t:SetWidth(320)
    W.Skin(t, "panel2", "line2")
    t.stripe = W.Rect(t, "ARTWORK")
    t.stripe:SetPoint("TOPLEFT", 1, -5)
    t.stripe:SetPoint("BOTTOMLEFT", 1, 5)
    t.stripe:SetWidth(3)
    t.text = W.Text(t, 12, "regular", "text")
    t.text:SetWordWrap(true)
    t.text:SetPoint("TOPLEFT", 14, -10)
    t.text:SetPoint("RIGHT", -12, 0)
    t.barBg = W.Round(t, "ARTWORK", "round3", T.Color("panel3"))
    t.barBg:SetHeight(3)
    t.barBg:SetPoint("BOTTOMLEFT", 14, 9)
    t.barBg:SetPoint("BOTTOMRIGHT", -12, 9)
    t.bar = W.Rect(t, "OVERLAY")
    t.bar:SetHeight(3)
    t.bar:SetPoint("LEFT", t.barBg, "LEFT")
    return t
end

local function setupToast(t, text, kind, progress)
    local c = TOAST_COLOR[kind or "info"]
    if c then t.stripe:SetVertexColor(T.Color(c)) else t.stripe:SetVertexColor(T.Accent()) end
    t.text:SetText(text)
    local h = t.text:GetStringHeight() + 20
    if progress then
        t.barBg:Show()
        t.bar:Show()
        t.bar:SetVertexColor(T.Accent())
        t.bar:SetWidth(math.max(1, (t:GetWidth() - 26) * progress))
        h = h + 8
    else
        t.barBg:Hide()
        t.bar:Hide()
    end
    t:SetHeight(h)
end

-- Short message in the window, or in chat when the window is closed.
function UI.Toast(text, kind, duration)
    if not frame or not frame:IsShown() then
        ns.Print(text)
        return
    end
    local t = tremove(toastPool) or newToast()
    t.gen = (t.gen or 0) + 1
    setupToast(t, text, kind)
    t:Show()
    tinsert(toastActive, t)
    if #toastActive > 4 then releaseToast(toastActive[1]) end
    layoutToasts()
    local gen = t.gen
    C_Timer.After(duration or 4, function()
        if t.gen == gen and t:IsShown() then releaseToast(t) end
    end)
end

-- One persistent progress toast (apply).
local progressToast
function UI.Progress(text, pct)
    if not frame then return end
    if not progressToast then progressToast = newToast() end
    setupToast(progressToast, text, "info", pct or 0)
    if not progressToast:IsShown() then
        progressToast:Show()
        tinsert(toastActive, progressToast)
    end
    layoutToasts()
end

function UI.ProgressDone()
    if progressToast and progressToast:IsShown() then
        for i, x in ipairs(toastActive) do
            if x == progressToast then tremove(toastActive, i) break end
        end
        progressToast:Hide()
        layoutToasts()
    end
end

---------------------------------------------------------------------------
-- Modal dialog inside the window
---------------------------------------------------------------------------
local modal

local function buildModal()
    modal = CreateFrame("Frame", nil, frame)
    modal:SetAllPoints()
    modal:SetFrameStrata("DIALOG")
    modal:SetFrameLevel(frame:GetFrameLevel() + 200)
    modal:EnableMouse(true)
    modal.dim = W.Round(modal, "BACKGROUND", "round", 0.01, 0.015, 0.03, 0.72)
    modal.dim:SetAllPoints()
    local box = CreateFrame("Frame", nil, modal)
    box:SetWidth(420)
    box:SetPoint("CENTER", 0, 30)
    W.Skin(box, "panel", "line2")
    box:EnableMouse(true)
    modal.box = box
    modal.title = W.Text(box, 15, "bold", "text")
    modal.title:SetPoint("TOPLEFT", 18, -18)
    modal.text = W.Text(box, 12, "regular", "muted")
    modal.text:SetWordWrap(true)
    modal.text:SetPoint("TOPLEFT", modal.title, "BOTTOMLEFT", 0, -8)
    modal.text:SetPoint("RIGHT", -18, 0)
    modal.input = W.Edit(box, { width = 384, height = 30 })
    modal.buttons = {}
    modal:SetScript("OnMouseDown", function() end)
    modal:Hide()
end

--[[ opts: title, text, input = { text, placeholder, maxLetters }, content = frame,
  contentHeight, width, buttons = { { text, kind, onClick(inputText) -> keepOpen } }, onClose ]]
function UI.Modal(opts)
    if not frame then return end
    if not modal then buildModal() end
    UI.CloseModal()
    local box = modal.box
    box:SetWidth(opts.width or 420)
    modal.title:SetText(opts.title or "")
    modal.text:SetText(opts.text or "")
    local y = 18 + modal.title:GetStringHeight() + 8
    if opts.text and opts.text ~= "" then
        y = y + modal.text:GetStringHeight() + 14
    end
    if opts.input then
        modal.input:ClearAllPoints()
        modal.input:SetPoint("TOPLEFT", 18, -y)
        modal.input:SetWidth((opts.width or 420) - 36)
        modal.input:SetText(opts.input.text or "")
        modal.input.placeholder:SetText(opts.input.placeholder or "")
        modal.input.edit:SetMaxLetters(opts.input.maxLetters or 0)
        modal.input:Show()
        y = y + 30 + 14
    else
        modal.input:Hide()
    end
    if opts.content then
        opts.content:SetParent(box)
        opts.content:ClearAllPoints()
        opts.content:SetPoint("TOPLEFT", 18, -y)
        opts.content:SetPoint("RIGHT", -18, 0)
        opts.content:SetHeight(opts.contentHeight or 200)
        opts.content:Show()
        y = y + (opts.contentHeight or 200) + 14
    end
    modal.content = opts.content
    modal.onClose = opts.onClose
    for _, b in ipairs(modal.buttons) do b:Hide() end
    local x = -18
    local list = opts.buttons or { { text = "OK", kind = "primary" } }
    for i = #list, 1, -1 do
        local spec = list[i]
        local b = modal.buttons[i]
        if not b then
            b = W.Button(box, { text = "", height = 30 })
            modal.buttons[i] = b
        end
        b:SetKind(spec.kind or "default")
        b:SetLabel(spec.text)
        b:SetDisabled(false)
        b:SetScript("OnClick", function()
            local keep = spec.onClick and spec.onClick(modal.input:GetText())
            if not keep then UI.CloseModal() end
        end)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", x, 16)
        b:Show()
        x = x - b:GetWidth() - 8
    end
    box:SetHeight(y + 30 + 16)
    modal:Show()
    if opts.input then
        modal.input.edit:SetFocus()
        modal.input.edit:HighlightText()
        modal.input.edit:SetScript("OnEnterPressed", function()
            local first = list[#list]
            local keep = first.onClick and first.onClick(modal.input:GetText())
            if not keep then UI.CloseModal() end
        end)
    end
end

function UI.CloseModal()
    if not modal or not modal:IsShown() then return end
    modal:Hide()
    modal.input.edit:ClearFocus()
    if modal.content then modal.content:Hide() end
    local cb = modal.onClose
    modal.onClose = nil
    if cb then cb() end
end

function UI.Confirm(title, text, okText, onOk, danger)
    UI.Modal({
        title = title, text = text,
        buttons = {
            { text = "Cancel", kind = "ghost" },
            { text = okText or "OK", kind = danger and "danger" or "primary", onClick = function() onOk() end },
        },
    })
end

---------------------------------------------------------------------------
-- Sidebar: loadout list
---------------------------------------------------------------------------
local sidebar, loadoutRows, loadoutScroll, filterBox
local ROW_H = 42

local function convLabel(conv, k)
    local L, R = Board.HalvesFor(conv or "oddeven", k or 4)
    if conv == "split" then
        return L[1] .. "-" .. L[#L] .. " / " .. R[1] .. "-" .. R[#R]
    end
    return "Odd / Even"
end
UI.ConvLabel = convLabel

local function loadoutMenu(row)
    local lo = Loadouts.Find(row.id)
    if not lo then return end
    W.Menu(row, function(_, root)
        root:CreateTitle(lo.name)
        root:CreateButton("Load", function() UI.LoadLoadout(lo.id) end)
        root:CreateButton("Rename", function() UI.RenameLoadout(lo.id) end)
        root:CreateButton("Duplicate", function() Loadouts.Duplicate(lo.id) end)
        root:CreateButton("Share", function() UI.ShareLoadout(lo.id) end)
        root:CreateDivider()
        root:CreateButton("|cffff6b6bDelete|r", function() UI.DeleteLoadout(lo.id) end)
    end)
end

local function rowShowActions(row, on)
    row.actions:SetShown(on)
    row.meta:SetPoint("RIGHT", on and -84 or -8, 0)
end

local function newLoadoutRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row.bg = W.Round(row, "BACKGROUND", "round", T.Color("panel"))
    row.bg:SetAllPoints()
    row.bg:Hide()
    row.border = W.Round(row, "BORDER", "ring", T.Color("line2"))
    row.border:SetAllPoints()
    row.border:Hide()
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(T.TEX.circle)
    row.dot:SetSize(6, 6)
    row.dot:SetPoint("TOPLEFT", 10, -12)
    row.name = W.Text(row, 12, "semibold", "text")
    row.name:SetPoint("TOPLEFT", 10, -7)
    row.name:SetPoint("RIGHT", -8, 0)
    row.meta = W.Text(row, 10.5, "regular", "dim")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.meta:SetPoint("RIGHT", -8, 0)
    row.actions = CreateFrame("Frame", nil, row)
    row.actions:SetSize(78, 22)
    row.actions:SetPoint("RIGHT", -4, 0)
    W.Skin(row.actions, "panel")
    local function act(icon, tip, fn, x)
        local b = W.IconButton(row.actions, icon, 22, tip, function() fn(row.id) end)
        b:SetPoint("LEFT", x, 0)
        b:HookScript("OnLeave", function() if not row:IsMouseOver() then rowShowActions(row, false) end end)
    end
    act("nav_share", "Share", function(id) UI.ShareLoadout(id) end, 2)
    act("copy", "Duplicate", function(id) Loadouts.Duplicate(id) end, 28)
    act("trash", "Delete", function(id) UI.DeleteLoadout(id) end, 54)
    row.actions:Hide()
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            loadoutMenu(self)
        else
            UI.LoadLoadout(self.id)
        end
    end)
    row:SetScript("OnEnter", function(self)
        self.bg:Show()
        rowShowActions(self, true)
    end)
    row:SetScript("OnLeave", function(self)
        if not self.active then self.bg:Hide() end
        if not self:IsMouseOver() then rowShowActions(self, false) end
    end)
    return row
end

function UI.RefreshLoadouts()
    if not sidebar then return end
    local filter = strlower(filterBox:GetText() or "")
    local child = loadoutScroll.child
    local y = 0
    local n = 0
    for _, lo in ipairs(Loadouts.List()) do
        if filter == "" or strlower(lo.name):find(filter, 1, true) then
            n = n + 1
            local row = loadoutRows[n]
            if not row then
                row = newLoadoutRow(child)
                loadoutRows[n] = row
            end
            row.id = lo.id
            row.active = Board.activeLoadout == lo.id
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
            row.name:SetText(lo.name)
            row.meta:SetText(Loadouts.Count(lo) .. " players  -  " .. convLabel(lo.conv, lo.k) .. "  -  " .. W.Ago(lo.updated))
            row.bg:SetShown(row.active)
            row.border:SetShown(row.active)
            row.dot:SetShown(row.active)
            row.dot:SetVertexColor(T.Accent())
            row.name:SetPoint("TOPLEFT", row.active and 22 or 10, -7)
            row:Show()
            y = y + ROW_H + 2
        end
    end
    for i = n + 1, #loadoutRows do loadoutRows[i]:Hide() end
    child:SetHeight(math.max(y, 1))
    if n == 0 then
        sidebar.empty:SetText(#Loadouts.List() == 0 and "No loadouts yet.\nSet up groups and press Save." or "No match.")
        sidebar.empty:Show()
    else
        sidebar.empty:Hide()
    end
    sidebar.count:SetText(#Loadouts.List() .. " saved")
end

function UI.LoadLoadout(id)
    Loadouts.Load(id)
    UI.ShowPage("groups")
    local l = Board.loaded
    if l and l.absent == 0 and l.fresh == 0 and l.returning == 0 then
        local n = Board:Pending()
        UI.Toast("Loaded \"" .. l.name .. "\". Everyone is here" .. (Board:IsLiveLike() and (", " .. n .. " move" .. (n == 1 and "" or "s") .. " pending.") or "."), "ok")
        Board.loaded = nil
        Board:Changed()
    end
end

function UI.RenameLoadout(id)
    local lo = Loadouts.Find(id)
    if not lo then return end
    UI.Modal({
        title = "Rename loadout",
        input = { text = lo.name, maxLetters = 48 },
        buttons = {
            { text = "Cancel", kind = "ghost" },
            { text = "Rename", kind = "primary", onClick = function(text) Loadouts.Rename(id, text) end },
        },
    })
end

function UI.DeleteLoadout(id)
    local lo = Loadouts.Find(id)
    if not lo then return end
    UI.Confirm("Delete \"" .. lo.name .. "\"?", "This cannot be undone. Export it first if you might need it again.",
        "Delete", function() Loadouts.Delete(id) end, true)
end

function UI.ShareLoadout(id)
    UI.ShowPage("share")
    local page = UI.pages.share
    if page and page.Select then page:Select(id) end
end

local function buildSidebar()
    sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 1, -TITLE_H)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_W)
    -- background with only the bottom-left corner rounded
    local r, g, b = T.Color("side")
    local corner = sidebar:CreateTexture(nil, "BACKGROUND")
    corner:SetTexture(T.TEX.round)
    corner:SetTexCoord(0, 0.5, 0.5, 1)
    corner:SetVertexColor(r, g, b)
    corner:SetSize(16, 16)
    corner:SetPoint("BOTTOMLEFT")
    local main = W.Rect(sidebar, "BACKGROUND", r, g, b)
    main:SetPoint("TOPLEFT")
    main:SetPoint("BOTTOMRIGHT", 0, 16)
    local foot = W.Rect(sidebar, "BACKGROUND", r, g, b)
    foot:SetPoint("BOTTOMLEFT", 16, 0)
    foot:SetPoint("TOPRIGHT", sidebar, "BOTTOMRIGHT", 0, 16)
    local line = W.Rect(sidebar, "BORDER", T.Color("line"))
    line:SetPoint("TOPRIGHT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetWidth(1)

    -- navigation
    sidebar.nav = {}
    local NAV = {
        { "groups", "Groups", "nav_groups" },
        { "rosters", "Rosters", "nav_rosters" },
        { "share", "Share", "nav_share" },
        { "options", "Options", "nav_options" },
    }
    local y = -10
    for _, n in ipairs(NAV) do
        local bt = CreateFrame("Button", nil, sidebar)
        bt:SetHeight(32)
        bt:SetPoint("TOPLEFT", 8, y)
        bt:SetPoint("RIGHT", -8, 0)
        bt.bg = W.Round(bt, "BACKGROUND", "round")
        bt.bg:SetAllPoints()
        bt.bar = W.Round(bt, "ARTWORK", "round3")
        bt.bar:SetSize(3, 16)
        bt.bar:SetPoint("LEFT", -8, 0)
        bt.icon = W.Icon(bt, n[3], 16)
        bt.icon:SetPoint("LEFT", 10, 0)
        bt.label = W.Text(bt, 12.5, "semibold", "muted")
        bt.label:SetPoint("LEFT", bt.icon, "RIGHT", 10, 0)
        bt.label:SetText(n[2])
        bt.page = n[1]
        bt:SetScript("OnClick", function(self) UI.ShowPage(self.page) end)
        bt:SetScript("OnEnter", function(self) self.hover = true UI.RefreshNav() end)
        bt:SetScript("OnLeave", function(self) self.hover = false UI.RefreshNav() end)
        sidebar.nav[n[1]] = bt
        y = y - 34
    end

    -- loadouts
    local head = W.Text(sidebar, 10.5, "bold", "dim")
    head:SetText("LOADOUTS")
    head:SetPoint("TOPLEFT", 16, y - 16)
    local add = W.IconButton(sidebar, "plus", 22, "Save the current setup as a loadout", function() UI.SaveDialog() end)
    add:SetPoint("RIGHT", sidebar, "RIGHT", -10, 0)
    add:SetPoint("TOP", head, "TOP", 0, 5)

    filterBox = W.Edit(sidebar, { height = 28, placeholder = "Filter loadouts", onChange = function() UI.RefreshLoadouts() end })
    filterBox:SetPoint("TOPLEFT", 10, y - 36)
    filterBox:SetPoint("RIGHT", -10, 0)
    local search = W.Icon(filterBox, "search", 12, T.Color("dim"))
    search:SetPoint("LEFT", 9, 0)
    filterBox.edit:SetPoint("TOPLEFT", 26, 0)
    filterBox.placeholder:SetPoint("LEFT", 27, 0)

    loadoutScroll = W.Scroll(sidebar)
    loadoutScroll:SetPoint("TOPLEFT", 8, y - 72)
    loadoutScroll:SetPoint("BOTTOMRIGHT", -14, 34)
    loadoutRows = {}

    sidebar.empty = W.Text(sidebar, 11.5, "regular", "dim")
    sidebar.empty:SetWordWrap(true)
    sidebar.empty:SetJustifyH("LEFT")
    sidebar.empty:SetPoint("TOPLEFT", loadoutScroll, "TOPLEFT", 6, -6)
    sidebar.empty:SetPoint("RIGHT", -12, 0)

    local fline = W.Rect(sidebar, "BORDER", T.Color("line"))
    fline:SetHeight(1)
    fline:SetPoint("BOTTOMLEFT", 0, 28)
    fline:SetPoint("BOTTOMRIGHT", -1, 28)
    local slash = W.Text(sidebar, 10.5, "regular", "dim")
    slash:SetText("/fg  -  /fastgroups")
    slash:SetPoint("BOTTOMLEFT", 14, 9)
    sidebar.count = W.Text(sidebar, 10.5, "regular", "dim")
    sidebar.count:SetPoint("BOTTOMRIGHT", -14, 9)

    T.OnAccent(function() UI.RefreshNav() UI.RefreshLoadouts() end)
end

function UI.RefreshNav()
    if not sidebar then return end
    local ar, ag, ab = T.Accent()
    for name, bt in pairs(sidebar.nav) do
        local on = UI.current == name
        if on then
            bt.bg:SetVertexColor(ar, ag, ab, 0.14)
            bt.bar:Show()
            bt.bar:SetVertexColor(ar, ag, ab)
            bt.icon:SetVertexColor(ar, ag, ab)
            bt.label:SetTextColor(T.Color("text"))
        else
            local r, g, b = T.Color("panel")
            bt.bg:SetVertexColor(r, g, b, bt.hover and 1 or 0)
            bt.bar:Hide()
            bt.icon:SetVertexColor(T.Color(bt.hover and "text" or "muted"))
            bt.label:SetTextColor(T.Color(bt.hover and "text" or "muted"))
        end
    end
end

---------------------------------------------------------------------------
-- Title bar status
---------------------------------------------------------------------------
local pills = {}

function UI.RefreshStatus()
    if not frame then return end
    local p1, p2, p3 = pills[1], pills[2], pills[3]
    p1:Hide() p2:Hide() p3:Hide()
    local src = Board.source
    if src == "live" then
        local rank = ns.Raid:MyRank()
        if rank == "leader" then p1:Set("Raid Leader", "ok")
        elseif rank == "assist" then p1:Set("Assistant", "ok")
        else p1:Set("Member - read only", "warn") end
        local diff = ns.Raid:DifficultyName()
        p2:Set((diff and (diff .. "  -  ") or "") .. ns.Raid.count .. " players")
    elseif src == "demo" then
        p1:Set("Demo raid", "warn")
        p2:Set("Mythic  -  20 players")
    elseif src == "roster" then
        local r = ns.Rosters.Find(Board.sourceId)
        p1:Set("Planning" .. (r and (": " .. r.name) or ""), "warn")
    elseif src == "loadout" then
        local lo = Loadouts.Find(Board.sourceId)
        p1:Set("Editing" .. (lo and (": " .. lo.name) or ""), "warn")
    else
        p1:Set(IsInRaid() and "In a raid" or "Not in a raid", nil)
    end
    if InCombatLockdown() then p3:Set("In combat", "danger") end
    local x = -44
    for i = 3, 1, -1 do
        local p = pills[i]
        if p:IsShown() then
            p:ClearAllPoints()
            p:SetPoint("RIGHT", frame, "TOPRIGHT", x, -TITLE_H / 2)
            x = x - p:GetWidth() - 6
        end
    end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local pageHost

function UI.ShowPage(name)
    if not frame then UI.Show(name) return end
    name = UI.pages[name] and name or "groups"
    local page = UI.pages[name]
    if UI.current and UI.current ~= name then
        local old = UI.pages[UI.current]
        if old.frame then old.frame:Hide() end
        if old.OnHide then old:OnHide() end
    end
    UI.current = name
    if not page.frame then
        page.frame = CreateFrame("Frame", nil, pageHost)
        page.frame:SetAllPoints()
        page:Build(page.frame)
    end
    page.frame:Show()
    if page.OnShow then page:OnShow() end
    page:Refresh()
    UI.RefreshNav()
    UI.CloseModal()
end

function UI.RefreshPage()
    local page = UI.current and UI.pages[UI.current]
    if page and page.frame and page.frame:IsShown() then page:Refresh() end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.settings.window.point = { point, relPoint, x, y }
end

local function restorePosition()
    local s = ns.settings.window
    frame:ClearAllPoints()
    frame:SetSize(s.w or 1040, s.h or 660)
    if s.point then
        frame:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
    else
        frame:SetPoint("CENTER")
    end
end

function UI.ResetPosition()
    ns.settings.window.point = nil
    if frame then restorePosition() end
end

local function onRoster()
    if InCombatLockdown() then
        UI.RefreshStatus()
        return
    end
    Board:AutoSource()
    ns.Inspect:SetActive(true)
    UI.RefreshStatus()
end

local function onCombat()
    UI.RefreshStatus()
    UI.RefreshPage()
end

local function onCombatEnd()
    onRoster()
    UI.RefreshPage()
end

local function onDifficulty()
    Board:Changed()
    UI.RefreshStatus()
end

local function build()
    frame = CreateFrame("Frame", "FastGroupsMainFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(960, 560)
    frame:EnableMouse(true)
    frame:SetScale(ns.settings.scale or 1)
    tinsert(UISpecialFrames, "FastGroupsMainFrame")
    W.Skin(frame, "win", "line2")
    restorePosition()

    -- title bar
    local title = CreateFrame("Frame", nil, frame)
    title:SetPoint("TOPLEFT", 1, -1)
    title:SetPoint("TOPRIGHT", -1, -1)
    title:SetHeight(TITLE_H - 1)
    title:EnableMouse(true)
    title:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" then frame:StartMoving() end end)
    title:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    local tline = W.Rect(title, "BORDER", T.Color("line"))
    tline:SetHeight(1)
    tline:SetPoint("BOTTOMLEFT")
    tline:SetPoint("BOTTOMRIGHT")
    local logo = W.Icon(title, "logo", 18)
    logo:SetPoint("LEFT", 14, 0)
    T.OnAccent(function(r, g, b) logo:SetVertexColor(r, g, b) end)
    local name = W.Text(title, 13.5, "bold", "text")
    name:SetText("FastGroups")
    name:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    local ver = W.Text(title, 10.5, "regular", "dim")
    ver:SetText(ns.version)
    ver:SetPoint("LEFT", name, "RIGHT", 6, -1)
    local close = W.IconButton(title, "close", 26, nil, function() frame:Hide() end)
    close:SetPoint("RIGHT", -8, 0)
    for i = 1, 3 do pills[i] = W.Pill(title) end

    -- resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 50)
    grip.icon = W.Icon(grip, "grip", 16)
    grip.icon:SetAllPoints()
    local function paintGrip()
        if grip.sizing then
            grip.icon:SetVertexColor(T.Accent())
        else
            grip.icon:SetVertexColor(T.Color(grip:IsMouseOver() and "muted" or "dim"))
        end
    end
    T.OnAccent(paintGrip)
    grip:SetScript("OnEnter", function()
        SetCursor("UI_RESIZE_CURSOR")
        paintGrip()
    end)
    grip:SetScript("OnLeave", function()
        if not grip.sizing then SetCursor(nil) end
        paintGrip()
    end)
    grip:SetScript("OnMouseDown", function()
        grip.sizing = true
        paintGrip()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        grip.sizing = nil
        if not grip:IsMouseOver() then SetCursor(nil) end
        paintGrip()
        ns.settings.window.w, ns.settings.window.h = frame:GetSize()
        savePosition()
    end)

    buildSidebar()

    pageHost = CreateFrame("Frame", nil, frame)
    pageHost:SetPoint("TOPLEFT", SIDEBAR_W + 1, -TITLE_H)
    pageHost:SetPoint("BOTTOMRIGHT", -1, 1)

    frame:SetScript("OnShow", function()
        ns.RegisterEvent(UI, "GROUP_ROSTER_UPDATE", onRoster)
        ns.RegisterEvent(UI, "PLAYER_REGEN_DISABLED", onCombat)
        ns.RegisterEvent(UI, "PLAYER_REGEN_ENABLED", onCombatEnd)
        ns.RegisterEvent(UI, "PLAYER_DIFFICULTY_CHANGED", onDifficulty)
        if not InCombatLockdown() then Board:AutoSource() end
        ns.Inspect:SetActive(true)
        UI.RefreshStatus()
        UI.RefreshLoadouts()
        UI.RefreshPage()
    end)
    frame:SetScript("OnHide", function()
        ns.UnregisterEvent(UI, "GROUP_ROSTER_UPDATE")
        ns.UnregisterEvent(UI, "PLAYER_REGEN_DISABLED")
        ns.UnregisterEvent(UI, "PLAYER_REGEN_ENABLED")
        ns.UnregisterEvent(UI, "PLAYER_DIFFICULTY_CHANGED")
        ns.Inspect:SetActive(false)
        UI.CloseModal()
        W.CloseMenu()
        local page = UI.current and UI.pages[UI.current]
        if page and page.OnHide then page:OnHide() end
    end)
    frame:SetScript("OnSizeChanged", function()
        UI.RefreshPage()
    end)

    ns.On("BOARD_CHANGED", UI, function()
        if frame:IsShown() then
            UI.RefreshStatus()
            UI.RefreshLoadouts()
            if UI.current == "groups" then UI.RefreshPage() end
        end
    end)
    ns.On("LOADOUTS_CHANGED", UI, function() if frame:IsShown() then UI.RefreshLoadouts() UI.RefreshPage() end end)
    ns.On("ROSTERS_CHANGED", UI, function() if frame:IsShown() then UI.RefreshPage() end end)
    ns.On("PLAYER_INFO_CHANGED", UI, function() if frame:IsShown() then UI.RefreshPage() end end)
    ns.On("SETTINGS_CHANGED", UI, function(_, what)
        if what == "scale" then frame:SetScale(ns.settings.scale) end
        if frame:IsShown() then
            UI.RefreshLoadouts()
            UI.RefreshPage()
        end
    end)
    ns.On("APPLY_STATE", UI, function(_, ok, reason, demoMoves)
        UI.OnApplyState(ok, reason, demoMoves)
    end)
    ns.On("APPLY_PROGRESS", UI, function()
        local a = ns.Apply
        local pct = a.total > 0 and a.done / a.total or 0
        local who = a.lastKey and ns.Players.ShortName(a.lastKey)
        local text = a.waiting and ("Waiting for the server... (" .. a.done .. "/" .. a.total .. ")  Click Apply to nudge it.")
            or ("Moving " .. (who or "") .. " to group " .. (a.lastGroup or "?") .. "  (" .. a.done .. "/" .. a.total .. ")")
        UI.Progress(text, pct)
        if UI.current == "groups" then UI.RefreshPage() end
    end)
    ns.On("COMM_STATUS", UI, function(_, kind, a, b) UI.OnCommStatus(kind, a, b) end)
end

local REASONS = {
    combat = "Stopped: combat started. Press Apply again after combat.",
    stuck = "Stopped: no legal move left. Check that no group has more than 5 players.",
    busy = "Stopped: the remaining players are in combat.",
    stopped = "Apply stopped.",
}

function UI.OnApplyState(ok, reason, demoMoves)
    if not frame then return end
    if ok == nil then
        UI.Progress("Applying...", 0)
    else
        UI.ProgressDone()
        if ok then
            if demoMoves then
                UI.Toast("Demo: groups applied with " .. demoMoves .. " server move" .. (demoMoves == 1 and "" or "s") .. ".", "ok")
            else
                UI.Toast("Raid groups applied (" .. ns.Apply.total .. " move" .. (ns.Apply.total == 1 and "" or "s") .. ").", "ok")
            end
        else
            UI.Toast(REASONS[reason] or ("Apply stopped: " .. tostring(reason)), "warn", 6)
        end
    end
    UI.RefreshPage()
end

function UI.OnCommStatus(kind, a, b)
    if kind == "sent" then
        UI.Toast("Sent to " .. ns.Players.DisplayName(a) .. ".", "ok")
    elseif kind == "receiving" then
        UI.Toast("Receiving from " .. ns.Players.DisplayName(a) .. "...")
    elseif kind == "received" then
        UI.Toast("Received " .. b .. " loadout" .. (b == 1 and "" or "s") .. " from " .. ns.Players.DisplayName(a) .. ".", "ok", 6)
    elseif kind == "declined" then
        UI.Toast(ns.Players.DisplayName(a) .. " declined.", "warn")
    elseif kind == "error" then
        UI.Toast(a or "Transfer failed.", "error", 6)
    end
end

function UI.Show(page)
    if not ns.db then return end
    if not frame then build() end
    frame:Show()
    UI.ShowPage(page or UI.current or "groups")
end

function UI.Toggle(page)
    if frame and frame:IsShown() and (not page or page == UI.current) then
        frame:Hide()
    else
        UI.Show(page)
    end
end

function UI.Frame() return frame end

---------------------------------------------------------------------------
-- Save dialog (used by the sidebar and the groups toolbar)
---------------------------------------------------------------------------
function UI.SaveDialog()
    local cur = Loadouts.Find(Board.activeLoadout)
    local buttons = { { text = "Cancel", kind = "ghost" } }
    local function save(text, overwrite)
        if #Board.members == 0 and #Board.ghosts == 0 then
            UI.Toast("The board is empty; nothing to save.", "warn")
            return
        end
        local lo = Loadouts.SaveCurrent(text, overwrite and cur and cur.id or nil)
        UI.Toast("Saved \"" .. lo.name .. "\".", "ok")
    end
    if cur then
        tinsert(buttons, { text = "Save as new", onClick = function(text) save(text, false) end })
        tinsert(buttons, { text = "Overwrite", kind = "primary", onClick = function(text) save(text, true) end })
    else
        tinsert(buttons, { text = "Save", kind = "primary", onClick = function(text) save(text, false) end })
    end
    UI.Modal({
        title = "Save loadout",
        text = "Stores who sits in which group and which half everyone belongs to, so returning players land on their old side next time.",
        input = { text = cur and cur.name or "", placeholder = "e.g. Boss 4 - Halves", maxLetters = 48 },
        buttons = buttons,
    })
end
