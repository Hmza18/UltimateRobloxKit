--!strict
-- Client adapter for Settings. Mirrors the server's accepted values, applies them through hooks and
-- sends changes. Changes apply locally at once (so sliders feel instant) and are corrected if the
-- server rejects them.
-- Built-in hooks from the schema's `hook` field:
--   "volume:<name>"    sets SoundService[<name>].Volume when that SoundGroup exists
--   "attribute:<name>" sets the attribute on the LocalPlayer (UI, camera and effects code read it)
-- Graphics quality is a hint only: game scripts cannot change the engine's quality level.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SettingsConfig = require("./SettingsConfig")
local SettingsLogic = require("./SettingsLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Options = {
	schema: SettingsLogic.Schema?, -- must match the server's schema
	hooks: { [string]: (value: any) -> () }?, -- extra per-setting callbacks
	remoteFolder: string?,
}

export type Client = {
	get: (self: Client, key: string) -> any,
	all: (self: Client) -> SettingsLogic.Values,
	set: (self: Client, key: string, value: any) -> (boolean, string?),
	reset: (self: Client, key: string) -> (),
	changed: Signal.Signal, -- (keys, values)
	destroy: (self: Client) -> (),
}

local SettingsClient = {}

local function applyHook(hook: string?, value: any)
	if hook == nil then
		return
	end
	local kind, name = string.match(hook, "^(%a+):(.+)$")
	if kind == "volume" and name and type(value) == "number" then
		local group = SoundService:FindFirstChild(name)
		if group and group:IsA("SoundGroup") then
			group.Volume = value
		end
	elseif kind == "attribute" and name then
		Players.LocalPlayer:SetAttribute(name, value)
	end
end

function SettingsClient.new(options: Options?): Client
	local opts: Options = options or {}
	local schema: SettingsLogic.Schema = opts.schema or (SettingsConfig.schema :: any)
	local hooks = opts.hooks or {}
	local folder = ReplicatedStorage:WaitForChild(opts.remoteFolder or SettingsConfig.remoteFolder)
	local updateRemote = folder:WaitForChild("Update") :: RemoteEvent
	local snapshotRemote = folder:WaitForChild("Snapshot") :: RemoteEvent
	local trove = Trove.new()
	local changed = Signal.new()
	trove:Add(function()
		changed:DisconnectAll()
	end)
	local values = SettingsLogic.defaults(schema)

	local function applyAll(nextValues: SettingsLogic.Values, force: boolean)
		local diff = if force then nil else SettingsLogic.diff(values, nextValues)
		values = nextValues
		for key, def in schema do
			local needed = force or (diff ~= nil and table.find(diff, key) ~= nil)
			if needed then
				applyHook(def.hook, values[key])
				local custom = hooks[key]
				if custom then
					task.spawn(custom, values[key])
				end
			end
		end
		if force or (diff and #diff > 0) then
			changed:Fire(diff or SettingsLogic.diff({}, values), values)
		end
	end

	trove:Connect(snapshotRemote.OnClientEvent, function(snapshot: any)
		if type(snapshot) ~= "table" then
			return
		end
		-- Re-check locally so a stale or partial snapshot never breaks the UI.
		local cleaned = SettingsLogic.apply(schema, SettingsLogic.defaults(schema), snapshot)
		applyAll(cleaned, false)
	end)

	applyAll(values, true)

	local client = {} :: Client
	client.changed = changed

	function client.get(_self: Client, key: string): any
		return values[key]
	end

	function client.all(_self: Client): SettingsLogic.Values
		return table.clone(values)
	end

	function client.set(_self: Client, key: string, value: any): (boolean, string?)
		local nextValues, rejected = SettingsLogic.apply(schema, values, { [key] = value })
		local reason = rejected[key]
		if reason then
			return false, reason
		end
		applyAll(nextValues, false)
		updateRemote:FireServer(key, nextValues[key])
		return true, nil
	end

	function client.reset(self: Client, key: string)
		local def = schema[key]
		if def then
			self:set(key, def.default)
		end
	end

	function client.destroy(_self: Client)
		trove:Clean()
	end

	return client
end

return SettingsClient
