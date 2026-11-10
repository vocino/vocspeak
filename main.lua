local name, ns = ...

-- VocSpeak: roleplay speaking for Forever and Midnight (retail).
-- Outgoing /say and /yell pass through a wrapper on the documented
-- send call (C_ChatInfo.SendChatMessage, documented identically on
-- the live and forever branches: the edit box calls it directly),
-- which rewrites the line in a dwarven or troll dialect before it
-- crosses. Emotes never change, and a (( prefix marks
-- out-of-character and stays as typed.

VocSpeakDB = VocSpeakDB or {}
ns.db = VocSpeakDB

-- Client flavor. The client loads exactly one of our tocs (the 1.x
-- VocSpeak_Camelot.toc on Forever, the 12.x VocSpeak.toc on
-- retail), so reading our own loaded Interface version back is
-- literally asking what we're loaded into. Below 20000 is our
-- classic-lineage toc; anything else keeps retail behavior, which is
-- today's behavior everywhere, including flavors we ship no toc for
-- (those clients fall back to the plain toc). A missing API falls
-- back to retail, never an error. C_AddOns.GetAddOnInterfaceVersion
-- is documented on the live and forever branches.
function ns.clientFlavor()
  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnInterfaceVersion) == "function" then
    local ok, v = pcall(C_AddOns.GetAddOnInterfaceVersion, name)
    if ok and type(v) == "number" and v < 20000 then
      return "forever"
    end
  end
  return "retail"
end

-- Secret values (Midnight): a refused read errors on compare and
-- arithmetic in addon code. canaccessvalue gates every such read
-- before it is touched; a missing API means no secrets exist there.
function ns.isSecret(v)
  if type(canaccessvalue) == "function" then
    local ok, accessible = pcall(canaccessvalue, v)
    if ok and accessible == false then
      return true
    end
  end
  return false
end

-- Busy window: combat lockdown. A missing API never reads as busy.
function ns.inCombat()
  if type(InCombatLockdown) == "function" then
    local ok, locked = pcall(InCombatLockdown)
    if ok and locked then
      return true
    end
  end
  return false
end

-- Chat voice shared by every Voc addon: one line, the addon name as
-- a colored prefix, then the message. A chat line is a fact or a
-- next step, never a greeting, and never ends in a period.
ns.PREFIX_COLOR = "ff66ccff"
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end

-- Confirmation sounds shared by every Voc addon: SOUNDKIT names
-- first, the numeric IDs behind them so a Blizzard rename never
-- silences the polish. Presence-gated: no sound API, no sound, never
-- an error.
ns.SOUNDS = {
  on = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  off = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
  open = { "IG_MAINMENU_OPEN", 850 },
  close = { "IG_MAINMENU_CLOSE", 851 },
}
function ns.play(kind)
  local s = ns.SOUNDS[kind]
  if not s or type(PlaySound) ~= "function" then
    return
  end
  local id = type(SOUNDKIT) == "table" and SOUNDKIT[s[1]] or nil
  pcall(PlaySound, type(id) == "number" and id or s[2])
end

-- Palette, defined once. The addon paints only its compartment
-- tooltip, so only the text tokens are ever read; nothing writes a
-- color at a call site.
ns.COLORS = {
  gold = { 1, 0.82, 0 },
  text = { 1, 1, 1 },
  muted = { 0.5, 0.5, 0.5 },
  red = { 0.9, 0.3, 0.25 },
  green = { 0.25, 0.9, 0.35 },
}

-- Defaults are the product: speaking dwarven at chance 8, the 2007
-- landing state, one slash away from troll or silence. An unknown
-- hand-edited dialect reads as silence downstream, never an error.
ns.defaults = {
  enabled = true,
  dialect = "dwarf",
  chance = 8,
  say = true,
  yell = true,
}

-- The live state table: VocSpeakDB and nowhere else. Missing keys
-- fill from defaults; a key holding the wrong type resets (a
-- hand-edited SavedVariable never misbehaves). Unknown keys are left
-- alone for forward compatibility.
function ns.opts()
  if type(ns.db) ~= "table" then
    ns.db = {}
    VocSpeakDB = ns.db
  end
  for k, v in pairs(ns.defaults) do
    if type(ns.db[k]) ~= type(v) then
      ns.db[k] = v
    end
  end
  return ns.db
end

local speak = {}
ns.speak = speak

-- Declarative option rows for the settings page (settings are data).
-- The toggle installs or removes the send wrapper; dialect, chance,
-- and channels read live at send time, so only the toggle needs a
-- row callback.
speak.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Speak in dialect",
    tooltip = "Rewrite outgoing chat in the chosen dialect before it sends",
  },
  {
    kind = "header",
    label = "Dialect",
  },
  {
    key = "dialect",
    kind = "dropdown",
    label = "Dialect",
    tooltip = "Which voice rewrites outgoing chat",
    choices = {
      { value = "dwarf", label = "Dwarven", tooltip = "Rewrite outgoing chat like a dwarf" },
      { value = "troll", label = "Troll", tooltip = "Rewrite outgoing chat like a troll" },
    },
  },
  {
    key = "chance",
    kind = "slider",
    label = "How often",
    tooltip = "How often the dialect rewrites words, from 0 (never) to 10 (always)",
    min = 0,
    max = 10,
    step = 1,
  },
  {
    kind = "header",
    label = "Channels",
  },
  {
    key = "say",
    kind = "checkbox",
    label = "Say",
    tooltip = "Rewrite /say chat",
  },
  {
    key = "yell",
    kind = "checkbox",
    label = "Yell",
    tooltip = "Rewrite /yell chat",
  },
}

-- Validity predicate. The whole job is one wrapper around the
-- documented send call; without it nothing here can act, so the
-- wrapper is never installed and the panel never builds.
function speak.IsAvailable()
  return type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function"
end

-- Whether one outgoing message changes. The toggle, a known dialect,
-- and a nonzero chance gate everything; emotes never change. Only
-- /say and /yell reach the engine; every other type passes through
-- untouched. A (( prefix marks out-of-character and stays as typed.
function speak.MangleForSend(message, chatType, target)
  -- Secret values (Midnight) fail open to the untouched line, never
  -- an error and never a mangled secret.
  if ns.isSecret(message) or ns.isSecret(chatType) or ns.isSecret(target) then
    return message
  end
  if message == nil then
    message = ""
  end
  if type(message) ~= "string" then
    return message
  end
  local o = ns.opts()
  if not o.enabled then
    return message
  end
  if o.dialect ~= "dwarf" and o.dialect ~= "troll" then
    return message
  end
  if (o.chance or 0) <= 0 then
    return message
  end
  local kind = "SAY"
  if type(chatType) == "string" and chatType ~= "" then
    kind = chatType:upper()
  end
  if kind == "EMOTE" then
    return message
  end
  if kind ~= "SAY" and kind ~= "YELL" then
    return message
  end
  if o[string.lower(kind)] ~= true then
    return message
  end
  if message:find("^%(%(") then
    return message
  end
  return speak.Mangle(message, speak.DICTIONARIES[o.dialect], o.chance)
end

-- The send wrapper: one gate, then the saved call with its original
-- arguments, so types, languages, and targets cross exactly as sent.
-- A mangling error fails open to the untouched line; a message is
-- never swallowed to protect a filter.
function speak.SendChatMessage(message, chatType, languageID, target)
  local out = message
  local ok, mangled = pcall(speak.MangleForSend, message, chatType, target)
  if ok then
    out = mangled
  end
  return speak.savedSend(out, chatType, languageID, target)
end

-- Wrap the documented send call. Chain-safe: only one wrapper stands
-- at a time, and removing it restores exactly what was there. A
-- missing API declines instead of erroring.
function speak.HookSend()
  if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.SendChatMessage) ~= "function" then
    return false
  end
  if C_ChatInfo.SendChatMessage == speak.SendChatMessage then
    return true
  end
  speak.savedSend = C_ChatInfo.SendChatMessage
  C_ChatInfo.SendChatMessage = speak.SendChatMessage
  return true
end

-- Remove the wrapper, but only while it is still ours: a later
-- wrapper from another addon stays standing, and our saved call
-- simply stops being reached.
function speak.UnhookSend()
  if type(C_ChatInfo) == "table" and C_ChatInfo.SendChatMessage == speak.SendChatMessage then
    C_ChatInfo.SendChatMessage = speak.savedSend
  end
  speak.savedSend = nil
end

-- Toggling applies live: the setting installs or removes the send
-- wrapper, so nothing intercepts while off.
function speak.ApplyEnabled()
  if ns.opts().enabled then
    speak.HookSend()
  else
    speak.UnhookSend()
  end
end

-- Toggle the filter: the setting applies live, the checkbox sound
-- confirms, and the wrapper installs or removes with it.
function speak.SetEnabled(on)
  ns.opts().enabled = on
  ns.play(on and "on" or "off")
  ns.say("speak in dialect " .. (on and "on" or "off"))
  speak.ApplyEnabled()
end

function speak.ToggleEnabled()
  speak.SetEnabled(not ns.opts().enabled)
end

-- One line naming every channel toggle, in stored-key order.
function speak.ChannelStates()
  local o = ns.opts()
  local parts = {}
  for _, key in ipairs({ "say", "yell" }) do
    parts[#parts + 1] = key .. " " .. (o[key] and "on" or "off")
  end
  return "channels " .. table.concat(parts, ", ")
end

-- Report one channel flip, or the whole list on a bare or list
-- toggle; an unknown channel prints help and changes nothing.
function speak.ToggleChannel(key)
  if key == nil or key == "" or key == "list" then
    ns.say(speak.ChannelStates())
    return
  end
  local o = ns.opts()
  if o[key] == nil then
    ns.help()
    return
  end
  local on = not o[key]
  o[key] = on
  ns.play(on and "on" or "off")
  ns.say(key .. " channel " .. (on and "on" or "off"))
end

-- Report one dialect switch. Chance 0 stays silent by design, so the
-- line says so instead of promising a voice that never speaks.
function speak.SetDialect(dialect)
  ns.opts().dialect = dialect
  ns.play("on")
  local line = "dialect " .. (dialect == "dwarf" and "dwarven" or "troll")
  if (ns.opts().chance or 0) <= 0 then
    line = line .. ", chance 0 stays silent"
  end
  ns.say(line)
end

-- Racial voices: the dialect follows the player's race. Troll and
-- dwarf characters speak their own voice; every other race keeps the
-- stored dialect, and a missing race API changes nothing (headless).
speak.RACE_DIALECTS = {
  dwarf = "dwarf",
  troll = "troll",
}

-- Pure mapping from a UnitRace return to a dialect, or nil when the
-- race has no voice of its own. Matches either return (localized or
-- english) case-insensitively, so any client locale still lands.
function speak.DialectForRace(race)
  if type(race) ~= "string" then
    return nil
  end
  if ns.isSecret(race) then
    return nil
  end
  return speak.RACE_DIALECTS[race:lower()]
end

-- Restore the racial voice on login. The english return is the
-- locale-independent one (UnitDocumentation, Forever build); the
-- localized return is only a fallback. Silent by design: login never
-- narrates the filter.
function speak.ApplyRaceDefault()
  if type(UnitRace) ~= "function" then
    return nil
  end
  local ok, raceName, raceFile = pcall(UnitRace, "player")
  if not ok then
    return nil
  end
  -- Data not loaded yet reads nil; a refused (secret) return reads
  -- as no voice, never an error.
  if ns.isSecret(raceName) then
    raceName = nil
  end
  if ns.isSecret(raceFile) then
    raceFile = nil
  end
  local dialect = speak.DialectForRace(raceFile) or speak.DialectForRace(raceName)
  if dialect == nil then
    return nil
  end
  ns.opts().dialect = dialect
  return dialect
end

-- Report one chance change. Zero mutes the filter without
-- uninstalling it; anything outside 0-10 is a typo and prints help
-- instead.
function speak.SetChance(raw)
  if ns.isSecret(raw) then
    ns.help()
    return
  end
  local chance = tonumber(raw)
  if chance == nil or chance < 0 or chance > 10 or chance ~= math.floor(chance) then
    ns.help()
    return
  end
  ns.opts().chance = chance
  ns.play(chance > 0 and "on" or "off")
  ns.say("chance " .. chance)
end

-- The one native Settings category for the addon. Options are
-- declarative rows rendered through the native controls; the toggle
-- applies live through its callback, and child rows disable (never
-- hide) while the filter is off. Built once, after SavedVariables
-- land, and only while the send call exists.
ns.settingsBuilt = false
function ns.ensureSettings()
  if ns.settingsBuilt then
    return
  end
  if type(Settings) ~= "table" then
    return
  end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then
    return
  end
  if type(Settings.RegisterAddOnSetting) ~= "function" then
    return
  end
  if not speak.IsAvailable() then
    return
  end
  local page = Settings.RegisterVerticalLayoutCategory("VocSpeak")
  Settings.RegisterAddOnCategory(page)
  local function note(text)
    if type(CreateSettingsListSectionHeaderInitializer) == "function" then
      pcall(function()
        ---@diagnostic disable-next-line: redundant-parameter
        local layout = SettingsPanel:GetLayout(page)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
      end)
    end
  end
  note("Rewrites outgoing /say and /yell in a dwarven or troll dialect before it sends")
  note("Only /say and /yell change; (( lines and emotes never do")
  local state = ns.opts()
  local parentInit = nil
  local function isEnabled()
    return ns.opts().enabled
  end
  local function buildInitializer(setting, row)
    if row.kind == "slider" then
      if type(Settings.CreateSlider) == "function" and type(Settings.CreateSliderOptions) == "function" then
        return Settings.CreateSlider(
          page,
          setting,
          Settings.CreateSliderOptions(row.min, row.max, row.step),
          row.tooltip
        )
      end
      return nil
    end
    if row.kind == "dropdown" then
      if type(Settings.CreateDropdown) ~= "function" then
        return nil
      end
      local options = function()
        if type(Settings.CreateControlTextContainer) ~= "function" then
          return {}
        end
        local container = Settings.CreateControlTextContainer()
        for _, choice in ipairs(row.choices or {}) do
          container:Add(choice.value, choice.label, choice.tooltip or "")
        end
        return container:GetData()
      end
      return Settings.CreateDropdown(page, setting, options, row.tooltip)
    end
    if type(Settings.CreateCheckbox) == "function" then
      return Settings.CreateCheckbox(page, setting, row.tooltip)
    end
    return nil
  end
  for _, row in ipairs(speak.OPTIONS) do
    if type(row) == "table" and row.kind == "header" and type(row.label) == "string" then
      note(row.label)
    elseif type(row) == "table" and type(row.key) == "string" then
      local setting = Settings.RegisterAddOnSetting(
        page,
        "VocSpeak_" .. row.key,
        row.key,
        state,
        type(ns.defaults[row.key]),
        row.label,
        ns.defaults[row.key]
      )
      local initializer = buildInitializer(setting, row)
      if setting and type(setting.SetValueChangedCallback) == "function" then
        local key = row.key
        setting:SetValueChangedCallback(function()
          if key == "enabled" then
            speak.ApplyEnabled()
          end
        end)
      end
      if row.key == "enabled" then
        parentInit = initializer
      elseif parentInit and initializer and type(initializer.SetParentInitializer) == "function" then
        pcall(initializer.SetParentInitializer, initializer, parentInit, isEnabled)
      end
    end
  end
  note("More on the slash line: /vs help")
  ns.settingsBuilt = true
  ns.settingsCategory = page
end

function ns.openConfig()
  -- Opening the panel is a protected act in combat: stay silent on
  -- the panel and name the way back instead, never error.
  if ns.inCombat() then
    ns.say("open Settings > AddOns > VocSpeak")
    return
  end
  local ok = ns.settingsCategory ~= nil
    and pcall(function()
      Settings.OpenToCategory(ns.settingsCategory:GetID())
    end)
  if not ok then
    ns.say("open Settings > AddOns > VocSpeak")
  end
end

-- Addon compartment: the toc names these three globals. The click
-- does what the bare slash does; hover follows the tooltip contract:
-- gold title, one line naming the job, one muted line teaching the
-- slash command.
function VocSpeak_CompartmentClick(_, _)
  -- Combat lockdown: clicks no-op, silent, and work again after.
  if ns.inCombat() then
    return
  end
  ns.play("open")
  speak.ToggleEnabled()
end

function VocSpeak_CompartmentEnter(_, button)
  if type(GameTooltip) ~= "table" then
    return
  end
  local c = ns.COLORS
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("VocSpeak", c.gold[1], c.gold[2], c.gold[3])
  GameTooltip:AddLine(
    "Roleplay speaking: outgoing /say and /yell in a dwarven or troll dialect",
    c.text[1],
    c.text[2],
    c.text[3],
    true
  )
  GameTooltip:AddLine("/vs toggles it. /vs help lists the rest", c.muted[1], c.muted[2], c.muted[3], true)
  GameTooltip:Show()
end

function VocSpeak_CompartmentLeave(_, _)
  if type(GameTooltip) == "table" then
    GameTooltip:Hide()
  end
end

-- Slash grammar: the bare command does the one main thing (toggle
-- the filter), `config` opens the panel, `help` lists the rest, and
-- anything unrecognized prints help instead of acting, so a typo can
-- never toggle anything.
ns.HELP = {
  "/vs                   turn the dialect filter on or off",
  "/vs on|off            turn the dialect filter on or off",
  "/vs dwarf|troll       speak dwarven or troll",
  "/vs chance <0-10>     how often the dialect rewrites words",
  "/vs toggle <say|yell>|list choose which channels change",
  "/vs config            open Settings > AddOns > VocSpeak",
  "/vs help              this list (/vocspeak works too)",
}

function ns.help()
  ns.say("commands")
  for _, line in ipairs(ns.HELP) do
    print("  " .. line)
  end
end

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these
-- cannot be namespaced (they are declared in .luacheckrc instead).
SLASH_VOCSPEAK1 = "/vs"
SLASH_VOCSPEAK2 = "/vocspeak"
SlashCmdList.VOCSPEAK = function(msg)
  -- A refused (secret) slash argument never errors: print help.
  if ns.isSecret(msg) then
    ns.help()
    return
  end
  local text = (msg or ""):lower()
  local cmd, arg = text:match("^(%S*)%s*(.-)%s*$")
  if cmd == "" then
    speak.ToggleEnabled()
  elseif cmd == "on" then
    speak.SetEnabled(true)
  elseif cmd == "off" then
    speak.SetEnabled(false)
  elseif cmd == "dwarf" or cmd == "troll" then
    speak.SetDialect(cmd)
  elseif cmd == "chance" then
    speak.SetChance(arg)
  elseif cmd == "toggle" then
    speak.ToggleChannel(arg)
  elseif cmd == "config" then
    ns.play("open")
    ns.openConfig()
  elseif cmd == "help" then
    ns.help()
  else
    ns.help()
  end
end

-- Character identity for ENTERING_WORLD: a GUID distinguishes a
-- character switch (reapply the racial voice) from a zone load on
-- the same character (keep the player's choice). A missing GUID
-- (data not loaded yet) never counts as a switch.
ns.identity = nil

local function readIdentity()
  if type(UnitGUID) ~= "function" then
    return nil
  end
  local ok, guid = pcall(UnitGUID, "player")
  if ok and type(guid) == "string" then
    return guid
  end
  return nil
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" then
    if addon ~= name then
      return
    end
    -- The client replaces the SavedVariables global with the loaded
    -- table after this file ran, so rebind or settings never persist.
    if type(VocSpeakDB) ~= "table" then
      VocSpeakDB = {}
    end
    ns.db = VocSpeakDB
    ns.opts()
    if speak.IsAvailable() then
      speak.ApplyEnabled()
    end
    ns.ensureSettings()
    boot:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    speak.ApplyRaceDefault()
    -- Data not loaded yet: the send call or Settings may appear
    -- after load, so retry both here.
    if speak.IsAvailable() then
      speak.ApplyEnabled()
    end
    ns.ensureSettings() -- in case the Settings API was not up at ADDON_LOADED
    boot:UnregisterEvent("PLAYER_LOGIN")
  elseif event == "PLAYER_ENTERING_WORLD" then
    ns.db = VocSpeakDB or ns.db
    ns.opts()
    if speak.IsAvailable() then
      speak.ApplyEnabled()
    end
    ns.ensureSettings()
    local id = readIdentity()
    local switched = id ~= nil and id ~= ns.identity
    if switched then
      if id ~= nil then
        ns.identity = id
      end
      -- New character, first login, or waking on a new toon: the
      -- racial voice restores. Zone loads on the same character keep
      -- history and keep the player's choice.
      speak.ApplyRaceDefault()
    elseif id ~= nil and ns.identity == nil then
      ns.identity = id
    end
  end
end)
