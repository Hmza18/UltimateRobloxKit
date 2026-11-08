--!strict
-- Binds behaviours to CollectionService tags, scoped to a set of roots (PlayerGui by default).
--
-- * Discovery is by tag, never by path, so UI can be moved or duplicated freely.
-- * Each bound instance gets its own Trove. It is cleaned when the instance is destroyed, leaves
--   the scope, or loses the tag, so behaviours never leak connections.
-- * When one of the tag's declared attributes changes, the behaviour is cleaned and bound again
--   (once per frame at most), so attributes can be edited live in Studio or from code.

local CollectionService = game:GetService("CollectionService")

local TagSpec = require("../Core/TagSpec")
local Trove = require("../../Util/Trove")

export type Handler = (instance: Instance, trove: any) -> ()

local Binder = {}

function Binder.new(roots: { Instance }, debug: boolean?)
	local binder = {}
	local unbinders: { () -> () } = {}

	local function inScope(instance: Instance): boolean
		for _, root in roots do
			if instance == root or instance:IsDescendantOf(root) then
				return true
			end
		end
		return false
	end

	function binder.inScope(_self: any, instance: Instance): boolean
		return inScope(instance)
	end

	-- Reads the tag's attributes with defaults; warnings are printed only in debug mode.
	function binder.read(_self: any, tag: string, instance: Instance): { [string]: any }
		local function getAttribute(name: string): any
			return instance:GetAttribute(name)
		end
		local values, warnings = TagSpec.read(tag, getAttribute, typeof)
		if debug then
			for _, message in warnings do
				warn("[UrkUI] " .. instance:GetFullName() .. ": " .. message)
			end
		end
		return values
	end

	function binder.bind(_self: any, tag: string, handler: Handler): () -> ()
		local bound: { [Instance]: any } = {}
		local watchers: { [Instance]: any } = {}
		local declared = TagSpec.tags[tag]

		local function detach(instance: Instance)
			local trove = bound[instance]
			if trove then
				bound[instance] = nil
				trove:Destroy()
			end
		end

		local function attach(instance: Instance)
			if bound[instance] ~= nil or not inScope(instance) then
				return
			end
			local trove = Trove.new()
			bound[instance] = trove
			local ok, err = pcall(handler, instance, trove)
			if not ok then
				warn(string.format("[UrkUI] %s failed on %s: %s", tag, instance:GetFullName(), tostring(err)))
			end
		end

		local function watch(instance: Instance)
			if watchers[instance] ~= nil then
				return
			end
			local watchTrove = Trove.new()
			watchers[instance] = watchTrove
			local rebindQueued = false
			watchTrove:Connect(instance.AncestryChanged, function()
				if inScope(instance) then
					attach(instance)
				else
					detach(instance)
				end
			end)
			watchTrove:Connect(instance.Destroying, function()
				detach(instance)
			end)
			if declared then
				watchTrove:Connect(instance.AttributeChanged, function(name: string)
					if declared.attributes[name] == nil or rebindQueued or bound[instance] == nil then
						return
					end
					rebindQueued = true
					task.defer(function()
						rebindQueued = false
						if bound[instance] ~= nil then
							detach(instance)
							attach(instance)
						end
					end)
				end)
			end
			attach(instance)
		end

		local function unwatch(instance: Instance)
			local watchTrove = watchers[instance]
			if watchTrove then
				watchers[instance] = nil
				watchTrove:Destroy()
			end
			detach(instance)
		end

		for _, instance in CollectionService:GetTagged(tag) do
			watch(instance)
		end
		local added = CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
		local removed = CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch)

		local function unbind()
			added:Disconnect()
			removed:Disconnect()
			for instance in table.clone(watchers) do
				unwatch(instance)
			end
		end
		table.insert(unbinders, unbind)
		return unbind
	end

	function binder.destroy(_self: any)
		for index = #unbinders, 1, -1 do
			unbinders[index]()
		end
		table.clear(unbinders)
	end

	return binder
end

return Binder
