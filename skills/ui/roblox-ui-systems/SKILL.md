---
name: roblox-ui-systems
description: Builds responsive, accessible Roblox UI - ScreenGui structure, ScreenInsets and safe areas, scale versus offset, UIAspectRatioConstraint, per-device UIScale, UIListLayout, UIGridLayout and UIFlexItem, AutomaticSize, HUDs, inventory grids, shops, settings menus persisted through the server, TweenService animation, design tokens as a Luau module, gamepad selection with GuiService.SelectedObject and NextSelection, and accessibility (text size, contrast, colour-blind safe palettes, reduced motion). Use when creating or fixing any screen, menu, HUD or UI component, or when UI breaks on phones, tablets, consoles or with a gamepad.
license: MIT
metadata:
  category: ui
  version: 1.0.0
  triggers: [ui, gui, screengui, hud, menu, inventory screen, shop ui, uiscale, safe area, gamepad selection, tweenservice, design tokens]
  depends: [luau-language, roblox-networking, roblox-camera-input]
---

# Roblox UI systems

## When to use

- New screens: HUD, inventory, shop, settings, dialogs, notifications.
- UI that is cut off by the notch, too small on phones, or unusable with a gamepad.
- Setting up a shared theme and component kit.

When not to use: icons, thumbnails and loading-screen art (use `game-art-presentation`), what the shop sells and at what price (use `monetization-economy-design`), inventory data and rules (use `roblox-inventory-economy`).

## Inputs

- Screen list with purpose of each, and which are modal.
- Target platforms (phone, tablet, desktop, console, VR).
- Brand palette and font choices, or permission to use the defaults below.
- Whether a UI library is used. Plain instances work everywhere; React-Lua (`jsdotlua/react`), Fusion and Vide are community libraries that suit larger UIs. Pick one and stay consistent.

## Workflow

1. **Structure.** One `ScreenGui` per layer under `StarterGui`: `HUD` (DisplayOrder 0), `Menus` (10), `Modals` (20), `Toasts` (30). Set `ResetOnSpawn = false` and `ZIndexBehavior = Sibling`. Build from `StarterPlayerScripts` client code or clone templates from `ReplicatedStorage/UI`.
2. **Safe areas.** Use `ScreenGui.ScreenInsets`: `CoreUISafeInsets` for HUD and menus (avoids the Roblox top bar and notches), `DeviceSafeInsets` for full-screen panels that may sit under the top bar, `None` for full-bleed backgrounds and loading screens. `IgnoreGuiInset` is the older equivalent; prefer `ScreenInsets` in new work.
3. **Sizing.** Size containers with Scale, controls with Offset plus a `UIScale`. Scale-only text and buttons stretch badly between 16:9 and 20:9. Lock panel shapes with `UIAspectRatioConstraint`; set `UISizeConstraint` min/max on panels so they stay usable on tablets and 4K.
4. **Per-device scale.** One `UIScale` per ScreenGui, driven from viewport size (component module below). Base design resolution 1280x720; clamp scale 0.7-1.5. Minimum touch target 44x44 px after scaling.
5. **Layout.** `UIListLayout` for stacks and toolbars (`Padding`, `HorizontalFlex`/`VerticalFlex`, `Wraps`), `UIFlexItem` on children to grow or shrink (`FlexMode = Fill`/`Grow`/`Shrink`), `UIGridLayout` for fixed cells or `UIListLayout` with `Wraps = true` for responsive grids, `UIPadding` everywhere instead of hand offsets. `AutomaticSize` on labels, tooltips and list containers; pair with a `ScrollingFrame` whose `AutomaticCanvasSize = Y`.
6. **Tokens.** Never hard-code colours or sizes inside screens; read the theme module below.
7. **Screens.**
   - **HUD:** currency top-left or top-centre inside the safe area, primary action bottom-right on touch (thumb zone), minimal persistent elements. Hide HUD while a modal is open.
   - **Inventory grid:** `ScrollingFrame` + `UIGridLayout` with `CellSize` in offset (scaled by UIScale) or wrapping `UIListLayout`; virtualise above about 200 items by reusing slot frames. Selected item details in a side panel (landscape) or bottom sheet (portrait).
   - **Shop:** clear item, price in Robux or soft currency with the icon, one primary buy button, owned state, and a confirm step for paid items. The client only requests; the server validates and calls `MarketplaceService:PromptProductPurchase` / grants soft-currency purchases.
   - **Settings:** toggles and sliders bound to a settings table. Client sends changes through one validated RemoteEvent; the server whitelists keys and types, clamps values, saves with the profile (`roblox-data-persistence`) and echoes the accepted value back. Debounce sends (0.5 s).
8. **Animation.** `TweenService` with short durations (0.12-0.25 s), `Quad`/`Back` easing on open, never block input during a tween. Route all motion through a helper that respects reduced motion.
9. **Gamepad and keyboard.** Set `Selectable = true` on interactive controls, `GuiService.SelectedObject` to the first control when a menu opens, and explicit `NextSelectionUp/Down/Left/Right` where the automatic guess is wrong. Use `GuiService:AddSelectionParent` or `SelectionGroup` to trap focus inside modals. Bind B / Escape to close with `ContextActionService`. Read the active input from `UserInputService.PreferredInput` (newer API; verify in creator docs) or `LastInputTypeChanged` and swap button prompts.
10. **Accessibility.**
    - Text: body 18 px minimum at base resolution, 14 px absolute minimum; avoid `TextScaled` for body text (inconsistent sizes), use `TextWrapped` with `UITextSizeConstraint` if scaling is unavoidable. Offer a text size setting that multiplies the UIScale for text-heavy screens. Roblox exposes a player preferred text size setting; verify current API (`GuiService.PreferredTextSize`) in creator docs.
    - Contrast: 4.5:1 for body text, 3:1 for large text and icons; add `UIStroke` on text over 3D scenes.
    - Colour-blind safe: never encode meaning by red/green alone; pair colour with icon, shape or label. The token palette below uses blue/orange for good/bad pairs.
    - Reduced motion: an in-game toggle; also read `GuiService.ReducedMotionEnabled` if available (verify in creator docs). When on, replace slides and bounces with instant changes or fades.
    - Every icon button gets a visible label or tooltip.

### Theme tokens and responsive components

```lua
--!strict
-- ReplicatedStorage/UI/Theme.lua
local rgb = Color3.fromRGB
local Theme = {
	color = {
		background = rgb(18, 20, 28), surface = rgb(32, 36, 48), surfaceRaised = rgb(44, 49, 64),
		text = rgb(240, 242, 248), textMuted = rgb(170, 176, 192),
		primary = rgb(64, 156, 255), positive = rgb(0, 158, 115), negative = rgb(230, 120, 0),
		currency = rgb(255, 200, 60), focus = rgb(255, 255, 255),
	},
	space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 },
	radius = { sm = UDim.new(0, 6), md = UDim.new(0, 10), pill = UDim.new(1, 0) },
	textSize = { caption = 14, body = 18, title = 24, display = 36 },
	font = {
		body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular),
		bold = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	},
	motion = { fast = 0.12, normal = 0.2 },
	baseResolution = Vector2.new(1280, 720),
}
return Theme
```

```lua
--!strict
-- ReplicatedStorage/UI/Components.lua
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Theme = require(script.Parent.Theme)

local Components = {}
Components.reducedMotion = false -- set from the player's saved settings

function Components.tween(object: Instance, info: TweenInfo, goal: { [string]: any })
	if Components.reducedMotion then
		for key, value in goal do
			(object :: any)[key] = value
		end
		return
	end
	TweenService:Create(object, info, goal):Play()
end

-- One UIScale per ScreenGui, updated when the viewport changes.
function Components.attachScale(gui: ScreenGui, textMultiplier: number?): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local vp = camera.ViewportSize
		local base = Theme.baseResolution
		local s = math.min(vp.X / base.X, vp.Y / base.Y)
		scale.Scale = math.clamp(s, 0.7, 1.5) * (textMultiplier or 1)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

export type ButtonProps = {
	text: string,
	variant: ("primary" | "surface")?,
	layoutOrder: number?,
	onActivated: () -> (),
}

function Components.button(props: ButtonProps): TextButton
	local base = if props.variant == "surface" then Theme.color.surfaceRaised else Theme.color.primary
	local b = Instance.new("TextButton")
	b.Name = props.text
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 48) -- 48 px tall keeps touch targets usable
	b.BackgroundColor3 = base
	b.AutoButtonColor = false
	b.FontFace = Theme.font.bold
	b.TextSize = Theme.textSize.body
	b.TextColor3 = Theme.color.text
	b.Text = props.text
	b.Selectable = true
	b.LayoutOrder = props.layoutOrder or 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.radius.md
	corner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Theme.space.lg)
	pad.PaddingRight = UDim.new(0, Theme.space.lg)
	pad.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.color.focus
	stroke.Thickness = 0
	stroke.Parent = b

	local info = TweenInfo.new(Theme.motion.fast, Enum.EasingStyle.Quad)
	local hover = base:Lerp(Color3.new(1, 1, 1), 0.12)
	b.MouseEnter:Connect(function() Components.tween(b, info, { BackgroundColor3 = hover }) end)
	b.MouseLeave:Connect(function() Components.tween(b, info, { BackgroundColor3 = base }) end)
	-- Visible focus ring for gamepad and keyboard navigation.
	b.SelectionGained:Connect(function() stroke.Thickness = 3 end)
	b.SelectionLost:Connect(function() stroke.Thickness = 0 end)
	b.Activated:Connect(props.onActivated)
	return b
end

return Components
```

Set `GuiService.SelectionImageObject` to an empty frame if you use the custom focus ring above, so the default and custom indicators do not both show.

## Outputs

- `ReplicatedStorage/UI/Theme.lua`, `Components.lua`, and one module per screen.
- ScreenGuis with the layer structure above.
- A settings RemoteEvent and server handler (validated, saved).

## Validation

1. Studio Device Emulator: iPhone SE (small), a 20:9 Android phone, iPad, 1080p, 4K, Xbox (10-foot). Check nothing is clipped by notches and touch targets are at least 44 px.
2. Gamepad: unplug the mouse, open every screen with a controller, reach every button, close with B.
3. Text: set the text multiplier to 1.5 and confirm no overflow (AutomaticSize grows, scrolling works).
4. Contrast: check text and background token pairs with any WCAG contrast checker (4.5:1 body).
5. Reduced motion on: no sliding or bouncing remains.
6. Exploit check: fire the settings remote with junk types and huge numbers from a test client; the server must reject or clamp.

## Pitfalls

- Scale-only text: unreadable on phones, huge on 4K. Use offset plus UIScale.
- `TextScaled` across a set of labels gives each a different size; looks broken.
- Forgetting `ResetOnSpawn = false` resets menus on every death.
- UI behind the top bar or notch: wrong `ScreenInsets`.
- Shop buttons that grant on the client; all grants are server-side.
- Gamepad focus lost after a screen closes; restore `SelectedObject` to the previous control or `nil`.
- Dozens of `UIStroke`/`UIGradient`s in a long scrolling list cost on low-end phones; reuse slots.

## Limitations

- Cannot see layouts; screenshots in the Device Emulator and on real devices are required.
- Some newer APIs named here (`PreferredInput`, `PreferredTextSize`, `ReducedMotionEnabled`, flex options) are recent and may change; verify in creator docs.
- Community UI libraries are outside this skill's scope beyond choosing one.
