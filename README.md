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

Open the plugin's page with its icon in the ribbon, and press **Open settings**. The settings are in a window of their own, which you can move and resize, so you can see the interface change behind it. It has three tabs: Look, Colours and Text. Under **Look**, each part can be turned on and off, and changes show right away:

- **Window frames**: the frames, title bars and tabs of windows.
- **Window backgrounds**: window backgrounds, and the coloured panels in their lists.
- **Buttons and controls**: buttons, dropdowns, list rows, checkboxes, input boxes, sliders and scrollbars.
- **Text colours**: turn this off to keep the new text colours, which some find easier to read.

Below those, **Textured panels** chooses between the two looks the Bank had before 2026. Off, its item area and the panels like it are the plain blue they were from 2019 on. On, they show the window's own texture, as before 2019.

The **Colours** tab has the **colour scheme**. Classic blue draws the old interface as it was. DarkScape draws DarkScape's own interface (2015-16): its versions of the old pieces (`resources/frames_darkscape`, made by `tools/frames/update_darkscape.sh` from its last cache), with the main game's buttons and controls, which it kept. The few pieces it had no version of are tinted to match. The others (Crimson, Emerald, Amethyst, Bronze, Teal, Steel) draw it in one colour: the plugin draws grey copies of the old images (`resources/frames_tintable`, made by `tools/frames/make_tintable.cjs`) and has the game tint them, so the gold and red details take the scheme's colour too. Panels and blue-grey text follow the scheme; gold headings stay gold (see [`src/game/colour_scheme.lua`](src/game/colour_scheme.lua)).

Choosing **Custom** shows its colour to pick. Below the scheme, under **Your own colours**, any part of the interface can have a colour of your own in whichever scheme is chosen: window frames, title bars, tabs, backgrounds, dropdowns, checkboxes and radio buttons, scrollbars, sliders, list rows and input boxes, buttons, and the close and +/- buttons. Pick a colour or type its hex value (like `#4A87FF`) and press Enter; clear a part's value and press Enter to go back to the scheme's. Which images belong to which part is decided by their names (see `colour_parts` in [`src/game/sprite_groups.lua`](src/game/sprite_groups.lua)), and an image has one colour, so a corner piece with an ornament on it is coloured as a whole.

In the **Text** tab you can pick your own colour for headings (gold in the old look) and for other text (blue-grey), in any colour scheme; a button goes back to the scheme's own. They only apply while the Text colours option is on in the Look tab.

Each option covers a few groups of the game's images (see [`src/game/sprite_groups.lua`](src/game/sprite_groups.lua)). The plugin depends on the [prettyui](https://prettyui.j3.gg/) plugin for its page and settings window (see `plugin.json`).

## What it leaves alone, and why

- **Parts added after the overhaul**, which have no old version, like the search box in Settings. Where the game's mobile version still has the old look, that's used instead (Settings' category headers).
- **Text in other colours**, like green or red status text and item names. Only the colours from the game's skin are changed.

## How it works

Plugins can't replace a game image everywhere at once, only on each part of a window, and the game has no event for a window opening. So before each frame the plugin looks for what's new: every interface is checked for having loaded or started showing (that's cheap), and one that has is walked right away, and again every update for a moment while the game fills it in. Hidden parts of a window are skipped along with everything inside them. A slower pass over everything that's showing, and a slower one still over everything, catch the rest. Parts it has already swapped are checked again after each game update, so when the game rebuilds them (like the tab bar when switching tabs) or changes their state (like hovering a button), they don't flash.

The old images are in [`resources/frames/`](resources/frames), each named after the game sprite it replaces. They come from a game cache from before the overhaul (cache 2409 in the [OpenRS2 archive](https://archive.openrs2.org/)), and some are stretched by a pixel or two to fit the current sprites' sizes. Big windows' frames, tabs and title banners are also cut to the current pieces' shapes, as the old ones were drawn for a different window layout. The old colours come from the game's own skin colour lists: the mobile skin still has them.

The code, in the order it's easiest to read:

| File | What it does |
|---|---|
| [`main.lua`](main.lua) | Starts the swapping with the saved settings, and the plugin's page |
| [`src/game/sprite_groups.lua`](src/game/sprite_groups.lua) | Which game sprites are swapped, in groups, and which part of the interface each belongs to |
| [`src/game/colour_scheme.lua`](src/game/colour_scheme.lua) | The colour schemes, and the colour arithmetic |
| [`src/game/sprite_images.lua`](src/game/sprite_images.lua) | Which image, and which tint, each game sprite gets in the chosen scheme |
| [`src/game/sprite_swapper.lua`](src/game/sprite_swapper.lua) | Swaps the sprites, and keeps them swapped when the game sets its own again |
| [`src/game/recolourer.lua`](src/game/recolourer.lua) | The same for plain colours: panels and text |
| [`src/game/interface_watcher.lua`](src/game/interface_watcher.lua) | Decides which components to look at when, so new windows are caught before they're drawn |
| [`src/game/interface_walker.lua`](src/game/interface_walker.lua) | Goes through an interface's components |
| [`src/game/component_fields.lua`](src/game/component_fields.lua), [`game_ids.lua`](src/game/game_ids.lua), [`skin_palette.lua`](src/game/skin_palette.lua), [`guard.lua`](src/game/guard.lua) | Small helpers: reading and writing components, IDs by name, the game's own old colours, keeping an event handler alive after an error |
| [`src/interface/`](src/interface), [`src/database/settings.lua`](src/database/settings.lua) | The plugin's page, the settings window, and the saved settings |
| [`src/debug/`](src/debug) | Tools for developing: what the swapping does and costs, printed to the console. Left out of release builds. Switched on from `main.lua` (see [`src/debug/events.lua`](src/debug/events.lua)) |

## Known issues

- Parts that turn up in a window that's been open a while (like rows when scrolling a long list, or the first plugin window opened) can show the new look for a few frames.
- New images in `resources/` only load after running `prf` in the game's console or restarting the client, not when reloading the plugin.

## Testing

The tests run the plugin's Lua outside the game, against a fake of the parts of the game's API it uses (see [`tests/`](tests)). They need Node.js:

```bash
cd tests && npm install && npm test
```

## Building

`./build.sh` copies the plugin into `Old-Interface/`. `./build.sh release` makes a release build and zips it into `Old-Interface.zip`. Release builds leave out the debug tools in `src/debug`. To also copy dev builds into the game's `dev_plugins` folder, create `build.local.sh` (gitignored) with:

```bash
dev_plugins_dir="$HOME/path/to/RuneScape-BETA/dev_plugins"
```
