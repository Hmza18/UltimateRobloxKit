--!strict
-- Action registry. An Action attribute such as "TogglePanel:Shop" or "OpenPanel:Shop;PlaySound:123"
-- names handlers; games add their own with UrkUI.registerActions({ Name = function(action) end })
-- instead of editing kit files. Handlers receive an ActionCall:
--   { name, args = { ... }, raw, source = the instance that triggered it (or nil), ui = UrkUI }
-- Actions run on the client. Anything that changes game state must go through a remote that the
-- server validates; use the built-in Fire action to raise UrkUI.Intent and handle it in game code.

local Sounds = require("./Sounds")
local TagSpec = require("../Core/TagSpec")

export type ActionCall = { name: string, args: { string }, raw: string, source: Instance?, ui: any }

export type Handler = (action: ActionCall) -> ()

local Actions = {}

local NAME_PATTERN = "^[%a][%w_]*$"

local function firstArg(action: ActionCall): string?
	local value = action.args[1]
	if value == nil or value == "" then
		return nil
	end
	return value
end

-- The built-in actions. `context` is the running UrkUI context.
local function builtins(context: any): { [string]: Handler }
	return {
		OpenPanel = function(action: ActionCall)
			local id = firstArg(action)
			if id then
				context.panels:open(id)
			end
		end,
		ClosePanel = function(action: ActionCall)
			local id = firstArg(action)
			if id then
				context.panels:close(id)
			else
				context.panels:back()
			end
		end,
		TogglePanel = function(action: ActionCall)
			local id = firstArg(action)
			if id then
				context.panels:toggle(id)
			end
		end,
		Back = function(_action: ActionCall)
			context.panels:back()
		end,
		CloseAll = function(action: ActionCall)
			context.panels:closeAll(firstArg(action))
		end,
		ShowToast = function(action: ActionCall)
			-- "ShowToast:Saved!" or "ShowToast:Saved!,success"; a raw text with commas needs a kind.
			local kind = action.args[#action.args]
			local text = action.raw
			if #action.args > 1 and (kind == "info" or kind == "success" or kind == "warning" or kind == "error") then
				text = table.concat(action.args, ", ", 1, #action.args - 1)
			else
				kind = "info"
			end
			context.toasts:show({ text = context.localize:t(text), kind = kind })
		end,
		SetTheme = function(action: ActionCall)
			local name = firstArg(action)
			if name then
				context.theme:setTheme(name)
			end
		end,
		CycleTheme = function(_action: ActionCall)
			context.theme:cycle()
		end,
		SetLocale = function(action: ActionCall)
			local locale = firstArg(action)
			if locale then
				context.localize:setLocale(locale)
			end
		end,
		PlaySound = function(action: ActionCall)
			Sounds.play(firstArg(action))
		end,
		-- Raises UrkUI.Intent(name, args, source). The game decides what it means.
		Fire = function(action: ActionCall)
			local name = firstArg(action)
			if name then
				local rest = table.move(action.args, 2, #action.args, 1, {})
				context.Intent:Fire(name, rest, action.source)
			end
		end,
	}
end

function Actions.new(context: any)
	local registry = {}
	local handlers: { [string]: Handler } = builtins(context)
	local warned: { [string]: boolean } = {}

	-- Adds or replaces handlers. Returns a function that removes exactly these handlers.
	function registry.register(_self: any, map: { [string]: Handler }): () -> ()
		for name, handler in map do
			assert(type(name) == "string" and string.find(name, NAME_PATTERN) ~= nil, "action names are identifiers")
			assert(type(handler) == "function", "action " .. name .. " needs a function")
			handlers[name] = handler
		end
		local function unregister()
			for name, handler in map do
				if handlers[name] == handler then
					handlers[name] = nil
				end
			end
		end
		return unregister
	end

	function registry.has(_self: any, name: string): boolean
		return handlers[name] ~= nil
	end

	-- Runs every call in `spec`. `fallbackArg` (the Target attribute) fills in calls without args.
	-- Returns true when at least one handler ran without error.
	function registry.run(_self: any, spec: string?, source: Instance?, fallbackArg: string?): boolean
		local ranAny = false
		for _, call in TagSpec.parseAction(spec) do
			local handler = handlers[call.name]
			if handler == nil then
				if not warned[call.name] then
					warned[call.name] = true
					warn("[UrkUI] unknown action " .. call.name .. " (register it with UrkUI.registerActions)")
				end
				continue
			end
			local args = call.args
			local raw = call.raw
			if #args == 0 and fallbackArg ~= nil and fallbackArg ~= "" then
				args = { fallbackArg }
				raw = fallbackArg
			end
			local action: ActionCall = { name = call.name, args = args, raw = raw, source = source, ui = context.api }
			local ok, err = pcall(handler, action)
			if ok then
				ranAny = true
			else
				warn("[UrkUI] action " .. call.name .. " failed: " .. tostring(err))
			end
		end
		return ranAny
	end

	return registry
end

return Actions
