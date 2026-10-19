# Floating Combat Alert Changelog

## Unreleased

- The travel region editor and the configuration window now move the moment you press the mouse button, with no dead zone before they start following the cursor.

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
