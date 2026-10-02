-- Share page: export strings, import, and sending over the addon channel.
local _, ns = ...

local T, W, UI = ns.T, ns.W, ns.UI
local Loadouts, Serialize, Comm = ns.Loadouts, ns.Serialize, ns.Comm

local Page = {
    selected = {},       -- loadout id -> true
    target = "RAID",
    includeSettings = false,
    applySettings = false,
}
UI.RegisterPage("share", Page)

local PAD = 14

local function box(parent, title, desc)
    local b = CreateFrame("Frame", nil, parent)
    W.Skin(b, "panel", "line")
    b.title = W.Text(b, 13.5, "bold", "text")
    b.title:SetPoint("TOPLEFT", 16, -14)
    b.title:SetText(title)
    b.desc = W.Text(b, 11.5, "regular", "muted")
    b.desc:SetWordWrap(true)
    b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -4)
    b.desc:SetPoint("RIGHT", -16, 0)
    b.desc:SetText(desc)
    return b
end

local function selectedLoadouts()
    local out = {}
    for _, lo in ipairs(Loadouts.List()) do
        if Page.selected[lo.id] then out[#out + 1] = lo end
    end
    return out
end

local function summary(los)
    if #los == 1 then return "loadout \"" .. los[1].name .. "\"" end
    local names = {}
    for i = 1, math.min(3, #los) do names[i] = los[i].name end
    return #los .. " loadouts (" .. table.concat(names, ", ") .. (#los > 3 and ", ..." or "") .. ")"
end

function Page:Select(id)
    wipe(self.selected)
    if id then self.selected[id] = true end
    self.export:SetText("")
    self:Refresh()
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
    title:SetText("Share")
    title:SetPoint("LEFT", PAD, 0)
    local pill = W.Pill(tb)
    pill:Set("export strings and in-game transfer")
    pill:SetPoint("LEFT", title, "RIGHT", 10, 0)

    self.scroll = W.Scroll(f)
    self.scroll:SetPoint("TOPLEFT", PAD, -64)
    self.scroll:SetPoint("BOTTOMRIGHT", -PAD - 8, 8)
    local c = self.scroll.child

    -- 1. pick loadouts
    local pick = box(c, "Loadouts to share", "Pick one or more.")
    pick.rows = {}
    pick.list = W.Scroll(pick)
    pick.list:SetPoint("TOPLEFT", 10, -54)
    pick.list:SetPoint("BOTTOMRIGHT", -20, 52)
    pick.settingsLabel = W.Text(pick, 12, "semibold", "text")
    pick.settingsLabel:SetText("Include my settings")
    pick.settingsLabel:SetPoint("BOTTOMLEFT", 16, 24)
    pick.settingsHint = W.Text(pick, 11, "regular", "dim")
    pick.settingsHint:SetText("Accent, convention, half names. Off by default.")
    pick.settingsHint:SetPoint("TOPLEFT", pick.settingsLabel, "BOTTOMLEFT", 0, -2)
    pick.settings = W.Toggle(pick, function() return Page.includeSettings end, function(v)
        Page.includeSettings = v
        Page.export:SetText("")
    end)
    pick.settings:SetPoint("BOTTOMRIGHT", -16, 18)
    self.pick = pick

    -- 2. send in game
    local send = box(c, "Send in game", "Hidden addon channel. The other player needs FastGroups and gets an accept prompt.")
    send.to = W.Text(send, 12, "semibold", "text")
    send.to:SetText("To")
    send.to:SetPoint("TOPLEFT", 16, -78)
    send.seg = W.Segmented(send, { { "RAID", "Raid" }, { "GUILD", "Guild" }, { "WHISPER", "Player" } },
        function() return Page.target end, function(v)
            Page.target = v
            Page:Refresh()
        end)
    send.seg:SetPoint("TOPRIGHT", -16, -72)
    send.name = W.Edit(send, { height = 28, placeholder = "Name-Realm" })
    send.name:SetPoint("TOPLEFT", 16, -110)
    send.name:SetPoint("RIGHT", -16, 0)
    send.go = W.Button(send, { text = "Send", icon = "send", kind = "primary", onClick = function() Page:Send() end })
    send.note = W.Text(send, 11, "regular", "dim")
    send.note:SetWordWrap(true)
    send.note:SetText("Not available during boss encounters and Mythic+ (Blizzard blocks addon messages there). Export strings always work.")
    self.send = send

    -- 3. export
    local exp = box(c, "Export string", "Paste it into Discord or a guild note. Compressed and base64 encoded.")
    self.export = W.Edit(exp, { multiline = true, placeholder = "Select loadouts, then Generate.", selectOnFocus = true, fontSize = 11, mono = true,
        onChange = function(text, user)
            if user and Page.exportText and text ~= Page.exportText then Page.export:SetText(Page.exportText) end
        end })
    self.export:SetPoint("TOPLEFT", 16, -58)
    self.export:SetPoint("RIGHT", -16, 0)
    self.export:SetHeight(110)
    exp.gen = W.Button(exp, { text = "Generate", icon = "wand", onClick = function() Page:Generate() end })
    exp.gen:SetPoint("TOPLEFT", self.export, "BOTTOMLEFT", 0, -10)
    exp.copy = W.Button(exp, { text = "Select all", icon = "copy", kind = "ghost", onClick = function()
        self.export.edit:SetFocus()
        self.export.edit:HighlightText()
        UI.Toast("Selected. Press Ctrl+C to copy.")
    end })
    exp.copy:SetPoint("LEFT", exp.gen, "RIGHT", 6, 0)
    self.exp = exp

    -- 4. import
    local imp = box(c, "Import string", "Paste a FastGroups string. You see what it contains before anything is saved.")
    self.import = W.Edit(imp, { multiline = true, placeholder = Serialize.PREFIX .. "...", fontSize = 11, mono = true,
        onChange = function(_, user) if user then Page.preview = nil Page:RefreshImport() end end })
    self.import:SetPoint("TOPLEFT", 16, -58)
    self.import:SetPoint("RIGHT", -16, 0)
    self.import:SetHeight(110)
    imp.result = W.Text(imp, 11.5, "regular", "muted")
    imp.result:SetWordWrap(true)
    imp.result:SetPoint("TOPLEFT", self.import, "BOTTOMLEFT", 0, -8)
    imp.apply = W.Check(imp, "Also apply the sender's settings", function() return Page.applySettings end, function(_, v) Page.applySettings = v end)
    imp.preview = W.Button(imp, { text = "Preview", onClick = function() Page:Preview() end })
    imp.go = W.Button(imp, { text = "Import", kind = "primary", onClick = function() Page:Import() end })
    self.imp = imp

    ns.On("LOADOUTS_CHANGED", Page, function() if f:IsShown() then Page:Refresh() end end)
end

function Page:Generate()
    local los = selectedLoadouts()
    if #los == 0 then
        UI.Toast("Select at least one loadout.", "warn")
        return
    end
    local ok, str = pcall(Serialize.Encode, Serialize.BuildPayload(los, self.includeSettings))
    if not ok then
        UI.Toast("Could not build the string: " .. tostring(str), "error")
        return
    end
    self.exportText = str
    self.export:SetText(str)
    self.export.edit:SetCursorPosition(0)
end

function Page:Send()
    local los = selectedLoadouts()
    if #los == 0 then
        UI.Toast("Select at least one loadout.", "warn")
        return
    end
    local ok, data = pcall(Serialize.Encode, Serialize.BuildPayload(los, self.includeSettings))
    if not ok then
        UI.Toast("Could not build the data: " .. tostring(data), "error")
        return
    end
    local sent, err = Comm.Offer(self.target, self.send.name:GetText(), data, summary(los))
    if sent then
        local to = self.target == "WHISPER" and self.send.name:GetText() or strlower(self.target)
        UI.Toast("Offer sent to " .. to .. ". The data follows when someone accepts.", "ok")
    else
        UI.Toast(err or "Could not send.", "warn")
    end
end

function Page:Preview()
    local payload, err = Serialize.Decode(self.import:GetText())
    if not payload then
        self.preview = { error = err }
    else
        local read = Serialize.ReadPayload(payload)
        self.preview = read
        if #read.loadouts == 0 then self.preview = { error = "The string contains no usable loadouts." } end
    end
    self:RefreshImport()
end

function Page:Import()
    local p = self.preview
    if not p or p.error then return end
    local added = Loadouts.Import(p.loadouts)
    if p.settings and self.applySettings then Serialize.ApplySettings(p.settings) end
    UI.Toast("Imported " .. #added .. " loadout" .. (#added == 1 and "" or "s") .. ".", "ok")
    self.import:SetText("")
    self.preview = nil
    self:RefreshImport()
end

function Page:RefreshImport()
    local imp = self.imp
    local p = self.preview
    imp.apply:Hide()
    if not p then
        imp.result:SetText("")
        imp.go:SetDisabled(true, "Preview the string first.")
    elseif p.error then
        imp.result:SetText("|cfff5a524" .. p.error .. "|r")
        imp.go:SetDisabled(true, p.error)
    else
        local names = {}
        for i, lo in ipairs(p.loadouts) do names[i] = lo.name .. " (" .. Loadouts.Count(lo) .. ")" end
        imp.result:SetText("|cff3ecf8e" .. #p.loadouts .. " loadout" .. (#p.loadouts == 1 and "" or "s") .. ":|r " .. table.concat(names, ", ")
            .. (p.settings and "\nIncludes the sender's settings." or ""))
        imp.apply:SetShown(p.settings ~= nil)
        imp.apply:Refresh()
        imp.go:SetDisabled(false)
    end
    -- measured, so a fixed width (see W.Text)
    imp.result:SetWidth(imp:GetWidth() - 32)
    local y = imp.result:GetText() ~= "" and (imp.result:GetStringHeight() + 12) or 4
    imp.apply:ClearAllPoints()
    imp.apply:SetPoint("TOPLEFT", self.import, "BOTTOMLEFT", -6, -(y + 2))
    imp.apply:SetPoint("RIGHT", -16, 0)
    if imp.apply:IsShown() then y = y + 30 end
    imp.preview:ClearAllPoints()
    imp.preview:SetPoint("TOPLEFT", self.import, "BOTTOMLEFT", 0, -(y + 6))
    imp.go:ClearAllPoints()
    imp.go:SetPoint("LEFT", imp.preview, "RIGHT", 6, 0)
end

function Page:Refresh()
    if not self.f or not self.f:IsShown() then return end
    local width = math.floor(self.scroll:GetWidth())
    if width < 50 then width = 760 end
    self.scroll.child:SetWidth(width)
    local colW = math.floor((width - 14) / 2)

    -- loadout checklist
    local pick = self.pick
    local list = Loadouts.List()
    local child = pick.list.child
    for i, lo in ipairs(list) do
        local row = pick.rows[i]
        if not row then
            row = W.Check(child, "", function(r) return Page.selected[r.id] end, function(r, v)
                Page.selected[r.id] = v or nil
                Page.export:SetText("")
                Page.exportText = nil
            end)
            pick.rows[i] = row
        end
        row.id = lo.id
        row.label:SetText(lo.name)
        row.right:SetText(Loadouts.Count(lo) .. " players")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 27)
        row:SetPoint("RIGHT", child, "RIGHT")
        row:Refresh()
        row:Show()
    end
    for i = #list + 1, #pick.rows do pick.rows[i]:Hide() end
    child:SetHeight(math.max(1, #list * 27))

    local topH = 280
    pick:ClearAllPoints()
    pick:SetPoint("TOPLEFT", 0, 0)
    pick:SetSize(colW, topH)

    local send = self.send
    send:ClearAllPoints()
    send:SetPoint("TOPLEFT", colW + 14, 0)
    send:SetSize(colW, topH)
    send.seg:Refresh()
    local whisper = self.target == "WHISPER"
    send.name:SetShown(whisper)
    send.go:ClearAllPoints()
    send.go:SetPoint("TOPLEFT", 16, whisper and -150 or -112)
    send.note:ClearAllPoints()
    send.note:SetPoint("TOPLEFT", send.go, "BOTTOMLEFT", 0, -12)
    send.note:SetPoint("RIGHT", -16, 0)
    local locked = Comm.Locked()
    send.go:SetDisabled(locked, "Addon messages are blocked right now.")

    local botH = 250
    self.exp:ClearAllPoints()
    self.exp:SetPoint("TOPLEFT", 0, -(topH + 14))
    self.exp:SetSize(colW, botH)
    self.imp:ClearAllPoints()
    self.imp:SetPoint("TOPLEFT", colW + 14, -(topH + 14))
    self.imp:SetSize(colW, botH + 30)
    self:RefreshImport()
    self.scroll.child:SetHeight(topH + 14 + botH + 30 + 10)
end
