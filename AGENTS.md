# AGENTS.md

## Code Map

- `VocSpeak.toc` - Forever client metadata (Interface 16001)
- `main.lua` - the addon: saved variables, send wrapper, settings page, slash, compartment, boot
- `Dialect.lua` - the dialect engine: pure text in, mangled text out
- `Dictionaries.lua` - the dwarven and troll tables (MIT, attributed in the file)
- `tests/` - headless tests (`lua tests/run.lua`)

## Conventions

- Forever only: verify every API against the Forever build, Lua 5.1, no deprecated globals.
- State lives only in `VocSpeakDB`. A fresh install speaks dwarven at chance 8 (troll for troll characters, restored on login).
- Settings are data and apply live; the toggle installs or removes the send wrapper.
- Before any commit: `lua tests/run.lua`, `luacheck .`, and
  `stylua --check .` all pass.
