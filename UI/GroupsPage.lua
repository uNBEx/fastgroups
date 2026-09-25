-- Groups page: toolbar, the two halves with their group columns, counters,
-- the unassigned tray and the bench.
local _, ns = ...

local T, W, UI = ns.T, ns.W, ns.UI
local Board, Players, Data, Loadouts = ns.Board, ns.Players, ns.Data, ns.Loadouts

local Page = {}
UI.RegisterPage("groups", Page)

local PAD = 14
local TOOLBAR_H = 52
local CARD_H = 30
local GAP = 3
local COL_PAD = 5
local COL_HEAD = 20
local COL_H = COL_PAD + COL_HEAD + 5 * CARD_H + 4 * GAP + COL_PAD
local HALF_PAD = 9
local HALF_HEAD = 24
local TRAY_CARD_W = 176

local tmpKeys, tmpGhosts = {}, {}

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
local function createCard(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(CARD_H)
    c.bg = W.Round(c, "BACKGROUND", "round")
    c.bg:SetAllPoints()
    c.stripe = W.Rect(c, "BORDER")
    c.stripe:SetPoint("TOPLEFT", 0, -5)
    c.stripe:SetPoint("BOTTOMLEFT", 0, 5)
    c.stripe:SetWidth(3)
    c.ring = W.Round(c, "BORDER", "ring")
    c.ring:SetAllPoints()
    c.hl = W.Round(c, "OVERLAY", "ring", 1, 1, 1, 0.4)
    c.hl:SetAllPoints()
    c.hl:Hide()
    c.drop = W.Round(c, "OVERLAY", "ring")
    c.drop:SetPoint("TOPLEFT", -1, 1)
    c.drop:SetPoint("BOTTOMRIGHT", 1, -1)
    c.drop:Hide()
    c.specBorder = W.Rect(c, "ARTWORK", 0, 0, 0, 0.55)
    c.specBorder:SetSize(22, 22)
    c.specBorder:SetPoint("LEFT", 4, 0)
    c.spec = c:CreateTexture(nil, "ARTWORK", nil, 1)
    c.spec:SetSize(20, 20)
    c.spec:SetPoint("CENTER", c.specBorder, "CENTER")
    c.role = c:CreateTexture(nil, "ARTWORK")
    c.role:SetSize(13, 13)
    c.role:SetPoint("RIGHT", -7, 0)
    c.posBg = W.Round(c, "ARTWORK", "round3", 0, 0, 0, 0.45)
    c.posBg:SetSize(16, 16)
    c.posBg:SetPoint("RIGHT", c.role, "LEFT", -4, 0)
    c.pos = c:CreateTexture(nil, "ARTWORK", nil, 1)
    c.pos:SetSize(10, 10)
    c.pos:SetPoint("CENTER", c.posBg, "CENTER")
    c.name = W.Text(c, 11.5, "bold", "text")
    c.sub = W.Text(c, 9.5, "regular", "text")
    c.tag = CreateFrame("Frame", nil, c)
    c.tag:SetHeight(13)
    c.tag:SetPoint("TOPRIGHT", -5, 6)
    c.tag:SetFrameLevel(c:GetFrameLevel() + 5)
    c.tag.bg = W.Round(c.tag, "BACKGROUND", "round3")
    c.tag.bg:SetAllPoints()
    c.tag.text = W.Text(c.tag, 8.5, "bold", "text")
    c.tag.text:SetPoint("CENTER", 0, 0)
    c.dotBg = c:CreateTexture(nil, "OVERLAY", nil, 1)
    c.dotBg:SetTexture(T.TEX.circle)
    c.dotBg:SetSize(11, 11)
    c.dotBg:SetPoint("TOPLEFT", -3, 3)
    c.dotBg:SetVertexColor(T.Color("win"))
    c.dot = c:CreateTexture(nil, "OVERLAY", nil, 2)
    c.dot:SetTexture(T.TEX.circle)
    c.dot:SetSize(7, 7)
    c.dot:SetPoint("CENTER", c.dotBg, "CENTER")
    return c
end

local function setTag(c, text, bgColor, textColor, bgAlpha)
    if not text then
        c.tag:Hide()
        return
    end
    c.tag.text:SetText(text)
    c.tag.bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgAlpha or 1)
    c.tag.text:SetTextColor(textColor[1], textColor[2], textColor[3])
    c.tag:SetWidth(c.tag.text:GetUnboundedStringWidth() + 9)
    c.tag:Show()
end

local INK = T.C.ink
local WHITE = { 1, 1, 1 }

-- Paint a card for `key`. ghost = absent loadout player.
local function fillCard(c, key, ghost)
    local s = ns.settings
    local info = Players.Get(key)
    local r, g, b = Data.ClassColor(info.class)
    c.key, c.ghost = key, ghost
    local subtle = s.cardStyle == "subtle"

    -- background
    if ghost then
        local wr, wg, wb = T.Color("win")
        c.bg:SetGradient("HORIZONTAL", CreateColor(wr, wg, wb, 1), CreateColor(wr, wg, wb, 1))
        c.ring:SetVertexColor(r, g, b, 0.5)
        c.ring:Show()
        c.stripe:Hide()
    elseif subtle then
        local pr, pg, pb = T.Color("panel2")
        c.bg:SetGradient("HORIZONTAL", CreateColor(pr, pg, pb, 1), CreateColor(pr, pg, pb, 1))
        c.stripe:SetVertexColor(r, g, b)
        c.stripe:Show()
        c.ring:Hide()
    else
        c.bg:SetGradient("HORIZONTAL", CreateColor(r * 0.88, g * 0.88, b * 0.88, 1), CreateColor(r * 0.58, g * 0.58, b * 0.58, 1))
        c.stripe:Hide()
        c.ring:SetVertexColor(1, 1, 1, 0.1)
        c.ring:Show()
    end

    -- spec / class icon
    local specName, icon = Data.SpecInfo(info.spec)
    c.spec:SetTexCoord(0, 1, 0, 1)
    c.spec:SetVertexColor(1, 1, 1, 1)
    if icon then
        c.spec:SetTexture(icon)
        c.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif info.class then
        c.spec:SetAtlas(GetClassAtlas(strlower(info.class)))
    else
        c.spec:SetTexture(T.ICON .. "pos_unknown")
        c.spec:SetVertexColor(T.Color("muted"))
    end
    c.spec:SetDesaturated(ghost and true or false)
    c.spec:SetAlpha(ghost and 0.45 or 1)

    -- role and position
    local rk = T.ROLE_KEY[info.role] or "D"
    c.role:SetTexture(T.ICON .. T.ROLE_ICON[rk])
    if subtle or ghost then
        c.role:SetVertexColor(T.Color(T.ROLE_COLOR[rk]))
    else
        c.role:SetVertexColor(1, 1, 1)
    end
    c.role:SetAlpha(ghost and 0.4 or (info.roleKnown and 1 or 0.5))
    local anchor = c.role
    if info.role == "DAMAGER" then
        c.pos:SetTexture(T.ICON .. T.POS_ICON[info.pos or "?"])
        c.pos:SetVertexColor(1, 1, 1, ghost and 0.4 or 1)
        c.posBg:SetVertexColor(0, 0, 0, subtle and 0.3 or 0.45)
        c.posBg:Show()
        c.pos:Show()
        anchor = c.posBg
    else
        c.posBg:Hide()
        c.pos:Hide()
    end

    -- text
    c.name:SetText(info.name)
    c.name:ClearAllPoints()
    c.sub:ClearAllPoints()
    c.name:SetPoint("LEFT", c.specBorder, "RIGHT", 6, 0)
    c.name:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
    if ghost then
        W.SetFont(c.name, 11.5, "bold")
        c.name:SetTextColor(T.Color("muted"))
        c.name:SetShadowOffset(0, 0)
    elseif subtle then
        W.SetFont(c.name, 11.5, "bold")
        c.name:SetTextColor(r, g, b)
        c.name:SetShadowOffset(0, 0)
    else
        W.SetFont(c.name, 11.5, "bold", "OUTLINE")
        c.name:SetTextColor(1, 1, 1)
        c.name:SetShadowOffset(0, 0)
    end
    if s.showSpec then
        c.name:SetPoint("LEFT", c.specBorder, "RIGHT", 6, 6)
        c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -1)
        c.sub:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        local label = specName or Data.ClassName(info.class)
        if info.posManual then label = label .. " *" end
        c.sub:SetText(label)
        if ghost or subtle then
            c.sub:SetTextColor(T.Color(ghost and "dim" or "muted"))
            c.sub:SetShadowOffset(0, 0)
        else
            c.sub:SetTextColor(1, 1, 1, 0.88)
            c.sub:SetShadowOffset(1, -1)
            c.sub:SetShadowColor(0, 0, 0, 1)
        end
        c.sub:Show()
    else
        c.sub:Hide()
    end

    -- tags
    if ghost then
        setTag(c, "ABSENT", T.C.danger, WHITE)
    elseif Board.subs[key] then
        setTag(c, "for " .. Players.ShortName(Board.subs[key]), T.C.ink, { T.Accent() })
    elseif Board.tags[key] == "new" then
        setTag(c, "NEW", { T.Accent() }, INK)
    elseif Board.tags[key] == "ret" then
        setTag(c, "BACK", T.C.ok, INK)
    else
        setTag(c, nil)
    end

    -- pending move marker
    local live = Board:Live()
    local m = live and live[key]
    local g2 = Board.draft[key]
    local moved = not ghost and m and g2 and g2 > 0 and g2 ~= m.group
    c.dot:SetShown(moved and true or false)
    c.dotBg:SetShown(moved and true or false)
    if moved then c.dot:SetVertexColor(T.Accent()) end
    c.drop:SetVertexColor(T.Accent())
end
Page.FillCard = fillCard

local function cardTooltip(c)
    local info = Players.Get(c.key)
    local name, realm = Players.DisplayName(c.key)
    GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
    GameTooltip:SetText(name .. (realm and (" - " .. realm) or ""), Data.ClassColor(info.class))
    local specName = Data.SpecInfo(info.spec)
    GameTooltip:AddLine((specName and (specName .. " ") or "") .. Data.ClassName(info.class), 0.8, 0.82, 0.86)
    local roleText = info.role == "TANK" and "Tank" or info.role == "HEALER" and "Healer" or "Damage"
    if info.role == "DAMAGER" then
        roleText = roleText .. ", " .. (info.pos == "M" and "melee" or info.pos == "R" and "ranged" or "melee or ranged unknown")
        if info.posManual then roleText = roleText .. " (set by you)" end
    end
    GameTooltip:AddLine(roleText, 0.8, 0.82, 0.86)
    if not info.spec and not c.ghost then
        GameTooltip:AddLine("Spec unknown. It is read by inspecting; right-click to set it.", 0.6, 0.62, 0.68, true)
    end
    if c.ghost then
        GameTooltip:AddLine("Not here today. Drop a player on this card to take the slot.", 0.95, 0.4, 0.4, true)
    else
        local live = Board:Live()
        local m = live and live[c.key]
        local g = Board.draft[c.key]
        if m and g ~= m.group then
            local ar, ag, ab = T.Accent()
            GameTooltip:AddLine("Live: group " .. m.group .. "  ->  " .. (g > 0 and ("group " .. g) or "unassigned"), ar, ag, ab)
        end
        if m and not m.online then GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6) end
        if Board.subs[c.key] then
            GameTooltip:AddLine("Takes the slot of " .. Players.ShortName(Board.subs[c.key]), T.Accent())
        end
        GameTooltip:AddLine("Drag to move, right-click for options.", 0.45, 0.48, 0.55)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Drag and drop: a floating copy of the card follows the cursor via
-- StartMoving; the target is found with IsMouseOver when the drag ends.
---------------------------------------------------------------------------
local dragCard

local function onCardDragStart(c)
    if c.ghost or not c.key or ns.Apply.running then return end
    local main = UI.Frame()
    if not dragCard then
        dragCard = createCard(UIParent)
        W.AddShapeRoot(dragCard)
        dragCard:EnableMouse(false)
        dragCard:SetMovable(true)
        dragCard:SetFrameStrata("TOOLTIP")
        dragCard:SetAlpha(0.95)
    end
    dragCard:SetScale(main:GetEffectiveScale() / UIParent:GetEffectiveScale())
    fillCard(dragCard, c.key, false)
    dragCard:SetSize(c:GetSize())
    -- Keep the point that was pressed under the cursor. The float and the
    -- card share one effective scale, so one conversion serves both.
    local s = dragCard:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local dx, dy = Page.downX or cx, Page.downY or cy
    Page.downX, Page.downY = nil, nil
    local gx, gy = dx / s - c:GetLeft(), c:GetTop() - dy / s
    dragCard:ClearAllPoints()
    dragCard:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / s - gx, cy / s + gy)
    dragCard:Show()
    -- Resolve the new anchor now; otherwise StartMoving can measure the
    -- cursor offset against the rect left over from the previous drag.
    dragCard:GetLeft()
    dragCard:StartMoving(true)
    c:SetAlpha(0.25)
    Page.dragKey = c.key
    Page.dragSource = c
    GameTooltip:Hide()
end

local function findDropTarget()
    for _, c in ipairs(Page.activeCards) do
        if c:IsVisible() and c.key ~= Page.dragKey and c:IsMouseOver() then
            return { card = c }
        end
    end
    for _, col in ipairs(Page.columns) do
        if col:IsVisible() and col:IsMouseOver() then
            return { group = col.group }
        end
    end
    if Page.tray:IsVisible() and Page.tray:IsMouseOver() then
        return { group = 0 }
    end
    return nil
end

local function onCardDragStop(c)
    if not Page.dragKey then return end
    local key = Page.dragKey
    dragCard:StopMovingOrSizing()
    dragCard:Hide()
    dragCard:ClearAllPoints()
    c:SetAlpha(1)
    local target = findDropTarget()
    Page.dragKey = nil
    Page.dragSource = nil
    for _, x in ipairs(Page.activeCards) do x.drop:Hide() end
    for _, col in ipairs(Page.columns) do col:SetDropHighlight(false) end
    if target then
        if target.card then
            local t = target.card
            if t.ghost then
                Board:Substitute(key, t.key)
            else
                Board:Swap(key, t.key)
            end
        elseif target.group ~= Board.draft[key] then
            local ok = Board:Move(key, target.group)
            if not ok then
                UI.Toast("Group " .. target.group .. " is full. Drop onto a player to swap.", "warn")
            end
        end
    end
    if Page.dirty then Page:Refresh() end
end

---------------------------------------------------------------------------
-- Card context menu
---------------------------------------------------------------------------
local function specMenu(parent, key, class)
    for _, specID in ipairs(Data.CLASS_SPECS[class]) do
        local name = Data.SpecInfo(specID) or tostring(specID)
        parent:CreateRadio(name, function() return Players.Get(key).spec == specID end, function()
            Players.SetSpec(key, specID, true)
            Board:Changed()
        end)
    end
end

local function cardMenu(c)
    local key = c.key
    local info = Players.Get(key)
    W.Menu(c, function(_, root)
        root:CreateTitle("|c" .. T.ClassHex(info.class) .. info.name .. "|r")
        local spec = root:CreateButton("Spec")
        if info.class then
            specMenu(spec, key, info.class)
        else
            for _, class in ipairs(Data.CLASSES) do
                local cm = spec:CreateButton("|c" .. T.ClassHex(class) .. Data.ClassName(class) .. "|r")
                specMenu(cm, key, class)
            end
        end
        if info.role == "DAMAGER" then
            local pos = root:CreateButton("Melee / ranged")
            local rec = Players.Record(key)
            local cur = rec and rec.pos or "auto"
            pos:CreateRadio("From spec", function() return cur == "auto" end, function() Players.SetPos(key, nil) Board:Changed() end)
            pos:CreateRadio("Melee", function() return cur == "M" end, function() Players.SetPos(key, "M") Board:Changed() end)
            pos:CreateRadio("Ranged", function() return cur == "R" end, function() Players.SetPos(key, "R") Board:Changed() end)
        end
        root:CreateDivider()
        local side = Board:SideOf(Board.draft[key] or 0)
        if side then
            local other = side == "L" and "R" or "L"
            root:CreateButton("Move to " .. ns.settings.halfNames[other], function()
                local g = Board:FreeGroupIn(other)
                if g then
                    Board:Move(key, g)
                else
                    UI.Toast("The " .. ns.settings.halfNames[other] .. " half is full. Drag onto a player there to swap.", "warn")
                end
            end)
        end
        if (Board.draft[key] or 0) <= Board:K() then
            root:CreateButton("Send to bench", function()
                local g = Board:FreeBenchGroup()
                if g then
                    Board:Move(key, g)
                    ns.settings.benchOpen = true
                    Page:Refresh()
                else
                    UI.Toast("The bench is full.", "warn")
                end
            end)
        end
        if Board.draft[key] ~= 0 then
            root:CreateButton("Unassign", function() Board:Move(key, 0) end)
        end
        if Board.source == "roster" then
            root:CreateButton("Remove from roster", function()
                ns.Rosters.Remove(Board.sourceId, key)
                Board:RemoveMember(key)
                Board:Changed()
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- Card pool
---------------------------------------------------------------------------
Page.activeCards = {}
local cardPool = {}

local function acquireCard(parent)
    local c = tremove(cardPool)
    if not c then
        c = createCard(parent)
        c:RegisterForDrag("LeftButton")
        c:RegisterForClicks("RightButtonUp")
        c:SetScript("OnDragStart", onCardDragStart)
        c:SetScript("OnDragStop", onCardDragStop)
        c:SetScript("OnMouseDown", function(_, mouse)
            if mouse == "LeftButton" then Page.downX, Page.downY = GetCursorPosition() end
        end)
        c:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" and not self.ghost and not Page.dragKey then cardMenu(self) end
        end)
        c:SetScript("OnEnter", function(self)
            if Page.dragKey then
                if self.key ~= Page.dragKey then self.drop:Show() end
                return
            end
            self.hl:Show()
            cardTooltip(self)
            if not self.ghost and Board.source == "live" then ns.Inspect:Kick(self.key) end
        end)
        c:SetScript("OnLeave", function(self)
            self.hl:Hide()
            self.drop:Hide()
            GameTooltip:Hide()
        end)
    end
    c:SetParent(parent)
    c:SetFrameLevel(parent:GetFrameLevel() + 3)
    c:SetAlpha(1)
    c.hl:Hide()
    c.drop:Hide()
    c:Show()
    tinsert(Page.activeCards, c)
    return c
end

local function releaseCards()
    for i = #Page.activeCards, 1, -1 do
        local c = Page.activeCards[i]
        c:Hide()
        c:ClearAllPoints()
        Page.activeCards[i] = nil
        tinsert(cardPool, c)
    end
end

---------------------------------------------------------------------------
-- Columns
---------------------------------------------------------------------------
local function createColumn(parent, g)
    local col = CreateFrame("Frame", nil, parent)
    col.group = g
    W.Skin(col, "win", "line")
    col.title = W.Text(col, 11, "semibold", "text")
    col.title:SetPoint("TOPLEFT", COL_PAD + 3, -COL_PAD - 3)
    col.title:SetText("Group " .. g)
    col.cap = W.Text(col, 10.5, "regular", "dim")
    col.cap:SetPoint("TOPRIGHT", -COL_PAD - 3, -COL_PAD - 3)
    col.sideTag = CreateFrame("Frame", nil, col)
    col.sideTag:SetHeight(13)
    col.sideTag:SetPoint("LEFT", col.title, "RIGHT", 6, 0)
    col.sideTag.bg = W.Round(col.sideTag, "BACKGROUND", "round3")
    col.sideTag.bg:SetAllPoints()
    col.sideTag.text = W.Text(col.sideTag, 8.5, "bold", "text")
    col.sideTag.text:SetPoint("CENTER")
    col.slots = {}
    for i = 1, 5 do
        local s = CreateFrame("Frame", nil, col)
        s:SetHeight(CARD_H)
        s:SetPoint("TOPLEFT", COL_PAD, -(COL_PAD + COL_HEAD + (i - 1) * (CARD_H + GAP)))
        s:SetPoint("RIGHT", -COL_PAD, 0)
        s.ring = W.Round(s, "BORDER", "ring", T.Color("line2"))
        s.ring:SetAllPoints()
        s.ring:SetAlpha(0.6)
        col.slots[i] = s
    end
    col:EnableMouse(true)
    col:SetScript("OnEnter", function(self) if Page.dragKey then self:SetDropHighlight(true) end end)
    col:SetScript("OnLeave", function(self) self:SetDropHighlight(false) end)
    function col:SetDropHighlight(on)
        if on then
            self.border:SetVertexColor(T.Accent())
        else
            self.border:SetVertexColor(T.Color("line"))
        end
    end
    col:SetHeight(COL_H)
    return col
end

-- Fill a column with its cards.
local function fillColumn(col, width)
    local g = col.group
    col:SetWidth(width)
    Board:MembersOf(g, tmpKeys)
    Board:GhostsOf(g, tmpGhosts)
    local n = #tmpKeys + #tmpGhosts
    col.cap:SetText(n .. "/5")
    col.cap:SetTextColor(T.Color(n > 5 and "danger" or "dim"))
    local side = Board:SideOf(g)
    if not ns.settings.arrangeByHalf and side then
        local name = ns.settings.halfNames[side]
        col.sideTag.text:SetText(strupper(name))
        if side == "L" then
            local r, gg, b = T.Accent()
            col.sideTag.bg:SetVertexColor(r, gg, b, 0.22)
            col.sideTag.text:SetTextColor(r, gg, b)
        else
            col.sideTag.bg:SetVertexColor(1, 1, 1, 0.08)
            col.sideTag.text:SetTextColor(T.Color("muted"))
        end
        col.sideTag:SetWidth(col.sideTag.text:GetUnboundedStringWidth() + 10)
        col.sideTag:Show()
    else
        col.sideTag:Hide()
    end
    -- members first by role, ghosts merged in role order
    local list = {}
    for _, k in ipairs(tmpKeys) do list[#list + 1] = { k, false } end
    for _, k in ipairs(tmpGhosts) do list[#list + 1] = { k, true } end
    table.sort(list, function(a, b)
        local oa, ob = Data.ROLE_ORDER[Players.Get(a[1]).bucket], Data.ROLE_ORDER[Players.Get(b[1]).bucket]
        if oa ~= ob then return oa < ob end
        if a[2] ~= b[2] then return b[2] end
        return Players.Get(a[1]).name < Players.Get(b[1]).name
    end)
    for i = 1, 5 do
        local slot = col.slots[i]
        local item = list[i]
        if item then
            slot.ring:Hide()
            local c = acquireCard(col)
            fillCard(c, item[1], item[2])
            c:SetAllPoints(slot)
        else
            slot.ring:Show()
        end
    end
    -- more than 5 (only possible while the live raid disagrees): stack the rest
    for i = 6, #list do
        local c = acquireCard(col)
        fillCard(c, list[i][1], list[i][2])
        c:SetPoint("TOPLEFT", col.slots[5], "BOTTOMLEFT", 0, -(i - 5) * (CARD_H + GAP))
        c:SetPoint("RIGHT", col.slots[5], "RIGHT")
    end
    col:Show()
end

---------------------------------------------------------------------------
-- Counters
---------------------------------------------------------------------------
local function createCounters(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(26 + 6 + 22)
    f.roles = {}
    local ROLES = {
        { "T", "role_tank", "tank", "Tanks" },
        { "H", "role_healer", "heal", "Healers" },
        { "M", "pos_melee", "dps", "Melee" },
        { "R", "pos_ranged", "dps", "Ranged" },
        { "U", "pos_unknown", "muted", "Unknown" },
    }
    for i, def in ipairs(ROLES) do
        local c = CreateFrame("Frame", nil, f)
        c:SetHeight(26)
        W.Skin(c, "win", "line")
        c.icon = W.Icon(c, def[2], 14, T.Color(def[3]))
        c.icon:SetPoint("LEFT", 8, 0)
        c.num = W.Text(c, 12.5, "bold", "text")
        c.num:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
        c.label = W.Text(c, 10.5, "regular", "dim")
        c.label:SetPoint("LEFT", c.num, "RIGHT", 5, 0)
        c.label:SetText(def[4])
        c.key = def[1]
        c:EnableMouse(true)
        c:SetScript("OnEnter", function(self)
            if self.tip then W.Tooltip(self, self.tip) end
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.roles[i] = c
    end
    f.clsLabel = W.Text(f, 9.5, "bold", "dim")
    f.clsLabel:SetText("CLASSES")
    f.clsLabel:SetPoint("TOPLEFT", 2, -(26 + 6 + 6))
    f.cls = {}
    f.even = W.Text(f, 11, "regular", "dim")
    f.even:SetText("all even")
    return f
end

local function classChip(f, i)
    local c = f.cls[i]
    if not c then
        c = CreateFrame("Frame", nil, f)
        c:SetHeight(22)
        W.Skin(c, "win", "line")
        c.sq = W.Round(c, "ARTWORK", "round3")
        c.sq:SetSize(10, 10)
        c.sq:SetPoint("LEFT", 6, 0)
        c.num = W.Text(c, 11, "semibold", "text")
        c.num:SetPoint("LEFT", c.sq, "RIGHT", 5, 0)
        c.star = W.Text(c, 11, "bold", "text")
        c.star:SetText("*")
        c.star:SetPoint("LEFT", c.num, "RIGHT", 1, 1)
        c:EnableMouse(true)
        c:SetScript("OnEnter", function(self) W.Tooltip(self, self.tip) end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.cls[i] = c
    end
    return c
end

local ROLE_NAMES = { T = "tanks", H = "healers", M = "melee", R = "ranged", U = "players with unknown position" }

local function fillCounters(f, side, width)
    f:SetWidth(width)
    local me = Board:Counts(side)
    local vals = { T = me.T, H = me.H, M = me.M, R = me.R, U = me.U }
    local cls = {}
    for k, v in pairs(me.cls) do cls[k] = v end
    local other = Board:Counts(side == "L" and "R" or "L")
    local ovals = { T = other.T, H = other.H, M = other.M, R = other.R, U = other.U }
    local x = 0
    for _, c in ipairs(f.roles) do
        local k = c.key
        if k == "U" and vals.U == 0 and ovals.U == 0 then
            c:Hide()
        else
            local bad = k ~= "U" and Board.Uneven(vals[k], ovals[k])
            c.num:SetText(vals[k])
            c.num:SetTextColor(T.Color(bad and "warn" or "text"))
            c.border:SetVertexColor(T.Color(bad and "warn" or "line"))
            c.border:SetAlpha(bad and 0.7 or 1)
            c.tip = vals[k] .. " " .. ROLE_NAMES[k] .. " here, " .. ovals[k] .. " on the other half"
            c.label:SetShown(width > 330)
            local w = 8 + 14 + 6 + c.num:GetUnboundedStringWidth() + (c.label:IsShown() and (5 + c.label:GetUnboundedStringWidth()) or 0) + 9
            c:SetWidth(math.floor(w))
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x, 0)
            c:Show()
            x = x + c:GetWidth() + 5
        end
    end
    -- class chips: raid-debuff classes always, others when uneven
    local n = 0
    local cx = f.clsLabel:GetUnboundedStringWidth() + 10
    for _, class in ipairs(Data.CLASSES) do
        local a, b = cls[class] or 0, other.cls[class] or 0
        local bad = Board.Uneven(a, b)
        if (a > 0 or b > 0) and (Data.BUFF_CLASSES[class] or bad) then
            n = n + 1
            local c = classChip(f, n)
            c.sq:SetVertexColor(Data.ClassColor(class))
            c.num:SetText(a)
            c.num:SetTextColor(T.Color(bad and "warn" or "text"))
            c.border:SetVertexColor(T.Color(bad and "warn" or "line"))
            c.border:SetAlpha(bad and 0.7 or 1)
            c.star:SetShown(Data.BUFF_CLASSES[class] and true or false)
            c.star:SetTextColor(T.Accent())
            c.tip = Data.ClassName(class) .. ": " .. a .. " here, " .. b .. " on the other half"
                .. (Data.BUFF_CLASSES[class] and "\nRaid debuff class, keep it even." or "")
            local w = 6 + 10 + 5 + c.num:GetUnboundedStringWidth() + (c.star:IsShown() and 8 or 0) + 7
            c:SetWidth(math.floor(w))
            if cx + w > width then break end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", cx, -(26 + 6))
            c:Show()
            cx = cx + w + 4
        end
    end
    for i = n + 1, #f.cls do f.cls[i]:Hide() end
    if n == 0 then
        f.even:ClearAllPoints()
        f.even:SetPoint("LEFT", f.clsLabel, "RIGHT", 8, 0)
        f.even:Show()
    else
        f.even:Hide()
    end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function sourceLabel()
    local src = Board.source
    if src == "live" then return "Live raid  -  " .. ns.Raid.count end
    if src == "demo" then return "Demo raid" end
    if src == "roster" then
        local r = ns.Rosters.Find(Board.sourceId)
        return "Roster: " .. (r and r.name or "?")
    end
    if src == "loadout" then
        local lo = Loadouts.Find(Board.sourceId)
        return "Loadout: " .. (lo and lo.name or "?")
    end
    return "No raid"
end

local function sourceMenu(owner)
    W.Dropdown(owner, function(_, root)
        root:CreateTitle("Show on the board")
        local live = root:CreateRadio("Live raid", function() return Board.source == "live" end, function() Board:SetSource("live") end)
        live:SetEnabled(IsInRaid())
        root:CreateRadio("Demo raid", function() return Board.source == "demo" end, function() Board:SetSource("demo") end)
        local rosters = ns.Rosters.List()
        if #rosters > 0 then
            root:CreateDivider()
            root:CreateTitle("Plan with a roster")
            for _, r in ipairs(rosters) do
                root:CreateRadio(r.name .. "  (" .. #r.members .. ")", function()
                    return Board.source == "roster" and Board.sourceId == r.id
                end, function() Board:SetSource("roster", r.id) end)
            end
        end
    end)
end

function Page:Build(f)
    self.f = f
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT")
    tb:SetPoint("TOPRIGHT")
    tb:SetHeight(TOOLBAR_H)
    local line = W.Rect(tb, "BORDER", T.Color("line"))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    self.toolbar = tb

    self.sourceBtn = W.Button(tb, { text = "", height = 28, weight = "regular", onClick = function(b) sourceMenu(b) end,
        tooltip = "What the board shows: the live raid, the demo raid, or a planning roster." })
    self.sourceBtn.chev = W.Icon(self.sourceBtn, "chevron", 10, T.Color("muted"))
    self.sourceBtn.chev:SetRotation(-math.pi / 2)
    self.sourceBtn:SetPoint("LEFT", PAD, 0)

    self.conv = W.Segmented(tb, { { "oddeven", "Odd / Even" }, { "split", "1-2 / 3-4" } },
        function() return ns.settings.conv end,
        function(v) Board:SetConvention(v) end)
    self.conv:SetPoint("LEFT", self.sourceBtn, "RIGHT", 6, 0)

    self.groups = W.Segmented(tb, { { "auto", "Auto" }, { 4, "4" }, { 6, "6" } },
        function() return ns.settings.groupsMode end,
        function(v) Board:SetGroupsMode(v) end)
    self.groups:SetPoint("LEFT", self.conv, "RIGHT", 6, 0)

    self.apply = W.Button(tb, { text = "Apply", icon = "play", kind = "primary", height = 28, onClick = function() Page:OnApply() end })
    self.apply:SetPoint("RIGHT", -PAD, 0)
    self.stop = W.IconButton(tb, "close", 28, "Stop applying", function() ns.Apply:Stop() end)
    self.stop:SetPoint("RIGHT", self.apply, "LEFT", -4, 0)
    self.save = W.Button(tb, { text = "Save", icon = "save", height = 28, onClick = function() UI.SaveDialog() end,
        tooltip = "Save the board as a loadout." })
    self.revert = W.IconButton(tb, "undo", 28, "Revert: throw away changes and show the live raid", function() Board:Revert() end)
    self.split = W.Button(tb, { text = "Auto-split", icon = "wand", height = 28, onClick = function()
        local n = ns.Split.Run(Board)
        if Board:IsLiveLike() then
            UI.Toast("Auto-split done: " .. n .. " move" .. (n == 1 and "" or "s") .. " pending. Review, then Apply.", "ok")
        else
            UI.Toast("Auto-split done.", "ok")
        end
    end, tooltip = "Balance tanks, healers, melee, ranged and classes between the halves, moving as few players as possible." })

    self.chip = CreateFrame("Frame", nil, tb)
    self.chip:SetHeight(26)
    W.Skin(self.chip, "win", "line")
    self.chip.icon = W.Icon(self.chip, "check", 13)
    self.chip.icon:SetPoint("LEFT", 8, 0)
    self.chip.text = W.Text(self.chip, 11.5, "semibold", "text")
    self.chip.text:SetPoint("LEFT", self.chip.icon, "RIGHT", 5, 0)
    self.chip:EnableMouse(true)
    self.chip:SetScript("OnEnter", function(c) if c.tip then W.Tooltip(c, c.tipTitle, c.tip) end end)
    self.chip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- content
    self.scroll = W.Scroll(f)
    self.scroll:SetPoint("TOPLEFT", PAD, -(TOOLBAR_H + 12))
    self.scroll:SetPoint("BOTTOMRIGHT", -PAD - 8, 8)
    local content = self.scroll.child
    self.content = content

    -- banner
    local banner = CreateFrame("Frame", nil, content)
    banner:SetHeight(46)
    banner.bg = W.Round(banner, "BACKGROUND", "round", T.Color("panel"))
    banner.bg:SetAllPoints()
    banner.tint = W.Round(banner, "BACKGROUND", "round", 1, 1, 1, 0.09, 1)
    banner.tint:SetAllPoints()
    banner.border = W.Round(banner, "BORDER", "ring", 1, 1, 1, 0.35)
    banner.border:SetAllPoints()
    banner.icon = W.Icon(banner, "info", 16)
    banner.icon:SetPoint("LEFT", 12, 0)
    banner.line1 = W.Text(banner, 12, "regular", "text")
    banner.line1:SetPoint("TOPLEFT", 38, -8)
    banner.line2 = W.Text(banner, 11.5, "regular", "muted")
    banner.line2:SetPoint("TOPLEFT", banner.line1, "BOTTOMLEFT", 0, -3)
    banner.close = W.IconButton(banner, "close", 24, "Dismiss", function() Page:OnBannerClose() end)
    banner.close:SetPoint("RIGHT", -8, 0)
    banner.b2 = W.Button(banner, { text = "", height = 28 })
    banner.b1 = W.Button(banner, { text = "", icon = "wand", kind = "primary", height = 28 })
    T.OnAccent(function(r, g, b)
        banner.tint:SetVertexColor(r, g, b, 0.09)
        banner.border:SetVertexColor(r, g, b, 0.35)
        banner.icon:SetVertexColor(r, g, b)
    end)
    self.banner = banner

    -- halves
    self.halves = {}
    for _, side in ipairs({ "L", "R" }) do
        local h = CreateFrame("Frame", nil, content)
        W.Skin(h, "panel", "line")
        h.sw = W.Round(h, "ARTWORK", "round3")
        h.sw:SetSize(9, 9)
        h.sw:SetPoint("TOPLEFT", HALF_PAD + 3, -HALF_PAD - 7)
        h.name = W.Text(h, 13, "bold", "text")
        h.name:SetPoint("LEFT", h.sw, "RIGHT", 7, 0)
        h.meta = W.Text(h, 11, "regular", "dim")
        h.meta:SetPoint("TOPRIGHT", -HALF_PAD - 3, -HALF_PAD - 5)
        h.counters = createCounters(h)
        h.side = side
        self.halves[side] = h
    end
    -- single panel when columns are not grouped by half
    local single = CreateFrame("Frame", nil, content)
    W.Skin(single, "panel", "line")
    single.counters = {}
    for _, side in ipairs({ "L", "R" }) do
        local lbl = W.Text(single, 10, "bold", "dim")
        single.counters[side] = createCounters(single)
        single.counters[side].lbl = lbl
    end
    self.single = single

    self.columns = {}
    for g = 1, 8 do self.columns[g] = createColumn(content, g) end
    Page.columns = self.columns

    -- tray
    local tray = CreateFrame("Frame", nil, content)
    tray.bg = W.Round(tray, "BACKGROUND", "round", T.Color("panel"))
    tray.bg:SetAllPoints()
    tray.border = W.Round(tray, "BORDER", "ring")
    tray.border:SetAllPoints()
    tray.title = W.Text(tray, 12.5, "semibold", "text")
    tray.title:SetPoint("TOPLEFT", 12, -11)
    tray.title:SetText("Unassigned")
    tray.hint = W.Text(tray, 11, "regular", "dim")
    tray.hint:SetPoint("LEFT", tray.title, "RIGHT", 8, 0)
    tray.hint:SetPoint("RIGHT", -12, 0)
    tray.empty = W.Text(tray, 11.5, "regular", "dim")
    tray.empty:SetText("Empty")
    tray.empty:SetPoint("TOPLEFT", 12, -36)
    tray:EnableMouse(true)
    tray:SetScript("OnEnter", function(t) if Page.dragKey then t.border:SetVertexColor(T.Accent()) end end)
    tray:SetScript("OnLeave", function(t) local r, g, b = T.Accent() t.border:SetVertexColor(r, g, b, 0.45) end)
    T.OnAccent(function(r, g, b) tray.border:SetVertexColor(r, g, b, 0.45) end)
    self.tray = tray
    Page.tray = tray

    -- bench
    local bench = CreateFrame("Frame", nil, content)
    W.Skin(bench, "panel", "line")
    bench.head = CreateFrame("Button", nil, bench)
    bench.head:SetPoint("TOPLEFT")
    bench.head:SetPoint("TOPRIGHT")
    bench.head:SetHeight(36)
    bench.chev = W.Icon(bench.head, "chevron", 11, T.Color("dim"))
    bench.chev:SetPoint("LEFT", 12, 0)
    bench.title = W.Text(bench.head, 12.5, "semibold", "text")
    bench.title:SetText("Bench")
    bench.title:SetPoint("LEFT", bench.chev, "RIGHT", 8, 0)
    bench.meta = W.Text(bench.head, 11, "regular", "dim")
    bench.meta:SetPoint("LEFT", bench.title, "RIGHT", 8, 0)
    bench.head:SetScript("OnClick", function()
        ns.settings.benchOpen = not ns.settings.benchOpen
        Page:Refresh()
    end)
    self.bench = bench

    -- empty state
    local empty = CreateFrame("Frame", nil, content)
    W.Skin(empty, "panel", "line")
    empty:SetHeight(190)
    empty.title = W.Text(empty, 16, "bold", "text")
    empty.title:SetPoint("TOP", 0, -30)
    empty.text = W.Text(empty, 12, "regular", "muted")
    empty.text:SetWordWrap(true)
    empty.text:SetJustifyH("CENTER")
    empty.text:SetWidth(460)
    empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -10)
    empty.demo = W.Button(empty, { text = "Try the demo raid", icon = "play", kind = "primary", onClick = function() Board:SetSource("demo") end })
    empty.roster = W.Button(empty, { text = "Plan from a roster", icon = "nav_rosters", onClick = function() UI.ShowPage("rosters") end })
    empty.demo:SetPoint("TOPRIGHT", empty, "TOP", -4, -112)
    empty.roster:SetPoint("TOPLEFT", empty, "TOP", 4, -112)
    self.empty = empty
end

---------------------------------------------------------------------------
-- Toolbar state
---------------------------------------------------------------------------
local IMB_NAMES = { T = "Tanks", H = "Healers", M = "Melee", R = "Ranged" }

function Page:RefreshToolbar()
    local k = Board:K()
    local live = Board:IsLiveLike()
    local none = Board.source == "none"
    local apply = ns.Apply

    self.sourceBtn:SetLabel(sourceLabel())
    self.sourceBtn:SetWidth(math.min(self.sourceBtn:GetWidth() + 18, 190))
    self.sourceBtn.label:SetWidth(self.sourceBtn:GetWidth() - 36)
    self.sourceBtn.label:ClearAllPoints()
    self.sourceBtn.label:SetPoint("LEFT", 11, 0)
    self.sourceBtn.chev:ClearAllPoints()
    self.sourceBtn.chev:SetPoint("RIGHT", -10, 0)

    local L, R = Board.HalvesFor("split", k)
    self.conv:SetItems({
        { "oddeven", "Odd / Even", "Left half = odd groups, right half = even groups." },
        { "split", L[1] .. "-" .. L[#L] .. " / " .. R[1] .. "-" .. R[#R], "Left half = low groups, right half = high groups." },
    })
    local autoK = ns.settings.groupsMode == "auto" and k or nil
    self.groups:SetItems({
        { "auto", autoK and ("Auto " .. autoK) or "Auto", "Mythic uses groups 1-4; other raids by size." },
        { 4, "4" }, { 6, "6" },
    })

    -- right side, right to left
    local running = apply.running
    local pending = Board:Pending()
    if running then
        self.apply:SetLabel("Applying " .. apply.done .. "/" .. apply.total)
        self.apply:SetBadge(nil)
        self.apply:SetDisabled(false)
        self.stop:Show()
    else
        self.stop:Hide()
        self.apply:SetLabel("Apply")
        self.apply:SetBadge(live and pending > 0 and pending or nil)
        local ok, reason = apply:CanApply()
        if not live then
            self.apply:SetDisabled(true, "Planning mode: save as a loadout, then load it while in the raid.")
        elseif not ok then
            self.apply:SetDisabled(true, reason)
        elseif pending == 0 then
            self.apply:SetDisabled(true, "Nothing to apply: the raid already matches the board.")
        else
            self.apply:SetDisabled(false)
        end
    end
    local right = running and self.stop or self.apply
    self.save:ClearAllPoints()
    self.save:SetPoint("RIGHT", right, "LEFT", -6, 0)
    self.save:SetDisabled(none or (#Board.members == 0 and #Board.ghosts == 0), "The board is empty.")
    local anchor = self.save
    if live then
        self.revert:Show()
        self.revert:ClearAllPoints()
        self.revert:SetPoint("RIGHT", self.save, "LEFT", -4, 0)
        self.revert:SetDisabled(running or not Board:Dirty())
        anchor = self.revert
    else
        self.revert:Hide()
    end
    self.split:ClearAllPoints()
    self.split:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    self.split:SetDisabled(none or running or #Board.members == 0)
    self.chip:ClearAllPoints()
    self.chip:SetPoint("RIGHT", self.split, "LEFT", -6, 0)

    local imb = Board:Imbalances()
    if none or #Board.members == 0 then
        self.chip:Hide()
    else
        self.chip:Show()
        if #imb == 0 then
            self.chip.icon:SetTexture(T.ICON .. "check")
            self.chip.icon:SetVertexColor(T.Color("ok"))
            self.chip.text:SetText("Even")
            self.chip.text:SetTextColor(T.Color("ok"))
            self.chip.border:SetVertexColor(T.Color("ok"))
            self.chip.border:SetAlpha(0.4)
            self.chip.tipTitle = "Halves are even"
            self.chip.tip = { "Tanks, healers, melee, ranged and every class are split as evenly as possible." }
        else
            self.chip.icon:SetTexture(T.ICON .. "warn")
            self.chip.icon:SetVertexColor(T.Color("warn"))
            self.chip.text:SetText(#imb .. " uneven")
            self.chip.text:SetTextColor(T.Color("warn"))
            self.chip.border:SetVertexColor(T.Color("warn"))
            self.chip.border:SetAlpha(0.5)
            local names = {}
            for _, x in ipairs(imb) do names[#names + 1] = IMB_NAMES[x] or Data.ClassName(x) end
            self.chip.tipTitle = "Uneven between the halves"
            self.chip.tip = { table.concat(names, ", ") }
        end
        self.chip:SetWidth(math.floor(8 + 13 + 5 + self.chip.text:GetUnboundedStringWidth() + 10))
    end

    local conv, groupsSeg = self.conv, self.groups
    conv:SetShown(not none)
    groupsSeg:SetShown(not none)

    -- narrow windows: drop button labels before things overlap. Measure with the full labels
    -- and sum widths instead of reading screen positions, so the result does not depend on the
    -- previous refresh or on rects that are not resolved yet during a resize.
    self.split:SetLabel("Auto-split")
    self.save:SetLabel("Save")
    local leftW = PAD + self.sourceBtn:GetWidth()
    if not none then leftW = leftW + 6 + conv:GetWidth() + 6 + groupsSeg:GetWidth() end
    local rightW = PAD + self.apply:GetWidth() + (running and 4 + self.stop:GetWidth() or 0)
        + 6 + self.save:GetWidth() + (live and 4 + self.revert:GetWidth() or 0)
        + 6 + self.split:GetWidth() + (self.chip:IsShown() and 6 + self.chip:GetWidth() or 0)
    local tbW = self.toolbar:GetWidth()
    if tbW < 50 then tbW = self.f:GetWidth() end
    if leftW + 8 + rightW > tbW then
        self.split:SetLabel("")
        self.save:SetLabel("")
    end
end

function Page:OnApply()
    local apply = ns.Apply
    if apply.running then
        apply:Start()
        return
    end
    local n = Board:Pending()
    local function go()
        local ok, reason = apply:Start()
        if not ok and reason then UI.Toast(reason, "warn") end
    end
    if ns.settings.confirmApply and Board.source == "live" then
        UI.Modal({
            title = "Apply " .. n .. " move" .. (n == 1 and "" or "s") .. "?",
            text = "FastGroups moves one player at a time and waits for the server to confirm each move. It stops by itself if combat starts.",
            buttons = {
                { text = "Cancel", kind = "ghost" },
                { text = "Apply", kind = "primary", onClick = go },
            },
        })
    else
        go()
    end
end

function Page:OnBannerClose()
    if Board.source == "loadout" or Board.source == "roster" then
        Board:AutoSource(true)
    else
        Board:DismissLoaded()
    end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function setBanner(b, line1, line2, b1, b2)
    b.line1:SetText(line1)
    b.line2:SetText(line2 or "")
    local x = -40
    for _, pair in ipairs({ { b.b2, b2 }, { b.b1, b1 } }) do
        local btn, spec = pair[1], pair[2]
        if spec then
            btn:SetLabel(spec.text)
            btn:SetKind(spec.kind or "default")
            btn:SetScript("OnClick", function() spec.onClick() end)
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", x, 0)
            btn:Show()
            x = x - btn:GetWidth() - 6
        else
            btn:Hide()
        end
    end
    b:Show()
end

local function colorNum(n, color)
    local r, g, bl
    if color == "accent" then r, g, bl = T.Accent() else r, g, bl = T.Color(color) end
    return "|c" .. T.Hex(r, g, bl) .. n .. "|r"
end

function Page:LayoutBanner(width, y)
    local b = self.banner
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -y)
    b:SetWidth(width)
    local src = Board.source
    if src == "loadout" then
        local lo = Loadouts.Find(Board.sourceId)
        setBanner(b, "Editing loadout |cffffffff" .. (lo and lo.name or "") .. "|r",
            "Drag players around, then Save and choose Overwrite.",
            { text = "Save", kind = "primary", onClick = function() UI.SaveDialog() end },
            nil)
        return y + 46 + 12
    elseif src == "roster" then
        local r = ns.Rosters.Find(Board.sourceId)
        setBanner(b, "Planning with |cffffffff" .. (r and r.name or "") .. "|r",
            "Auto-split or drag players into groups, then Save as a loadout and load it when the raid forms.",
            { text = "Auto-split", kind = "primary", onClick = function() ns.Split.Run(Board) end },
            nil)
        return y + 46 + 12
    end
    local l = Board.loaded
    if l and (l.absent > 0 or l.fresh > 0 or l.returning > 0) then
        local waiting = 0
        for _, key in ipairs(Board.members) do
            if Board.draft[key] == 0 then waiting = waiting + 1 end
        end
        local stats = colorNum(l.present, "text") .. " matched     " .. colorNum(#Board.ghosts, "danger") .. " absent     "
            .. colorNum(l.fresh, "accent") .. " new     " .. colorNum(l.returning, "ok") .. " returning"
        setBanner(b, "Loaded |cffffffff" .. l.name .. "|r", stats,
            waiting > 0 and { text = "Auto-fill", kind = "primary", onClick = function()
                local placed = Board:AutoFill()
                UI.Toast("Auto-fill placed " .. placed .. " player" .. (placed == 1 and "" or "s") .. ". Substitutes are marked; review and Apply.", "ok")
            end } or nil,
            #Board.ghosts > 0 and { text = "Clear absent", onClick = function() Board:ClearGhosts() end } or nil)
        return y + 46 + 12
    end
    b:Hide()
    return y
end

function Page:LayoutHalves(width, y)
    local s = ns.settings
    local k = Board:K()
    local L, R = Board:Halves()
    local counterW
    if s.arrangeByHalf then
        self.single:Hide()
        local halfW = math.floor((width - 12) / 2)
        local hh = HALF_PAD + HALF_HEAD + COL_H + 10 + 54 + HALF_PAD
        for i, side in ipairs({ "L", "R" }) do
            local h = self.halves[side]
            local groups = side == "L" and L or R
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", (i - 1) * (halfW + 12), -y)
            h:SetSize(halfW, hh)
            h.name:SetText(strupper(s.halfNames[side]))
            if side == "L" then h.sw:SetVertexColor(T.Accent()) else h.sw:SetVertexColor(T.Color("muted")) end
            h.meta:SetText("Groups " .. table.concat(groups, ", ") .. "  -  " .. Board:Counts(side).n .. " players")
            local nc = #groups
            local colW = math.floor((halfW - 2 * HALF_PAD - (nc - 1) * 6) / nc)
            for j, g in ipairs(groups) do
                local col = self.columns[g]
                col:SetParent(h)
                col:SetFrameLevel(h:GetFrameLevel() + 1)
                col:ClearAllPoints()
                col:SetPoint("TOPLEFT", HALF_PAD + (j - 1) * (colW + 6), -(HALF_PAD + HALF_HEAD))
                fillColumn(col, colW)
            end
            counterW = halfW - 2 * HALF_PAD
            h.counters:ClearAllPoints()
            h.counters:SetPoint("TOPLEFT", HALF_PAD, -(HALF_PAD + HALF_HEAD + COL_H + 10))
            fillCounters(h.counters, side, counterW)
            h:Show()
        end
        return y + hh + 14
    end
    -- one panel, groups 1..k in order with side tags
    for _, side in ipairs({ "L", "R" }) do self.halves[side]:Hide() end
    local p = self.single
    local hh = HALF_PAD + COL_H + 10 + 16 + 54 + HALF_PAD
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", 0, -y)
    p:SetSize(width, hh)
    local colW = math.floor((width - 2 * HALF_PAD - (k - 1) * 6) / k)
    for g = 1, k do
        local col = self.columns[g]
        col:SetParent(p)
        col:SetFrameLevel(p:GetFrameLevel() + 1)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", HALF_PAD + (g - 1) * (colW + 6), -HALF_PAD)
        fillColumn(col, colW)
    end
    local halfW = math.floor((width - 2 * HALF_PAD - 12) / 2)
    for i, side in ipairs({ "L", "R" }) do
        local c = p.counters[side]
        c.lbl:SetText(strupper(s.halfNames[side]))
        c.lbl:ClearAllPoints()
        c.lbl:SetPoint("TOPLEFT", HALF_PAD + (i - 1) * (halfW + 12), -(HALF_PAD + COL_H + 10))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", c.lbl, "BOTTOMLEFT", 0, -6)
        fillCounters(c, side, halfW)
    end
    p:Show()
    return y + hh + 14
end

function Page:LayoutTray(width, y)
    local tray = self.tray
    local waiting = {}
    for _, key in ipairs(Board.members) do
        if Board.draft[key] == 0 then waiting[#waiting + 1] = key end
    end
    local show = #waiting > 0 or Board.source == "roster" or Board.loaded ~= nil
    if not show then
        tray:Hide()
        return y
    end
    Board.SortKeys(waiting)
    tray:ClearAllPoints()
    tray:SetPoint("TOPLEFT", 0, -y)
    tray:SetWidth(width)
    if #waiting > 0 then
        tray.hint:SetText(#waiting .. " waiting  -  drag into a group, drop onto an ABSENT card to substitute, or use Auto-fill / Auto-split")
        tray.empty:Hide()
    else
        tray.hint:SetText("drop players here to take them out of the setup")
        tray.empty:Show()
    end
    local perRow = math.max(1, math.floor((width - 24 + 6) / (TRAY_CARD_W + 6)))
    local cw = math.floor((width - 24 - (perRow - 1) * 6) / perRow)
    for i, key in ipairs(waiting) do
        local c = acquireCard(tray)
        fillCard(c, key, false)
        local row, colN = math.floor((i - 1) / perRow), (i - 1) % perRow
        c:SetSize(cw, CARD_H)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", 12 + colN * (cw + 6), -(36 + row * (CARD_H + 8)))
    end
    local rows = math.max(1, math.ceil(#waiting / perRow))
    local h = 36 + rows * (CARD_H + 8) + 6
    tray:SetHeight(h)
    tray:Show()
    return y + h + 14
end

function Page:LayoutBench(width, y)
    local k = Board:K()
    local bench = self.bench
    bench:ClearAllPoints()
    bench:SetPoint("TOPLEFT", 0, -y)
    bench:SetWidth(width)
    local count = 0
    for g = k + 1, 8 do count = count + Board:Occupancy(g) end
    bench.meta:SetText("groups " .. (k + 1) .. "-8  -  " .. count .. " player" .. (count == 1 and "" or "s")
        .. (Board:IsMythic() and k == 4 and "  -  outside the Mythic 20" or ""))
    local open = ns.settings.benchOpen
    bench.chev:SetRotation(open and -math.pi / 2 or 0)
    local h = 36
    if open then
        local n = 8 - k
        local colW = math.floor((width - 20 - (n - 1) * 6) / n)
        for g = k + 1, 8 do
            local col = self.columns[g]
            col:SetParent(bench)
            col:SetFrameLevel(bench:GetFrameLevel() + 1)
            col:ClearAllPoints()
            col:SetPoint("TOPLEFT", 10 + (g - k - 1) * (colW + 6), -36)
            fillColumn(col, colW)
        end
        h = 36 + COL_H + 10
    end
    bench:SetHeight(h)
    bench:Show()
    return y + h + 14
end

function Page:Refresh()
    if not self.f or not self.f:IsShown() then return end
    if Page.dragKey then
        Page.dirty = true
        return
    end
    Page.dirty = false
    releaseCards()
    self:RefreshToolbar()
    local width = math.floor(self.scroll:GetWidth())
    if width < 50 then width = math.floor(self.f:GetWidth() - 2 * PAD - 8) end
    self.content:SetWidth(width)
    for _, col in ipairs(self.columns) do col:Hide() end

    if Board.source == "none" then
        self.banner:Hide()
        self.halves.L:Hide()
        self.halves.R:Hide()
        self.single:Hide()
        self.tray:Hide()
        self.bench:Hide()
        local e = self.empty
        e:ClearAllPoints()
        e:SetPoint("TOPLEFT", 0, 0)
        e:SetWidth(width)
        e.title:SetText(IsInRaid() and "Loading raid..." or "You are not in a raid")
        e.text:SetText("The board shows your raid as soon as you join one. Until then you can try the demo raid, "
            .. "plan groups from a roster, or click a loadout on the left to edit it.")
        e:Show()
        self.content:SetHeight(200)
        return
    end
    self.empty:Hide()

    local y = 0
    y = self:LayoutBanner(width, y)
    y = self:LayoutHalves(width, y)
    y = self:LayoutTray(width, y)
    y = self:LayoutBench(width, y)
    self.content:SetHeight(math.max(y, 10))
end

function Page:OnHide()
    if Page.dragKey and Page.dragSource then onCardDragStop(Page.dragSource) end
end
