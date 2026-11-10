# Visuals.Icons

Registry and helpers for icon packs imported with `tools/icons/vault.py` (see [the import workflow](../../../../docs/workflows/icon-pack-import.md)). The game receives a data module with names, categories, tags, sizes and Roblox asset ids. The image files stay in the private vault and are never modified.

No pack ships with the kit, and the owner's paid pack has not been imported yet. Until a pack is registered, every call falls back to the kit's own `Icons` module.

| File | Role |
|---|---|
| `IconVaultLogic.luau` | pure registry: validation, name resolution, search, filters, asset ids, sheet rects, picker grid maths. Spec: `library/tests/visuals_icons.spec.luau` |
| `IconVault.luau` | Roblox side: apply, create, themed container, animated container, picker, UrkUI bridge |

## API

Reached as `Visuals.Icons` (both `Icons.apply(...)` and `Icons:Apply(...)` work through the facade).

| Function | Result |
|---|---|
| `register(pack, data, options?)` | registers the generated module's table; returns the icon count. Raises on invalid data and registers nothing. `options.override` replaces a pack, `options.default` makes it the default |
| `configure({ defaultPack?, assetIds?, sheets? })` | default pack, asset ids per pack, sheet ids per pack |
| `apply(label, name, options?) -> boolean` | sets `Image` (and `ImageRectOffset` / `ImageRectSize` for sheet icons). Falls back to the kit `Icons` module when the name is not a pack icon |
| `create(name, options?) -> ImageLabel` | a new 24 px label |
| `container(name, options?) -> Container` | themed tile: rounded background, gradient and outline from the active UrkUI style |
| `animated(name, presetId?, options?) -> Container` | a container whose Frame plays a `Visuals.UI` preset; `options.bind` adds hover / press states |
| `picker(props) -> Picker` | search box, category tabs, virtualised scrolling grid |
| `bridge() -> undo` | makes pack icons usable by name in UrkUI components and screen specs |
| `refresh()` | restyles every live container after a style or theme change |
| `has`, `get`, `search`, `categories`, `list`, `autocomplete`, `packs`, `info`, `assetId`, `missingAssetIds`, `setAssetIds`, `setSheetIds`, `setDefaultPack`, `defaultPack`, `unregister` | registry queries, see `IconVaultLogic.luau` |

Names: `"pack:name"` is exact. A bare `"name"` is looked up in the default pack (the first registered unless set), then the other packs, then the kit icons. `"Arrow Left"`, `"arrow_left"` and `"arrowLeft"` all resolve to `arrow-left`. Lists returned by `search`, `list` and `autocomplete` hold qualified ids.

Search ranking: exact name 100, name prefix 60, whole word in the name 50, substring 40, tag 30, tag prefix 20, category 10. Ties go to the default pack, then alphabetical.

### Options

`apply` / `create`: `size` (pixels), `tint` (recolours any icon), `color` (kit glyphs only), `transparency`, `style` (kit icons: `"glyph"` or `"color"`).

`container` / `animated`: `size` (default 64), `padding` (fraction around the icon, default 0.16), `palette` or `surface` (default `"inset"`), `gradient` (default true), `stroke` (default true), `outline` (default `"thin"`), `radius` (token, default `"md"`; `"pill"` is a circle), `button`, `style`, `tint`, `color`, `iconStyle`, `parent`, `name`, `layoutOrder`, `position`, `anchor`, and for `animated`: `animation` (options for `UI.animate`) and `bind` (`true` or a bind style name).

A container has `Instance`, `Icon`, `setIcon(name)`, `restyle(styleName?)`, `stop()` / `cancel()` and `destroy()`. Stopping or destroying twice is harmless, and destroying the Instance from outside cleans the container up.

`picker`: `parent` (required), `title`, `pack`, `category`, `query`, `cell` (default 76), `gap` (default 8), `size` (default 560 x 440), `position`, `anchor`, `style`, `closeOnPick`, `onPick(id, entry)`. It returns `Instance`, `Picked` (Signal), `setQuery`, `setCategory`, `refresh`, `selected`, `destroy`.

## Colours and theming

Pack icons are multi-colour artwork, so `apply` leaves `ImageColor3` white (no tint) unless `options.tint` is given. A theme changes the container around the icon, never the icon. `options.color` is passed only to the kit's white glyphs, which are made to be tinted.

## Example

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local Icons = Visuals.Icons

Icons.register("mypack", require(ReplicatedStorage.Shared.MypackIcons))
Icons.bridge()

local tile = Icons.container("mypack:sword", { size = 72, palette = "purple", parent = row })
local gem = Icons.animated("mypack:gem", "Pulse", { parent = hud })

for _, name in Icons.missingAssetIds("mypack") do
	warn("not uploaded yet:", name)
end
```

## UrkUI and screen specs

UrkUI components (through `UI/Runtime/IconBridge`), the Game components and the UI generator's `Builder` all show icons by calling the kit module `Icons/Icons`, and screen specs are validated with `SpecSchema.isIcon`. None of those has a registration hook, so `Icons.bridge()` wraps `Icons.apply`, `Icons.has`, `Icons.get` and `SpecSchema.isIcon` on the loaded module tables at run time. No file is edited, and `bridge()` returns a function that restores the originals.

- `"pack:name"` always shows the pack icon.
- A bare name shows the kit icon when the kit has one, otherwise the pack icon.
- Every other name behaves as before.
- The colour UrkUI passes for glyphs is ignored for pack icons.

Limits: the Python spec validator (`tools/ui/spec_rules.py`, used by `urk.py ui validate` and the preview renderer) does not know about pack icons and reports `icon = "pack:name"` as an unknown icon. Code that captured `Icons.apply` in a local before `bridge()` ran keeps the old function; the kit's own callers look it up on each call.

## Performance

- Lookup is a table index per pack. Search is a linear scan (800 icons: a few thousand string comparisons per query).
- The picker is virtualised: only cells in the rows near the viewport exist, and they are recycled while scrolling.
- Individually uploaded icons are one image request each. Sprite sheets (`vault.py derive --sheets`) cut that to one request per sheet at the cost of a fixed cell size.
- Containers do no per-frame work. `animated` runs through the UI animation library, which uses the shared `Host.clock`.

## Not verified in Studio

`IconVault.luau` creates Instances and was NOT run in Studio: `apply`, `container`, `animated`, `picker` and `bridge` are `NEEDS MANUAL REVIEW`. `animated` depends on `Visuals/UI/UIAnimations` (`animate`, `bind`); when that module cannot be loaded the container is returned without animation and a warning is printed once. Checked here: StyLua, Selene, `luau-lsp` with Roblox type definitions, and the Lune spec for `IconVaultLogic`.
