--!strict
-- HUD layout helper: a ScreenGui with anchored rails (topLeft, topCenter, topRight, left, center,
-- right, bottomLeft, bottomCenter, bottomRight) inside the safe area. ScreenInsets keeps rails
-- clear of the Roblox top bar and device cut-outs; `padding` adds a margin on every side.
-- Rails stack their children with a UIListLayout and grow to fit them.
--   local hud = Hud.new({ name = "MainHud" })
--   Currency.new({ icon = "coin", path = "Stats.Cash", parent = hud:rail("topRight") })

local Context = require("../Runtime/Context")
local Create = require("../Runtime/Create")
local Layout = require("../Core/Layout")

export type Props = {
	name: string?,
	insets: string?, -- "core" (default: avoid Roblox UI), "device" (notches only) or "none"
	padding: number?, -- pixels, default 12
	gap: number?, -- pixels between items on a rail, default 8
	displayOrder: number?,
	autoScale: boolean?, -- scale each rail with the responsive breakpoint (default true)
}

local Hud = {}

local INSETS: { [string]: Enum.ScreenInsets } = {
	core = Enum.ScreenInsets.CoreUISafeInsets,
	device = Enum.ScreenInsets.DeviceSafeInsets,
	none = Enum.ScreenInsets.None,
}

local ALIGN_X: { [string]: Enum.HorizontalAlignment } = {
	left = Enum.HorizontalAlignment.Left,
	center = Enum.HorizontalAlignment.Center,
	right = Enum.HorizontalAlignment.Right,
}

local ALIGN_Y: { [string]: Enum.VerticalAlignment } = {
	top = Enum.VerticalAlignment.Top,
	center = Enum.VerticalAlignment.Center,
	bottom = Enum.VerticalAlignment.Bottom,
}

function Hud.new(props: Props?)
	local context = Context.get()
	local opts: Props = props or {}
	local padding = opts.padding or 12
	local gap = opts.gap or 8
	local gui = Create.screen(opts.name or "UrkHud", opts.displayOrder or context.theme:layer("hud"), context.playerGui)
	gui.ScreenInsets = INSETS[opts.insets or "core"] or Enum.ScreenInsets.CoreUISafeInsets
	local area = Create.new("Frame", {
		Name = "SafeArea",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padding, padding),
		Size = UDim2.new(1, -padding * 2, 1, -padding * 2),
		Parent = gui,
	})

	local rails: { [string]: Frame } = {}

	local handle = {}
	handle.Instance = gui
	handle.Area = area

	-- The rail frame called `name`, created on first use. Errors for unknown names.
	function handle.rail(_self: any, name: string): Frame
		local existing = rails[name]
		if existing then
			return existing
		end
		local spec = Layout.rail(name)
		assert(spec ~= nil, "unknown HUD rail " .. tostring(name))
		local frame = Create.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(spec.anchor.x, spec.anchor.y),
			Position = UDim2.fromScale(spec.position.x, spec.position.y),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Parent = area,
		})
		local horizontal = spec.direction == "horizontal"
		local fill = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		local layout = Create.list(fill, gap, ALIGN_X[spec.horizontal], ALIGN_Y[spec.vertical])
		layout.Parent = frame
		if opts.autoScale ~= false then
			-- One UIScale per rail scales it around its own anchor, so corners stay in corners.
			local scale = Instance.new("UIScale")
			scale.Name = "UrkHudScale"
			scale.Parent = frame
			context.responsive:manage(scale)
		end
		rails[name] = frame
		return frame
	end

	-- Parents `object` to a rail with an optional LayoutOrder.
	function handle.add(self: any, railName: string, object: GuiObject, order: number?)
		if order then
			object.LayoutOrder = order
		end
		object.Parent = self:rail(railName)
		return object
	end

	function handle.Destroy(_self: any)
		gui:Destroy()
	end

	return handle
end

return Hud
