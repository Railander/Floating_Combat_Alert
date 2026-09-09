# Floating Combat Alert

Super lightweight WoW addon that shows floating text above the player when entering or leaving combat. No libraries, no Ace, one Lua file.

Target client: Midnight 12.1 (`## Interface: 120100` in the .toc — bump it if the client complains the addon is out of date).

## Features

- Floating "Entering Combat" (red) / "Leaving Combat" (green) text driven by the player unit's combat state, with two redundant triggers: `PLAYER_ENTER_COMBAT`/`PLAYER_LEAVE_COMBAT` plus `UNIT_FLAGS` transitions checked against `UnitAffectingCombat("player")` — deliberately not the regen lockout (regen lags real combat state and can keep running in combat, e.g. troll racial)
- **Concurrent messages**: a new combat message spawns its own floating text and never replaces an in-flight one — rapid transitions leave multiple texts floating through the band at once (capped at 8; duplicate triggers for the same transition never double-spawn)
- The text is fully bound inside the configurable on-screen **region**: its bottom edge starts at the region's bottom and its top edge ends at the region's top, fading as it goes
- `/fca` opens a small drag-and-drop options window. While it is open a test loop alternates both alerts, each entering while the previous is at 80% of its travel so the texts chain with a slight overlap; closing the window stops the loop and despawns its text (real combat alerts are unaffected)
  - Both alert columns (Entering / Leaving) are always visible side by side, with a **Link checkbox column** on the left — one checkbox per setting (font, size, color, outline, text). Linked settings edit both alerts at once; unlinked ones edit only their column
  - **Link defaults**: font/size/outline/text linked; **color unlinked** (entering = red, leaving = green)
  - **Font**: real dropdown of the seven western typefaces the game ships — Friz Quadrata (latin/cyrillic), Arial Narrow, Morpheus (latin/cyrillic), Skurri (latin/cyrillic) — each name rendered in its own font. Candidates are validated at load against the actual client, so only fonts that exist and load appear. (The CJK locale families are excluded on purpose: their Latin glyphs fall back to the default font, making them pointless here.)
  - **Size**: numeric text box — type any value and press enter
  - **Color**: color picker, per alert
  - **Outline**: dropdown (None / Thin / Thick) — the client's `SetFont` API only exposes these two outline weights
  - **Text**: per-alert text box replacing the default "Entering Combat"/"Leaving Combat"
  - **Direction**: does the text travel up or down the band
  - **Duration**: seconds between spawning and despawning, per alert
  - **Fade start**: percent of the duration at which the constant fade-out begins (50 = opaque for the first half then a steady fade; 0 = fades the whole time; 100 = never fades)
  - **Move region**: semi-transparent overlay of the travel band, sized horizontally to hug the widest of the two alert texts (grows/shrinks with font, size and text changes, including the bigger side after unlinking). Drag the top/bottom green edges (50% alpha) to set the walk distance, drag the middle to move it anywhere. The four coordinate values are plain clickthrough text readouts (relative to screen center, positive Y up): left/right show the derived band edges, top/bottom show the Y values the handles set
- The config window position persists across sessions (defaults to screen center); no alert plays on login
- The color picker opens above all addon windows and can be dragged by its header
- Style/size/color/appearance/text/direction/duration/fade changes restyle an already-flying alert immediately, resuming from its current position and alpha — nothing restarts or jumps; no need to wait for the next alert

## Slash commands

| Command | Effect |
| --- | --- |
| `/fca` (or anything unrecognized) | Open/close the options window |
| `/fca test in` / `/fca test out` | Preview the enter/leave alert |
| `/fca region` | Toggle the region editor |
| `/fca duration <sec>` | How long each alert stays on screen |
| `/fca reset` | Restore all default settings (window re-centers too) |

## Installing in the game client

Copy this folder into the client's `Interface/AddOns` directory (only `Floating_Combat_Alert.toc` and `Floating_Combat_Alert.lua` are loaded in game; `tests/` is inert) and `/reload`.

## Testing outside the game

The test suites run in plain Lua against a shared mock client at `../shared/wow_test_env.lua` — no game client needed. They run under **`lua5.1`** (installed on this machine), which shares the WoW client's exact interpreter semantics.

```bash
lua5.1 tests/test_fca.lua    # unit tests: schema + v1 migration, combat events, window, link mode, menus, color picker, region editor, reload, resilience
lua5.1 tests/sim_12_1.lua    # 12.1 lifecycle sim: login -> pull -> kill -> twitching -> regen ignored -> options -> region editing -> /reload
```

## Files

```
Floating_Combat_Alert.toc      addon manifest (interface, deps, SavedVariables)
Floating_Combat_Alert.lua      all addon code
tests/test_fca.lua             unit test suite
tests/sim_12_1.lua             full combat lifecycle simulation
../shared/wow_test_env.lua     shared mock WoW client (used by the test suites)
../AGENTS.md                   workspace guide for agents/sessions
```

## Saved variables

`Floating_Combat_Alert` (per-account): `link {font, size, color, outline, text, direction, duration, fade}`, `win {x, y}`, `region {cx, y1, y2}` (center x, bottom/top edges — width derives from the text), and `enter`/`leave` each with `text`, `color`, `font`, `size`, `outlineStyle`, `direction`, `duration`, `fadeStart`. Defaults: size 28 Friz Quadrata, enter red / leave green, direction up, duration 2s, fade start 50%, travel band centered on screen center (-100 to +100). Missing keys are backfilled from defaults on login, and older profiles (flat v1, boolean-appearance v2, single `linked` bool, global `duration`) are migrated automatically, so upgrades never wipe existing configs.
