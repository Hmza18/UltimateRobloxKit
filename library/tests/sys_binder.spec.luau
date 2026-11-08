--!strict
local BinderLogic = require("../src/Systems/Binder/BinderLogic")
local t = require("./lib/t")

type Log = { string }

-- A fake class whose objects record their lifecycle in `log`.
local function makeHooks(log: Log, overrides: { [string]: any }?): BinderLogic.Hooks
	local hooks: { [string]: any } = {
		construct = function(key: any): any
			table.insert(log, "new " .. tostring(key))
			local object = { key = key, destroyed = false }
			function object.Destroy(self: any)
				self.destroyed = true
				table.insert(log, "destroy " .. tostring(self.key))
			end
			return object
		end,
		added = function(key: any, _object: any)
			table.insert(log, "added " .. tostring(key))
		end,
		removing = function(key: any, _object: any)
			table.insert(log, "removing " .. tostring(key))
		end,
	}
	for name, value in overrides or {} do
		hooks[name] = value
	end
	return hooks :: any
end

return {
	["new validates the hooks"] = function()
		local missing: any = nil
		local notFunction: any = { construct = 5 }
		local badDestroy: any = { construct = tostring, destroy = "no" }
		t.throws(function()
			BinderLogic.new(missing)
		end)
		t.throws(function()
			BinderLogic.new(notFunction)
		end)
		t.throws(function()
			BinderLogic.new(badDestroy)
		end)
	end,

	["tag constructs and fires added"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		local outcome = BinderLogic.tag(state, "door")
		t.equal(outcome.status, "bound")
		t.equal(outcome.object.key, "door")
		t.deepEqual(log, { "new door", "added door" })
		t.equal(BinderLogic.get(state, "door"), outcome.object)
		t.equal(BinderLogic.phase(state, "door"), "bound")
	end,

	["untag fires removing then destroys"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		local object = BinderLogic.tag(state, "door").object
		local outcome = BinderLogic.untag(state, "door")
		t.equal(outcome.status, "unbound")
		t.truthy(object.destroyed)
		t.deepEqual(log, { "new door", "added door", "removing door", "destroy door" })
		t.equal(BinderLogic.get(state, "door"), nil)
		t.falsy(BinderLogic.isTagged(state, "door"))
	end,

	["a duplicate tag does not construct twice"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		local first = BinderLogic.tag(state, "a")
		local second = BinderLogic.tag(state, "a")
		t.equal(second.status, "duplicate")
		t.equal(second.object, first.object)
		t.equal(state.stats.constructed, 1)
		t.equal(state.stats.duplicates, 1)
		t.equal(BinderLogic.count(state), 1)
	end,

	["a remove before any add is ignored"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		t.equal(BinderLogic.untag(state, "ghost").status, "unknown")
		t.equal(#log, 0)
		t.equal(BinderLogic.tag(state, "ghost").status, "bound", "a later add still works")
	end,

	["untagging twice is harmless"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		BinderLogic.tag(state, "a")
		BinderLogic.untag(state, "a")
		t.equal(BinderLogic.untag(state, "a").status, "unknown")
		t.equal(state.stats.destroyed, 1)
	end,

	["re-tagging after untag builds a new object"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		local first = BinderLogic.tag(state, "a").object
		BinderLogic.untag(state, "a")
		local second = BinderLogic.tag(state, "a").object
		t.truthy(second ~= first)
		t.truthy(first.destroyed)
		t.falsy(second.destroyed)
	end,

	["a filtered key waits until its filter passes"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		t.equal(BinderLogic.tag(state, "npc", false).status, "filtered")
		t.equal(#log, 0)
		t.truthy(BinderLogic.isTagged(state, "npc"))
		t.equal(BinderLogic.phase(state, "npc"), "waiting")
		local outcome = BinderLogic.setFilter(state, "npc", true)
		t.equal(outcome.status, "bound")
		t.equal(BinderLogic.get(state, "npc"), outcome.object)
	end,

	["failing the filter destroys the object but keeps the tag"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		local object = BinderLogic.tag(state, "npc").object
		t.equal(BinderLogic.setFilter(state, "npc", false).status, "unbound")
		t.truthy(object.destroyed)
		t.truthy(BinderLogic.isTagged(state, "npc"))
		t.equal(BinderLogic.setFilter(state, "npc", false).status, "unchanged")
		t.equal(BinderLogic.setFilter(state, "npc", true).status, "bound", "streaming back in rebinds")
		t.equal(state.stats.constructed, 2)
	end,

	["setFilter on an untagged key is unknown"] = function()
		local state = BinderLogic.new(makeHooks({}))
		t.equal(BinderLogic.setFilter(state, "x", true).status, "unknown")
	end,

	["untagging a filtered key destroys nothing"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		BinderLogic.tag(state, "a", false)
		t.equal(BinderLogic.untag(state, "a").status, "untagged")
		t.equal(#log, 0)
	end,

	["a construct error is caught and reported"] = function()
		local log: Log = {}
		local hooks = makeHooks(log, {
			construct = function(_key: any): any
				error("bad model")
			end,
		})
		local state = BinderLogic.new(hooks)
		local outcome = BinderLogic.tag(state, "a")
		t.equal(outcome.status, "failed")
		t.truthy(outcome.error and string.find(outcome.error, "bad model"))
		t.equal(BinderLogic.get(state, "a"), nil)
		t.truthy(BinderLogic.isTagged(state, "a"), "the key stays tagged and can be retried")
		t.equal(state.stats.failed, 1)
		t.equal(BinderLogic.untag(state, "a").status, "untagged")
	end,

	["construct returning nil counts as a failure"] = function()
		local state = BinderLogic.new({
			construct = function(_key: any): any
				return nil
			end,
		})
		local outcome = BinderLogic.tag(state, "a")
		t.equal(outcome.status, "failed")
		t.equal(outcome.error, "construct returned nil")
	end,

	["retry constructs again after a failure"] = function()
		local attempts = 0
		local state = BinderLogic.new({
			construct = function(key: any): any
				attempts += 1
				if attempts == 1 then
					error("not ready")
				end
				return { key = key }
			end,
		})
		t.equal(BinderLogic.tag(state, "a").status, "failed")
		t.equal(BinderLogic.retry(state, "a").status, "bound")
		t.equal(BinderLogic.retry(state, "a").status, "unchanged", "already bound")
		t.equal(BinderLogic.retry(state, "missing").status, "unknown")
	end,

	["an untag from inside construct cancels the bind"] = function()
		local log: Log = {}
		local state: BinderLogic.State
		local hooks = makeHooks(log, {
			construct = function(key: any): any
				table.insert(log, "new " .. key)
				t.equal(BinderLogic.untag(state, key).status, "deferred")
				return {
					Destroy = function()
						table.insert(log, "destroy " .. key)
					end,
				}
			end,
		})
		state = BinderLogic.new(hooks)
		local outcome = BinderLogic.tag(state, "a")
		t.equal(outcome.status, "unbound")
		t.deepEqual(log, { "new a", "destroy a" }, "never announced, so no removing")
		t.falsy(BinderLogic.isTagged(state, "a"))
		t.equal(BinderLogic.count(state), 0)
	end,

	["a filter change during construct is honoured"] = function()
		local log: Log = {}
		local state: BinderLogic.State
		local flipBack = false
		local hooks = makeHooks(log, {
			construct = function(key: any): any
				BinderLogic.setFilter(state, key, false)
				if flipBack then
					BinderLogic.setFilter(state, key, true)
				end
				return { key = key }
			end,
		})
		state = BinderLogic.new(hooks)
		t.equal(BinderLogic.tag(state, "a").status, "unbound")
		t.equal(BinderLogic.phase(state, "a"), "waiting")
		flipBack = true
		t.equal(BinderLogic.tag(state, "b").status, "bound", "a flip back to true cancels the cancel")
	end,

	["a duplicate tag from inside construct is ignored"] = function()
		local state: BinderLogic.State
		local nested = ""
		state = BinderLogic.new({
			construct = function(key: any): any
				nested = BinderLogic.tag(state, key).status
				return { key = key }
			end,
		})
		t.equal(BinderLogic.tag(state, "a").status, "bound")
		t.equal(nested, "duplicate")
		t.equal(state.stats.constructed, 1)
	end,

	["errors in added, removing and destroy are reported, not raised"] = function()
		local log: Log = {}
		local hooks = makeHooks(log, {
			added = function()
				error("added broke")
			end,
			removing = function()
				error("removing broke")
			end,
			destroy = function()
				error("destroy broke")
			end,
		})
		local state = BinderLogic.new(hooks)
		local bound = BinderLogic.tag(state, "a")
		t.equal(bound.status, "bound")
		t.truthy(bound.error and string.find(bound.error, "added broke"))
		local unbound = BinderLogic.untag(state, "a")
		t.equal(unbound.status, "unbound")
		t.truthy(unbound.error and string.find(unbound.error, "removing broke"), "first error wins")
		t.equal(state.stats.destroyed, 1)
	end,

	["a custom destroy hook replaces object:Destroy"] = function()
		local destroyed: { any } = {}
		local state = BinderLogic.new({
			construct = function(key: any): any
				return { key = key }
			end,
			destroy = function(object: any, key: any)
				table.insert(destroyed, key)
				t.equal(object.key, key)
			end,
		})
		BinderLogic.tag(state, "a")
		BinderLogic.untag(state, "a")
		t.deepEqual(destroyed, { "a" })
	end,

	["objects without Destroy are dropped quietly"] = function()
		local state = BinderLogic.new({
			construct = function(_key: any): any
				return true
			end,
		})
		BinderLogic.tag(state, "a")
		t.equal(BinderLogic.untag(state, "a").status, "unbound")
		t.equal(BinderLogic.untag(state, "a").error, nil)
	end,

	["getAll lists bound objects in bind order"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		BinderLogic.tag(state, "a")
		BinderLogic.tag(state, "b", false)
		BinderLogic.tag(state, "c")
		BinderLogic.setFilter(state, "b", true)
		local keys: { any } = {}
		for _, object in BinderLogic.getAll(state) do
			table.insert(keys, object.key)
		end
		t.deepEqual(keys, { "a", "c", "b" })
		BinderLogic.untag(state, "c")
		t.deepEqual(BinderLogic.keys(state), { "a", "b" })
		t.equal(BinderLogic.count(state), 2)
	end,

	["table keys work like Instances"] = function()
		local state = BinderLogic.new(makeHooks({}))
		local part = {}
		local other = {}
		BinderLogic.tag(state, part)
		t.truthy(BinderLogic.get(state, part))
		t.equal(BinderLogic.get(state, other), nil)
		t.throws(function()
			BinderLogic.tag(state, nil)
		end)
	end,

	["destroyAll destroys newest first and refuses new tags"] = function()
		local log: Log = {}
		local state = BinderLogic.new(makeHooks(log))
		BinderLogic.tag(state, "a")
		BinderLogic.tag(state, "b")
		BinderLogic.tag(state, "c", false)
		table.clear(log)
		t.equal(BinderLogic.destroyAll(state), 2)
		t.deepEqual(log, { "removing b", "destroy b", "removing a", "destroy a" })
		t.equal(BinderLogic.count(state), 0)
		t.falsy(BinderLogic.isTagged(state, "c"))
		t.equal(BinderLogic.tag(state, "d").status, "unchanged")
		t.equal(BinderLogic.untag(state, "a").status, "unknown")
	end,
}
