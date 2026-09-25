-- Small widget toolkit in the FastGroups style: flat, dark, square or rounded corners.
local _, ns = ...

local T = ns.T

local W = {}
ns.W = W

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------
-- Shapes that follow the "Square corners" option.
-- kind = { rounded texture, square texture, slice margin, tex coords }
local SHAPES = {
    round = { "round", "square", 8 },         -- fill
    ring = { "ring", "ring0", 8 },            -- 1px border
    round3 = { "round3", "square", 4 },       -- small radius for pills and badges
    knob = { "circle", "square" },            -- switch knob, slider thumb
    capTop = { "circle", "square", nil, { 0, 1, 0, 0.5 } },   -- scroll bar ends
    capBottom = { "circle", "square", nil, { 0, 1, 0.5, 1 } },
    corner = { "round", "square", nil, { 0, 0.5, 0.5, 1 } },  -- one bottom-left corner
}

-- Sets (or resets after the option changed) the texture of a shaped region.
function W.SetShape(t, kind)
    local s = SHAPES[kind]
    t.fgShape = kind
    t:SetTexture(T.TEX[s[ns.settings.squareCorners and 2 or 1]])
    local m = s[3]
    if m then
        t:SetTextureSliceMargins(m, m, m, m)
        t:SetTextureSliceMode(Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
    end
    local c = s[4]
    if c then t:SetTexCoord(c[1], c[2], c[3], c[4]) end
end

-- A shaped texture, nine-sliced when the kind has a margin. kind: see SHAPES.
function W.Round(parent, layer, kind, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    W.SetShape(t, kind or "round")
    t:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    return t
end

-- Top level frames holding shaped regions. W.RefreshShapes walks them only when
-- the option changes; nothing is tracked per texture.
local shapeRoots = {}
function W.AddShapeRoot(f)
    shapeRoots[#shapeRoots + 1] = f
end

local function reshape(f)
    local regions = { f:GetRegions() }
    for i = 1, #regions do
        local kind = regions[i].fgShape
        if kind then W.SetShape(regions[i], kind) end
    end
    local children = { f:GetChildren() }
    for i = 1, #children do reshape(children[i]) end
end

function W.RefreshShapes()
    for i = 1, #shapeRoots do reshape(shapeRoots[i]) end
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

-- Widgets that size themselves to their text register a relayout here while the fonts
-- are still loading (see Theme.lua); W.FontsReady runs each one once. Nothing is kept
-- once the fonts are in.
local pendingLayout

function W.WhenFontsReady(obj, fn)
    if T.fontsReady then return end
    if not pendingLayout then pendingLayout = setmetatable({}, { __mode = "k" }) end
    pendingLayout[obj] = fn
end

function W.FontsReady()
    local list = pendingLayout
    pendingLayout = nil
    if not list then return end
    for obj, fn in pairs(list) do fn(obj) end
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

local buttonRelayout

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
    W.WhenFontsReady(b, buttonRelayout)
end

buttonRelayout = function(b)
    local badge = b.badge
    if badge and badge:IsShown() then
        badge:SetWidth(math.max(18, badge.text:GetUnboundedStringWidth() + 10))
    end
    buttonLayout(b)
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
local function relayoutSegmented(f) f:SetItems(f.items) end

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
        f.items = list
        W.WhenFontsReady(f, relayoutSegmented)
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
    b.knob = W.Round(b, "ARTWORK", "knob")
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
-- Slim scroll bar (used by W.Scroll and multiline edit boxes)
---------------------------------------------------------------------------
local WHEEL_STEP = 40

local function paintScrollBar(bar)
    local hot = bar.hover or bar.dragging
    local r, g, b = T.Color(hot and "muted" or "dim")
    local a = hot and 1 or 0.7
    local w = hot and 6 or 4
    bar.top:SetSize(w, w / 2)
    bar.mid:SetWidth(w)
    bar.bottom:SetSize(w, w / 2)
    bar.top:SetVertexColor(r, g, b, a)
    bar.mid:SetVertexColor(r, g, b, a)
    bar.bottom:SetVertexColor(r, g, b, a)
end

-- A vertical Slider on the right of the scroll frame. The Slider does the
-- dragging; its thumb is an invisible hit area and the visible bar is a thin
-- capsule drawn from two half circles (or squares) and a rect.
-- The thumb stays small (THUMB_MIN..THUMB_MAX): the engine Slider does not
-- keep the grab point on a thumb that fills most of the bar, so dragging a
-- near-full thumb jumped the wrong way. Blizzard's Slider bars use small thumbs too.
local THUMB_MIN, THUMB_MAX = 20, 40
local function attachScrollBar(sf, parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(8)
    bar:SetOrientation("VERTICAL")
    bar:EnableMouse(true)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0, 0, 0, 0)
    thumb:SetSize(8, 24)
    bar:SetThumbTexture(thumb)
    bar.top = W.Round(bar, "OVERLAY", "capTop")
    bar.top:SetPoint("TOP", thumb, "TOP")
    bar.bottom = W.Round(bar, "OVERLAY", "capBottom")
    bar.bottom:SetPoint("BOTTOM", thumb, "BOTTOM")
    bar.mid = W.Rect(bar, "OVERLAY", 1, 1, 1, 1)
    bar.mid:SetPoint("TOP", bar.top, "BOTTOM")
    bar.mid:SetPoint("BOTTOM", bar.bottom, "TOP")
    paintScrollBar(bar)

    local function update()
        local range = sf:GetVerticalScrollRange() or 0
        local cur = sf:GetVerticalScroll()
        if cur > range then
            sf:SetVerticalScroll(range)
            cur = range
        end
        bar:SetShown(range > 0.5)
        local h = bar:GetHeight()
        if h > 0 then
            thumb:SetHeight(math.max(THUMB_MIN, math.min(THUMB_MAX, math.floor(h * h / (h + range)))))
        end
        bar:SetMinMaxValues(0, range)
        bar:SetValue(cur)
    end
    local function wheel(_, delta)
        local range = sf:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        sf:SetVerticalScroll(math.max(0, math.min(range, sf:GetVerticalScroll() - delta * WHEEL_STEP)))
    end

    sf:HookScript("OnScrollRangeChanged", update)
    sf:HookScript("OnVerticalScroll", function(_, offset) bar:SetValue(offset) end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", wheel)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", wheel)
    bar:SetScript("OnSizeChanged", update)
    bar:SetScript("OnValueChanged", function(_, v, user)
        if user then sf:SetVerticalScroll(v) end
    end)
    bar:SetScript("OnEnter", function(self) self.hover = true paintScrollBar(self) end)
    bar:SetScript("OnLeave", function(self) self.hover = false paintScrollBar(self) end)
    bar:SetScript("OnMouseDown", function(self) self.dragging = true paintScrollBar(self) end)
    bar:SetScript("OnMouseUp", function(self) self.dragging = false paintScrollBar(self) end)
    bar:Hide()
    return bar
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
        sf:SetPoint("BOTTOMRIGHT", -14, 7)
        local bar = attachScrollBar(sf, holder)
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, 0)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 0)
        eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetWidth(100)
        sf:SetScrollChild(eb)
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
-- Scroll area
---------------------------------------------------------------------------
function W.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local bar = attachScrollBar(sf, parent)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 2, -2)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 2)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
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
    local thumb = W.Round(s, "OVERLAY", "knob")
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
-- Menus. The generator fills a description with the part of the Blizzard_Menu
-- builder API the addon uses: CreateTitle, CreateDivider, CreateButton,
-- CreateRadio and SetEnabled. A button that gets children is a submenu.
-- Frames are built on first use; GLOBAL_MOUSE_DOWN is registered only while
-- a menu is open, to close it on a click outside.
---------------------------------------------------------------------------
local Desc = {}
Desc.__index = Desc

local function newDesc(kind, text)
    return setmetatable({ kind = kind, text = text, enabled = true }, Desc)
end

local function addChild(parent, d)
    local list = parent.children
    if not list then
        list = {}
        parent.children = list
    end
    list[#list + 1] = d
    return d
end

function Desc:CreateTitle(text) return addChild(self, newDesc("title", text)) end
function Desc:CreateDivider() return addChild(self, newDesc("divider")) end
function Desc:CreateButton(text, fn)
    local d = addChild(self, newDesc("button", text))
    d.fn = fn
    return d
end
function Desc:CreateRadio(text, isSelected, setSelected)
    local d = addChild(self, newDesc("radio", text))
    d.isSelected = isSelected
    d.fn = setSelected
    return d
end
function Desc:SetEnabled(on) self.enabled = on and true or false end

local MENU_PAD, ROW_H, TITLE_H, DIV_H = 4, 24, 22, 9
local menu, menuOwner, menuToggle
local levels = {}
local openLevel

-- Uppercase for titles, keeping |c and |r escapes intact.
local function upper(s)
    return (strupper(s or ""):gsub("|C(%x%x%x%x%x%x%x%x)", "|c%1"):gsub("|R", "|r"))
end

function W.CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

local function hideLevelsFrom(depth)
    for i = depth, #levels do
        local f = levels[i]
        if f:IsShown() then
            f:Hide()
            if f.anchor then f.anchor.bg:Hide() end
        end
    end
end

local function rowEnter(row)
    local d = row.desc
    hideLevelsFrom(row.depth + 1)
    if not d.enabled then return end
    row.bg:Show()
    if d.children then openLevel(row.depth + 1, d, row) end
end

local function rowLeave(row)
    -- keep the path to an open submenu highlighted
    local sub = levels[row.depth + 1]
    if sub and sub:IsShown() and sub.anchor == row then return end
    row.bg:Hide()
end

local function rowClick(row)
    local d = row.desc
    if not d.enabled or d.children then return end
    W.CloseMenu()
    if d.fn then d.fn() end
end

local function levelRow(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, f)
    row.depth = f.depth
    row.bg = W.Round(row, "BACKGROUND", "round", T.Color("panel3"))
    row.bg:SetAllPoints()
    row.bg:Hide()
    row.check = W.Icon(row, "check", 11)
    row.check:SetPoint("LEFT", 10, 0)
    row.label = W.Text(row, 12.5, "regular", "text")
    row.chev = W.Icon(row, "chevron", 9, T.Color("muted"))
    row.chev:SetPoint("RIGHT", -8, 0)
    row.line = W.Rect(row, "ARTWORK", T.Color("line"))
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", 2, 0)
    row.line:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", rowLeave)
    row:SetScript("OnClick", rowClick)
    f.rows[i] = row
    return row
end

local function newLevel(depth)
    local f = CreateFrame("Frame", nil, menu)
    f.depth = depth
    f.rows = {}
    f:SetFrameLevel(menu:GetFrameLevel() + depth * 20)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local shadow = W.Round(f, "BACKGROUND", "round", 0, 0, 0, 0.45, -8)
    shadow:SetPoint("TOPLEFT", -4, 2)
    shadow:SetPoint("BOTTOMRIGHT", 4, -6)
    W.Skin(f, "panel2", "line2")
    f:Hide()
    levels[depth] = f
    return f
end

-- Lays out desc.children in level `depth`. Submenus open beside `anchor`.
function openLevel(depth, desc, anchor, minWidth)
    local f = levels[depth] or newLevel(depth)
    local items = desc.children
    local textX = 10
    for _, d in ipairs(items) do
        if d.kind == "radio" then
            textX = 29
            break
        end
    end
    local y, w = MENU_PAD, 0
    for i, d in ipairs(items) do
        local row = levelRow(f, i)
        row.desc = d
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", MENU_PAD, -y)
        row:SetPoint("TOPRIGHT", -MENU_PAD, -y)
        row:SetAlpha(1)
        row.bg:Hide()
        row.check:Hide()
        row.chev:Hide()
        row.line:Hide()
        row.label:ClearAllPoints()
        local h
        if d.kind == "divider" then
            h = DIV_H
            row.label:SetText("")
            row.line:Show()
            row:EnableMouse(false)
        elseif d.kind == "title" then
            h = TITLE_H
            W.SetFont(row.label, 10.5, "bold")
            row.label:SetTextColor(T.Color("dim"))
            row.label:SetText(upper(d.text))
            row.label:SetPoint("BOTTOMLEFT", 10, 4)
            w = math.max(w, row.label:GetUnboundedStringWidth() + 20)
            row:EnableMouse(false)
        else
            h = ROW_H
            W.SetFont(row.label, 12.5, "regular")
            row.label:SetTextColor(T.Color("text"))
            row.label:SetText(d.text or "")
            row.label:SetPoint("LEFT", textX, 0)
            if d.kind == "radio" and d.isSelected and d.isSelected() then
                row.check:SetVertexColor(T.Accent())
                row.check:Show()
            end
            if d.children then row.chev:Show() end
            row:SetAlpha(d.enabled and 1 or 0.4)
            w = math.max(w, textX + row.label:GetUnboundedStringWidth() + (d.children and 28 or 12))
            row:EnableMouse(true)
        end
        row:SetHeight(h)
        row:Show()
        y = y + h
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    f:SetSize(math.floor(math.max(minWidth or 120, w + MENU_PAD * 2) + 0.5), y + MENU_PAD)
    f.anchor = anchor
    if anchor then
        f:ClearAllPoints()
        local s = f:GetEffectiveScale()
        if (anchor:GetRight() + MENU_PAD + 2 + f:GetWidth()) * s > UIParent:GetRight() * UIParent:GetEffectiveScale() then
            f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -MENU_PAD - 2, MENU_PAD)
        else
            f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", MENU_PAD + 2, MENU_PAD)
        end
    end
    f:Show()
    return f
end

local function onGlobalMouseDown()
    for i = 1, #levels do
        if levels[i]:IsShown() and levels[i]:IsMouseOver() then return end
    end
    -- a dropdown's own button toggles it on click
    if menuToggle and menuOwner and menuOwner:IsMouseOver() then return end
    W.CloseMenu()
end

local function buildMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    W.AddShapeRoot(menu)
    menu:SetAllPoints(UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    menu:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            W.CloseMenu()
        end
    end)
    menu:SetScript("OnHide", function()
        hideLevelsFrom(1)
        menuOwner, menuToggle = nil, nil
        ns.UnregisterEvent(W, "GLOBAL_MOUSE_DOWN")
    end)
end

local function openMenu(owner, generator, dropdown)
    if menu and menu:IsShown() then
        local same = menuOwner == owner
        W.CloseMenu()
        if same and dropdown then return end
    end
    local root = newDesc("root")
    generator(owner, root)
    W.menuRoot = root
    if not root.children then return end
    if not menu then buildMenu() end
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    -- Escape closes the menu; keyboard propagation cannot be changed in combat
    if InCombatLockdown() then
        menu:EnableKeyboard(false)
    else
        menu:EnableKeyboard(true)
        menu:SetPropagateKeyboardInput(true)
    end
    menuOwner, menuToggle = owner, dropdown
    menu:Show()
    local f = openLevel(1, root, nil, dropdown and math.max(160, owner:GetWidth()) or 180)
    f:ClearAllPoints()
    if dropdown then
        f:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local s = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 2, y / s - 2)
    end
    ns.RegisterEvent(W, "GLOBAL_MOUSE_DOWN", onGlobalMouseDown)
end

-- Context menu at the cursor.
function W.Menu(owner, generator)
    openMenu(owner, generator, false)
end

-- Dropdown below its button; clicking the button again closes it.
function W.Dropdown(owner, generator)
    openMenu(owner, generator, true)
end

-- "2d ago" style
function W.Ago(t)
    if not t then return "" end
    local d = math.floor((time() - t) / 86400)
    if d <= 0 then return "today" end
    if d == 1 then return "yesterday" end
    return d .. "d ago"
end
