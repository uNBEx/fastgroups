std = "lua51"
max_line_length = false
codes = true
exclude_files = { "Libs/", "resources/", ".luarocks/" }
ignore = {
    "212/self",   -- unused self in methods
    "432/self",   -- nested methods shadow self
    "211/_.*",    -- unused locals named with an underscore
    "212/_.*",
    "213/_.*",
}

-- globals this addon defines or writes into
globals = {
    "FastGroupsDB",
    "SLASH_FASTGROUPS1", "SLASH_FASTGROUPS2",
    "FastGroups_OnAddonCompartmentClick", "FastGroups_OnAddonCompartmentEnter", "FastGroups_OnAddonCompartmentLeave",
    "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames",
}

-- WoW API used by the addon (verified against Gethe/wow-ui-source, live 12.1)
read_globals = {
    "ACCEPT", "DECLINE", "DEFAULT_CHAT_FRAME", "LOCALIZED_CLASS_NAMES_MALE", "MAX_RAID_MEMBERS",
    "RAID_CLASS_COLORS", "STANDARD_TEXT_FONT", "Enum",
    "C_AddOns", "C_ChatInfo", "C_EncodingUtil", "C_GuildInfo", "C_SpecializationInfo", "C_Timer",
    "CanInspect", "ClearInspectPlayer", "ColorPickerFrame", "CreateColor", "CreateFrame",
    "GameTooltip", "GetClassAtlas", "GetDifficultyInfo", "GetGuildRosterInfo", "GetInstanceInfo",
    "GetLocale", "GetNormalizedRealmName", "GetNumGuildMembers", "GetRaidDifficultyID", "GetRaidRosterInfo",
    "GetRealmName", "GetSpecializationInfoByID", "InCombatLockdown", "InspectFrame", "IsInGuild", "IsInRaid",
    "LibStub", "MenuUtil", "NotifyInspect", "ScrollUtil", "SetRaidSubgroup", "StaticPopup_Show",
    "SwapRaidSubgroup", "UIParent", "UnitAffectingCombat", "UnitGUID", "UnitGroupRolesAssigned",
    "UnitIsConnected", "UnitIsGroupAssistant", "UnitIsGroupLeader", "UnitIsUnit", "UnitIsVisible", "UnitName",
    "strlower", "strtrim", "strupper", "time", "tinsert", "tremove", "wipe",
}

files["tests/"] = { std = "+lua51", globals = { "*" }, ignore = { "1", "2", "4", "5" } }
