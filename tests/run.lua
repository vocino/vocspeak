-- VocSpeak headless tests. Stub-harness: no WoW client needed.
-- Run from anywhere:  lua tests/run.lua   (repo root also fine)
-- Works on Lua 5.1 (the client's dialect) and 5.2+.
--
-- Convention (from VocXP): each test builds a fresh stub world, drives
-- the boot frame's OnEvent scripts or the slash handler, and asserts.
-- Any failed assert aborts with the test name. The addon files load in
-- toc order (main.lua, Dialect.lua, Dictionaries.lua) into an isolated
-- env per test, so no state leaks between tests.

local testDir = debug.getinfo(1, "S").source:gsub("\\", "/"):match("@?(.*/)") or ""
local mainPath = testDir .. "../main.lua"
local dialectPath = testDir .. "../Dialect.lua"
local dictsPath = testDir .. "../Dictionaries.lua"

local passed = 0
local function check(name, cond)
  if not cond then
    error("FAIL: " .. name, 2)
  end
  passed = passed + 1
end

-- Fresh stub world per test. Fields mirror the client surface VocSpeak
-- reads: chat send, race/guid, secrets, combat, toc version, settings,
-- tooltip, sounds, frames, slash.
local function newWorld()
  return {
    raceName = "Dwarf",
    raceFile = "Dwarf",
    guid = "Player-11-0001",
    inCombat = false,
    secretStamps = {},
    secretGuard = true,
    addonInterfaceVersion = 120105,
    queriedAddon = nil,
    withSettings = false,
    settingsReg = {},
    settingCallbacks = {},
    settingsChecks = 0,
    printed = {},
    sounds = {},
    frames = {},
    savedVars = nil,
    chatSent = {},
    gametip = { lines = {} },
  }
end

-- Loads the whole addon into an isolated env for one world, in toc
-- order, as the client does. Returns ns; stashes env/frame on world.
local function loadAddon(w)
  local g = {}
  for k, v in pairs(_G) do
    g[k] = v
  end -- inherit stdlib
  g._G = g
  g.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    w.printed[#w.printed + 1] = table.concat(parts, " ")
  end
  if w.secretGuard ~= false then
    g.canaccessvalue = function(v)
      return w.secretStamps[v] ~= true
    end
  end
  g.InCombatLockdown = function()
    return w.inCombat
  end
  g.C_AddOns = {
    GetAddOnInterfaceVersion = function(n)
      w.queriedAddon = n
      return w.addonInterfaceVersion
    end,
  }
  if w.raceMissing then
    g.UnitRace = nil
  else
    g.UnitRace = function()
      if w.raceErrors then
        error("race unavailable")
      end
      return w.raceName, w.raceFile
    end
  end
  if w.guidMissing then
    g.UnitGUID = nil
  else
    g.UnitGUID = function()
      if w.guidErrors then
        error("guid unavailable")
      end
      return w.guid
    end
  end
  local originalSend = function(message, chatType, languageID, target)
    w.chatSent = { message = message, chatType = chatType, languageID = languageID, target = target }
  end
  g.C_ChatInfo = { SendChatMessage = originalSend }
  w.originalSend = originalSend
  g.PlaySound = function(id)
    w.sounds[#w.sounds + 1] = id
  end
  g.GameTooltip = {
    SetOwner = function(_, owner, anchor)
      w.gametip.owner, w.gametip.anchor = owner, anchor
    end,
    SetText = function(_, t, r, gg, b)
      w.gametip.title = t
      w.gametip.titleColor = { r, gg, b }
    end,
    AddLine = function(_, t, r, gg, b)
      w.gametip.lines[#w.gametip.lines + 1] = { text = t, r = r, g = gg, b = b }
    end,
    Show = function()
      w.gametip.shown = true
    end,
    Hide = function()
      w.gametip.shown = false
    end,
  }
  if w.withSettings then
    local S = {}
    S.RegisterVerticalLayoutCategory = function(n)
      w.settingsCat = n
      return {
        GetID = function()
          return 42
        end,
      }
    end
    S.RegisterAddOnCategory = function()
      w.settingsCatRegistered = true
    end
    S.RegisterAddOnSetting = function(_, var, key, tbl, typ, label, default)
      w.settingsReg[#w.settingsReg + 1] =
        { var = var, key = key, tbl = tbl, type = typ, label = label, default = default }
      local s = {}
      s.SetValueChangedCallback = function(_, fn)
        w.settingCallbacks[var] = fn
      end
      return s
    end
    S.CreateCheckbox = function()
      w.settingsChecks = w.settingsChecks + 1
    end
    S.CreateSlider = function()
      w.settingsChecks = w.settingsChecks + 1
    end
    S.CreateSliderOptions = function(minValue, maxValue, step)
      return { minValue = minValue, maxValue = maxValue, step = step }
    end
    S.CreateDropdown = function(_, _, options)
      w.dropdownOptions = options
      return {}
    end
    S.CreateControlTextContainer = function()
      local data = {}
      return {
        Add = function(_, v, label)
          data[#data + 1] = { value = v, label = label }
        end,
        GetData = function()
          return data
        end,
      }
    end
    S.OpenToCategory = function(id)
      w.openedCategory = id
    end
    g.Settings = S
    g.SettingsPanel = {
      GetLayout = function()
        return {
          AddInitializer = function(_, init)
            w.headers = w.headers or {}
            w.headers[#w.headers + 1] = init
          end,
        }
      end,
    }
    g.CreateSettingsListSectionHeaderInitializer = function(text)
      return text
    end
  end
  g.CreateFrame = function()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(e)
      self.events[e] = true
    end
    function f:UnregisterEvent(e)
      self.events[e] = nil
    end
    function f:SetScript(s, fn)
      self.scripts[s] = fn
    end
    w.frames[#w.frames + 1] = f
    return f
  end
  g.SlashCmdList = {}
  g.VocSpeakDB = nil -- client hasn't restored SavedVariables at file-exec time
  g.UIParent = {}
  local function loadInto(path)
    local f = assert(io.open(path, "r"))
    local src = f:read("*a")
    f:close()
    local chunk
    if setfenv then
      chunk = assert(loadstring(src, "@" .. path))
      setfenv(chunk, g)
    else
      chunk = assert(load(src, "@" .. path, "t", g))
    end
    return chunk
  end
  local ns = {}
  loadInto(mainPath)("VocSpeak", ns)
  loadInto(dialectPath)("VocSpeak", ns)
  loadInto(dictsPath)("VocSpeak", ns)
  w.frame = w.frames[1] -- the boot frame, created at load
  w.ns = ns
  w.env = g
  return ns
end

-- Simulate the client deserializing SavedVariables (a FRESH table
-- replaces the file-top default) and then firing the login sequence.
local function clientLoaded(w)
  w.env.VocSpeakDB = w.savedVars or {}
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  w.frame.scripts.OnEvent(w.frame, "PLAYER_LOGIN")
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
end

-- Deterministic randomness for dialect tests: variant picks take the
-- first variant, chance rolls return the controllable roll. Scoped to
-- the speak table under test, so the shared generator is never touched.
local testRoll = 1
local function stubRandom(speak)
  testRoll = 1
  speak.random = function(n)
    if n == 100 then
      return testRoll
    end
    return 1
  end
end

-- 1. Chat voice: the colored prefix carries the addon name, no trailing period
do
  local w = newWorld()
  local ns = loadAddon(w)
  check("chat prefix color", ns.PREFIX_COLOR == "ff66ccff")
  ns.say("hello")
  check("say prefixes the addon name", w.printed[1] == "|c" .. ns.PREFIX_COLOR .. "VocSpeak|r: hello")
end

-- 2. Sounds: SOUNDKIT names first, numeric fallback, silent without an API
do
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.SOUNDKIT = nil
  ns.play("open")
  ns.play("off")
  w.env.SOUNDKIT = { IG_MAINMENU_OPEN = 1850 }
  ns.play("open")
  ns.play("bogus")
  check("sound fallback then SOUNDKIT name", table.concat(w.sounds, ",") == "850,857,1850")
  w.env.PlaySound = nil
  ns.play("open") -- no sound API: silent, never an error
  check("no sound API is silent", #w.sounds == 3)
  w.env.SOUNDKIT = nil
  check("unknown kind never errors", pcall(ns.play, "bogus") == true)
end

-- 3. State: flat VocSpeakDB, defaults fill once, wrong types reset
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  local o = ns.opts()
  check("defaults speak dwarven at chance 8", o.enabled == true and o.dialect == "dwarf" and o.chance == 8)
  check("state lives in VocSpeakDB", ns.db == w.env.VocSpeakDB and ns.db.say == true and ns.db.yell == true)
  ns.db.chance = "loud"
  ns.db.extra = "kept"
  local refilled = ns.opts()
  check("wrong types reset", refilled.chance == 8)
  check("unknown keys are left alone", refilled.extra == "kept")
end

-- 4. Slash help: family grammar, config second to last, long form named
do
  local w = newWorld()
  local ns = loadAddon(w)
  check(
    "help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("/vs config", 1, true) ~= nil
      and ns.HELP[#ns.HELP]:find("/vocspeak works too", 1, true) ~= nil
      and ns.HELP[1]:find("/vs ", 1, true) ~= nil
  )
  check("help names none", ns.HELP[3]:find("none", 1, true) ~= nil)
end

-- 5. Options: present in panel order
do
  local w = newWorld()
  local ns = loadAddon(w)
  local keys = {}
  for _, row in ipairs(ns.speak.OPTIONS) do
    if type(row.key) == "string" then
      keys[#keys + 1] = row.key
    end
  end
  check("options present in panel order", table.concat(keys, ",") == "enabled,dialect,chance,say,yell")
end

-- 6. Engine: dwarven word rewrites at full chance
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  local dwarf = speak.DICTIONARIES.dwarf
  check("dwarf says gday", speak.Mangle("well hello there friend", dwarf, 10) == "well G'day ther' friend")
  check("dwarf phrases need surrounding spaces", speak.Mangle("here I am today", dwarf, 10) == "'ere I'mma today")
  check("all caps stays untouched", speak.Mangle("HELLO FRIEND", dwarf, 10) == "HELLO FRIEND")
  check("punctuation rides along", speak.Mangle("hello, traveler!", dwarf, 10) == "G'day, traveler!")
  check("double apostrophes collapse", speak.Mangle("a''b", dwarf, 10) == "a'b")
  local troll = speak.DICTIONARIES.troll
  check("troll greets", speak.Mangle("hello yes man", troll, 10) == "'ello yah, mon mon")
end

-- 7. Engine: flavor markers thin out below chance 10
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  local dwarf = speak.DICTIONARIES.dwarf
  testRoll = 90
  check("flavor sits out a bad roll", speak.Mangle("hello there", dwarf, 8) == "G'day there")
  check("plain words ignore the roll", speak.Mangle("hello boy", dwarf, 8) == "G'day lad")
  testRoll = 80
  check("the boundary roll still applies", speak.Mangle("hello there", dwarf, 8) == "G'day ther'")
end

-- 8. Engine: hyperlinks shelter and come back byte-identical
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  local dwarf, troll = speak.DICTIONARIES.dwarf, speak.DICTIONARIES.troll
  check(
    "one link survives",
    speak.Mangle("hello |cffffff00|Hitem:12345|h[Thunderfury]|h|r today", dwarf, 10)
      == "G'day |cffffff00|Hitem:12345|h[Thunderfury]|h|r today"
  )
  check(
    "two links survive with mangling between",
    speak.Mangle("say this |c1|h[A]|h|r and that |c2|h[B]|h|r now", troll, 10)
      == "say dis |c1|h[A]|h|r an' that |c2|h[B]|h|r now"
  )
end

-- 9. Gate: toggles, types, channels, and the (( hatch
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  local speak = ns.speak
  stubRandom(speak)
  check("say mangles", speak.MangleForSend("hello", "SAY") == "G'day")
  check("lowercase types mangle", speak.MangleForSend("hello", "say") == "G'day")
  check("ooc stays as typed", speak.MangleForSend("(( hello", "SAY") == "(( hello")
  check("emote never changes", speak.MangleForSend("hello", "EMOTE") == "hello")
  check("unknown types pass through", speak.MangleForSend("hello", "RAID_WARNING") == "hello")
  check(
    "only say and yell mangle",
    speak.MangleForSend("hello", "YELL") == "G'day"
      and speak.MangleForSend("hello", "WHISPER") == "hello"
      and speak.MangleForSend("hello", "GUILD") == "hello"
      and speak.MangleForSend("hello", "PARTY") == "hello"
      and speak.MangleForSend("hello", "RAID") == "hello"
      and speak.MangleForSend("hello", "CHANNEL", 2) == "hello"
  )
  local o = ns.opts()
  o.yell = false
  check("a flipped channel passes through", speak.MangleForSend("hello", "YELL") == "hello")
  o.yell = true
  o.chance = 0
  check("chance 0 stays silent", speak.MangleForSend("hello", "SAY") == "hello")
  o.chance = 8
  o.enabled = false
  check("a disabled filter passes through", speak.MangleForSend("hello", "SAY") == "hello")
  o.enabled = true
  o.dialect = "troll"
  check("troll speaks", speak.MangleForSend("hello", "SAY") == "'ello")
  o.dialect = "orc"
  check("unknown dialects stay silent", speak.MangleForSend("hello", "SAY") == "hello")
  o.dialect = "none"
  check("none stays silent", speak.MangleForSend("hello", "SAY") == "hello")
  o.dialect = "dwarf"
  check("nil sends empty", speak.MangleForSend(nil, "SAY") == "")
  check("junk input crosses untouched", speak.MangleForSend(42, "SAY") == 42)
end

-- 10. Hook: the wrapper mangles in place and restores on disable
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  local speak = ns.speak
  stubRandom(speak)
  check("send wrapper installs", w.env.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  w.env.C_ChatInfo.SendChatMessage("hello", "SAY", 1, nil)
  check(
    "wrapper mangles and passes args through",
    w.chatSent.message == "G'day"
      and w.chatSent.chatType == "SAY"
      and w.chatSent.languageID == 1
      and w.chatSent.target == nil
  )
  local brokenGate = speak.MangleForSend
  speak.MangleForSend = function()
    error("boom")
  end
  w.env.C_ChatInfo.SendChatMessage("hello", "SAY")
  check("a mangling error fails open", w.chatSent.message == "hello")
  speak.MangleForSend = brokenGate
  speak.SetEnabled(false)
  check("disable restores the saved call", w.env.C_ChatInfo.SendChatMessage == w.originalSend)
  speak.SetEnabled(true)
  check("re-enable rewraps", w.env.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  w.env.C_ChatInfo = nil
  check("hook declines without the api", speak.HookSend() == false)
  check("disable without the api stays silent", pcall(speak.ApplyEnabled) == true)
end

-- 11. Slash: dialect, chance, and channel subcommands on /vs
do
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  clientLoaded(w)
  local speak = ns.speak
  stubRandom(speak)
  w.env.SlashCmdList.VOCSPEAK("troll")
  check(
    "slash sets the dialect with sound",
    ns.opts().dialect == "troll"
      and w.sounds[#w.sounds] == 856
      and w.printed[#w.printed]:find("dialect troll", 1, true) ~= nil
  )
  w.env.SlashCmdList.VOCSPEAK("none")
  check(
    "slash sets none with sound",
    ns.opts().dialect == "none"
      and w.sounds[#w.sounds] == 856
      and w.printed[#w.printed]:find("dialect none", 1, true) ~= nil
  )
  w.env.SlashCmdList.VOCSPEAK("chance 3")
  check(
    "slash sets the chance with sound",
    ns.opts().chance == 3 and w.sounds[#w.sounds] == 856 and w.printed[#w.printed] == "|cff66ccffVocSpeak|r: chance 3"
  )
  local before = ns.opts().chance
  local printedBefore = #w.printed
  w.env.SlashCmdList.VOCSPEAK("chance 11")
  check("out-of-range chance only prints help", ns.opts().chance == before and #w.printed >= printedBefore + #ns.HELP)
  w.env.SlashCmdList.VOCSPEAK("toggle say")
  check(
    "slash flips a channel with sound",
    ns.opts().say == false
      and w.sounds[#w.sounds] == 857
      and w.printed[#w.printed]:find("say channel off", 1, true) ~= nil
  )
  printedBefore = #w.printed
  w.env.SlashCmdList.VOCSPEAK("toggle general")
  check(
    "general is no longer a channel",
    ns.opts().general == nil and ns.opts().say == false and #w.printed >= printedBefore + #ns.HELP
  )
  w.env.SlashCmdList.VOCSPEAK("toggle list")
  check("toggle list names every channel", w.printed[#w.printed]:find("channels say off", 1, true) ~= nil)
  before = ns.opts().say
  printedBefore = #w.printed
  w.env.SlashCmdList.VOCSPEAK("toggle bogus")
  check("unknown channels only print help", ns.opts().say == before and #w.printed >= printedBefore + #ns.HELP)
  w.env.SlashCmdList.VOCSPEAK("")
  check(
    "bare slash toggles the filter",
    ns.opts().enabled == false
      and w.sounds[#w.sounds] == 857
      and w.env.C_ChatInfo.SendChatMessage ~= speak.SendChatMessage
  )
  w.env.SlashCmdList.VOCSPEAK("on")
  check("slash turns the filter on", ns.opts().enabled == true and w.sounds[#w.sounds] == 856)
  printedBefore = #w.printed
  w.env.SlashCmdList.VOCSPEAK("bogus")
  check("unknown subcommands only print help", ns.opts().enabled == true and #w.printed >= printedBefore + #ns.HELP)
  w.env.SlashCmdList.VOCSPEAK("config")
  check("config plays the open sound", w.sounds[#w.sounds] == 850)
end

-- 12. Settings: one category for the addon, rows in order, live toggle
do
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  clientLoaded(w)
  local speak = ns.speak
  check("panel builds one category for the addon", w.settingsCat == "VocSpeak")
  local keys = {}
  for _, s in ipairs(w.settingsReg) do
    keys[#keys + 1] = s.key
  end
  check("panel registers the rows in order", table.concat(keys, ",") == "enabled,dialect,chance,say,yell")
  check(
    "panel leads with the job and the escape hatch",
    w.headers[1] == "Rewrites outgoing /say and /yell in the chosen dialect before it sends"
      and w.headers[2] == "Only /say and /yell change; (( lines and emotes never do"
      and w.headers[3] == "Dialect"
      and w.headers[4] == "Channels"
  )
  local picked = w.dropdownOptions and w.dropdownOptions() or {}
  check(
    "dialect row offers dwarven, troll, and none",
    #picked == 3 and picked[1].value == "dwarf" and picked[2].value == "troll" and picked[3].value == "none"
  )
  local enabledCb = w.settingCallbacks["VocSpeak_enabled"]
  check("panel toggle callback exists", type(enabledCb) == "function")
  speak.HookSend()
  ns.db.enabled = false
  enabledCb()
  check("panel toggle removes the wrapper", w.env.C_ChatInfo.SendChatMessage ~= speak.SendChatMessage)
  ns.db.enabled = true
  enabledCb()
  check("panel toggle reinstalls the wrapper", w.env.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  local built = w.settingsCat
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("settings build once", w.settingsCat == built)
end

-- 13. Boot: login fills defaults and hooks, no compartment entry points
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  check("boot frame registers for login", w.frame.events["ADDON_LOADED"] and w.frame.events["PLAYER_LOGIN"])
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "someone-else")
  check("other addons never boot us", ns.db == nil or ns.db.enabled == nil)
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("login fills the defaults", ns.opts().enabled == true and ns.opts().dialect == "dwarf")
  check("login installs the wrapper", w.env.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  check(
    "no compartment entry points",
    w.env.VocSpeak_CompartmentClick == nil
      and w.env.VocSpeak_CompartmentEnter == nil
      and w.env.VocSpeak_CompartmentLeave == nil
  )
end

-- 14. Engine: rebuilt voice vectors (chance 10, first variant)
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  local dwarf, troll = speak.DICTIONARIES.dwarf, speak.DICTIONARIES.troll
  local vectors = {
    { dwarf, "say hello to my little friend", "say G'day ta me wee lad" },
    { dwarf, "tell me what do you want", "tell me wha' d'ye want" },
    { dwarf, "fight for the Alliance today", "fight fer Khaz Modan today" },
    { dwarf, "those lads are brave", "them lads are brave" },
    { dwarf, "do you ken me", "do ya ken me" },
    { dwarf, "we cannot win", "we cannae win" },
    { dwarf, "she is no girl", "she is nay lass" },
    { dwarf, "yes I know the way", "aye I ken th' way" },
    { dwarf, "go to hell now", "go ta blazes now" },
    { dwarf, "give him the gold", "give 'im th' gold" },
    { dwarf, "it is never just a little beer", "it is nev'r jes a wee ale" },
    { dwarf, "before you go tell me no", "afore ya go tell me nay" },
    { dwarf, "the thane thanked them", "th' thane thanked 'em" },
    { troll, "tell me are you coming", "tell me ya be coming" },
    { troll, "we are going to take the city", "we be gonna take da city" },
    { troll, "who are you mon", "who ya be mon" },
    { troll, "what do you want", "wha' do ya want" },
    { troll, "I thank you very much", "I tank ya, mon real much" },
    { troll, "my brother is very brave", "my brudda be real brave" },
    { troll, "this power is dark", "dis mojo be dark" },
    { troll, "the doctor is in", "da doctor be in" },
    { troll, "those men", "dose men" },
    { troll, "thanks", "tank ya" },
    { troll, "thank the loa", "tank da loa" },
    { troll, "do you feel lucky", "do ya be feelin' lucky" },
    { troll, "sure thing thanks bye", "ya mon thing tank ya later, mon" },
    { troll, "your gear is ready", "ya gear be ready" },
  }
  for _, v in ipairs(vectors) do
    check("voice: " .. v[2], speak.Mangle(v[2], v[1], 10) == v[3])
  end
end

-- 15. Race: the dialect follows the player's race on login
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  check("dwarf race maps to dwarven", speak.DialectForRace("Dwarf") == "dwarf")
  check("troll race maps to troll", speak.DialectForRace("Troll") == "troll")
  check(
    "unmapped races map to none",
    speak.DialectForRace("Human") == "none" and speak.DialectForRace(nil) == nil and speak.DialectForRace("") == nil
  )
  clientLoaded(w)
  w.raceName, w.raceFile = "Troll", "Troll"
  check("troll login speaks troll", speak.ApplyRaceDefault() == "troll" and ns.opts().dialect == "troll")
  w.raceName, w.raceFile = "Dwarf", "Dwarf"
  ns.opts().dialect = "troll"
  check("dwarf login speaks dwarven", speak.ApplyRaceDefault() == "dwarf" and ns.opts().dialect == "dwarf")
  w.raceName, w.raceFile = "Human", "Human"
  ns.opts().dialect = "troll"
  check("unmapped races default to none", speak.ApplyRaceDefault() == "none" and ns.opts().dialect == "none")
  w.raceMissing = true
  w.env.UnitRace = nil
  ns.db = {}
  check("missing race api keeps the default", speak.ApplyRaceDefault() == nil and ns.opts().dialect == "dwarf")
end

-- 16. Boot: login restores the racial voice
do
  local w = newWorld()
  w.raceName, w.raceFile = "Troll", "Troll"
  local ns = loadAddon(w)
  clientLoaded(w)
  check("login switches a troll to troll", ns.opts().dialect == "troll")
end
do
  local w = newWorld()
  w.raceName, w.raceFile = "Human", "Human"
  local ns = loadAddon(w)
  clientLoaded(w)
  check("login switches a human to none", ns.opts().dialect == "none")
end

-- 17. Troll voice: restrained, lore-grounded conversions
do
  local w = newWorld()
  local ns = loadAddon(w)
  local speak = ns.speak
  stubRandom(speak)
  local troll = speak.DICTIONARIES.troll
  check("little converts but littlest does not", speak.Mangle("little littlest", troll, 10) == "li'l littlest")
  check("other converts but mother does not", speak.Mangle("other mother", troll, 10) == "odda mother")
  check("guide forms dem dey", speak.Mangle("tell them they wait", troll, 10) == "tell dem dey wait")
  check("guard spares meself after wit'", speak.Mangle("that there with myself", troll, 10) == "dat der wit' myself")
  check("thinking shortens before the ing rule", speak.Mangle("thinking", troll, 10) == "tinkin'")
  check("capitalized running still shortens", speak.Mangle("Running McDonald", troll, 10) == "Runnin' McDonald")
  check("that converts but thing stands", speak.Mangle("that thing", troll, 10) == "dat thing")
  check(
    "dark stays while magic turns to voodoo",
    speak.Mangle("dark magic is mine", troll, 10) == "dark voodoo be mi own"
  )
  check("joke placeholders pass through", speak.Mangle("kek lolz", troll, 10) == "kek lolz")
  check("line-start phrases stay put", speak.Mangle("I am here", troll, 10) == "I am here")
  testRoll = 90
  check("flavor-held forms sit out a bad roll", speak.Mangle("those i'm and", troll, 8) == "those i'm and")
  testRoll = 80
  check("flavor-held forms apply on the boundary", speak.Mangle("those i'm and", troll, 8) == "dose i be an'")
end

-- 18. Forever + Midnight (retail today): own toc, nothing assumed
do -- the shipped Midnight Interface version reads retail
  local w = newWorld()
  w.addonInterfaceVersion = 120105
  local ns = loadAddon(w)
  clientLoaded(w)
  check("midnight flavor", ns.clientFlavor() == "retail")
  check("midnight queries own addon", w.queriedAddon == "VocSpeak")
end
do -- the Forever Interface version reads forever
  local w = newWorld()
  w.addonInterfaceVersion = 16001
  local ns = loadAddon(w)
  clientLoaded(w)
  check("forever flavor", ns.clientFlavor() == "forever")
end
do -- a missing toc-version API falls back to retail, never an error
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.C_AddOns = nil
  check("missing flavor api reads retail", ns.clientFlavor() == "retail")
end
do -- a missing send call declines the hook and skips the panel, never errors
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  w.env.C_ChatInfo = nil
  check("hook declines without send", ns.speak.HookSend() == false)
  w.env.VocSpeakDB = {}
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("panel skips without send", ns.settingsBuilt == false)
end
do -- a missing Settings stack skips the panel, retried at login
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.VocSpeakDB = {}
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("load without settings skips", ns.settingsBuilt == false)
  w.withSettings = true
  w.env.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      w.settingsCat = n
      return {
        GetID = function()
          return 42
        end,
      }
    end,
    RegisterAddOnCategory = function() end,
    RegisterAddOnSetting = function(_, var, key, tbl, typ, label, default)
      local s = {}
      s.SetValueChangedCallback = function(_, fn)
        w.settingCallbacks[var] = fn
      end
      return s
    end,
    CreateCheckbox = function() end,
    OpenToCategory = function() end,
  }
  w.frame.scripts.OnEvent(w.frame, "PLAYER_LOGIN")
  check("login builds settings", ns.settingsBuilt == true and w.settingsCat == "VocSpeak")
end

-- 19. Game data not loaded yet: nil reads fail open, retries fill in
do -- UnitRace returning nil keeps the default, never errors
  local w = newWorld()
  w.raceName, w.raceFile = nil, nil
  local ns = loadAddon(w)
  clientLoaded(w)
  check("nil race keeps dwarven", ns.opts().dialect == "dwarf")
end
do -- a failing UnitRace keeps the default, never errors
  local w = newWorld()
  w.raceErrors = true
  local ns = loadAddon(w)
  clientLoaded(w)
  check("erroring race keeps dwarven", ns.opts().dialect == "dwarf")
end
do -- a nil GUID never counts as a switch and never wipes settings
  local w = newWorld()
  w.guid = nil
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.opts().dialect = "troll"
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("nil guid keeps the choice", ns.opts().dialect == "troll")
end
do -- the send call appearing late still hooks at entering world
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.C_ChatInfo = nil
  w.env.VocSpeakDB = {}
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("load without send skips hook", ns.speak.IsAvailable() == false)
  w.env.C_ChatInfo = { SendChatMessage = w.originalSend }
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("entering world hooks late send", w.env.C_ChatInfo.SendChatMessage == ns.speak.SendChatMessage)
end

-- 20. Secret values (Midnight): refused reads fail open, never error
do -- the guard itself: refused reads true, the rest false
  local w = newWorld()
  w.secretStamps[4242] = true
  local ns = loadAddon(w)
  check("secret reads true", ns.isSecret(4242) == true)
  check("plain reads false", ns.isSecret(5) == false)
end
do -- without the guard every read stays plain, never an error
  local w = newWorld()
  w.secretGuard = false
  w.secretStamps[99] = true
  local ns = loadAddon(w)
  check("no guard stays plain", ns.isSecret(99) == false)
end
do -- a refused message crosses untouched, never mangled, never an error
  local w = newWorld()
  w.secretStamps["hello"] = true
  local ns = loadAddon(w)
  clientLoaded(w)
  stubRandom(ns.speak)
  check("secret message passes through", ns.speak.MangleForSend("hello", "SAY") == "hello")
  check("secret engine input passes through", ns.speak.Mangle("hello", ns.speak.DICTIONARIES.dwarf, 10) == "hello")
end
do -- a refused chat type never errors and never mangles
  local w = newWorld()
  w.secretStamps["SAY"] = true
  local ns = loadAddon(w)
  clientLoaded(w)
  stubRandom(ns.speak)
  check("secret type passes through", ns.speak.MangleForSend("hello", "SAY") == "hello")
end
do -- a refused race return reads as no voice, never an error
  local w = newWorld()
  w.raceName, w.raceFile = "Troll", "Troll"
  w.secretStamps["Troll"] = true
  local ns = loadAddon(w)
  clientLoaded(w)
  check("secret race maps to nil", ns.speak.DialectForRace("Troll") == nil)
  ns.opts().dialect = "dwarf"
  check("secret race keeps the default", ns.speak.ApplyRaceDefault() == nil and ns.opts().dialect == "dwarf")
end
do -- a refused slash argument prints help instead of acting
  local w = newWorld()
  w.secretStamps["troll"] = true
  local ns = loadAddon(w)
  clientLoaded(w)
  local before = ns.opts().dialect
  w.env.SlashCmdList.VOCSPEAK("troll")
  check("secret slash keeps the dialect", ns.opts().dialect == before)
end

-- 21. Combat: nothing forbidden, recovery clean after
do -- the panel open in combat names the way back, never calls Settings
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  clientLoaded(w)
  w.inCombat = true
  local opened = w.openedCategory
  ns.openConfig()
  check("combat config skips the panel", (w.openedCategory or nil) == opened)
  check("combat config names the way back", w.printed[#w.printed]:find("open Settings", 1, true) ~= nil)
  w.inCombat = false
  ns.openConfig()
  check("regen config opens the panel", w.openedCategory == 42)
end
do -- slash toggles still apply in combat (Lua state only, no protected frame)
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  w.inCombat = true
  w.env.SlashCmdList.VOCSPEAK("")
  check("combat slash flips", ns.opts().enabled == false)
  w.env.SlashCmdList.VOCSPEAK("")
  check("combat slash flips back", ns.opts().enabled == true)
  w.inCombat = false
  w.env.SlashCmdList.VOCSPEAK("troll")
  check("regen slash works", ns.opts().dialect == "troll")
end

-- 22. Login, reload, logout, and saved data: nothing lost, nothing invented
do -- another addon's load never touches our settings
  local w = newWorld()
  local ns = loadAddon(w)
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "SomeOtherAddon")
  check("wrong addon ignored", ns.settingsBuilt == false)
end
do -- a missing SavedVariables table starts clean, never errors
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  w.env.VocSpeakDB = nil
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("nil db starts clean", type(ns.db) == "table" and ns.db.enabled == true)
  check("nil db builds settings", ns.settingsBuilt == true)
end
do -- the restore replaces the file-top table instead of merging into it
  local w = newWorld()
  local ns = loadAddon(w)
  ns.db.enabled = false
  w.env.VocSpeakDB = { dialect = "troll" }
  w.frame.scripts.OnEvent(w.frame, "ADDON_LOADED", "VocSpeak")
  check("restore replaces file-top", ns.db.dialect == "troll" and ns.db.enabled == true)
end
do -- unknown keys ride along for forward compatibility
  local w = newWorld()
  w.savedVars = { enabled = false, futureKey = 7 }
  local ns = loadAddon(w)
  clientLoaded(w)
  check("unknown keys preserved", ns.db.futureKey == 7 and ns.db.enabled == false)
end
do -- an old partial profile fills the rest with defaults
  local w = newWorld()
  w.savedVars = { chance = 3 }
  local ns = loadAddon(w)
  clientLoaded(w)
  check("old profile keeps saved", ns.db.chance == 3)
  check(
    "old profile fills defaults",
    ns.db.enabled == true and ns.db.say == true and ns.db.yell == true and ns.db.dialect == "dwarf"
  )
end
do -- corrupt types reset to defaults instead of misbehaving
  local w = newWorld()
  w.savedVars = { enabled = "yes", dialect = 42, chance = "loud", say = 1, yell = 0 }
  local ns = loadAddon(w)
  clientLoaded(w)
  check(
    "corrupt db resets",
    ns.db.enabled == true
      and ns.db.dialect == "dwarf"
      and ns.db.chance == 8
      and ns.db.say == true
      and ns.db.yell == true
  )
end
do -- a reload restores the saved filter instead of inventing one
  local w = newWorld()
  w.raceName, w.raceFile = "Troll", "Troll"
  w.savedVars = { enabled = false, dialect = "troll", chance = 3, say = false, yell = true }
  local ns = loadAddon(w)
  clientLoaded(w)
  check(
    "reload restores the filter",
    ns.opts().enabled == false
      and ns.opts().dialect == "troll"
      and ns.opts().chance == 3
      and ns.opts().say == false
      and ns.opts().yell == true
  )
end

-- 23. Character, zone, and group: switches restore, travel keeps, noise ignored
do -- a zone load on the same character keeps the player's choice
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.opts().dialect = "troll"
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("zone keeps the choice", ns.opts().dialect == "troll" and ns.opts().enabled == true)
end
do -- a character switch restores the racial voice
  local w = newWorld()
  w.raceName, w.raceFile = "Dwarf", "Dwarf"
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.opts().dialect = "troll"
  w.guid = "Player-11-0002"
  w.raceName, w.raceFile = "Troll", "Troll"
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("character switch restores troll", ns.opts().dialect == "troll")
  w.guid = "Player-11-0003"
  w.raceName, w.raceFile = "Dwarf", "Dwarf"
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("character switch restores dwarven", ns.opts().dialect == "dwarf")
  w.guid = "Player-11-0004"
  w.raceName, w.raceFile = "Human", "Human"
  w.frame.scripts.OnEvent(w.frame, "PLAYER_ENTERING_WORLD")
  check("character switch restores none", ns.opts().dialect == "none")
end
do -- group chatter is not a reset and never errors
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.opts().dialect = "troll"
  w.frame.scripts.OnEvent(w.frame, "GROUP_ROSTER_UPDATE")
  check("group noise keeps the choice", ns.opts().dialect == "troll")
  check("group noise keeps the hook", w.env.C_ChatInfo.SendChatMessage == ns.speak.SendChatMessage)
end
do -- spec and zone events never touch the filter
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.opts().enabled = false
  w.frame.scripts.OnEvent(w.frame, "PLAYER_SPECIALIZATION_CHANGED")
  w.frame.scripts.OnEvent(w.frame, "ZONE_CHANGED_NEW_AREA")
  check("spec and zone noise keeps state", ns.opts().enabled == false)
end

print(string.format("tests/run.lua: %d checks passed", passed))
