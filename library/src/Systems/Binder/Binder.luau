--!strict
-- Roblox adapter for BinderLogic. Binds a class to a CollectionService tag: every tagged
-- instance that passes the filter gets `class.new(instance)`, and the object is destroyed
-- when the tag is removed, the instance is destroyed or streamed out, or it leaves the
-- allowed ancestors. Works on the server and on clients. Call `start()` after connecting
-- ClassAdded, so the handler also sees instances that were tagged before.

local CollectionService = game:GetService("CollectionService")

local BinderLogic = require("./BinderLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Class = { new: (instance: Instance) -> any }

export type Options = {
	workspaceOnly: boolean?, -- only bind instances inside Workspace (default false)
	ancestors: { Instance }?, -- only bind instances inside one of these (default anywhere in the game)
	className: string?, -- only bind instances that IsA this class
	filter: ((instance: Instance) -> boolean)?, -- extra check, re-run when ancestry changes
}

local Binder = {}

function Binder.new(tag: string, class: Class, options: Options?)
	assert(type(tag) == "string" and tag ~= "", "tag must be a non-empty string")
	assert(type(class) == "table" and type(class.new) == "function", "class needs a new(instance) function")
	local opts: Options = options or {}
	local ancestors: { Instance } = opts.ancestors or {}
	if opts.workspaceOnly then
		ancestors = { workspace }
	end

	local trove = Trove.new()
	local watchers: { [Instance]: RBXScriptConnection } = {}
	local started = false

	local binder = {}
	binder.tag = tag
	binder.ClassAdded = Signal.new() -- (object, instance)
	binder.ClassRemoving = Signal.new() -- (object, instance)

	local state = BinderLogic.new({
		construct = function(instance: any): any
			return class.new(instance)
		end,
		added = function(instance: any, object: any)
			binder.ClassAdded:Fire(object, instance)
		end,
		removing = function(instance: any, object: any)
			binder.ClassRemoving:Fire(object, instance)
		end,
	})
	binder.state = state

	local function passes(instance: Instance): boolean
		if not instance:IsDescendantOf(game) then
			return false
		end
		if opts.className and not instance:IsA(opts.className) then
			return false
		end
		if #ancestors > 0 then
			local inside = false
			for _, ancestor in ancestors do
				if instance:IsDescendantOf(ancestor) then
					inside = true
					break
				end
			end
			if not inside then
				return false
			end
		end
		local filter = opts.filter
		if filter then
			local ok, allowed = pcall(filter, instance)
			return ok and allowed == true
		end
		return true
	end

	local function report(instance: Instance, outcome: BinderLogic.Result)
		if outcome.status == "failed" or outcome.error then
			warn(string.format("[Binder:%s] %s: %s", tag, instance:GetFullName(), tostring(outcome.error)))
		end
	end

	local function onAdded(instance: Instance)
		if watchers[instance] == nil then
			watchers[instance] = instance.AncestryChanged:Connect(function()
				report(instance, BinderLogic.setFilter(state, instance, passes(instance)))
			end)
		end
		report(instance, BinderLogic.tag(state, instance, passes(instance)))
	end

	local function onRemoved(instance: Instance)
		local watcher = watchers[instance]
		if watcher then
			watchers[instance] = nil
			watcher:Disconnect()
		end
		report(instance, BinderLogic.untag(state, instance))
	end

	-- Starts listening and binds every instance that already has the tag. Safe to call twice.
	function binder:start()
		if started then
			return
		end
		started = true
		trove:Connect(CollectionService:GetInstanceAddedSignal(tag), onAdded)
		trove:Connect(CollectionService:GetInstanceRemovedSignal(tag), onRemoved)
		for _, instance in CollectionService:GetTagged(tag) do
			onAdded(instance)
		end
	end

	function binder:get(instance: Instance): any?
		return BinderLogic.get(state, instance)
	end

	function binder:getAll(): { any }
		return BinderLogic.getAll(state)
	end

	-- Adds or removes the tag, which binds or unbinds through the normal signals.
	function binder:bind(instance: Instance)
		CollectionService:AddTag(instance, tag)
	end

	function binder:unbind(instance: Instance)
		CollectionService:RemoveTag(instance, tag)
	end

	-- Tries class.new again for an instance whose construct failed.
	function binder:retry(instance: Instance): any?
		local outcome = BinderLogic.retry(state, instance)
		report(instance, outcome)
		return outcome.object
	end

	function binder:destroy()
		trove:Clean()
		for _, watcher in watchers do
			watcher:Disconnect()
		end
		table.clear(watchers)
		BinderLogic.destroyAll(state)
		binder.ClassAdded:DisconnectAll()
		binder.ClassRemoving:DisconnectAll()
	end

	return binder
end

return Binder
