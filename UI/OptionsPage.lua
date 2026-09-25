-- Options page. Every option applies immediately.
local _, ns = ...

local T, W, UI = ns.T, ns.W, ns.UI
local Board = ns.Board

local Page = { controls = {} }
UI.RegisterPage("options", Page)

local PAD = 14
local ROW_H = 46

local function s() return ns.settings end

local function changed(what)
    ns.Fire("SETTINGS_CHANGED", what)
    Board:Changed()
end

-- A box of rows: label, hint and a control on the right.
local function newBox(parent, title, desc)
    local b = CreateFrame("Frame", nil, parent)
    W.Skin(b, "panel", "line")
    b.title = W.Text(b, 13.5, "bold", "text")
    b.title:SetText(title)
    b.title:SetPoint("TOPLEFT", 16, -14)
    b.desc = W.Text(b, 11.5, "regular", "muted")
    b.desc:SetText(desc)
    b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
    b.rows = {}
    function b:AddRow(label, hint, control)
        local row = CreateFrame("Frame", nil, self)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 16, -(52 + #self.rows * ROW_H))
        row:SetPoint("RIGHT", -16, 0)
        if #self.rows > 0 then
            local l = W.Rect(row, "BORDER", T.Color("line"))
            l:SetHeight(1)
            l:SetPoint("TOPLEFT")
            l:SetPoint("TOPRIGHT")
        end
        row.label = W.Text(row, 12, "semibold", "text")
        row.label:SetText(label)
        row.hint = W.Text(row, 11, "regular", "dim")
        row.hint:SetText(hint or "")
        if hint then
            row.label:SetPoint("TOPLEFT", 0, -9)
            row.hint:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
        else
            row.label:SetPoint("LEFT", 0, 0)
        end
        if control then
            control:SetParent(row)
            control:ClearAllPoints()
            control:SetPoint("RIGHT", 0, 0)
            tinsert(Page.controls, control)
        end
        row.control = control
        tinsert(self.rows, row)
        self:SetHeight(52 + #self.rows * ROW_H + 8)
        return row
    end
    return b
end

local function seg(items, key, onSet)
    return W.Segmented(UIParent, items, function() return s()[key] end, function(v)
        if onSet then onSet(v) else s()[key] = v changed(key) end
    end)
end

local function toggle(key, onSet)
    return W.Toggle(UIParent, function() return s()[key] end, function(v)
        s()[key] = v
        if onSet then onSet(v) end
        changed(key)
    end)
end

function Page:Build(f)
    self.f = f
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT")
    tb:SetPoint("TOPRIGHT")
    tb:SetHeight(52)
    local line = W.Rect(tb, "BORDER", T.Color("line"))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    local title = W.Text(tb, 17, "bold", "text")
    title:SetText("Options")
    title:SetPoint("LEFT", PAD, 0)
    local reset = W.Button(tb, { text = "Reset to defaults", icon = "undo", kind = "ghost", onClick = function()
        UI.Confirm("Reset all options?", "Loadouts, rosters and known players are kept; only the options go back to their defaults.", "Reset", function()
            if s().sharedGroup then Board:SetShared(false) end
            local keep = { window = s().window }
            local fresh = ns.CopyTable(ns.defaults.settings)
            fresh.window = keep.window
            for k in pairs(s()) do s()[k] = nil end
            for k, v in pairs(fresh) do s()[k] = v end
            T.SetAccent(unpack(s().accent))
            W.RefreshShapes()
            ns.UI.Minimap.Update()
            ns.Comm.Listen(s().acceptFrom ~= "never")
            changed("scale")
        end)
    end })
    reset:SetPoint("RIGHT", -PAD, 0)

    self.scroll = W.Scroll(f)
    self.scroll:SetPoint("TOPLEFT", PAD, -64)
    self.scroll:SetPoint("BOTTOMRIGHT", -PAD - 8, 8)
    local c = self.scroll.child

    -- Appearance
    local app = newBox(c, "Appearance", "Only affects your own window.")
    local sw = CreateFrame("Frame")
    sw:SetSize(6 * 26 + 30, 24)
    sw.items = {}
    for i, col in ipairs(T.ACCENTS) do
        local b = CreateFrame("Button", nil, sw)
        b:SetSize(22, 22)
        b:SetPoint("LEFT", (i - 1) * 26, 0)
        b.ring = W.Round(b, "BACKGROUND", "round", 1, 1, 1)
        b.ring:SetAllPoints()
        b.fill = W.Round(b, "ARTWORK", "round", col[1], col[2], col[3])
        b.fill:SetPoint("TOPLEFT", 2, -2)
        b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
        b.col = col
        b:SetScript("OnClick", function() T.SetAccent(col[1], col[2], col[3]) end)
        sw.items[i] = b
    end
    local custom = W.IconButton(sw, "edit", 24, "Custom color", function()
        local r, g, b = T.Accent()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() T.SetAccent(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() T.SetAccent(ColorPickerFrame:GetPreviousValues()) end,
        })
    end)
    custom:SetPoint("LEFT", 6 * 26, 0)
    function sw:Refresh()
        local r, g, b = T.Accent()
        for _, it in ipairs(self.items) do
            local on = math.abs(it.col[1] - r) < 0.01 and math.abs(it.col[2] - g) < 0.01 and math.abs(it.col[3] - b) < 0.01
            it.ring:SetVertexColor(1, 1, 1, on and 1 or 0)
        end
    end
    T.OnAccent(function() sw:Refresh() end)
    app:AddRow("Accent color", nil, sw)
    app:AddRow("Card style", "Filled class color, or dark with a class stripe",
        seg({ { "filled", "Filled" }, { "subtle", "Subtle" } }, "cardStyle"))
    app:AddRow("Square corners", "Off for rounded corners", toggle("squareCorners", W.RefreshShapes))
    app:AddRow("Spec name on cards", nil, toggle("showSpec"))
    local scaleText
    local slider = W.Slider(UIParent, 150, 0.7, 1.3, 0.05, function() return s().scale end,
        function(v) scaleText:SetText(math.floor(v * 100 + 0.5) .. "%") end,
        function(v)
            s().scale = v
            ns.Fire("SETTINGS_CHANGED", "scale")
        end)
    function slider:Refresh() self:SetValue(s().scale) end
    local scaleRow = app:AddRow("Window scale", "100%", slider)
    scaleText = scaleRow.hint
    app:AddRow("Minimap button", "Also in the addon compartment menu",
        W.Toggle(UIParent, function() return not s().minimap.hide end, function(v)
            s().minimap.hide = not v
            ns.UI.Minimap.Update()
        end))
    self.app = app
    self.scaleText = scaleText

    -- Groups
    local grp = newBox(c, "Groups", "How the halves map to the raid's groups.")
    grp:AddRow("Split convention", "Simple: no halves, only groups. Switching keeps everyone on their side",
        seg({ { "oddeven", "Odd / Even" }, { "split", "Low / High" }, { "none", "Simple" } }, "conv",
            function(v) Board:SetConvention(v) end))
    local names = CreateFrame("Frame")
    names:SetSize(186, 28)
    local nL = W.Edit(names, { width = 90, height = 28, maxLetters = 16, onChange = function(t, user)
        if user and strtrim(t) ~= "" then s().halfNames.L = strtrim(t) changed("halfNames") end
    end })
    nL:SetPoint("LEFT")
    local nR = W.Edit(names, { width = 90, height = 28, maxLetters = 16, onChange = function(t, user)
        if user and strtrim(t) ~= "" then s().halfNames.R = strtrim(t) changed("halfNames") end
    end })
    nR:SetPoint("RIGHT")
    function names:Refresh()
        if not nL.edit:HasFocus() then nL:SetText(s().halfNames.L) end
        if not nR.edit:HasFocus() then nR:SetText(s().halfNames.R) end
    end
    grp:AddRow("Half names", "Shown above the halves", names)
    grp:AddRow("Groups used", "Auto: 4 on Mythic, otherwise by raid size",
        seg({ { "auto", "Auto" }, { 4, "4" }, { 6, "6" } }, "groupsMode", function(v) Board:SetGroupsMode(v) end))
    grp:AddRow("Share the odd group", "11-15 or 21-25 players: full groups per half, the last one split",
        W.Toggle(UIParent, function() return s().sharedGroup end, function(v)
            Board:SetShared(v)
            ns.Fire("SETTINGS_CHANGED", "sharedGroup")
        end))
    grp:AddRow("Arrange columns by half", "Off: groups in order with side tags", toggle("arrangeByHalf"))
    grp:AddRow("Sort inside a group", "Always tanks, healers, melee, ranged first",
        seg({ { "role", "Then name" }, { "class", "Then class" } }, "sortMode"))
    self.grp = grp

    -- Behavior
    local beh = newBox(c, "Behavior", "Features cost nothing while they are off.")
    beh:AddRow("Confirm before Apply", nil, toggle("confirmApply"))
    beh:AddRow("Detect specs", "Inspects while this window is open; also reads specs shared by BigWigs",
        toggle("autoInspect", function(v)
            ns.SpecComm.SetEnabled(v)
            ns.Inspect:SetActive(UI.Frame() and UI.Frame():IsShown())
        end))
    beh:AddRow("Remember sides in loadouts", "Auto-fill sends returning players to their old half", toggle("rememberSides"))
    self.beh = beh

    -- Announcements
    local ann = newBox(c, "Announcements", "Raid chat lines from you, so players know their half.")
    ann:AddRow("Announce after Apply", "Posts when all moves are done", toggle("announceOnApply"))
    ann:AddRow("What to announce", "All: also which groups form each half",
        seg({ { "shared", "Shared group" }, { "all", "All groups" } }, "announceWhat"))
    self.ann = ann

    -- Sharing
    local sh = newBox(c, "Sharing", "In-game transfers between FastGroups users.")
    sh:AddRow("Incoming loadouts", "Ignore stops listening completely",
        seg({ { "ask", "Ask" }, { "leader", "Auto from leader" }, { "never", "Ignore" } }, "acceptFrom", function(v)
            s().acceptFrom = v
            ns.Comm.Listen(v ~= "never")
        end))
    local trusted = W.Button(UIParent, { text = "Forget", kind = "ghost", onClick = function()
        wipe(ns.db.trusted)
        Page:Refresh()
    end })
    local trow = sh:AddRow("Always accepted from", "", trusted)
    self.trustedRow = trow
    self.sh = sh

    ns.On("SETTINGS_CHANGED", Page, function() if f:IsShown() then Page:Refresh() end end)
end

function Page:Refresh()
    if not self.f or not self.f:IsShown() then return end
    for _, c in ipairs(self.controls) do
        if c.Refresh then c:Refresh() end
    end
    self.scaleText:SetText(math.floor(s().scale * 100 + 0.5) .. "%")
    local n = 0
    for _ in pairs(ns.db.trusted) do n = n + 1 end
    self.trustedRow.hint:SetText(n == 0 and "Nobody yet" or (n .. " player" .. (n == 1 and "" or "s")))
    self.trustedRow.control:SetShown(n > 0)

    local width = math.floor(self.scroll:GetWidth())
    if width < 50 then width = 760 end
    self.scroll.child:SetWidth(width)
    local colW = math.floor((width - 14) / 2)
    local function place(b, x, y)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -y)
        b:SetWidth(colW)
        return y + b:GetHeight() + 14
    end
    local y1 = place(self.app, 0, 0)
    y1 = place(self.beh, 0, y1)
    y1 = place(self.ann, 0, y1)
    local y2 = place(self.grp, colW + 14, 0)
    y2 = place(self.sh, colW + 14, y2)
    self.scroll.child:SetHeight(math.max(y1, y2))
end
