# Old Interface

A RuneScape 3 plugin that brings back the blue interface from before the overhaul on 19 January 2026. It draws the old window art in place of the new brown one.

**Work in progress.** This is a proof of concept: it covers the parts that can be swapped cleanly, and leaves the rest as it is.

## What it changes

- **Docked windows**: the frames, headers and backgrounds of the windows you dock around the game screen (Skills, Friends, Chat, Worn Equipment and so on), and windows built from the same pieces, like the Bank.
- **Every window's background**, including big windows like Settings, the Bank's item area, and windows made by other plugins.
- **Window contents**: buttons, tabs, list rows, dropdowns, checkboxes, input boxes, sliders and scrollbars, including the newer controls in windows like Settings' Gameplay tab.
- **Colours**: plain coloured panels, like the cards in Settings' lists, get the old blue.
- **Tooltips.**

It turns on when the plugin loads, and the game's own look comes back when the plugin is turned off. The swapped parts are split into groups (see [`src/game/sprite_groups.lua`](src/game/sprite_groups.lua)), ready to be turned on and off separately.

## What it leaves alone, and why

- **The frames of big windows** like Settings. Their old images are a different size from the new ones, and swapping them breaks the layout. Backgrounds are fine everywhere, as the game tiles or stretches them to fill whatever space there is.
- **Parts added after the overhaul**, which have no old version, like the search box in Settings. Where the game's mobile version still has the old look, that's used instead (Settings' category headers).
- **Text colours**, for now.

## How it works

Plugins can't replace a game image everywhere at once, only on each part of a window. So the plugin keeps walking the game's open windows, a slice every client update, and swaps the images it has an old version of. Windows that just opened or were just shown are walked first. Parts it has already swapped are checked again just before every frame is drawn, so when the game rebuilds them (like the tab bar when switching tabs) or changes their state (like hovering a button), they don't flash.

The old images are in [`resources/frames/`](resources/frames), each named after the game sprite it replaces. They come from a game cache from before the overhaul (cache 2409 in the [OpenRS2 archive](https://archive.openrs2.org/)), and some are stretched by a pixel or two to fit the current sprites' sizes. The old colours come from the game's own skin colour lists: the mobile skin still has them.

## Known issues

- A window can show the new look for a moment the first time it opens, until the plugin gets to it.
- New images in `resources/` only load after restarting the game client, not when reloading the plugin.

## Building

`./build.sh` copies the plugin into `Old-Interface/`. `./build.sh release` makes a release build and zips it into `Old-Interface.zip`. To also copy dev builds into the game's `dev_plugins` folder, create `build.local.sh` (gitignored) with:

```bash
dev_plugins_dir="$HOME/path/to/RuneScape-BETA/dev_plugins"
```
