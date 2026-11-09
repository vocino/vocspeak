-- Headless tests for VocSpeak. No game client needed.
-- Run from the repo root:  lua tests/run.lua

local mock = dofile("tests/mock.lua")
mock.install()

local pass, fail = 0, 0
local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL " .. name)
  end
end

local FILES = {
  "main.lua",
  "Dialect.lua",
  "Dictionaries.lua",
}

-- Loads the whole addon into one namespace, in toc order, as the client does.
local function loadAddon()
  mock.reset()
  local ns = {}
  for _, file in ipairs(FILES) do
    assert(loadfile(file))("VocSpeak", ns)
  end
  return ns
end

-- Runs fn with print captured; print is restored even when fn errors.
local function capturePrint(fn)
  local lines = {}
  local realPrint = print
  print = function(s)
    lines[#lines + 1] = s
  end
  local ok, err = pcall(fn)
  print = realPrint
  assert(ok, err)
  return lines
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

-- Chat voice: the colored prefix carries the addon name, no trailing period
do
  local ns = loadAddon()
  check("chat prefix color", ns.PREFIX_COLOR == "ff66ccff")
  local said = capturePrint(function()
    ns.say("hello")
  end)
  check("say prefixes the addon name", said[1] == "|c" .. ns.PREFIX_COLOR .. "VocSpeak|r: hello")
end

-- Sounds: SOUNDKIT names first, numeric fallback, silent without an API
do
  local ns = loadAddon()
  local played = {}
  _G.PlaySound = function(id)
    played[#played + 1] = id
  end
  _G.SOUNDKIT = nil
  ns.play("open")
  ns.play("off")
  _G.SOUNDKIT = { IG_MAINMENU_OPEN = 1850 }
  ns.play("open")
  ns.play("bogus")
  check("sound fallback then SOUNDKIT name", table.concat(played, ",") == "850,857,1850")
  _G.PlaySound = nil
  ns.play("open") -- no sound API: silent, never an error
  check("no sound API is silent", #played == 3)
  _G.SOUNDKIT = nil
  check("unknown kind never errors", pcall(ns.play, "bogus") == true)
end

-- State: flat VocSpeakDB, defaults fill once, wrong types reset
do
  local ns = loadAddon()
  local o = ns.opts()
  check("defaults speak dwarven at chance 8", o.enabled == true and o.dialect == "dwarf" and o.chance == 8)
  check("state lives in VocSpeakDB", ns.db == _G.VocSpeakDB and ns.db.say == true and ns.db.yell == true)
  ns.db.chance = "loud"
  ns.db.extra = "kept"
  local refilled = ns.opts()
  check("wrong types reset", refilled.chance == 8)
  check("unknown keys are left alone", refilled.extra == "kept")
end

-- Slash help: family grammar, config second to last, long form named
do
  local ns = loadAddon()
  check(
    "help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("/vs config", 1, true) ~= nil
      and ns.HELP[#ns.HELP]:find("/vocspeak works too", 1, true) ~= nil
      and ns.HELP[1]:find("/vs ", 1, true) ~= nil
  )
end

-- Options: present in panel order
do
  local ns = loadAddon()
  local keys = {}
  for _, row in ipairs(ns.speak.OPTIONS) do
    if type(row.key) == "string" then
      keys[#keys + 1] = row.key
    end
  end
  check("options present in panel order", table.concat(keys, ",") == "enabled,dialect,chance,say,yell")
end

-- Engine: dwarven word rewrites at full chance
do
  local ns = loadAddon()
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

-- Engine: flavor markers thin out below chance 10
do
  local ns = loadAddon()
  local speak = ns.speak
  stubRandom(speak)
  local dwarf = speak.DICTIONARIES.dwarf
  testRoll = 90
  check("flavor sits out a bad roll", speak.Mangle("hello there", dwarf, 8) == "G'day there")
  check("plain words ignore the roll", speak.Mangle("hello boy", dwarf, 8) == "G'day lad")
  testRoll = 80
  check("the boundary roll still applies", speak.Mangle("hello there", dwarf, 8) == "G'day ther'")
end

-- Engine: hyperlinks shelter and come back byte-identical
do
  local ns = loadAddon()
  local speak = ns.speak
  stubRandom(speak)
  local dwarf, troll = speak.DICTIONARIES.dwarf, speak.DICTIONARIES.troll
  check(
    "one link survives",
    speak.Mangle("hello |cffffff00|Hitem:12345|h[Thunderfury]|h|r today", dwarf, 10)
      == "G'day |cffffff00|Hitem:12345|h[Thunderfury]|h|r today"
  )
  -- The apostrophe guard skips ^-anchored rules after an', so that
  -- stays untouched there: no loose rule reads it through.
  check(
    "two links survive with mangling between",
    speak.Mangle("say this |c1|h[A]|h|r and that |c2|h[B]|h|r now", troll, 10)
      == "say dis |c1|h[A]|h|r an' that |c2|h[B]|h|r now"
  )
end

-- Gate: toggles, types, channels, and the (( hatch
do
  local ns = loadAddon()
  ns.db = {}
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
  o.dialect = "dwarf"
  check("nil sends empty", speak.MangleForSend(nil, "SAY") == "")
  check("junk input crosses untouched", speak.MangleForSend(42, "SAY") == 42)
end

-- Hook: the wrapper mangles in place and restores on disable
do
  local sent = {}
  local original = function(message, chatType, languageID, target)
    sent = { message = message, chatType = chatType, languageID = languageID, target = target }
  end
  _G.C_ChatInfo = { SendChatMessage = original }
  local ns = loadAddon()
  ns.db = {}
  local speak = ns.speak
  stubRandom(speak)
  ns.say = function() end
  ns.play = function() end
  check("send wrapper installs", speak.HookSend() == true and _G.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  _G.C_ChatInfo.SendChatMessage("hello", "SAY", 1, nil)
  check(
    "wrapper mangles and passes args through",
    sent.message == "G'day" and sent.chatType == "SAY" and sent.languageID == 1 and sent.target == nil
  )
  local brokenGate = speak.MangleForSend
  speak.MangleForSend = function()
    error("boom")
  end
  _G.C_ChatInfo.SendChatMessage("hello", "SAY")
  check("a mangling error fails open", sent.message == "hello")
  speak.MangleForSend = brokenGate
  speak.SetEnabled(false)
  check("disable restores the saved call", _G.C_ChatInfo.SendChatMessage == original)
  speak.SetEnabled(true)
  check("re-enable rewraps", _G.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  _G.C_ChatInfo = nil
  check("hook declines without the api", speak.HookSend() == false)
  check("disable without the api stays silent", pcall(speak.ApplyEnabled) == true)
end

-- Slash: dialect, chance, and channel subcommands on /vs
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local ns = loadAddon()
  ns.db = {}
  local speak = ns.speak
  stubRandom(speak)
  local said, played = {}, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  _G.SlashCmdList.VOCSPEAK("troll")
  check(
    "slash sets the dialect with sound",
    ns.opts().dialect == "troll" and played[#played] == "on" and said[#said] == "dialect troll"
  )
  _G.SlashCmdList.VOCSPEAK("chance 3")
  check(
    "slash sets the chance with sound",
    ns.opts().chance == 3 and played[#played] == "on" and said[#said] == "chance 3"
  )
  local before = ns.opts().chance
  local saidBefore = #said
  local printed = capturePrint(function()
    _G.SlashCmdList.VOCSPEAK("chance 11")
  end)
  check(
    "out-of-range chance only prints help",
    ns.opts().chance == before and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCSPEAK("toggle say")
  check(
    "slash flips a channel with sound",
    ns.opts().say == false and played[#played] == "off" and said[#said] == "say channel off"
  )
  saidBefore = #said
  printed = capturePrint(function()
    _G.SlashCmdList.VOCSPEAK("toggle general")
  end)
  check(
    "general is no longer a channel",
    ns.opts().general == nil and ns.opts().say == false and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCSPEAK("toggle list")
  check("toggle list names every channel", said[#said]:find("channels say off", 1, true) ~= nil)
  before = ns.opts().say
  saidBefore = #said
  printed = capturePrint(function()
    _G.SlashCmdList.VOCSPEAK("toggle bogus")
  end)
  check(
    "unknown channels only print help",
    ns.opts().say == before and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCSPEAK("")
  check(
    "bare slash toggles the filter",
    ns.opts().enabled == false and played[#played] == "off" and _G.C_ChatInfo.SendChatMessage ~= speak.SendChatMessage
  )
  _G.SlashCmdList.VOCSPEAK("on")
  check("slash turns the filter on", ns.opts().enabled == true and played[#played] == "on")
  saidBefore = #said
  printed = capturePrint(function()
    _G.SlashCmdList.VOCSPEAK("bogus")
  end)
  check(
    "unknown subcommands only print help",
    ns.opts().enabled == true and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCSPEAK("config")
  check("config plays the open sound", played[#played] == "open")
  _G.C_ChatInfo = nil
end

-- Settings: one category for the addon, rows in order, live toggle
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local registered, headers, categoryName = {}, {}, nil
  local dropdownInit
  _G.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      categoryName = n
      return {
        name = n,
        GetID = function()
          return 7
        end,
      }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
    RegisterAddOnSetting = function(page, variable, key, tbl, vtype, label, default)
      local s = { page = page, variable = variable, key = key }
      s.SetValueChangedCallback = function(_, fn)
        s.callback = fn
      end
      registered[#registered + 1] = s
      return s
    end,
    CreateCheckbox = function(_, s)
      return { setting = s }
    end,
    CreateSlider = function(_, s, options)
      return { setting = s, options = options }
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
      return { minValue = minValue, maxValue = maxValue, step = step }
    end,
    CreateDropdown = function(_, s, options)
      dropdownInit = { setting = s, options = options }
      return dropdownInit
    end,
    CreateControlTextContainer = function()
      local data = {}
      return {
        Add = function(_, v, label)
          data[#data + 1] = { value = v, label = label }
        end,
        GetData = function()
          return data
        end,
      }
    end,
  }
  _G.SettingsPanel = {
    GetLayout = function()
      return {
        AddInitializer = function(_, init)
          headers[#headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end
  local ns = loadAddon()
  ns.db = {}
  ns.ensureSettings()
  local speak = ns.speak
  check("panel builds one category for the addon", categoryName == "VocSpeak")
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check("panel registers the rows in order", table.concat(keys, ",") == "enabled,dialect,chance,say,yell")
  check(
    "panel leads with the job and the escape hatch",
    headers[1] == "Rewrites outgoing /say and /yell in a dwarven or troll dialect before it sends"
      and headers[2] == "Only /say and /yell change; (( lines and emotes never do"
      and headers[3] == "Dialect"
      and headers[4] == "Channels"
  )
  local dropdown
  for _, s in ipairs(registered) do
    if s.key == "dialect" then
      dropdown = s
    end
  end
  check("dialect row exists", dropdown ~= nil)
  local picked = dropdownInit ~= nil and dropdownInit.options() or {}
  check(
    "dialect dropdown offers dwarven and troll",
    #picked == 2 and picked[1].value == "dwarf" and picked[2].value == "troll"
  )
  local enabledSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    end
  end
  speak.HookSend()
  ns.db.enabled = false
  enabledSetting.callback()
  check("panel toggle removes the wrapper", _G.C_ChatInfo.SendChatMessage ~= speak.SendChatMessage)
  ns.db.enabled = true
  enabledSetting.callback()
  check("panel toggle reinstalls the wrapper", _G.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  ns.ensureSettings()
  check("settings build once", categoryName == "VocSpeak")
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
  _G.C_ChatInfo = nil
end

-- Boot and compartment: login fills defaults and hooks, clicks toggle
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local ns = loadAddon()
  ns.db = {}
  local speak = ns.speak
  stubRandom(speak)
  ns.say = function() end
  ns.play = function() end
  local boot
  for _, frame in ipairs(mock.frames) do
    if frame.events["ADDON_LOADED"] then
      boot = frame
    end
  end
  check("boot frame registers for login", boot ~= nil)
  boot.scripts.OnEvent(boot, "ADDON_LOADED", "someone-else")
  check("other addons never boot us", ns.db.enabled == nil)
  boot.scripts.OnEvent(boot, "ADDON_LOADED", "VocSpeak")
  check("login fills the defaults", ns.opts().enabled == true and ns.opts().dialect == "dwarf")
  check("login installs the wrapper", _G.C_ChatInfo.SendChatMessage == speak.SendChatMessage)
  VocSpeak_CompartmentClick()
  check("compartment click toggles off", ns.opts().enabled == false)
  VocSpeak_CompartmentClick()
  check("compartment click toggles on", ns.opts().enabled == true)
  check("tooltip enter without a tooltip stays silent", pcall(VocSpeak_CompartmentEnter) == true)
  check("tooltip leave without a tooltip stays silent", pcall(VocSpeak_CompartmentLeave) == true)
  _G.C_ChatInfo = nil
end

-- Engine: rebuilt voice vectors (chance 10, first variant)
do
  local ns = loadAddon()
  ns.db = {}
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

-- Race: the dialect follows the player's race on login
do
  local ns = loadAddon()
  local speak = ns.speak
  check("dwarf race maps to dwarven", speak.DialectForRace("Dwarf") == "dwarf")
  check("troll race maps to troll", speak.DialectForRace("Troll") == "troll")
  check("unmapped races keep their voice", speak.DialectForRace("Human") == nil and speak.DialectForRace(nil) == nil)
  ns.db = {}
  _G.UnitRace = function()
    return "Troll", "Troll"
  end
  check("troll login speaks troll", speak.ApplyRaceDefault() == "troll" and ns.opts().dialect == "troll")
  _G.UnitRace = function()
    return "Dwarf", "Dwarf"
  end
  ns.opts().dialect = "troll"
  check("dwarf login speaks dwarven", speak.ApplyRaceDefault() == "dwarf" and ns.opts().dialect == "dwarf")
  _G.UnitRace = function()
    return "Human", "Human"
  end
  ns.opts().dialect = "troll"
  check("unmapped races leave the dialect alone", speak.ApplyRaceDefault() == nil and ns.opts().dialect == "troll")
  _G.UnitRace = nil
  ns.db = {}
  check("missing race api keeps the default", speak.ApplyRaceDefault() == nil and ns.opts().dialect == "dwarf")
end

-- Boot: login restores the racial voice
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local ns = loadAddon()
  ns.db = {}
  ns.say = function() end
  ns.play = function() end
  _G.UnitRace = function()
    return "Troll", "Troll"
  end
  local boot
  for _, frame in ipairs(mock.frames) do
    if frame.events["ADDON_LOADED"] then
      boot = frame
    end
  end
  boot.scripts.OnEvent(boot, "ADDON_LOADED", "VocSpeak")
  check("addon loaded still defaults dwarven before login", ns.opts().dialect == "dwarf")
  boot.scripts.OnEvent(boot, "PLAYER_LOGIN")
  check("login switches a troll to troll", ns.opts().dialect == "troll")
  _G.UnitRace = nil
  _G.C_ChatInfo = nil
end

-- Troll voice: restrained, lore-grounded conversions
do
  local ns = loadAddon()
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

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
