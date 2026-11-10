--!strict
-- One view over every preset registry in the kit (pure Luau). Tools, the playground and AI agents
-- ask here what exists instead of reading each module: search across kinds, list by category, and
-- export plain metadata.

local Registry = require("../Core/Registry")

export type Entry = { kind: string, id: string, score: number? }

local PresetsLogic = {}

export type Catalog = {
	add: (self: Catalog, registry: Registry.Registry) -> (),
	kinds: (self: Catalog) -> { string },
	registry: (self: Catalog, kind: string) -> Registry.Registry?,
	count: (self: Catalog) -> number,
	search: (self: Catalog, query: string, limit: number?) -> { Entry },
	list: (self: Catalog, kind: string?, filter: Registry.Filter?) -> { Entry },
	describe: (self: Catalog, kind: string, id: string) -> { [string]: any },
	export: (self: Catalog) -> { [string]: any },
	usage: (self: Catalog, kind: string, id: string) -> string,
}

-- Default one-line usage for presets that do not carry their own.
local USAGE: { [string]: string } = {
	vfx = 'Visuals:Play("%s", position)',
	ui = 'Visuals.UI:Animate(gui, "%s")',
	object = 'Visuals.Objects:Animate(model, "%s")',
	camera = 'Visuals.Camera:Shake("%s")',
	pet = 'Visuals.Pets:Play("%s", petModel)',
	rarity = 'Visuals.Rewards:Reveal("%s", reward)',
	screen = 'Visuals.Screens:Create("%s", props)',
	feedback = 'Visuals.Feedback:Fire("%s", context)',
}

function PresetsLogic.new(): Catalog
	local registries: { [string]: Registry.Registry } = {}
	local self: Catalog

	local function kinds(): { string }
		local out: { string } = {}
		for kind in registries do
			table.insert(out, kind)
		end
		table.sort(out)
		return out
	end

	self = {
		-- Adds (or replaces) the registry for its kind.
		add = function(_self: Catalog, registry: Registry.Registry)
			registries[registry.kind] = registry
		end,
		kinds = function(_self: Catalog): { string }
			return kinds()
		end,
		registry = function(_self: Catalog, kind: string): Registry.Registry?
			return registries[kind]
		end,
		count = function(_self: Catalog): number
			local total = 0
			for _, registry in registries do
				total += registry:count()
			end
			return total
		end,
		-- Best matches across every kind. Scores follow Registry.search order within a kind; ties
		-- between kinds are broken by kind then id so results are stable.
		search = function(_self: Catalog, query: string, limit: number?): { Entry }
			local out: { Entry } = {}
			for _, kind in kinds() do
				local ids = registries[kind]:search(query)
				for rank, id in ids do
					table.insert(out, { kind = kind, id = id, score = #ids - rank + 1 })
				end
			end
			table.sort(out, function(a: Entry, b: Entry): boolean
				local sa, sb = a.score or 0, b.score or 0
				if sa ~= sb then
					return sa > sb
				elseif a.kind ~= b.kind then
					return a.kind < b.kind
				end
				return a.id < b.id
			end)
			if limit then
				for index = #out, limit + 1, -1 do
					out[index] = nil
				end
			end
			return out
		end,
		list = function(_self: Catalog, kind: string?, filter: Registry.Filter?): { Entry }
			local out: { Entry } = {}
			for _, name in kinds() do
				if kind == nil or kind == name then
					for _, id in registries[name]:ids(filter) do
						table.insert(out, { kind = name, id = id })
					end
				end
			end
			return out
		end,
		describe = function(_self: Catalog, kind: string, id: string): { [string]: any }
			local registry = registries[kind]
			if registry == nil then
				error("unknown preset kind: " .. tostring(kind), 2)
			end
			local described = registry:describe(id)
			if described.usage == "" then
				described.usage = self:usage(kind, id)
			end
			return described
		end,
		usage = function(_self: Catalog, kind: string, id: string): string
			local registry = registries[kind]
			local preset = if registry then registry:find(id) else nil
			if preset and preset.usage and preset.usage ~= "" then
				return preset.usage
			end
			return string.format(USAGE[kind] or 'Visuals.Presets:Describe("' .. kind .. '", "%s")', id)
		end,
		-- Plain data for JSON: { kinds = { [kind] = { describe(id), ... } }, total }.
		export = function(_self: Catalog): { [string]: any }
			local out: { [string]: any } = {}
			local total = 0
			for _, kind in kinds() do
				local items: { any } = {}
				for _, id in registries[kind]:ids() do
					table.insert(items, self:describe(kind, id))
					total += 1
				end
				out[kind] = items
			end
			return { kinds = out, total = total }
		end,
	}
	return self
end

return PresetsLogic
