--!strict
-- Applies the pure PanelRouter to instances: visibility with transitions, modal backdrops,
-- DisplayOrder / ZIndex layering, AdoptPriority duplicates, lazy construction and the Back input
-- (gamepad B and Escape, bound only while a panel is open so gameplay keeps those keys otherwise).

local ContextActionService = game:GetService("ContextActionService")

local Motion = require("./Motion")
local PanelRouter = require("../Core/PanelRouter")
local Signal = require("../../Util/Signal")

export type Options = { transition: string?, closeOnBackdrop: boolean? }

type PanelDef = PanelRouter.PanelDef

type Record = {
	id: string,
	instance: Instance,
	def: PanelRouter.PanelDef,
	transition: string,
	closeOnBackdrop: boolean,
	backdrop: GuiObject?,
}

local BACK_ACTION = "UrkUIBack"

local Panels = {}

function Panels.new(context: any)
	local layers = context.theme.tokens.layers
	local router = PanelRouter.new({ panel = layers.panel, modal = layers.modal })
	local records: { [Instance]: Record } = {}
	local lazy: { [string]: { builder: () -> Instance, def: PanelRouter.PanelDef, options: Options? } } = {}
	local backBound = false
	local baseOrders: { [ScreenGui]: number } = {}

	local panels = {}
	panels.router = router
	panels.Opened = Signal.new()
	panels.Closed = Signal.new()

	local function screenGuiOf(instance: Instance): ScreenGui?
		if instance:IsA("ScreenGui") then
			return instance
		end
		local found = instance:FindFirstAncestorWhichIsA("ScreenGui")
		return found
	end

	local function removeBackdrop(record: Record)
		local backdrop = record.backdrop
		if backdrop then
			record.backdrop = nil
			backdrop:Destroy()
		end
	end

	local function addBackdrop(record: Record)
		if record.backdrop ~= nil or not record.def.modal then
			return
		end
		local instance = record.instance
		local parent = if instance:IsA("ScreenGui") then instance else instance.Parent
		if parent == nil then
			return
		end
		local backdrop = Instance.new("TextButton")
		backdrop.Name = "UrkBackdrop"
		backdrop.Text = ""
		backdrop.AutoButtonColor = false
		backdrop.Selectable = false
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.Position = UDim2.fromScale(0, 0)
		backdrop.BackgroundColor3 = context.theme:color("overlay")
		backdrop.BackgroundTransparency = context.theme:transparency("overlay")
		backdrop.ZIndex = if instance:IsA("GuiObject") then instance.ZIndex - 1 else 0
		backdrop.Activated:Connect(function()
			if record.closeOnBackdrop and record.def.dismissible ~= false then
				panels:close(record.id)
			end
		end)
		backdrop.Parent = parent
		record.backdrop = backdrop
	end

	local function setShown(record: Record, shown: boolean, instant: boolean?)
		local instance = record.instance
		if instance:IsA("LayerCollector") then
			local layer: any = instance
			layer.Enabled = shown
		elseif instance:IsA("GuiObject") then
			local transition = if instant then "none" else record.transition
			if shown then
				Motion.show(instance, transition)
			else
				Motion.hide(instance, transition)
			end
		end
		if shown then
			addBackdrop(record)
		else
			removeBackdrop(record)
		end
	end

	local function recordFor(owner: any): Record?
		if typeof(owner) ~= "Instance" then
			return nil
		end
		return records[owner]
	end

	local function updateLayers()
		local raised: { [ScreenGui]: number } = {}
		for _, id in router:stack() do
			local record = recordFor(router:owner(id))
			local layer = router:layer(id)
			if record and layer then
				local instance = record.instance
				if instance:IsA("ScreenGui") then
					instance.DisplayOrder = layer
				elseif instance:IsA("GuiObject") then
					instance.ZIndex = layer
					if record.backdrop then
						record.backdrop.ZIndex = layer - 1
					end
					local gui = screenGuiOf(instance)
					if gui and record.def.modal then
						raised[gui] = math.max(raised[gui] or 0, layer)
					end
				end
			end
		end
		-- Modals inside a shared ScreenGui lift that ScreenGui while they are open.
		for gui, base in table.clone(baseOrders) do
			if raised[gui] == nil then
				gui.DisplayOrder = base
				baseOrders[gui] = nil
			end
		end
		for gui, layer in raised do
			if baseOrders[gui] == nil then
				baseOrders[gui] = gui.DisplayOrder
			end
			gui.DisplayOrder = math.max(baseOrders[gui], layer)
		end
	end

	local function onBack(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if context.menu and context.menu:isOpen() then
			context.menu:close()
			return Enum.ContextActionResult.Sink
		end
		if router:canGoBack() then
			panels:back()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end

	local function updateBackBinding()
		local wanted = router:top() ~= nil
		if wanted and not backBound then
			backBound = true
			local priority = Enum.ContextActionPriority.High.Value
			local keys = { Enum.KeyCode.ButtonB, Enum.KeyCode.Escape }
			ContextActionService:BindActionAtPriority(BACK_ACTION, onBack, false, priority, table.unpack(keys))
		elseif not wanted and backBound then
			backBound = false
			ContextActionService:UnbindAction(BACK_ACTION)
		end
	end

	local function apply(events: { PanelRouter.Event })
		for _, event in events do
			local record = recordFor(event.owner)
			if record then
				if event.kind == "open" then
					setShown(record, true)
					panels.Opened:Fire(event.id, record.instance)
					if context.focus then
						context.focus:panelOpened(record.instance)
					end
				elseif event.kind == "close" then
					setShown(record, false)
					panels.Closed:Fire(event.id, record.instance)
					if context.focus then
						context.focus:panelClosed(record.instance)
					end
				elseif event.kind == "reject" then
					-- A lower-priority duplicate: keep it hidden while another copy is in charge.
					setShown(record, false, true)
				end
			end
		end
		updateLayers()
		updateBackBinding()
	end

	-- Registers an instance as panel `id`. Called by the UrkPanel / UrkModal behaviour and by
	-- code-created windows. Returns a function that unregisters it.
	function panels.registerInstance(_self: any, id: string, instance: Instance, def: PanelDef, options: Options?)
		local opts: Options = options or {}
		local record: Record = {
			id = id,
			instance = instance,
			def = def,
			transition = opts.transition or "pop",
			closeOnBackdrop = opts.closeOnBackdrop ~= false,
			backdrop = nil,
		}
		records[instance] = record
		local events = router:register(id, def, instance)
		if router:owner(id) == instance and not router:isOpen(id) then
			setShown(record, false, true)
		end
		apply(events)
		local function unregister()
			if records[instance] ~= record then
				return
			end
			removeBackdrop(record)
			records[instance] = nil
			apply(router:unregister(id, instance))
		end
		return unregister
	end

	-- Registers a panel that is built on first open. `builder` returns the panel instance, already
	-- parented. Nothing is created until the panel is needed.
	function panels.define(_self: any, id: string, builder: () -> Instance, def: PanelDef?, options: Options?)
		lazy[id] = { builder = builder, def = def or {}, options = options }
	end

	local function ensureBuilt(id: string)
		if router:isRegistered(id) then
			return
		end
		local entry = lazy[id]
		if entry == nil then
			return
		end
		lazy[id] = nil
		local ok, instance = pcall(entry.builder)
		if not ok or typeof(instance) ~= "Instance" then
			warn("[UrkUI] building panel " .. id .. " failed: " .. tostring(instance))
			return
		end
		local unregister = panels:registerInstance(id, instance, entry.def, entry.options)
		instance.Destroying:Connect(unregister)
	end

	function panels.open(_self: any, id: string, from: string?)
		ensureBuilt(id)
		if not router:isRegistered(id) then
			warn("[UrkUI] OpenPanel: no panel with PanelId " .. id)
			return
		end
		apply(router:open(id, { from = from }))
	end

	function panels.close(_self: any, id: string)
		apply(router:close(id))
	end

	function panels.toggle(self: any, id: string)
		if router:isOpen(id) then
			self:close(id)
		else
			self:open(id)
		end
	end

	function panels.back(_self: any): boolean
		local events = router:back()
		apply(events)
		return #events > 0
	end

	function panels.closeAll(_self: any, group: string?)
		apply(router:closeAll(group))
	end

	function panels.isOpen(_self: any, id: string): boolean
		return router:isOpen(id)
	end

	function panels.top(_self: any): string?
		return router:top()
	end

	function panels.destroy(_self: any)
		if backBound then
			backBound = false
			ContextActionService:UnbindAction(BACK_ACTION)
		end
		for _, record in records do
			removeBackdrop(record)
		end
		table.clear(records)
		panels.Opened:DisconnectAll()
		panels.Closed:DisconnectAll()
	end

	return panels
end

return Panels
