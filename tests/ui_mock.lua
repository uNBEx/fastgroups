-- A permissive mock of WoW's frame API: enough for the UI files to build and
-- lay out under plain Lua, so typos and nil errors show up without the game.
local stub = require("wow_stub")

local M = { objects = {} }

local Obj = {}
local noop = function() end

-- Unknown CamelCase keys are widget methods (no-ops); anything else is a
-- plain field and nil, like on real frames.
Obj.__index = function(_, k)
    local v = rawget(Obj, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:find("^%u") then return noop end
    return nil
end

local function new(kind, parent)
    local o = setmetatable({
        _kind = kind, _parent = parent, _shown = true, _w = 0, _h = 0,
        scripts = {}, events = {}, _text = "", _points = 0, _value = 0,
    }, Obj)
    table.insert(M.objects, o)
    table.insert(stub.frames, o)
    if parent then
        parent._kids = parent._kids or {}
        table.insert(parent._kids, o)
    end
    return o
end
M.new = new

function Obj:GetObjectType() return self._kind end
function Obj:SetWidth(w) self._w = w end
function Obj:SetHeight(h) self._h = h end
function Obj:SetSize(w, h) self._w, self._h = w, h end
function Obj:GetWidth()
    if self._w and self._w > 0 then return self._w end
    if self._parent then return self._parent:GetWidth() end
    return 800
end
function Obj:GetHeight() return (self._h and self._h > 0) and self._h or 20 end
function Obj:GetSize() return self:GetWidth(), self:GetHeight() end
function Obj:Show() self._shown = true end
function Obj:Hide()
    local was = self._shown
    self._shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return self._shown end
function Obj:IsVisible()
    if not self._shown then return false end
    if self._parent then return self._parent:IsVisible() end
    return true
end
function Obj:SetScript(name, fn) self.scripts[name] = fn end
function Obj:GetScript(name) return self.scripts[name] end
function Obj:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Obj:SetText(t) self._text = t == nil and "" or tostring(t) end
function Obj:GetText() return self._text end
function Obj:GetStringWidth() return #(self._text or "") * 6 end
Obj.GetUnboundedStringWidth = Obj.GetStringWidth
function Obj:GetStringHeight() return 14 end
function Obj:CreateTexture() return new("Texture", self) end
function Obj:CreateFontString() return new("FontString", self) end
function Obj:GetParent() return self._parent end
function Obj:SetParent(p)
    self._parent = p
    if p then
        p._kids = p._kids or {}
        table.insert(p._kids, self)
    end
end
local REGION = { Texture = true, FontString = true }
local function kids(self, regions)
    local out, seen = {}, {}
    for _, o in ipairs(self._kids or {}) do
        if o._parent == self and not seen[o] and (REGION[o._kind] or false) == regions then
            seen[o] = true
            out[#out + 1] = o
        end
    end
    return unpack(out)
end
function Obj:GetChildren() return kids(self, false) end
function Obj:GetRegions() return kids(self, true) end
function Obj:GetFrameLevel() return 1 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetScale() return 1 end
function Obj:GetLeft() return 100 end
function Obj:GetRight() return 100 + self:GetWidth() end
function Obj:GetTop() return 500 end
function Obj:GetBottom() return 500 - self:GetHeight() end
function Obj:IsMouseOver() return self._mouseOver or false end
function Obj:HasFocus() return false end
function Obj:GetVerticalScroll() return 0 end
function Obj:GetVerticalScrollRange() return 0 end
function Obj:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Obj:SetPoint() self._points = self._points + 1 end
function Obj:ClearAllPoints() self._points = 0 end
function Obj:GetNumPoints() return self._points end
function Obj:SetValue(v) self._value = v end
function Obj:GetValue() return self._value end
function Obj:RegisterEvent(e) self.events[e] = true end
function Obj:UnregisterEvent(e) self.events[e] = nil end
function Obj:IsEventRegistered(e) return self.events[e] or false end
function Obj:GetAlpha() return 1 end
function Obj:GetTexture() return self._tex end
function Obj:SetTexture(t) self._tex = t end

function CreateFrame(kind, name, parent)
    local o = new(kind, parent)
    if name then _G[name] = o end
    return o
end

UIParent = new("Frame")
GameTooltip = new("GameTooltip")
ColorPickerFrame = new("Frame")
function ColorPickerFrame:GetColorRGB() return 1, 0, 0 end
function ColorPickerFrame:GetPreviousValues() return 0, 1, 0 end
UISpecialFrames = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function GetLocale() return "enUS" end
function GetClassAtlas(c) return "classicon-" .. c end
function GetDifficultyInfo(id) return "Difficulty " .. tostring(id) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function SetRaidSubgroup(i, g) stub.lastSet = { i, g } end
function SwapRaidSubgroup(a, b) stub.lastSwap = { a, b } end
C_GuildInfo = { GuildRoster = noop }
Enum.UITextureSliceMode = { Stretched = 0, Tiled = 1 }
function GetCursorPosition() return 400, 300 end
function SetCursor() end

-- Libraries (minimap)
local fakeLDB = { NewDataObject = function(_, _, obj) return obj end }
local fakeIcon = { Register = noop, Show = noop, Hide = noop }
function LibStub(name)
    if name == "LibDataBroker-1.1" then return fakeLDB end
    if name == "LibDBIcon-1.0" then return fakeIcon end
end

return M
