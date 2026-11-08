# Floating Combat Alert Changelog

## v1.2.4 (2026-11-08)

- Fixed: a damaged saved position, or an unreadable mouse position during a drag, could make the travel region or the configuration window disappear and stay broken across sessions. Such values are now ignored: the last good position is kept, and a damaged saved position is repaired to a usable one (a readable center is kept).
- Fixed: a damaged saved setting, such as a travel region with only one corner or a size that is not a number, could stop every alert; these values now fall back to what the configuration window allows.
- Fixed: closing the window in the middle of a drag could leave the travel region following the mouse afterwards, and `/fca reset` during a drag could be overwritten by the stale drag.
- Fixed: when the travel region was shorter than the alert text, the text moved against the direction you picked.
- Fixed: an old profile's alert duration now carries over instead of falling back to two seconds.
- Fixed: the color picker window is shared with other addons. Opening it from Floating Combat Alert no longer takes over its drag behavior, and it returns to its normal layer when it closes. It still moves by its title bar.
- Typing text that is not a real number (such as `nan` or `inf`) into a numeric box no longer changes its setting.

## v1.2.3 (2026-10-19)

- The download is about 7 times smaller (0.5 MB instead of 3.5 MB). The fonts that come with the addon now hold only the letters of English and other Western European languages, accents included, and look exactly as before. Text in other alphabets, such as Cyrillic, shows as boxes in these fonts. The game's own fonts are unchanged.
- PT Sans Narrow, PT Sans Narrow Bold, Carlito and Gentium Plus are now called Narrow Sans, Narrow Sans Bold, Humanist Sans and Book Serif, as their licence requires for trimmed copies. If your alert used one of them, it keeps that font under its new name.
- The font list drops Friz Quadrata Cyrillic and Skurri Cyrillic, which look the same as Friz Quadrata and Skurri in English. If you had picked one of them, your alert switches to its look-alike.

## v1.2.2 (2026-10-19)

- The travel region editor and the configuration window now move the moment you press the mouse button, with no dead zone before they start following the cursor.
- Picking a new font now applies it on the first try. Before, the first pick of a font that comes with the addon showed blank text in the font menu and changed nothing in the preview.
- Each entry in the font menu is now drawn in its own font, so you can compare fonts without picking them.
- Fonts shared by other addons whose file is missing no longer appear in the font menu. If your alert used a font from an addon you have since removed, it switches to Friz Quadrata.
- The font list drops 2002, AR Zhongkai and AR Zhongkai Combat, which look the same as Friz Quadrata in English. If you had picked one of them, your alert switches to Friz Quadrata.

## v1.2.1 (2026-10-18)

- The font list drops 2002 Bold, Morpheus Cyrillic and AR Crystalzcuhei: in English they look the same as Friz Quadrata, Morpheus and AR Zhongkai. If you had picked one of them, your alert switches to its look-alike.

## v1.2.0 (2026-10-18)

- More fonts: Nimrod MT, 2002, 2002 Bold, MoK, AR Crystalzcuhei, AR Zhongkai and AR Zhongkai Combat join the font list.
- 16 new fonts come with the addon: PT Sans Narrow, PT Sans Narrow Bold, Fira Sans Medium, Fira Sans Black, Fira Sans Condensed Medium, Fira Sans Condensed Black, Fira Mono Medium, Oswald, Noto Sans Medium, Noto Sans SemiCondensed, Carlito, Gentium Plus, Francois One, DejaVu Sans, DejaVu Serif and Hack. Their licences are included in the Fonts folder.
- The font list scrolls.
- Fonts your other addons share with the rest of your UI (the same extra fonts most popular addons let you pick) now appear in the font list too, after the built-in ones.
- If the addon that provided your chosen font is removed, the alert falls back to Friz Quadrata instead of showing an error.

## v1.1.3 (2026-10-15)

- The addon now works in World of Warcraft: Midnight (12.1.5).

## v1.1.2 (2026-09-30)

- The travel region editor's yellow zone now renders below the floating text.
- Combat alerts now follow your actual combat state instead of your melee swings: "Leaving Combat" no longer appears while you are still fighting (for example when your target dies mid-pull or you stop attacking between casts), and starting a fight with spells or by taking aggro now shows "Entering Combat".

## v1.1.1 (2026-09-20)

- Tidier options window: every setting lines up in even rows and columns, with dividers marking the Link, Entering and Leaving sections and all three headers sharing one row.
- The travel region editor (`move region`) is now a plain yellow zone without the rounded border.
- The font list reads cleaner, and long font names shrink to fit inside their boxes instead of getting cut off.
- Long alert texts shrink while you type so they stay visible inside the text box.

## v1.1.0 (2026-09-19)

- The addon now works in World of Warcraft: Forever (beta).

## v1.0.1 (2026-09-12)

- Everything keeps working while fighting: entering/leaving combat alerts, every options-window setting, the travel region editor, the color picker and `/fca reset` all behave normally mid-combat and in Mythic+ / rated PvP, with no errors.
- Existing settings carry over automatically.

## v1.0.0 (2026-09-09)

- First release.
- Floating "Entering Combat" / "Leaving Combat" text when your combat state changes; rapid transitions leave several texts floating at once.
- `/fca` options window: text, color, font, size, outline, direction, duration and fade start, editable per alert or linked across both.
- Settings apply instantly, even to text already on screen.
- Draggable, resizable travel region via the `move region` button.
- `/fca reset` restores the default settings.
