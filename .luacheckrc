-- Lint config for VocSpeak (Forever client, Lua 5.1). read_globals is
-- the allowlist of WoW API verified against the Forever build in
-- `## Interface:`; lint fails on any other global on purpose: add a
-- name here only after confirming it exists, under that namespace, in
-- the Forever build. Never from a wiki.
std = "lua51"
max_line_length = false
self = false
unused_args = false

-- Globals this addon owns: the SavedVariable, slash registration,
-- and the addon compartment entry points named in the .toc.
globals = {
  "VocSpeakDB",
  "SLASH_VOCSPEAK1", "SLASH_VOCSPEAK2",
  "SlashCmdList",
  "VocSpeak_CompartmentClick", "VocSpeak_CompartmentEnter", "VocSpeak_CompartmentLeave",
}

-- WoW API and UI globals read by the addon. Every entry is
-- presence-gated at the call site; a missing API is never an error.
read_globals = {
  "C_ChatInfo",
  "CreateFrame",
  "CreateSettingsListSectionHeaderInitializer",
  "GameTooltip",
  "PlaySound", "SOUNDKIT",
  "Settings", "SettingsPanel", "UnitRace",
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
  read_globals = { "os" },
}
