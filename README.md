# VocSpeak

Roleplay speaking for World of Warcraft: Forever and Midnight
(retail). Outgoing `/say` and `/yell` are rewritten in the chosen
dialect (dwarven, troll, or none) before they send, through the
edit box's pre-send event (`ChatFrame.OnEditBoxPreSendText`,
fired on both branches). Emotes never change, and a `((`
prefix marks out-of-character and stays as typed.

Graduated from VocUI's chat module: the same engine, the same two
dialect tables (rebuilt in the Ironforge and Darkspear registers
from the 2007 Dwarvenizer/Trollizer tables, MIT, Carlo Zottmann),
now standing alone with its own settings page, slash, and saved
variables. The VocUI module is gone; this addon is where the voice
lives. State does not migrate: a fresh install speaks dwarven at
  chance 8 (troll for troll characters, none for other races,
  restored on login and on character switch), one slash away from
  any of them.

## Use

- `/vs` turns the dialect filter on or off
- `/vs dwarf|troll|none` speaks dwarven, troll, or leaves chat as typed
- `/vs chance <0-10>` how often the dialect rewrites words
- `/vs toggle <say|yell>|list` chooses which channels change
- `/vs config` opens Settings > AddOns > VocSpeak
- `/vs help` lists the rest (`/vocspeak` works too)

Settings > AddOns > VocSpeak carries the same rows: the toggle, the
dialect, the chance slider, and the channel checkboxes.

## What this is not

- Not a chat frame. It rewrites what you send; it never touches how
  chat looks, and replacement chat frames need no integration.

## Status

The headless suite (`lua tests/run.lua`) pins the engine,
the gate, the pre-send edit, the slash, the panel, and the robustness
contract: Forever + Midnight flavor reads, data-not-loaded retries,
secret fail-open, combat no-op and recovery, login/reload/saved-data,
character/zone/group handling. `luacheck .` and `stylua --check .`
pass.

---

Part of the Voc family: tiny addons that do one job.
[VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear) ·
[VocXP](https://github.com/vocino/vocxp) ·
[VocVendor](https://github.com/vocino/vocvendor) ·
[VocSpeak](https://github.com/vocino/vocspeak)

Built for Forever and Midnight, for one player, by vocino.
