# Old Interface

A RuneScape 3 plugin that brings back the blue interface from before the overhaul on 19 January 2026. It draws the old window art in place of the new brown one.

**Work in progress.** This is a proof of concept: it covers the parts that can be swapped cleanly, and leaves the rest as it is.

## What it changes

- **Docked windows**: the frames, headers and backgrounds of the windows you dock around the game screen (Skills, Friends, Chat, Worn Equipment and so on), and windows built from the same pieces, like the Bank.
- **Big windows** like Settings and plugin windows: the frame and title banner.
- **Plugins' windows**, like Area Names' settings: the frame, title bar and close button, and the frames round their boxes.
- **The Bank**: its window frame and title bar, the frames around the item area and side panels, and the bank tabs.
- **Every window's background**, including big windows like Settings, the Bank's item area, and windows made by other plugins.
- **Window contents**: buttons, tabs, list rows, dropdowns, checkboxes, input boxes, sliders and scrollbars, including the newer controls in windows like Settings' Gameplay tab.
- **Colours**: plain coloured panels, like the cards in Settings' lists, get the old blue.
- **Text colours**: headings, descriptions and button text get the old colours, in plugins' windows too.

It turns on when the plugin loads, and the game's own look comes back when the plugin is turned off.

## Settings

Open the plugin's settings with the gear on its row in the Plugin Hub's Manage tab. Each part can be turned on and off, and changes show right away:

- **Window frames**: the frames, title bars and tabs of windows.
- **Window backgrounds**: window backgrounds, and the coloured panels in their lists.
- **Buttons and controls**: buttons, dropdowns, list rows, checkboxes, input boxes, sliders and scrollbars.
- **Text colours**: turn this off to keep the new text colours, which some find easier to read.

Each option covers a few groups of the game's images (see [`src/game/sprite_groups.lua`](src/game/sprite_groups.lua)). The plugin depends on the [prettyui](https://prettyui.j3.gg/) plugin for its settings page (see `plugin.json`).

## What it leaves alone, and why

- **Parts added after the overhaul**, which have no old version, like the search box in Settings. Where the game's mobile version still has the old look, that's used instead (Settings' category headers).
- **Text in other colours**, like green or red status text and item names. Only the colours from the game's skin are changed.

## How it works

Plugins can't replace a game image everywhere at once, only on each part of a window. So the plugin keeps walking the game's open windows, a slice every client update, and swaps the images it has an old version of. Windows that just opened or were just shown are walked first. Parts it has already swapped are checked again just before every frame is drawn, so when the game rebuilds them (like the tab bar when switching tabs) or changes their state (like hovering a button), they don't flash.

The old images are in [`resources/frames/`](resources/frames), each named after the game sprite it replaces. They come from a game cache from before the overhaul (cache 2409 in the [OpenRS2 archive](https://archive.openrs2.org/)), and some are stretched by a pixel or two to fit the current sprites' sizes. Big windows' frames, tabs and title banners are also cut to the current pieces' shapes, as the old ones were drawn for a different window layout. The old colours come from the game's own skin colour lists: the mobile skin still has them.

## Known issues

- A window can show the new look for a moment the first time it opens, until the plugin gets to it.
- New images in `resources/` only load after running `prf` in the game's console or restarting the client, not when reloading the plugin.

## Testing

The tests run the plugin's Lua outside the game, against a fake of the parts of the game's API it uses (see [`tests/`](tests)). They need Node.js:

```bash
cd tests && npm install && npm test
```

## Building

`./build.sh` copies the plugin into `Old-Interface/`. `./build.sh release` makes a release build and zips it into `Old-Interface.zip`. To also copy dev builds into the game's `dev_plugins` folder, create `build.local.sh` (gitignored) with:

```bash
dev_plugins_dir="$HOME/path/to/RuneScape-BETA/dev_plugins"
```
