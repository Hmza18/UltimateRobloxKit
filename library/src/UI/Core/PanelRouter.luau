--!strict
-- Panel stack and router state machine. Pure Luau: it decides which panels are open, in which
-- order, on which layer, and which duplicate wins; Runtime/Panels applies the result to instances.
--
-- * Opening a panel in an exclusive group closes the other panels of that group.
-- * The open stack is ordered: the last opened panel is on top. back() closes the top panel that
--   is dismissible; a non-dismissible modal blocks back() until it is closed explicitly.
-- * Panels opened with { from = id } are children: closing the parent closes them too.
-- * Several registrations may claim the same id (for example a menu copied into two ScreenGuis).
--   The one with the highest AdoptPriority is active; ties keep the first. If the active one
--   unregisters, the next candidate is adopted.
-- Every mutating call returns a list of Events ({ kind = "open" | "close" | "adopt" | "reject", id }).

export type PanelDef = {
	group: string?, -- panels in the same exclusive group replace each other
	exclusive: boolean?, -- default true when group is set
	modal: boolean?, -- drawn above normal panels, with a backdrop
	dismissible: boolean?, -- default true; false blocks back() and outside clicks
	priority: number?, -- AdoptPriority, default 0
}

export type Event = { kind: string, id: string, owner: any }

export type OpenOptions = { from: string? }

export type Router = {
	register: (self: Router, id: string, def: PanelDef, owner: any) -> { Event },
	unregister: (self: Router, id: string, owner: any) -> { Event },
	open: (self: Router, id: string, options: OpenOptions?) -> { Event },
	close: (self: Router, id: string) -> { Event },
	toggle: (self: Router, id: string) -> { Event },
	back: (self: Router) -> { Event },
	closeAll: (self: Router, group: string?) -> { Event },
	isOpen: (self: Router, id: string) -> boolean,
	isRegistered: (self: Router, id: string) -> boolean,
	top: (self: Router) -> string?,
	stack: (self: Router) -> { string },
	owner: (self: Router, id: string) -> any,
	layer: (self: Router, id: string) -> number?,
	canGoBack: (self: Router) -> boolean,
	definition: (self: Router, id: string) -> PanelDef?,
}

export type Layers = { panel: number, modal: number }

type Candidate = { def: PanelDef, owner: any, priority: number, order: number }
type Entry = { id: string, from: string? }

local PanelRouter = {}

local function isExclusive(def: PanelDef): boolean
	if def.group == nil then
		return false
	end
	return def.exclusive ~= false
end

function PanelRouter.new(layers: Layers?): Router
	local layerBase: Layers = layers or { panel = 10, modal = 50 }
	local candidates: { [string]: { Candidate } } = {}
	local openStack: { Entry } = {}
	local registrations = 0

	local function active(id: string): Candidate?
		local list = candidates[id]
		if list == nil then
			return nil
		end
		return list[1]
	end

	local function stackIndex(id: string): number?
		for index, entry in openStack do
			if entry.id == id then
				return index
			end
		end
		return nil
	end

	local function closeInto(id: string, events: { Event })
		local index = stackIndex(id)
		if index == nil then
			return
		end
		table.remove(openStack, index)
		-- Close children (and their children) before reporting the parent as closed.
		while true do
			local childId: string? = nil
			for childIndex = #openStack, 1, -1 do
				if openStack[childIndex].from == id then
					childId = openStack[childIndex].id
					break
				end
			end
			if childId == nil then
				break
			end
			closeInto(childId, events)
		end
		local candidate = active(id)
		table.insert(events, { kind = "close", id = id, owner = if candidate then candidate.owner else nil })
	end

	local function sortCandidates(list: { Candidate })
		table.sort(list, function(a: Candidate, b: Candidate): boolean
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			return a.order < b.order
		end)
	end

	-- Ids from the top of the stack down, copied so closing can reshuffle the stack safely.
	local function openIdsTopDown(): { string }
		local ids: { string } = {}
		for index = #openStack, 1, -1 do
			table.insert(ids, openStack[index].id)
		end
		return ids
	end

	local router: Router = {
		register = function(_self: Router, id: string, def: PanelDef, owner: any): { Event }
			assert(type(id) == "string" and id ~= "", "panel id must be a non-empty string")
			local events: { Event } = {}
			local list = candidates[id]
			if list == nil then
				list = {}
				candidates[id] = list
			end
			for _, existing in list do
				if existing.owner == owner then
					existing.def = def
					existing.priority = def.priority or 0
					sortCandidates(list)
					return events
				end
			end
			local previous = list[1]
			registrations += 1
			table.insert(list, { def = def, owner = owner, priority = def.priority or 0, order = registrations })
			sortCandidates(list)
			local winner = list[1]
			if winner.owner == owner then
				if previous then
					table.insert(events, { kind = "reject", id = id, owner = previous.owner })
				end
				table.insert(events, { kind = "adopt", id = id, owner = owner })
				if stackIndex(id) ~= nil then
					table.insert(events, { kind = "open", id = id, owner = owner })
				end
			else
				table.insert(events, { kind = "reject", id = id, owner = owner })
			end
			return events
		end,

		unregister = function(_self: Router, id: string, owner: any): { Event }
			local events: { Event } = {}
			local list = candidates[id]
			if list == nil then
				return events
			end
			local wasActive = list[1] ~= nil and list[1].owner == owner
			for index, candidate in list do
				if candidate.owner == owner then
					table.remove(list, index)
					break
				end
			end
			if #list == 0 then
				candidates[id] = nil
				local index = stackIndex(id)
				if index then
					table.remove(openStack, index)
				end
				return events
			end
			if wasActive then
				local nextOwner = list[1].owner
				table.insert(events, { kind = "adopt", id = id, owner = nextOwner })
				if stackIndex(id) ~= nil then
					table.insert(events, { kind = "open", id = id, owner = nextOwner })
				end
			end
			return events
		end,

		open = function(_self: Router, id: string, options: OpenOptions?): { Event }
			local events: { Event } = {}
			local candidate = active(id)
			if candidate == nil then
				return events
			end
			local def = candidate.def
			if isExclusive(def) then
				for _, otherId in openIdsTopDown() do
					local other = active(otherId)
					if otherId ~= id and other and other.def.group == def.group then
						closeInto(otherId, events)
					end
				end
			end
			local existing = stackIndex(id)
			local from = if options then options.from else nil
			if existing then
				-- Already open: bring it to the top without re-running its open transition.
				local entry = table.remove(openStack, existing) :: Entry
				if from ~= nil then
					entry.from = from
				end
				table.insert(openStack, entry)
				return events
			end
			table.insert(openStack, { id = id, from = from })
			table.insert(events, { kind = "open", id = id, owner = candidate.owner })
			return events
		end,

		close = function(_self: Router, id: string): { Event }
			local events: { Event } = {}
			closeInto(id, events)
			return events
		end,

		toggle = function(self: Router, id: string): { Event }
			if stackIndex(id) ~= nil then
				return self:close(id)
			end
			return self:open(id)
		end,

		back = function(_self: Router): { Event }
			local events: { Event } = {}
			local entry = openStack[#openStack]
			if entry == nil then
				return events
			end
			local candidate = active(entry.id)
			if candidate and candidate.def.dismissible == false then
				return events
			end
			closeInto(entry.id, events)
			return events
		end,

		closeAll = function(_self: Router, group: string?): { Event }
			local events: { Event } = {}
			for _, openId in openIdsTopDown() do
				local candidate = active(openId)
				if group == nil or (candidate ~= nil and candidate.def.group == group) then
					closeInto(openId, events)
				end
			end
			return events
		end,

		isOpen = function(_self: Router, id: string): boolean
			return stackIndex(id) ~= nil
		end,

		isRegistered = function(_self: Router, id: string): boolean
			return candidates[id] ~= nil
		end,

		top = function(_self: Router): string?
			local entry = openStack[#openStack]
			return if entry then entry.id else nil
		end,

		stack = function(_self: Router): { string }
			local ids: { string } = {}
			for _, entry in openStack do
				table.insert(ids, entry.id)
			end
			return ids
		end,

		owner = function(_self: Router, id: string): any
			local candidate = active(id)
			return if candidate then candidate.owner else nil
		end,

		-- DisplayOrder for an open panel: modal band or panel band, plus its position in the stack.
		layer = function(_self: Router, id: string): number?
			local index = stackIndex(id)
			local candidate = active(id)
			if index == nil or candidate == nil then
				return nil
			end
			local base = if candidate.def.modal then layerBase.modal else layerBase.panel
			return base + index
		end,

		canGoBack = function(_self: Router): boolean
			local entry = openStack[#openStack]
			if entry == nil then
				return false
			end
			local candidate = active(entry.id)
			return not (candidate and candidate.def.dismissible == false)
		end,

		definition = function(_self: Router, id: string): PanelDef?
			local candidate = active(id)
			return if candidate then candidate.def else nil
		end,
	}
	return router
end

return PanelRouter
