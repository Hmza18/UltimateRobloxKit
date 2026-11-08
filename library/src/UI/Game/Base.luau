--!strict
-- Component scaffold shared by every game component. It gives each one the contract shape:
--
--   local object = Component.new(props)
--   object.Instance        root GuiObject
--   object:update(partial) merge props and redraw
--   object:destroy()       clean everything (also object:Destroy())
--   object.Activated       Signal for interactive components
--
-- A component supplies `build(object)`, which draws into object.Instance and puts everything it
-- creates or connects into object.parts (a Trove cleaned before every rebuild). Long-lived state
-- (hover scale, count-up jobs, signals) goes into object.trove, cleaned on destroy. `apply` can
-- handle some prop changes without a rebuild (a counter value, a timer) by returning true.

local Kit = require("./Kit")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")
local Trove = require("../../Util/Trove")

export type Object = {
	Instance: any,
	Activated: Signal.Signal,
	props: { [string]: any },
	style: Style.StyleDef,
	trove: Trove.Trove,
	parts: Trove.Trove,
	destroyed: boolean,
	update: (self: Object, partial: { [string]: any }) -> (),
	destroy: (self: Object) -> (),
	Destroy: (self: Object) -> (),
	[string]: any,
}

export type Spec = {
	className: string, -- root class, for example "Frame" or "TextButton"
	name: string, -- default instance name
	props: { [string]: any }?,
	defaults: { [string]: any }?,
	size: UDim2?, -- default root size
	build: (object: Object) -> (),
	apply: ((object: Object, partial: { [string]: any }) -> boolean)?,
	interactive: boolean?, -- wire hover / press / select and Activated
	onPress: ((object: Object) -> ())?, -- always runs first on activation (toggle, open a list)
	onActivated: ((object: Object) -> ())?, -- runs when no `action` is set (purchase intents)
	setup: ((object: Object) -> ())?, -- runs once after the first build (long-lived state)
}

local Base = {}

local function merge(defaults: { [string]: any }?, props: { [string]: any }?): { [string]: any }
	local merged: { [string]: any } = {}
	for key, value in pairs(defaults or {}) do
		merged[key] = value
	end
	for key, value in pairs(props or {}) do
		merged[key] = value
	end
	return merged
end

-- Runs the shared activation: the component's own behaviour (onPress), Activated, then the
-- action, else the component's default (onActivated).
function Base.activate(object: Object, spec: Spec)
	if spec.onPress then
		spec.onPress(object)
	end
	object.Activated:Fire(object.props.name)
	local action = object.props.action
	if action and action ~= "" then
		Kit.runAction(action, object.Instance)
		return
	end
	if spec.onActivated then
		spec.onActivated(object)
	end
end

function Base.new(spec: Spec): Object
	local props = merge(spec.defaults, spec.props)
	local root = Instance.new(spec.className) :: any
	root.Name = spec.name
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	if spec.size then
		root.Size = spec.size
	end
	if root:IsA("TextButton") then
		root.Text = ""
		root.AutoButtonColor = false
	end
	if props.action then
		root:SetAttribute("Action", props.action)
	end

	local object: Object = {
		Instance = root,
		Activated = Signal.new(),
		props = props,
		style = Style.get(props.style),
		trove = Trove.new(),
		parts = Trove.new(),
		destroyed = false,
	} :: any

	-- Children the caller put into object.Content survive a rebuild (moved into the new Content).
	-- Instances the component made itself carry the UrkInternal attribute and are rebuilt instead.
	local function rebuild()
		local kept: { Instance } = {}
		local content = object.Content
		if typeof(content) == "Instance" then
			for _, child in content:GetChildren() do
				if child:GetAttribute("UrkInternal") ~= true then
					child.Parent = nil
					table.insert(kept, child)
				end
			end
		end
		object.parts:Clean()
		spec.build(object)
		Kit.applyCommon(root, object.props)
		local target = object.Content
		for _, child in kept do
			child.Parent = if typeof(target) == "Instance" then target else root
		end
	end

	function object.update(self: Object, partial: { [string]: any })
		if self.destroyed then
			return
		end
		for key, value in pairs(partial) do
			self.props[key] = value
		end
		if partial.style ~= nil then
			self.style = Style.get(self.props.style)
		end
		if partial.action ~= nil then
			root:SetAttribute("Action", self.props.action)
		end
		local handled = partial.style == nil and spec.apply ~= nil and spec.apply(self, partial)
		if handled then
			Kit.applyCommon(root, self.props)
		else
			rebuild()
		end
		if partial.parent ~= nil then
			root.Parent = partial.parent
		end
	end

	function object.destroy(self: Object)
		if self.destroyed then
			return
		end
		self.destroyed = true
		self.parts:Clean()
		self.trove:Clean()
		self.Activated:DisconnectAll()
		root:Destroy()
	end
	object.Destroy = object.destroy

	rebuild()
	if spec.interactive and root:IsA("GuiButton") then
		local options: Kit.InteractOptions = {
			enabled = function(): boolean
				return object.props.enabled ~= false
			end,
			onActivated = function()
				Base.activate(object, spec)
			end,
			radius = Kit.radius(object.style, object.props.radius or "md"),
		}
		Kit.interact(root, object.style, object.trove, options)
	end
	if spec.setup then
		spec.setup(object)
	end
	if props.parent then
		root.Parent = props.parent
	end
	return object
end

return Base
