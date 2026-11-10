# AGENTS.md

## Code Map

- `VocSpeak.toc` - retail metadata (Interface 120105)
- `VocSpeak_Camelot.toc` - the same, for the Forever client (Interface 16001); both list the same Lua files
- `main.lua` - the addon: saved variables, flavor/secrets/combat guards, send wrapper, settings page, slash, compartment, boot
- `Dialect.lua` - the dialect engine: pure text in, mangled text out
- `Dictionaries.lua` - the dwarven and troll tables (MIT, attributed in the file)
- `tests/run.lua` - stub-harness headless tests (`lua tests/run.lua`): each test builds a fresh stub world, drives the boot frame or slash, and asserts
- `.reference/api-verification.md` - per-API findings on live + forever (gitignored)

## API references

Code targets the build in `## Interface:` of the `.toc`. Verify every
WoW API fact against that build, in this order, and nothing else:

1. Blizzard's own API docs for the build, or the mirror at
   https://github.com/Gethe/wow-ui-source, branch `live` (and
   `forever` for the Forever client), folder
   `Interface/AddOns/Blizzard_APIDocumentationGenerated/`.
   Names, namespaces, arguments, returns, and events come from here.
2. Blizzard's UI source in the same mirror for templates and mixins.
3. The Lua 5.1 manual, https://www.lua.org/manual/5.1/. The client is
   Lua 5.1 in a sandbox; nothing from 5.2+ exists there.

Never Wowpedia (fandom), WoWWiki, forums, tutorials, or memory of an
older patch. `.luacheckrc` is the allowlist of verified globals: lint
fails on any other, and a name is added only after confirming it in
source 1 for both builds. See `.reference/api-verification.md` for
the finding behind each name.

## Conventions

- Forever + Midnight (retail): the same code runs on both; version-locked behavior degrades silently behind presence gates, and a missing API is never an error.
- State lives only in `VocSpeakDB`. A fresh install speaks dwarven at chance 8 (troll for troll characters, restored on login and on character switch).
- Secrets (Midnight): refused values fail open to the untouched line via `ns.isSecret`, never an error and never a mangled secret.
- Combat: the compartment click no-ops in combat and the panel open names the way back; slash state changes stay allowed and everything works again after.
- Settings are data and apply live; the toggle installs or removes the send wrapper.
- Before any commit: `lua tests/run.lua`, `luacheck .`, and
  `stylua --check .` all pass.
