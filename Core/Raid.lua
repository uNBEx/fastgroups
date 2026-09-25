-- Snapshot of the real raid roster. Only refreshed while the window is open
-- or an apply is running.
local _, ns = ...

local Players = ns.Players

local Raid = {
    members = {},   -- key -> { index, group, rank, online, class, role, unit }
    count = 0,
}
ns.Raid = Raid

local MYTHIC = 16

function Raid:Refresh()
    local members = self.members
    for _, m in pairs(members) do m.present = false end
    local n = 0
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS or 40 do
            local name, rank, subgroup, _, _, classFile, _, online, _, _, _, combatRole = GetRaidRosterInfo(i)
            if name then
                local key = Players.Key(name)
                local m = members[key]
                if not m then
                    m = {}
                    members[key] = m
                end
                local unit = "raid" .. i
                m.present = true
                m.index = i
                m.group = subgroup
                m.rank = rank
                m.online = online
                m.class = classFile
                m.unit = unit
                local role = UnitGroupRolesAssigned(unit)
                if role == "NONE" or not role then role = combatRole end
                m.role = role
                n = n + 1
                Players.Seen(key, classFile)
                if UnitIsUnit(unit, "player") then
                    self:UpdateOwnSpec(key)
                end
            end
        end
    end
    for key, m in pairs(members) do
        if not m.present then members[key] = nil end
    end
    self.count = n
end

function Raid:UpdateOwnSpec(key)
    local index = C_SpecializationInfo.GetSpecialization()
    if index and index > 0 then
        local specID = C_SpecializationInfo.GetSpecializationInfo(index)
        if specID then Players.SetSpec(key, specID) end
    end
end

function Raid:IsMythic()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" then
        return difficultyID == MYTHIC
    end
    return GetRaidDifficultyID() == MYTHIC
end

function Raid:CanManage()
    return IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and true or false
end

function Raid:MyRank()
    if not IsInRaid() then return nil end
    if UnitIsGroupLeader("player") then return "leader" end
    if UnitIsGroupAssistant("player") then return "assist" end
    return "member"
end

function Raid:DifficultyName()
    local name, instanceType = GetInstanceInfo()
    local _, _, difficultyID = GetInstanceInfo()
    if instanceType ~= "raid" then
        difficultyID = GetRaidDifficultyID()
    end
    local dname = difficultyID and GetDifficultyInfo(difficultyID)
    return dname, name
end
