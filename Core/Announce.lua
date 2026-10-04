-- Raid chat announcements: who in the shared group goes to which half, and
-- optionally which groups make up each half. Sent after Apply when enabled,
-- or from the toolbar button. Also the whispers to players a later
-- Auto-split had to send to the other half.
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
    if board:IsSimple() then return false end
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
    if board:IsSimple() then return lines end
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

-- More whispers than this at once means a reshuffle, not a forced move;
-- the raid announcement covers that.
local WHISPER_CAP = 3

local whisperList = {}

-- Settled players a normal Auto-split sent to the other half, now that the
-- board has them there: array of { key, group, side }. Empty when there are
-- more than WHISPER_CAP; the second return is how many there were.
function Announce.Whispers(board)
    board = board or ns.Board
    wipe(whisperList)
    local live = board:Live()
    if not live then return whisperList, 0 end
    local me = Players.Key(UnitName("player"))
    for key, was in pairs(board.flipped) do
        local m = live[key]
        local now = board:PlayerSide(key)
        if m and m.online and key ~= me and now and now ~= was then
            tinsert(whisperList, { key = key, group = board.draft[key], side = now })
        end
    end
    local n = #whisperList
    if n > WHISPER_CAP then
        wipe(whisperList)
    else
        table.sort(whisperList, function(a, b) return a.key < b.key end)
    end
    return whisperList, n
end

function Announce.WhisperText(w)
    return "Your group has changed to " .. w.group .. " (" .. clean(ns.settings.halfNames[w.side]) .. ")."
end

-- Whisper the players a forced move sent across, once.
function Announce.SendWhispers()
    local board = ns.Board
    if not next(board.flipped) then return end
    if not ns.settings.whisperSwitches then
        wipe(board.flipped)
        return
    end
    local list, n = Announce.Whispers(board)
    wipe(board.flipped)
    if n == 0 then return end
    if #list == 0 then
        ns.Print(n .. " players switched halves; no whispers sent.")
        return
    end
    local demo = board.source == "demo"
    if not demo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        ns.Print("Chat is locked during encounters; no whispers sent.")
        return
    end
    for _, w in ipairs(list) do
        local msg = Announce.WhisperText(w)
        if demo then
            ns.Print("Demo, not sent: whisper to " .. Players.ShortName(w.key) .. ": " .. msg)
        else
            C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, w.key)
        end
    end
end

-- After a successful Apply: the raid line, then the whispers.
ns.On("APPLY_STATE", Announce, function(_, ok)
    if not ok then return end
    if ns.settings.announceOnApply then
        local sent, reason = Announce.Send()
        if not sent and reason ~= "empty" then ns.Print(reason) end
    end
    Announce.SendWhispers()
end)
