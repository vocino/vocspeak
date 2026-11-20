-- Lint config for VocSpeak (Forever + retail, Lua 5.1). read_globals is
-- the allowlist of WoW API verified against both branches in
-- `## Interface:` (Blizzard_APIDocumentationGenerated for live and
-- forever, see .reference/api-verification.md); lint fails on any
-- other global on purpose: add a name here only after confirming it
-- exists, under that namespace, in both builds. Never from a wiki.
std = "lua51"
max_line_length = false
self = false
unused_args = false
exclude_files = { ".reference/**" }

-- Globals this addon owns: the SavedVariable, slash registration,
-- and the addon compartment entry points named in the .toc.
globals = {
  "VocSpeakDB",
  "SLASH_VOCSPEAK1", "SLASH_VOCSPEAK2",
  "SlashCmdList",
}

-- WoW API and UI globals read by the addon. Every entry is
-- presence-gated at the call site; a missing API is never an error.
read_globals = {
  "C_AddOns", -- GetAddOnInterfaceVersion: own-toc flavor fallback in Compat.lua (live + forever)
  "C_ChatInfo", -- SendChatMessage: the send wrapper (live + forever)
  "CreateFrame",
  "CreateSettingsListSectionHeaderInitializer",
  "GetBuildInfo", -- Interface fallback in Compat.lua, never for version sniffing
  "InCombatLockdown", -- combat gate for the panel (live + forever)
  "PlaySound", "SOUNDKIT",
  "Settings", "SettingsPanel", "UnitGUID", "UnitRace",
  "WOW_PROJECT_CAMELOT", "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", -- flavor identity, read only in Compat.lua
  "canaccessvalue", -- secret guard (live + forever)
}

-- The send wrapper writes C_ChatInfo.SendChatMessage; the write is the
-- hook itself, installed only while the filter runs and restored on
-- disable.
files["main.lua"] = {
  globals = { "C_ChatInfo" },
}

-- Tests install stubs onto _G by design.
files["tests/**"] = {
  std = "max",
  globals = { "print", "_G" },
  read_globals = { "os", "setfenv", "loadstring", "unpack" },
}
