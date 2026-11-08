# __GAME_NAME__

Made from the UltimateRobloxKit `ui` template, which is `starter-game` plus the UI overlay.

## UI overlay

A small, accessible UI kit on top of `starter-game`. The new project gets every base file plus:

| File | Purpose |
| --- | --- |
| `src/shared/UI/Theme.luau` | design tokens: colours, fonts, text sizes, radius, motion |
| `src/shared/UI/Responsive.luau` | one UIScale per ScreenGui, driven by the viewport (1280 x 720 reference) |
| `src/shared/UI/Components.luau` | `Label`, `Button`, `Panel` factories |
| `src/shared/UI/Tween.luau` | `play`, `fade`, `pop`, and a global `reducedMotion` switch |
| `src/shared/Logic/ColorContrast.luau` | pure WCAG contrast maths, tested by Lune |
| `src/client/Controllers/UIController.luau` | **replaces** the base HUD with a kit-built one and a Rebirth button |
| `tests/colorcontrast.spec.luau` | Lune tests for ColorContrast |

## Accessibility built in

- **Text size.** Components never go below `Theme.MinTextSize` (16 px at the reference size, and 12.8 px
  at the smallest UI scale).
- **Contrast.** Every label and button checks its text colour against its background. Below 4.5:1
  (WCAG AA), it switches to the theme text colour that reads better.
- **Touch targets.** Buttons keep a `UISizeConstraint` minimum of 44 x 44 px.
- **Input.** Buttons use `Activated`, which fires for mouse, touch and gamepad.
- **Motion.** Set `TweenUtil.reducedMotion = true` to make every tween instant.

## Usage

```lua
local UI = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI")
local Components = require(UI:WaitForChild("Components"))
local Responsive = require(UI:WaitForChild("Responsive"))

local gui = Instance.new("ScreenGui")
gui.Parent = player:WaitForChild("PlayerGui")
Responsive.attach(gui)

local panel = Components.Panel({ Direction = "Vertical", Parent = gui })
Components.Label({ Text = "Hello", Parent = panel })
Components.Button({ Text = "Play", OnActivated = function() print("play") end, Parent = panel })
```

## Base project

Everything from `starter-game` is included: the service and controller loaders, `Net`,
`PlayerDataService`, `EconomyService`, `InventoryService`, the pure `src/shared/Logic` modules and the
Lune tests. See the UltimateRobloxKit `templates/starter-game/README.md` for the full structure and
type-checking setup.

```bash
rokit install               # install the pinned tools
rojo serve                  # live-sync into Studio
rojo build -o game.rbxl     # build a place file
selene src tests            # lint
stylua --check src tests    # formatting check
lune run tests/run          # logic tests, including this template's spec file
```
