# VocSpeak

Roleplay speaking for World of Warcraft: Forever. Outgoing `/say`
and `/yell` are rewritten in a dwarven or troll dialect before they
send, through a wrapper on the documented send call
(`C_ChatInfo.SendChatMessage`). Emotes never change, and a `((`
prefix marks out-of-character and stays as typed.

Graduated from VocUI's chat module: the same engine, the same two
dialect tables (rebuilt in the Ironforge and Darkspear registers
from the 2007 Dwarvenizer/Trollizer tables, MIT, Carlo Zottmann),
now standing alone with its own settings page, slash, and saved
variables. The VocUI module is gone; this addon is where the voice
lives. State does not migrate: a fresh install speaks dwarven at
  chance 8 (troll for troll characters, restored on login),
one slash away from the other or silence.

## Use

- `/vs` turns the dialect filter on or off
- `/vs dwarf|troll` speaks dwarven or troll
- `/vs chance <0-10>` how often the dialect rewrites words
- `/vs toggle <say|yell>|list` chooses which channels change
- `/vs config` opens Settings > AddOns > VocSpeak
- `/vs help` lists the rest (`/vocspeak` works too)

Settings > AddOns > VocSpeak carries the same rows: the toggle, the
dialect, the chance slider, and the channel checkboxes.

## What this is not

- Not a retail addon. Forever only, like the VocUI module it
  graduated from.
- Not a chat frame. It rewrites what you send; it never touches how
  chat looks, and replacement chat frames need no integration.

## Status

The headless suite (`lua tests/run.lua`) pins the engine, the gate,
the hook, the slash, and the panel. `luacheck .` and
`stylua --check .` pass.

---

Built for Forever, for one player, by vocino.
