--!strict
-- Client adapter for Input. Binds every action in the map with ContextActionService (keyboard keys,
-- mouse buttons, gamepad buttons and an optional on-screen touch button), reports the active device,
-- and rebinds at runtime with InputLogic's conflict rules.
-- Device detection uses UserInputService.PreferredInput when the engine has it (verify in the Roblox
-- docs; it is read inside pcall) and falls back to LastInputTypeChanged.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local InputLogic = require("./InputLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Options = {
	actions: InputLogic.ActionMap, -- the defaults
	overrides: any?, -- saved InputLogic.overrides() data
	sink: boolean?, -- stop bound inputs reaching lower-priority bindings (default true)
}

export type Client = {
	triggered: Signal.Signal, -- (action, state: "Begin" | "Change" | "End" | "Cancel", inputObject)
	deviceChanged: Signal.Signal, -- (device)
	overridesChanged: Signal.Signal, -- (overrides) save these
	device: (self: Client) -> InputLogic.Device,
	isDown: (self: Client, action: string) -> boolean,
	map: (self: Client) -> InputLogic.ActionMap,
	-- rebind(action, device, slot, key, options?) -> ok, reason, conflicting action
	rebind: (Client, string, string, number, string, InputLogic.RebindOptions?) -> (boolean, string?, string?),
	resetAction: (self: Client, action: string) -> (),
	displayKeys: (self: Client, action: string) -> { string }, -- labels for the current device
	destroy: (self: Client) -> (),
}

local InputClient = {}

-- Converts a name to an Enum.KeyCode or Enum.UserInputType. Unknown names return nil.
local function toInput(name: string): EnumItem?
	local ok, keyCode = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and keyCode then
		return keyCode
	end
	local okType, inputType = pcall(function()
		return (Enum.UserInputType :: any)[name]
	end)
	if okType and inputType then
		return inputType
	end
	return nil
end

local function bindName(action: string): string
	return "Urk_" .. action
end

function InputClient.new(options: Options): Client
	local ok, errors = InputLogic.validateMap(options.actions)
	assert(ok, "InputClient: invalid action map: " .. table.concat(errors, "; "))
	local defaults = InputLogic.cloneMap(options.actions)
	local map = InputLogic.applyOverrides(defaults, options.overrides)
	local sink = options.sink ~= false
	local trove = Trove.new()
	local triggered = Signal.new()
	local deviceChanged = Signal.new()
	local overridesChanged = Signal.new()
	trove:Add(function()
		triggered:DisconnectAll()
		deviceChanged:DisconnectAll()
		overridesChanged:DisconnectAll()
	end)
	local down: { [string]: boolean } = {}
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local currentDevice: InputLogic.Device = if touchOnly then "touch" else "keyboard"

	local function setDevice(device: InputLogic.Device?)
		if device and device ~= currentDevice then
			currentDevice = device
			deviceChanged:Fire(device)
		end
	end

	local function unbindAll()
		for action in map do
			ContextActionService:UnbindAction(bindName(action))
		end
	end

	local function bindAll()
		for action, def in map do
			local inputs: { EnumItem } = {}
			for _, name in def.keyboard or {} do
				local item = toInput(name)
				if item then
					table.insert(inputs, item)
				end
			end
			for _, name in def.gamepad or {} do
				local item = toInput(name)
				if item then
					table.insert(inputs, item)
				end
			end
			local touch = def.touch
			local handler = function(_name: string, state: Enum.UserInputState, inputObject: InputObject)
				if state == Enum.UserInputState.Begin then
					down[action] = true
				elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					down[action] = false
				end
				triggered:Fire(action, state.Name, inputObject)
				return if sink then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
			end
			local priority = def.priority or Enum.ContextActionPriority.Default.Value
			local bound = bindName(action)
			ContextActionService:BindActionAtPriority(bound, handler, touch ~= nil, priority, table.unpack(inputs))
			if touch then
				if touch.title then
					ContextActionService:SetTitle(bound, touch.title)
				end
				if touch.image then
					ContextActionService:SetImage(bound, touch.image)
				end
				local position = touch.position
				if position then
					ContextActionService:SetPosition(bound, UDim2.fromScale(position.x, position.y))
				end
			end
		end
	end

	local function rebuild()
		unbindAll()
		table.clear(down)
		bindAll()
	end

	bindAll()
	trove:Add(unbindAll)

	trove:Connect(UserInputService.LastInputTypeChanged, function(inputType: Enum.UserInputType)
		setDevice(InputLogic.detectDevice(inputType.Name))
	end)
	-- PreferredInput is newer than LastInputType; read it only if this engine version has it.
	local hasPreferred, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if hasPreferred and preferred ~= nil then
		setDevice(InputLogic.preferredToDevice(preferred.Name))
		local signalOk, signal = pcall(function()
			return UserInputService:GetPropertyChangedSignal("PreferredInput" :: any)
		end)
		if signalOk and signal then
			trove:Connect(signal, function()
				local value = (UserInputService :: any).PreferredInput
				setDevice(InputLogic.preferredToDevice(value.Name))
			end)
		end
	else
		setDevice(InputLogic.detectDevice(UserInputService:GetLastInputType().Name))
	end

	local client = {} :: Client
	client.triggered = triggered
	client.deviceChanged = deviceChanged
	client.overridesChanged = overridesChanged

	function client.device(_self: Client): InputLogic.Device
		return currentDevice
	end

	function client.isDown(_self: Client, action: string): boolean
		return down[action] == true
	end

	function client.map(_self: Client): InputLogic.ActionMap
		return InputLogic.cloneMap(map)
	end

	function client.rebind(
		_self: Client,
		action: string,
		device: InputLogic.BindDevice,
		slot: number,
		key: string,
		rebindOptions: InputLogic.RebindOptions?
	): (boolean, string?, string?)
		if toInput(key) == nil then
			return false, "unknown key", nil
		end
		local rebound, reason, nextMap, other = InputLogic.rebind(map, action, device, slot, key, rebindOptions)
		if not rebound or nextMap == nil then
			return false, reason, other
		end
		unbindAll()
		map = nextMap
		rebuild()
		overridesChanged:Fire(InputLogic.overrides(map, defaults))
		return true, nil, other
	end

	function client.resetAction(_self: Client, action: string)
		unbindAll()
		map = InputLogic.resetAction(map, defaults, action)
		rebuild()
		overridesChanged:Fire(InputLogic.overrides(map, defaults))
	end

	function client.displayKeys(_self: Client, action: string): { string }
		local device: InputLogic.BindDevice = if currentDevice == "gamepad" then "gamepad" else "keyboard"
		local labels: { string } = {}
		for _, key in InputLogic.bindingsFor(map, action, device) do
			table.insert(labels, InputLogic.displayName(key))
		end
		return labels
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return InputClient
