-- Small widget toolkit in the FastGroups style: flat, rounded, dark.
local _, ns = ...

local T = ns.T

local W = {}
ns.W = W

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
local SLICE = { round = 8, ring = 8, round3 = 4 }

-- A nine-sliced rounded texture. kind: "round" (fill), "ring" (1px border), "round3".
function W.Round(parent, layer, kind, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(T.TEX[kind or "round"])
    local m = SLICE[kind or "round"]
    if m then
        t:SetTextureSliceMargins(m, m, m, m)
        t:SetTextureSliceMode(Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
    end
    t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return t
end

function W.Rect(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetTexture(T.TEX.white)
    t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return t
end

function W.Icon(parent, name, size, r, g, b, a, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(T.ICON .. name)
    t:SetSize(size, size)
    t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return t
end

function W.SetIcon(t, name)
    t:SetTexture(T.ICON .. name)
end

-- Background + border on any frame.
function W.Skin(frame, bg, border, bgAlpha, borderAlpha)
    if bg then
        frame.bg = W.Round(frame, "BACKGROUND", "round", T.Color(bg))
        frame.bg:SetAlpha(bgAlpha or 1)
        frame.bg:SetAllPoints()
    end
    if border then
        frame.border = W.Round(frame, "BORDER", "ring", T.Color(border))
        frame.border:SetAlpha(borderAlpha or 1)
        frame.border:SetAllPoints()
    end
    return frame
end

function W.Text(parent, size, weight, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(T.FONT[weight or "regular"], size or 12, "")
    fs:SetTextColor(T.Color(color or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function W.SetFont(fs, size, weight, flags)
    fs:SetFont(T.FONT[weight or "regular"], size, flags or "")
end

function W.Frame(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    if w then f:SetWidth(w) end
    if h then f:SetHeight(h) end
    return f
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
function W.Tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    if lines then
        for _, l in ipairs(lines) do
            if type(l) == "table" then
                GameTooltip:AddLine(l[1], l[2], l[3], l[4], true)
            else
                GameTooltip:AddLine(l, 0.75, 0.78, 0.84, true)
            end
        end
    end
    GameTooltip:Show()
end

local function hideTooltip() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function buttonUpdate(b)
    local kind, hover = b.kind, b.hover and not b.disabled
    local ar, ag, ab = T.Accent()
    if kind == "primary" then
        local m = hover and 1.12 or 1
        b.bg:SetVertexColor(math.min(ar * m, 1), math.min(ag * m, 1), math.min(ab * m, 1), 1)
        b.border:SetVertexColor(ar, ag, ab, 1)
        b.label:SetTextColor(T.Color("ink"))
        if b.icon then b.icon:SetVertexColor(T.Color("ink")) end
    elseif kind == "danger" then
        local r, g, bl = T.Color("danger")
        local m = hover and 1.1 or 1
        b.bg:SetVertexColor(math.min(r * m, 1), g * m, bl * m, 1)
        b.border:SetVertexColor(r, g, bl, 1)
        b.label:SetTextColor(1, 1, 1)
        if b.icon then b.icon:SetVertexColor(1, 1, 1) end
    elseif kind == "ghost" then
        local r, g, bl = T.Color("panel2")
        b.bg:SetVertexColor(r, g, bl, hover and 1 or 0)
        b.border:SetVertexColor(0, 0, 0, 0)
        local tc = hover and "text" or "muted"
        b.label:SetTextColor(T.Color(tc))
        if b.icon then b.icon:SetVertexColor(T.Color(tc)) end
    else
        b.bg:SetVertexColor(T.Color(hover and "panel3" or "panel2"))
        b.border:SetVertexColor(T.Color("line2"))
        b.label:SetTextColor(T.Color("text"))
        if b.icon then b.icon:SetVertexColor(T.Color(b.iconColor or "text")) end
    end
    b:SetAlpha(b.disabled and 0.4 or 1)
end

local function buttonLayout(b)
    local w
    local tw = b.label:GetText() and b.label:GetText() ~= "" and b.label:GetUnboundedStringWidth() or 0
    local pad = b.pad or 11
    if b.icon then
        b.icon:ClearAllPoints()
        if tw > 0 then
            b.icon:SetPoint("LEFT", pad - 1, 0)
            b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
            w = pad - 1 + b.icon:GetWidth() + 6 + tw + pad
        else
            b.icon:SetPoint("CENTER")
            w = b:GetHeight()
        end
    else
        b.label:ClearAllPoints()
        b.label:SetPoint("CENTER")
        w = tw + pad * 2
    end
    if b.badge and b.badge:IsShown() then
        b.badge:ClearAllPoints()
        b.badge:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
        w = w + b.badge:GetWidth() + 6
    end
    if not b.fixedWidth then b:SetWidth(math.floor(w + 0.5)) end
end

local buttonMethods = {}
function buttonMethods:SetLabel(text)
    self.label:SetText(text or "")
    buttonLayout(self)
end
function buttonMethods:SetDisabled(disabled, reason)
    self.disabled = disabled and true or false
    self.disabledReason = reason
    buttonUpdate(self)
end
function buttonMethods:SetKind(kind)
    self.kind = kind
    buttonUpdate(self)
end
function buttonMethods:SetBadge(n)
    if not self.badge then
        local f = CreateFrame("Frame", nil, self)
        f:SetSize(18, 16)
        f.bg = W.Round(f, "ARTWORK", "round3", T.Color("ink"))
        f.bg:SetAllPoints()
        f.text = W.Text(f, 10.5, "bold", "text")
        f.text:SetPoint("CENTER", 0, 0)
        self.badge = f
        T.OnAccent(function(r, g, b) f.text:SetTextColor(r, g, b) end)
    end
    if n and n ~= 0 then
        self.badge.text:SetText(n)
        self.badge:SetWidth(math.max(18, self.badge.text:GetUnboundedStringWidth() + 10))
        self.badge:Show()
    else
        self.badge:Hide()
    end
    buttonLayout(self)
end
buttonMethods.Refresh = buttonUpdate

--[[ opts: text, icon, kind ("default"|"primary"|"ghost"|"danger"), width, height,
  onClick(self, mouseButton), tooltip (string or function(self)), iconColor ]]
function W.Button(parent, opts)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(opts.height or 28)
    b.kind = opts.kind or "default"
    b.pad = opts.pad
    b.iconColor = opts.iconColor
    b.bg = W.Round(b, "BACKGROUND", "round")
    b.bg:SetAllPoints()
    b.border = W.Round(b, "BORDER", "ring")
    b.border:SetAllPoints()
    if opts.icon then b.icon = W.Icon(b, opts.icon, opts.iconSize or 14) end
    b.label = W.Text(b, opts.fontSize or 12, opts.weight or "semibold", "text")
    b.label:SetText(opts.text or "")
    if opts.icon then b.label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0) end
    for k, fn in pairs(buttonMethods) do b[k] = fn end
    if opts.width then
        b.fixedWidth = true
        b:SetWidth(opts.width)
    end
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", function(self)
        self.hover = true
        buttonUpdate(self)
        local tip = opts.tooltip
        if self.disabled and self.disabledReason then
            W.Tooltip(self, self.label:GetText() or "", { { self.disabledReason, 1, 0.65, 0.2 } })
        elseif type(tip) == "function" then
            tip(self)
        elseif tip then
            W.Tooltip(self, tip)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        buttonUpdate(self)
        hideTooltip()
    end)
    b:SetScript("OnClick", function(self, mouse)
        if self.disabled then return end
        if opts.onClick then opts.onClick(self, mouse) end
    end)
    buttonLayout(b)
    buttonUpdate(b)
    if b.kind == "primary" then T.OnAccent(function() buttonUpdate(b) end) end
    return b
end

function W.IconButton(parent, icon, size, tooltip, onClick)
    local b = W.Button(parent, { icon = icon, kind = "ghost", height = size or 24, iconSize = math.floor((size or 24) * 0.55), tooltip = tooltip, onClick = onClick })
    b:SetWidth(size or 24)
    b.fixedWidth = true
    return b
end

---------------------------------------------------------------------------
-- Segmented control
---------------------------------------------------------------------------
--[[ items: array of { value, label }; get() -> value; set(value) ]]
function W.Segmented(parent, items, get, set, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(opts.height or 28)
    W.Skin(f, "panel", "line")
    f.buttons = {}

    local function refresh()
        local cur = get()
        for _, b in ipairs(f.buttons) do
            if b:IsShown() then
                local on = tostring(b.value) == tostring(cur)
                b.bg:SetVertexColor(T.Color("panel3"))
                b.bg:SetAlpha(on and 1 or (b.hover and 0.45 or 0))
                b.label:SetTextColor(T.Color((on or b.hover) and "text" or "muted"))
            end
        end
    end

    function f:SetItems(list)
        local x = 2
        for i, it in ipairs(list) do
            local b = f.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, f)
                b.bg = W.Round(b, "ARTWORK", "round")
                b.bg:SetAllPoints()
                b.label = W.Text(b, opts.fontSize or 11.5, "semibold", "muted")
                b.label:SetPoint("CENTER")
                b:SetScript("OnClick", function(self)
                    set(self.value)
                    refresh()
                end)
                b:SetScript("OnEnter", function(self)
                    self.hover = true
                    refresh()
                    if self.tip then W.Tooltip(self, self.tip) end
                end)
                b:SetScript("OnLeave", function(self)
                    self.hover = false
                    refresh()
                    hideTooltip()
                end)
                f.buttons[i] = b
            end
            b.value = it[1]
            b.tip = it[3]
            b.label:SetText(it[2])
            local w = math.floor(b.label:GetUnboundedStringWidth() + 18)
            b:SetSize(w, f:GetHeight() - 4)
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            b:Show()
            x = x + w + 2
        end
        for i = #list + 1, #f.buttons do f.buttons[i]:Hide() end
        f:SetWidth(x)
        refresh()
    end

    f.Refresh = refresh
    f:SetItems(items)
    return f
end

---------------------------------------------------------------------------
-- Toggle switch and checkbox
---------------------------------------------------------------------------
function W.Toggle(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 20)
    b.track = W.Round(b, "BACKGROUND", "round")
    b.track:SetAllPoints()
    b.knob = b:CreateTexture(nil, "ARTWORK")
    b.knob:SetTexture(T.TEX.circle)
    b.knob:SetSize(14, 14)
    function b:Refresh()
        local on = get()
        self.knob:ClearAllPoints()
        if on then
            self.track:SetVertexColor(T.Accent())
            self.knob:SetVertexColor(T.Color("ink"))
            self.knob:SetPoint("RIGHT", -3, 0)
        else
            self.track:SetVertexColor(T.Color("panel3"))
            self.knob:SetVertexColor(0.67, 0.69, 0.75)
            self.knob:SetPoint("LEFT", 3, 0)
        end
    end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    b:Refresh()
    T.OnAccent(function() b:Refresh() end)
    return b
end

function W.Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    b.hl = W.Round(b, "BACKGROUND", "round", T.Color("panel2"))
    b.hl:SetAllPoints()
    b.hl:Hide()
    b.box = W.Round(b, "ARTWORK", "round3")
    b.box:SetSize(15, 15)
    b.box:SetPoint("LEFT", 7, 0)
    b.mark = W.Icon(b, "check", 11, T.Color("ink"), nil, nil, nil, "OVERLAY")
    b.mark:SetPoint("CENTER", b.box, "CENTER")
    b.label = W.Text(b, 12, "regular", "text")
    b.label:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", -8, 0)
    b.label:SetText(label or "")
    b.right = W.Text(b, 11, "regular", "dim")
    b.right:SetPoint("RIGHT", -8, 0)
    function b:Refresh()
        local on = get(self)
        if on then
            self.box:SetVertexColor(T.Accent())
            self.mark:Show()
        else
            self.box:SetVertexColor(T.Color("panel3"))
            self.mark:Hide()
        end
    end
    b:SetScript("OnClick", function(self)
        set(self, not get(self))
        self:Refresh()
    end)
    b:SetScript("OnEnter", function(self) self.hl:Show() end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    b:Refresh()
    return b
end

---------------------------------------------------------------------------
-- Edit boxes
---------------------------------------------------------------------------
--[[ opts: width, height, placeholder, multiline, onEnter(text), onChange(text, user), fontSize ]]
function W.Edit(parent, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(opts.width or 160, opts.height or 28)
    W.Skin(holder, "win", "line2")

    local eb
    if opts.multiline then
        local sf = CreateFrame("ScrollFrame", nil, holder)
        sf:SetPoint("TOPLEFT", 8, -7)
        sf:SetPoint("BOTTOMRIGHT", -18, 7)
        local bar = CreateFrame("EventFrame", nil, holder, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
        eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetWidth(100)
        sf:SetScrollChild(eb)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
        sf:HookScript("OnScrollRangeChanged", function(_, _, yrange) bar:SetShown((yrange or 0) > 0.5) end)
        sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(w) end)
        eb:SetScript("OnCursorChanged", function(self, _, y, _, h)
            local top = sf:GetVerticalScroll()
            local height = sf:GetHeight()
            y = -y
            if y < top then
                sf:SetVerticalScroll(y)
            elseif y + h > top + height then
                sf:SetVerticalScroll(math.max(0, y + h - height))
            end
        end)
        -- clicking anywhere in the box focuses the text
        holder:EnableMouse(true)
        holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
        holder.scroll = sf
    else
        eb = CreateFrame("EditBox", nil, holder)
        eb:SetPoint("TOPLEFT", 9, 0)
        eb:SetPoint("BOTTOMRIGHT", -9, 0)
    end
    eb:SetAutoFocus(false)
    eb:SetFont(opts.mono and "Fonts\\ARIALN.TTF" or T.FONT.regular, opts.fontSize or 12, "")
    eb:SetTextColor(T.Color("text"))
    if opts.maxLetters then eb:SetMaxLetters(opts.maxLetters) end

    local ph = W.Text(holder, opts.fontSize or 12, "regular", "dim")
    ph:SetText(opts.placeholder or "")
    if opts.multiline then
        ph:SetPoint("TOPLEFT", 9, -8)
    else
        ph:SetPoint("LEFT", 9, 0)
    end
    local function updatePh()
        ph:SetShown(eb:GetText() == "" and not eb:HasFocus())
    end
    eb:SetScript("OnEditFocusGained", function(self)
        holder.border:SetVertexColor(T.Accent())
        updatePh()
        if opts.selectOnFocus then self:HighlightText() end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        holder.border:SetVertexColor(T.Color("line2"))
        self:HighlightText(0, 0)
        updatePh()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if not opts.multiline then
        eb:SetScript("OnEnterPressed", function(self)
            if opts.onEnter then opts.onEnter(self:GetText()) end
            self:ClearFocus()
        end)
    end
    eb:SetScript("OnTextChanged", function(self, user)
        updatePh()
        if opts.onChange then opts.onChange(self:GetText(), user) end
    end)
    holder.edit = eb
    holder.placeholder = ph
    function holder:GetText() return eb:GetText() end
    function holder:SetText(t)
        eb:SetText(t or "")
        updatePh()
    end
    updatePh()
    return holder
end

---------------------------------------------------------------------------
-- Scroll area with Blizzard's minimal scroll bar
---------------------------------------------------------------------------
function W.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, -2)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 2)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
    sf:HookScript("OnScrollRangeChanged", function(_, _, yrange)
        bar:SetShown((yrange or 0) > 0.5)
    end)
    sf:SetScript("OnSizeChanged", function(self, w)
        child:SetWidth(w)
        if self.onResize then self.onResize(w) end
    end)
    sf.child = child
    sf.bar = bar
    return sf
end

---------------------------------------------------------------------------
-- Slider (value applied on release, so dragging does not rescale under the mouse)
---------------------------------------------------------------------------
function W.Slider(parent, width, minV, maxV, step, get, onChange, onRelease)
    local s = CreateFrame("Slider", nil, parent)
    s:SetSize(width, 16)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = W.Round(s, "BACKGROUND", "round3", T.Color("panel3"))
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.TEX.circle)
    thumb:SetSize(14, 14)
    s:SetThumbTexture(thumb)
    T.OnAccent(function(r, g, b) thumb:SetVertexColor(r, g, b) end)
    s:SetValue(get())
    s:SetScript("OnValueChanged", function(_, v, user)
        if user and onChange then onChange(v) end
    end)
    s:SetScript("OnMouseUp", function(self)
        if onRelease then onRelease(self:GetValue()) end
    end)
    return s
end

---------------------------------------------------------------------------
-- Pill (status chips in the title bar)
---------------------------------------------------------------------------
function W.Pill(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(20)
    W.Skin(f, "panel2", "line")
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetTexture(T.TEX.circle)
    f.dot:SetSize(6, 6)
    f.dot:SetPoint("LEFT", 8, 0)
    f.text = W.Text(f, 11, "regular", "muted")
    f.text:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
    function f:Set(text, color)
        self.text:SetText(text)
        if color then
            self.dot:Show()
            self.dot:SetVertexColor(T.Color(color))
            self.text:SetPoint("LEFT", self.dot, "RIGHT", 5, 0)
            self:SetWidth(self.text:GetUnboundedStringWidth() + 27)
        else
            self.dot:Hide()
            self.text:SetPoint("LEFT", 8, 0)
            self:SetWidth(self.text:GetUnboundedStringWidth() + 16)
        end
        self:Show()
    end
    return f
end

---------------------------------------------------------------------------
-- Context menu (Blizzard_Menu)
---------------------------------------------------------------------------
function W.Menu(owner, generator)
    MenuUtil.CreateContextMenu(owner, generator)
end

-- "2d ago" style
function W.Ago(t)
    if not t then return "" end
    local d = math.floor((time() - t) / 86400)
    if d <= 0 then return "today" end
    if d == 1 then return "yesterday" end
    return d .. "d ago"
end
