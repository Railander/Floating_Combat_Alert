# Floating Combat Alert

A super lightweight World of Warcraft addon that shows floating text when you enter or leave combat.

## Usage

Type `/fca` to open the options window. While it's open, the two alerts preview in an endless loop; closing the window stops it.

Every setting — text, color, font, size, outline, direction, duration, fade start — is editable per alert, or linked across both. `Move region` opens an overlay of the travel band: drag the middle to move it, drag the top/bottom edges to resize.

| Command | Effect |
| --- | --- |
| `/fca` | Open/close the options window |
| `/fca test in` / `/fca test out` | Preview the enter/leave alert |
| `/fca region` | Toggle the region editor |
| `/fca duration <sec>` | How long each alert stays on screen |
| `/fca reset` | Restore all default settings |

## Details

- Rapid combat transitions leave multiple texts floating at once (capped at 8); duplicate triggers never double-spawn.
- Motion and fading run on the client's animation engine — no polling, zero per-frame Lua work.
- Settings changes apply instantly to in-flight text without restarting it.
- Combat state uses `PLAYER_ENTER_COMBAT`/`PLAYER_LEAVE_COMBAT` with `UNIT_FLAGS` as fallback — not the regen lockout, which lags real combat.
- No libraries, one Lua file. Settings persist per account; old profiles migrate automatically.

## Compatibility

WoW Midnight (12.x).

## License

GNU General Public License v2.0. See [LICENSE](LICENSE) for details.
