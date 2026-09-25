-- Minimap button via LibDataBroker + LibDBIcon. Nothing is created while the
-- button is hidden.
local _, ns = ...

local T = ns.T

local Minimap = {}
ns.UI.Minimap = Minimap

local NAME = "FastGroups"
local object, registered

local function ensure()
    if registered then return true end
    local LDB = LibStub("LibDataBroker-1.1", true)
    local Icon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not Icon then return false end
    object = LDB:NewDataObject(NAME, {
        type = "launcher",
        text = NAME,
        icon = T.ICON .. "logo",
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.Show("options")
            else
                ns.Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("FastGroups")
            tt:AddLine("Left-click: group board", 1, 1, 1)
            tt:AddLine("Right-click: options", 1, 1, 1)
        end,
    })
    T.OnAccent(function(r, g, b)
        object.iconR, object.iconG, object.iconB = r, g, b
    end)
    Icon:Register(NAME, object, ns.settings.minimap)
    registered = true
    return true
end

function Minimap.Update()
    local Icon = LibStub("LibDBIcon-1.0", true)
    if ns.settings.minimap.hide then
        if registered and Icon then Icon:Hide(NAME) end
    elseif ensure() then
        Icon:Show(NAME)
    end
end

ns.On("LOGIN", Minimap, function() Minimap.Update() end)
