# UI playground

A Studio place that renders the real UrkUI game layer: the screen specs in
`src/UI/Spec/Screens/` through `Spec/Builder`, the Game components, the icon catalogue, the motion
presets and the styles. Use it to look at a spec before you ship it, to try component props live,
and to check a style.

| Page | Shows |
|---|---|
| Shop demo | `PetSimShop` built by Builder |
| Premium store | `PremiumStore` |
| HUD demo | `MainHud`: rails in the safe area, cash and level bound to the store and ticking |
| Inventory demo | `Inventory` |
| Daily rewards | `DailyRewards` |
| All screens | a button per `Screens/*.json`; builds any of the 16 |
| Icon gallery | every icon, glyph and `-color` side by side, search box (names and tags), tint swatches for the glyphs |
| Animation gallery | a button per `MotionPresets.names()` playing on a sample ProductCard (`Motion.play`), plus Stop |
| Components | each Game component with a small inspector: text boxes for strings and numbers, buttons that flip booleans and cycle options, all calling `:update` |
| Theme preview | a button per `Style.names()`; sets `Style.setDefault` and rebuilds the shop (other pages then use that style) |

The strip under the stage logs intents: `UrkUI.Intent` (purchases raised by the components) and each
screen's `Intent` (Select, Change, Close). Nothing is ever granted; the playground has no server
code.

## Files

| File | Purpose |
|---|---|
| `playground.project.json` | Rojo project: `src/` as `ReplicatedStorage.UltimateRobloxKit`, the script in `StarterPlayer.StarterPlayerScripts` |
| `Playground.client.luau` | The LocalScript (`UrkPlayground`) |

## Preview in Studio

From the repository root, with the pinned tools installed (`rokit install` in `library/`):

```bash
rojo serve library/examples/playground/playground.project.json
```

The project file lives in this folder (not `library/`) so it stays with the example; the paths in it
are relative to this folder (`../../src`).

1. Open Roblox Studio and create a new Baseplate place (or open a scratch place). Do not use a
   published game: the playground adds a full-screen ScreenGui.
2. Install the Rojo Studio plugin if you do not have it (Plugins tab, or the Rojo releases page).
3. In the Rojo plugin, press **Connect** (default `localhost:34872`). Studio now has
   `ReplicatedStorage.UltimateRobloxKit` and `StarterPlayer.StarterPlayerScripts.UrkPlayground`, and
   edits to the files sync live.
4. Press **Play** (F5). The playground opens on the shop demo. Switch pages in the left column.
5. Icons need their sprite sheets uploaded and configured (`Icons.configure({ sheets = { ... } })`);
   without that the icon slots stay empty and Icons warns once per sheet. Everything else renders.

To build a place file instead of serving: `rojo build library/examples/playground/playground.project.json -o playground.rbxl`.

Insert a single screen into your own game instead: build `library/default.project.json` into a model,
put it in `ReplicatedStorage` as `UltimateRobloxKit`, and call `Builder.build` from a LocalScript as
shown in `src/UI/Spec/README.md`.

## Status

This playground has **not been run in Studio** in this repository's automated checks. CI runs Selene
and StyLua over it, and the specs it renders are validated by Lune tests, but layout, motion and the
look of each page need a manual playtest. Pages build inside `pcall`, so a component that is missing
or fails shows its error on the stage instead of stopping the playground. Known gaps to check:
`Dropdown` and `RewardPopup` may not exist yet in `src/UI/Game/` (the Components and All screens pages
say so when they are missing).
