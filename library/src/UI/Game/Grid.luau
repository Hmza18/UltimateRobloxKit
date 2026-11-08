--!strict
-- Responsive card grid: a UIGridLayout whose column count follows the breakpoint (Core/Breakpoints,
-- read from UrkUI's responsive service when running, else from the camera and input devices).
-- Cell widths are scale-based, so the grid stays correct under any UIScale; a UIAspectRatioConstraint
-- on the layout keeps the cell shape. The grid grows vertically (AutomaticSize Y) for scrolling.
--   local grid = Grid.new({ columns = { phone = 2, tablet = 3, desktop = 4 }, parent = window.Content })
--   grid:add(ProductCard.new({ ... }))
--
-- cellAspect is width / height (Roblox's AspectRatio convention), default 1.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Base = require("./Base")
local Breakpoints = require("../Core/Breakpoints")
local Kit = require("./Kit")

export type Columns = { phone: number, tablet: number, desktop: number, console: number? }

export type Props = {
	columns: Columns?,
	cellAspect: number?,
	gap: string?, -- spacing token, default "md"
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

local Grid = {}

local DEFAULT_COLUMNS: Columns = { phone = 2, tablet = 3, desktop = 4 }

-- Column count for a breakpoint; console falls back to desktop.
function Grid.columnsFor(columns: Columns?, breakpoint: string): number
	local spec = columns or DEFAULT_COLUMNS
	local count: number?
	if breakpoint == "phone" then
		count = spec.phone
	elseif breakpoint == "tablet" then
		count = spec.tablet
	elseif breakpoint == "console" then
		count = spec.console or spec.desktop
	else
		count = spec.desktop
	end
	return math.max(1, math.floor(count or DEFAULT_COLUMNS.desktop))
end

local function localBreakpoint(): string
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	local input: Breakpoints.InputState = {
		touch = UserInputService.TouchEnabled,
		keyboard = UserInputService.KeyboardEnabled,
		tenFoot = GuiService:IsTenFootInterface(),
	}
	return Breakpoints.classify({ x = viewport.X, y = viewport.Y }, input)
end

local function currentBreakpoint(): string
	local context = Kit.context()
	if context and context.responsive then
		return context.responsive.breakpoint
	end
	return localBreakpoint()
end

local function applyColumns(object: any)
	local layout: UIGridLayout? = object.layout
	if layout == nil then
		return
	end
	local count = Grid.columnsFor(object.props.columns, currentBreakpoint())
	local gap = Kit.spacing(object.style, object.props.gap or "md")
	local share = gap * (count - 1) / count
	layout.CellSize = UDim2.new(1 / count, -share, 0, 0)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	object.Instance:SetAttribute("UrkColumns", count)
end

local function build(object: any)
	local props = object.props
	local root: Frame = object.Instance
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.fromScale(1, 0)
	end
	root.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Kit.internal(Instance.new("UIGridLayout"))
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.FillDirectionMaxCells = 0
	local aspect = Kit.internal(Instance.new("UIAspectRatioConstraint"))
	aspect.AspectRatio = math.max(0.05, props.cellAspect or 1)
	aspect.AspectType = Enum.AspectType.ScaleWithParentSize
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = layout
	layout.Parent = root
	object.parts:Add(layout)
	object.layout = layout
	object.Content = root
	applyColumns(object)
end

local function setup(object: any)
	local context = Kit.context()
	if context and context.responsive then
		object.trove:Connect(context.responsive.Changed, function()
			applyColumns(object)
		end)
		return
	end
	local function watch()
		applyColumns(object)
	end
	object.trove:Connect(UserInputService.LastInputTypeChanged, watch)
	local camera = workspace.CurrentCamera
	if camera then
		object.trove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), watch)
	end
end

function Grid.new(props: Props)
	local object = Base.new({ className = "Frame", name = "Grid", props = props, build = build, setup = setup })
	-- Parents a component object (or an Instance) into the grid.
	function object.add(self: any, child: any): any
		local instance = if typeof(child) == "Instance" then child else child.Instance
		instance.Parent = self.Instance
		return child
	end
	return object
end

return Grid
