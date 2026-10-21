-- The add-on runs on the game's Lua 5.1.
std = "lua51"
max_line_length = 110
exclude_files = { ".luarocks", "lua_modules" }

-- Globals the add-on creates: its saved data and its slash command.
globals = { "BureaucracyForeverDB", "SLASH_BUREAUCRACYFOREVER1", "SlashCmdList" }

-- Game functions the add-on calls. Add each new one here as it's first used.
read_globals = {
  "C_AddOns", "C_ChatInfo", "C_Timer", "CreateFrame", "GetAddOnMetadata",
  "GetLootSlotInfo", "GetLootSlotLink", "GetLootSourceInfo", "GetLootThreshold",
  "GetMasterLootCandidate", "GetNumLootItems", "GiveMasterLoot", "LoggingChat",
  "SendChatMessage", "UnitName", "strtrim", "date", "time", "GetTime",
  "UIParent", "Minimap", "GameTooltip", "UISpecialFrames", "GetCursorPosition", "GetInstanceInfo",
  "GetItemInfo", "IsInRaid", "GetNumGroupMembers", "GetRaidRosterInfo", "ItemRefTooltip",
  "TooltipDataProcessor", "Enum", "C_PartyInfo", "C_RestrictedActions",
  -- The desktop helper's inbox (Inbox.lua), read at load.
  "BureaucracyLootInbox",
}

files["spec"] = { std = "+busted" }
-- The stand-in plays the game, so it sets the game's globals.
files["spec/support/wow.lua"] = { globals = { "_G" } }
