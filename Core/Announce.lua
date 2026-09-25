-- Raid chat announcements: who in the shared group goes to which half, and
-- optionally which groups make up each half. Sent after Apply when enabled,
-- or from the toolbar button.
local _, ns = ...

local Players = ns.Players

local Announce = {}
ns.Announce = Announce

-- "|" starts an escape sequence in chat; keep it out of user-set half names.
local function clean(s)
    return (tostring(s):gsub("|", ""))
end

local function groupList(list)
    return (#list == 1 and "group " or "groups ") .. table.concat(list, ", ")
end

-- Is there anything to announce? Cheap; used to show the button.
function Announce.Has(board)
    board = board or ns.Board
    if ns.settings.announceWhat == "all" then return true end
    local shared = board:Shared()
    return shared ~= nil and board:Occupancy(shared) > 0
end

local sideKeys = { L = {}, R = {} }

-- The chat lines for the board; an empty table when there is nothing to say.
function Announce.Lines(board)
    board = board or ns.Board
    local s = ns.settings
    local nameL, nameR = clean(s.halfNames.L), clean(s.halfNames.R)
    local lines = {}
    if s.announceWhat == "all" then
        local L, R = board:Halves()
        if #L > 0 or #R > 0 then
            tinsert(lines, "Halves - " .. nameL .. ": " .. groupList(L) .. "; " .. nameR .. ": " .. groupList(R))
        end
    end
    local shared = board:Shared()
    if shared then
        wipe(sideKeys.L)
        wipe(sideKeys.R)
        for _, key in ipairs(board.members) do
            local side = board.draft[key] == shared and board.sides[key]
            if side then tinsert(sideKeys[side], key) end
        end
        local parts = {}
        for _, side in ipairs({ "L", "R" }) do
            local list = board.SortKeys(sideKeys[side])
            if #list > 0 then
                local names = {}
                for i, key in ipairs(list) do names[i] = Players.ShortName(key) end
                tinsert(parts, (side == "L" and nameL or nameR) .. ": " .. table.concat(names, ", "))
            end
        end
        if #parts > 0 then
            tinsert(lines, "Group " .. shared .. " is split - " .. table.concat(parts, "; "))
        end
    end
    return lines
end

-- Post the lines to raid chat (the demo prints them locally). Returns ok,
-- reason; reason "empty" means there was nothing to announce.
function Announce.Send()
    local board = ns.Board
    local lines = Announce.Lines(board)
    if #lines == 0 then return false, "empty" end
    if board.source == "demo" then
        for _, line in ipairs(lines) do ns.Print("Demo, not sent: " .. line) end
        return true
    end
    if board.source ~= "live" or not IsInRaid() then
        return false, "Announcements go to raid chat; you are not in a raid."
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "Chat is locked during encounters. Announce after the pull."
    end
    for _, line in ipairs(lines) do C_ChatInfo.SendChatMessage(line, "RAID") end
    return true
end

-- After a successful Apply.
ns.On("APPLY_STATE", Announce, function(_, ok)
    if not ok or not ns.settings.announceOnApply then return end
    local sent, reason = Announce.Send()
    if not sent and reason ~= "empty" then ns.Print(reason) end
end)
