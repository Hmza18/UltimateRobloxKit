--!strict
-- Shared helpers for the animated game components (PremiumButton, TabBar, Modal, XPBar,
-- InventorySlot, PetCard ...). They draw with the same Surface / GameText / Kit pieces as the
-- original components and take their motion from Visuals/UI, so every component moves with the
-- same presets. Internal to UI/Game.

local Base = require("./Base")
local Context = require("../Runtime/Context")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Sounds = require("../Runtime/Sounds")
local Style = require("../Style/Style")
local Surface = require("./Surface")
local UIAnimations = require("../../Visuals/UI/UIAnimations")

export type Layout = {
	position: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	zIndex: number?,
	order: number?,
}

export type WireOptions = {
	style: string?, -- Visuals/UI button style, default "BouncyPress"
	target: GuiObject?, -- object that animates (default: the root)
	radius: number?, -- selection outline radius in pixels
	color: any?, -- glow / ripple colour
	onPress: ((object: any) -> ())?, -- runs first on activation
	onActivated: ((object: any) -> ())?, -- runs when no `action` prop is set
	selected: boolean?,
}

local Extra = {}

Extra.UI = UIAnimations

-- Touch targets never go below this many pixels (at 1x).
Extra.MIN_TOUCH = 44

local function sounds(): { [string]: any }
	local context = Context.peek()
	return if context and context.config and context.config.sounds then context.config.sounds else {}
end

local function place(instance: GuiObject, layout: Layout?)
	if layout == nil then
		return
	end
	if layout.position then
		instance.Position = layout.position
	end
	if layout.size then
		instance.Size = layout.size
	end
	if layout.anchor then
		instance.AnchorPoint = layout.anchor
	end
	if layout.zIndex then
		instance.ZIndex = layout.zIndex
	end
	if layout.order then
		instance.LayoutOrder = layout.order
	end
end

-- A transparent frame made by a component (marked internal so rebuilds replace it).
function Extra.frame(parent: Instance, name: string, layout: Layout?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	place(frame, layout)
	Kit.internal(frame)
	frame.Parent = parent
	return frame
end

-- Outlined game text. Its stroke, constraint and connections are cleaned on the next rebuild.
function Extra.label(
	object: any,
	parent: Instance,
	name: string,
	options: GameText.TextOptions,
	layout: Layout?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	place(label, layout)
	Kit.internal(label)
	GameText.decorate(label, object.style, options, object.parts)
	label.Parent = parent
	return label
end

-- An icon by catalog name or asset id. Returns nil (and creates nothing) when neither resolves.
function Extra.image(parent: Instance, name: string, icon: string?, image: string?, layout: Layout?): ImageLabel?
	local holder = Instance.new("ImageLabel")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ScaleType = Enum.ScaleType.Fit
	place(holder, layout)
	Kit.internal(holder)
	if not Kit.icon(holder, icon, image) then
		holder:Destroy()
		return nil
	end
	holder.Parent = parent
	return holder
end

export type SurfaceOptions = {
	radius: number?, -- pixels, default the "lg" token
	outline: string?, -- outline weight, default "thick"
	outlineColor: string?,
	gloss: boolean?,
	pattern: boolean?,
	shadow: boolean?,
	padding: number?,
}

-- Draws a surface from an explicit swatch (rarity colours, medals) instead of a palette name.
-- Cleaned on the object's next rebuild, like Panel.surface.
function Extra.surface(object: any, root: GuiObject, swatch: Style.Swatch, options: SurfaceOptions?): Surface.Parts
	local opts: SurfaceOptions = options or {}
	local style = object.style
	local parts = Surface.build(style, root, {
		swatch = swatch,
		radius = opts.radius or Kit.radius(style, "lg"),
		outline = Style.outline(style, opts.outline or "thick"),
		outlineColor = opts.outlineColor,
		gloss = opts.gloss ~= false,
		pattern = opts.pattern == true,
		shadow = opts.shadow ~= false,
		padding = opts.padding,
	})
	object.parts:Add(function()
		Surface.clear(parts)
	end)
	return parts
end

-- A swatch from one colour: lighter on top, darker at the bottom, white text.
function Extra.swatch(hex: string): Style.Swatch
	return { top = Style.lighten(hex, 0.22), bottom = Style.darken(hex, 0.12), text = "#FFFFFF" }
end

-- Runs the shared activation (onPress, Activated, `action`, else onActivated) with the click sound.
function Extra.activate(object: any, options: WireOptions?)
	if object.destroyed or object.props.enabled == false then
		return
	end
	Sounds.play(sounds().click)
	local opts: WireOptions = options or {}
	Base.activate(object, { onPress = opts.onPress, onActivated = opts.onActivated } :: any)
end

-- Makes a component root interactive: gamepad-selectable with the kit's selection outline, hover
-- and click sounds, Activated, and hover / press / release / selected motion from a Visuals/UI
-- button style. Call it from `setup`. The binding is stored as object.binding and cleaned on
-- destroy; object.binding.setSelected(true) shows the selected state.
function Extra.wire(object: any, options: WireOptions?)
	local opts: WireOptions = options or {}
	local button: GuiButton = object.Instance
	button.AutoButtonColor = false
	button.Selectable = true
	local radius = opts.radius or Kit.radius(object.style, object.props.radius or "md")
	local selection = Kit.selectionImage(object.style, radius)
	object.trove:Add(selection)
	button.SelectionImageObject = selection
	object.trove:Connect(button.MouseEnter, function()
		if object.props.enabled ~= false then
			Sounds.play(sounds().hover, 0.6)
		end
	end)
	local binding = UIAnimations.bind(button, opts.style, {
		target = opts.target,
		color = opts.color,
		selected = opts.selected,
		enabled = function(): boolean
			return not object.destroyed and object.props.enabled ~= false
		end,
		onActivated = function()
			Extra.activate(object, opts)
		end,
	})
	object.binding = binding
	object.trove:Add(binding.destroy)
	return binding
end

-- Stops a Visuals/UI handle or preset when the component rebuilds.
function Extra.own(object: any, handle: { stop: (restore: boolean?) -> () }?)
	if handle then
		object.parts:Add(function()
			handle.stop()
		end)
	end
end

-- The ScreenGui (or other LayerCollector) an instance is shown in.
function Extra.layer(instance: Instance): Instance?
	return instance:FindFirstAncestorWhichIsA("LayerCollector")
end

return Extra
