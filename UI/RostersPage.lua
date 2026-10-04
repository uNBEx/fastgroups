-- Rosters page: hand-picked player lists for planning groups ahead of time.
local _, ns = ...

local T, W, UI = ns.T, ns.W, ns.UI
local Rosters, Players, Data, Board = ns.Rosters, ns.Players, ns.Data, ns.Board

local Page = {}
UI.RegisterPage("rosters", Page)

local PAD = 14
local LIST_W = 220
local ROW_H = 30

---------------------------------------------------------------------------
-- Guild picker (content of a modal). GUILD_ROSTER_UPDATE is only listened
-- to while it is open.
---------------------------------------------------------------------------
local picker

local function buildPicker()
    picker = CreateFrame("Frame")
    picker.selected = {}
    picker.search = W.Edit(picker, { height = 28, placeholder = "Search name or rank", onChange = function() picker:Refresh() end })
    picker.search:SetPoint("TOPLEFT")
    picker.search:SetPoint("RIGHT", -130, 0)
    picker.onlineOnly = false
    picker.onlineToggle = W.Toggle(picker, function() return picker.onlineOnly end, function(v)
        picker.onlineOnly = v
        picker:Refresh()
    end)
    picker.onlineToggle:SetPoint("TOPRIGHT", 0, -4)
    local ol = W.Text(picker, 11.5, "regular", "muted")
    ol:SetText("Online only")
    ol:SetPoint("RIGHT", picker.onlineToggle, "LEFT", -8, 0)
    picker.scroll = W.Scroll(picker)
    picker.scroll:SetPoint("TOPLEFT", 0, -38)
    picker.scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    picker.rows = {}
    picker.empty = W.Text(picker, 12, "regular", "dim")
    picker.empty:SetPoint("TOPLEFT", 6, -46)

    function picker:Refresh()
        local roster = Rosters.Find(Page.selected)
        local filter = strlower(self.search:GetText() or "")
        local child = self.scroll.child
        local n = 0
        for _, m in ipairs(Rosters.guild) do
            local match = (filter == "" or strlower(m.key):find(filter, 1, true) or strlower(m.rank or ""):find(filter, 1, true))
            if match and (not self.onlineOnly or m.online) and not (roster and Rosters.Has(roster, m.key)) then
                n = n + 1
                local row = self.rows[n]
                if not row then
                    row = W.Check(child, "", function(r) return picker.selected[r.key] end, function(r, v)
                        picker.selected[r.key] = v or nil
                        picker.selectedClass[r.key] = r.class
                    end)
                    self.rows[n] = row
                end
                row.key, row.class = m.key, m.class
                local name, realm = Players.DisplayName(m.key)
                row.label:SetText("|c" .. T.ClassHex(m.class) .. name .. "|r" .. (realm and ("|cff5d6575-" .. realm .. "|r") or ""))
                row.right:SetText((m.rank or "") .. "  -  " .. (m.level or "") .. (m.online and "  -  |cff3ecf8eonline|r" or ""))
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(n - 1) * 27)
                row:SetPoint("RIGHT", child, "RIGHT")
                row:Refresh()
                row:Show()
            end
        end
        for i = n + 1, #self.rows do self.rows[i]:Hide() end
        child:SetHeight(math.max(1, n * 27))
        if n == 0 then
            self.empty:SetText(IsInGuild() and (#Rosters.guild == 0 and "Loading the guild roster..." or "Nobody matches.") or "You are not in a guild.")
            self.empty:Show()
        else
            self.empty:Hide()
        end
    end
    ns.On("GUILD_LIST_CHANGED", picker, function() if picker:IsShown() then picker:Refresh() end end)
end

local function openGuildPicker(rosterId)
    if not picker then buildPicker() end
    picker.selected = {}
    picker.selectedClass = {}
    picker.search:SetText("")
    Rosters.StartGuildScan()
    UI.Modal({
        title = "Add from guild",
        width = 520,
        content = picker,
        contentHeight = 320,
        buttons = {
            { text = "Cancel", kind = "ghost" },
            { text = "Add selected", kind = "primary", onClick = function()
                local n = 0
                for key in pairs(picker.selected) do
                    if Rosters.Add(rosterId, key, picker.selectedClass[key]) then n = n + 1 end
                end
                UI.Toast("Added " .. n .. " player" .. (n == 1 and "" or "s") .. ".", "ok")
            end },
        },
        onClose = function() Rosters.StopGuildScan() end,
    })
    picker:Refresh()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function specMenu(owner, key)
    local info = Players.Get(key)
    W.Menu(owner, function(_, root)
        root:CreateTitle(info.name)
        local function specs(parent, class)
            for _, specID in ipairs(Data.CLASS_SPECS[class]) do
                parent:CreateRadio(Data.SpecInfo(specID) or tostring(specID), function() return Players.Get(key).spec == specID end,
                    function() Players.SetSpec(key, specID, true) ns.Fire("ROSTERS_CHANGED") end)
            end
        end
        if info.class then
            specs(root, info.class)
            root:CreateDivider()
            local other = root:CreateButton("Other class")
            for _, class in ipairs(Data.CLASSES) do
                if class ~= info.class then
                    specs(other:CreateButton("|c" .. T.ClassHex(class) .. Data.ClassName(class) .. "|r"), class)
                end
            end
        else
            for _, class in ipairs(Data.CLASSES) do
                specs(root:CreateButton("|c" .. T.ClassHex(class) .. Data.ClassName(class) .. "|r"), class)
            end
        end
    end)
end

local function newMemberRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.hl = W.Round(row, "BACKGROUND", "round", T.Color("panel2"))
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.line = W.Rect(row, "BORDER", T.Color("line"))
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT")
    row.line:SetPoint("BOTTOMRIGHT")
    row.name = W.Text(row, 12, "semibold", "text")
    row.name:SetPoint("LEFT", 8, 0)
    row.spec = CreateFrame("Button", nil, row)
    row.spec:SetHeight(ROW_H)
    row.spec.text = W.Text(row.spec, 12, "regular", "text")
    row.spec.text:SetPoint("LEFT")
    row.spec.text:SetPoint("RIGHT")
    row.spec:SetScript("OnClick", function(self) specMenu(self, row.key) end)
    row.spec:SetScript("OnEnter", function(self)
        self.text:SetTextColor(T.Accent())
        W.Tooltip(self, "Set spec", { "Specs are learned by inspecting in a raid; here you can set them by hand." })
    end)
    row.spec:SetScript("OnLeave", function(self)
        self.text:SetTextColor(T.Color("text"))
        GameTooltip:Hide()
    end)
    row.role = row:CreateTexture(nil, "ARTWORK")
    row.role:SetSize(14, 14)
    row.pos = row:CreateTexture(nil, "ARTWORK")
    row.pos:SetSize(12, 12)
    row.inRaid = W.Text(row, 11.5, "regular", "dim")
    row.remove = W.IconButton(row, "close", 22, "Remove from roster", function()
        Rosters.Remove(Page.selected, row.key)
    end)
    row.remove:SetPoint("RIGHT", -4, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self.hl:Show() end)
    row:SetScript("OnLeave", function(self) if not self:IsMouseOver() then self.hl:Hide() end end)
    return row
end

local function addByName()
    UI.Modal({
        title = "Add player",
        text = "Name, or Name-Realm for players from another realm. Set the spec afterwards by clicking it in the list.",
        input = { text = "", placeholder = "Name-Realm", maxLetters = 64 },
        buttons = { { text = "Cancel", kind = "ghost" }, { text = "Add", kind = "primary", onClick = function(t)
            t = strtrim(t or "")
            if t == "" then return true end
            local key = Players.Key(t:sub(1, 1):upper() .. t:sub(2))
            if not Rosters.Add(Page.selected, key) then UI.Toast("Already on this roster.", "warn") end
        end } },
    })
end

local function addRaid()
    local n = Rosters.AddCurrentRaid(Page.selected)
    UI.Toast("Added " .. n .. " raid member" .. (n == 1 and "" or "s") .. ".", "ok")
end

local function addMenu(owner)
    W.Dropdown(owner, function(_, root)
        root:CreateButton("From guild...", function() openGuildPicker(Page.selected) end)
        root:CreateButton("Current raid", addRaid):SetEnabled(IsInRaid())
        root:CreateButton("By name...", addByName)
    end)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
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
    title:SetText("Rosters")
    title:SetPoint("LEFT", PAD, 0)
    local pill = W.Pill(tb)
    pill:Set("plan groups before raid night")
    pill:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local new = W.Button(tb, { text = "New roster", icon = "plus", onClick = function()
        UI.Modal({
            title = "New roster",
            input = { text = "", placeholder = "e.g. Mythic core", maxLetters = 48 },
            buttons = {
                { text = "Cancel", kind = "ghost" },
                { text = "Create", kind = "primary", onClick = function(text)
                    local r = Rosters.Create(strtrim(text or "") ~= "" and text or "New roster")
                    Page.selected = r.id
                    Page:Refresh()
                end },
            },
        })
    end })
    new:SetPoint("RIGHT", -PAD, 0)

    -- roster list
    self.list = W.Scroll(f)
    self.list:SetPoint("TOPLEFT", PAD, -64)
    self.list:SetPoint("BOTTOMLEFT", PAD, 110)
    self.list:SetWidth(LIST_W)
    self.listRows = {}
    local note = CreateFrame("Frame", nil, f)
    W.Skin(note, "win", "line")
    note:SetPoint("BOTTOMLEFT", PAD, 14)
    note:SetSize(LIST_W, 88)
    local ni = W.Icon(note, "info", 13)
    ni:SetPoint("TOPLEFT", 9, -10)
    T.OnAccent(function(r, g, b) ni:SetVertexColor(r, g, b) end)
    local nt = W.Text(note, 11, "regular", "muted")
    nt:SetWordWrap(true)
    nt:SetPoint("TOPLEFT", 28, -9)
    nt:SetPoint("RIGHT", -9, 0)
    nt:SetText("Plan with a roster days ahead, save the result as a loadout, and load it when the raid forms. Missing and new players are reconciled then.")

    -- detail panel
    local d = CreateFrame("Frame", nil, f)
    d:SetPoint("TOPLEFT", PAD + LIST_W + 14, -64)
    d:SetPoint("BOTTOMRIGHT", -PAD, 14)
    W.Skin(d, "panel", "line")
    self.detail = d
    d.name = W.Text(d, 15, "bold", "text")
    d.counts = W.Text(d, 11.5, "regular", "muted")
    d.rename = W.IconButton(d, "edit", 24, "Rename", function()
        local r = Rosters.Find(Page.selected)
        if not r then return end
        UI.Modal({
            title = "Rename roster",
            input = { text = r.name, maxLetters = 48 },
            buttons = { { text = "Cancel", kind = "ghost" }, { text = "Rename", kind = "primary", onClick = function(t) Rosters.Rename(r.id, t) end } },
        })
    end)
    d.rename:SetPoint("LEFT", d.name, "RIGHT", 6, 0)
    d.delete = W.IconButton(d, "trash", 24, "Delete roster", function()
        local r = Rosters.Find(Page.selected)
        if not r then return end
        UI.Confirm("Delete \"" .. r.name .. "\"?", "The players stay known to FastGroups; only this list is removed.", "Delete", function()
            Rosters.Delete(r.id)
            Page.selected = nil
        end, true)
    end)
    d.delete:SetPoint("LEFT", d.rename, "RIGHT", 2, 0)

    d.plan = W.Button(d, { text = "Plan groups", icon = "nav_groups", kind = "primary", onClick = function()
        if Page.selected then
            Board:SetSource("roster", Page.selected)
            UI.ShowPage("groups")
        end
    end, tooltip = "Open this roster on the group board." })
    d.plan:SetPoint("TOPRIGHT", -14, -14)
    d.add = W.Button(d, { text = "Add players", icon = "plus", onClick = function(b) addMenu(b) end })
    d.add.chev = W.Icon(d.add, "chevron", 10, T.Color("muted"))
    d.add.chev:SetRotation(-math.pi / 2)
    d.add.chev:SetPoint("RIGHT", -10, 0)
    d.add:SetWidth(d.add:GetWidth() + 14)
    d.add:SetPoint("RIGHT", d.plan, "LEFT", -6, 0)
    d.invite = W.Button(d, { text = "Invite", icon = "send", onClick = function() UI.InviteRoster(Page.selected) end,
        tooltip = function(b)
            W.Tooltip(b, b.label:GetText(), { ns.Invite.running and "Waiting for the first player to join, then the rest are invited. Click to cancel."
                or "Invite everyone on this roster who is not in your group yet." })
        end })
    d.invite:SetPoint("RIGHT", d.add, "LEFT", -6, 0)
    d.name:SetPoint("LEFT", d, "TOPLEFT", 16, -28)
    d.counts:SetPoint("TOPLEFT", 16, -50)
    d.counts:SetPoint("RIGHT", -16, 0)

    -- table header
    local head = CreateFrame("Frame", nil, d)
    head:SetPoint("TOPLEFT", 12, -72)
    head:SetPoint("TOPRIGHT", -12, -72)
    head:SetHeight(22)
    local hl = W.Rect(head, "BORDER", T.Color("line"))
    hl:SetHeight(1)
    hl:SetPoint("BOTTOMLEFT")
    hl:SetPoint("BOTTOMRIGHT")
    d.head = head
    d.cols = {}
    for i, name in ipairs({ "PLAYER", "SPEC", "ROLE", "IN RAID NOW" }) do
        local t = W.Text(head, 9.5, "bold", "dim")
        t:SetText(name)
        d.cols[i] = t
    end

    self.members = W.Scroll(d)
    self.members:SetPoint("TOPLEFT", 12, -96)
    self.members:SetPoint("BOTTOMRIGHT", -22, 10)
    self.memberRows = {}

    d.empty = W.Text(d, 12, "regular", "dim")
    d.empty:SetWordWrap(true)
    d.empty:SetPoint("TOPLEFT", 20, -110)
    d.empty:SetPoint("RIGHT", -20, 0)
end

local function columnX(width)
    return 8, math.floor(width * 0.36), math.floor(width * 0.68), math.floor(width * 0.8)
end

function Page:RefreshList()
    local child = self.list.child
    local list = Rosters.List()
    if not Rosters.Find(self.selected) then self.selected = list[1] and list[1].id or nil end
    for i, r in ipairs(list) do
        local row = self.listRows[i]
        if not row then
            row = CreateFrame("Button", nil, child)
            row:SetHeight(44)
            W.Skin(row, "win", "line")
            row.name = W.Text(row, 12.5, "semibold", "text")
            row.name:SetPoint("TOPLEFT", 12, -8)
            row.name:SetPoint("RIGHT", -8, 0)
            row.meta = W.Text(row, 11, "regular", "dim")
            row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
            row:SetScript("OnClick", function(self)
                Page.selected = self.id
                Page:Refresh()
            end)
            self.listRows[i] = row
        end
        row.id = r.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 50)
        row:SetPoint("RIGHT", child, "RIGHT")
        row.name:SetText(r.name)
        row.meta:SetText(#r.members .. " player" .. (#r.members == 1 and "" or "s"))
        if r.id == self.selected then
            row.border:SetVertexColor(T.Accent())
        else
            row.border:SetVertexColor(T.Color("line"))
        end
        row:Show()
    end
    for i = #list + 1, #self.listRows do self.listRows[i]:Hide() end
    child:SetHeight(math.max(1, #list * 50))
end

function Page:Refresh()
    if not self.f or not self.f:IsShown() then return end
    self:RefreshList()
    local d = self.detail
    local r = Rosters.Find(self.selected)
    local has = r ~= nil
    -- seen by OnRoster, so roster events only redraw when these change
    ns.Raid:Refresh()
    self.raidVersion = ns.Raid.version
    local canInvite, why = ns.Invite:CanInvite()
    self.canInvite = canInvite
    for _, x in ipairs({ d.rename, d.delete, d.plan, d.add, d.invite, d.head }) do x:SetShown(has) end
    if not r then
        d.name:SetText("No roster yet")
        d.name:SetWidth(0)
        d.counts:SetText("")
        d.empty:SetText("Create a roster with \"New roster\", then add guild members or your current raid.")
        d.empty:Show()
        for _, row in ipairs(self.memberRows) do row:Hide() end
        return
    end
    local missing = 0
    for _, key in ipairs(r.members) do
        if not ns.Raid.members[key] then missing = missing + 1 end
    end
    if ns.Invite.running then
        d.invite:SetLabel("Cancel")
        d.invite:SetDisabled(false)
    else
        d.invite:SetLabel("Invite")
        if #r.members == 0 then
            d.invite:SetDisabled(true, "Add players first.")
        elseif not canInvite then
            d.invite:SetDisabled(true, why)
        elseif missing == 0 then
            d.invite:SetDisabled(true, "Everyone is already in your group.")
        else
            d.invite:SetDisabled(false)
        end
    end
    -- long names are cut before the buttons; the rename and delete icons follow the name
    d.name:SetText(r.name)
    local room = d:GetWidth() - 16 - 4 * 2 - d.rename:GetWidth() - d.delete:GetWidth() - 12
        - d.invite:GetWidth() - 6 - d.add:GetWidth() - 6 - d.plan:GetWidth() - 14
    d.name:SetWidth(math.max(40, math.min(d.name:GetUnboundedStringWidth() + 2, room)))
    local c = { T = 0, H = 0, M = 0, R = 0, ["?"] = 0 }
    for _, key in ipairs(r.members) do
        local b = Players.Get(key).bucket
        c[b] = c[b] + 1
    end
    d.counts:SetText(#r.members .. " players  -  " .. c.T .. " tanks, " .. c.H .. " healers, " .. c.M .. " melee, " .. c.R .. " ranged"
        .. (c["?"] > 0 and (", " .. c["?"] .. " unknown") or ""))
    d.plan:SetDisabled(#r.members == 0, "Add players first.")

    local width = math.floor(self.members:GetWidth())
    if width < 50 then width = 500 end
    local x1, x2, x3, x4 = columnX(width)
    local xs = { x1, x2, x3, x4 }
    for i, t in ipairs(d.cols) do
        t:ClearAllPoints()
        t:SetPoint("LEFT", d.head, "LEFT", xs[i], 0)
    end

    local keys = {}
    for i, key in ipairs(r.members) do keys[i] = key end
    Board.SortKeys(keys)
    local child = self.members.child
    for i, key in ipairs(keys) do
        local row = self.memberRows[i]
        if not row then
            row = newMemberRow(child)
            self.memberRows[i] = row
        end
        row.key = key
        local info = Players.Get(key)
        local name, realm = Players.DisplayName(key)
        row.name:SetText("|c" .. T.ClassHex(info.class) .. name .. "|r" .. (realm and ("|cff5d6575-" .. realm .. "|r") or ""))
        row.name:SetWidth(x2 - x1 - 8)
        row.spec:ClearAllPoints()
        row.spec:SetPoint("LEFT", x2, 0)
        row.spec:SetWidth(x3 - x2 - 8)
        local specName = Data.SpecInfo(info.spec)
        row.spec.text:SetText(specName and (specName .. " " .. Data.ClassName(info.class))
            or (info.class and (Data.ClassName(info.class) .. "  |cff5d6575(set spec)|r") or "|cff5d6575Unknown - set spec|r"))
        local rk = T.ROLE_KEY[info.role] or "D"
        row.role:SetTexture(T.ICON .. T.ROLE_ICON[rk])
        row.role:SetVertexColor(T.Color(T.ROLE_COLOR[rk]))
        row.role:SetAlpha(info.roleKnown and 1 or 0.4)
        row.role:ClearAllPoints()
        row.role:SetPoint("LEFT", x3, 0)
        if info.role == "DAMAGER" then
            row.pos:SetTexture(T.ICON .. T.POS_ICON[info.pos or "?"])
            row.pos:SetVertexColor(T.Color("muted"))
            row.pos:ClearAllPoints()
            row.pos:SetPoint("LEFT", row.role, "RIGHT", 6, 0)
            row.pos:Show()
        else
            row.pos:Hide()
        end
        local inRaid = ns.Raid.members[key] ~= nil
        row.inRaid:SetText(inRaid and "|cff3ecf8eyes|r" or "no")
        row.inRaid:ClearAllPoints()
        row.inRaid:SetPoint("LEFT", x4, 0)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", child, "RIGHT")
        row:Show()
    end
    for i = #keys + 1, #self.memberRows do self.memberRows[i]:Hide() end
    child:SetHeight(math.max(1, #keys * ROW_H))
    if #keys == 0 then
        d.empty:SetText("This roster is empty. Add players from your guild, your current raid, or by name.")
        d.empty:Show()
    else
        d.empty:Hide()
    end
end

-- Group changed while the page is open: redraw when the raid or our right
-- to invite did.
function Page:OnRoster()
    ns.Raid:Refresh()
    if ns.Raid.version ~= self.raidVersion or (ns.Invite:CanInvite()) ~= self.canInvite then
        self:Refresh()
    end
end
