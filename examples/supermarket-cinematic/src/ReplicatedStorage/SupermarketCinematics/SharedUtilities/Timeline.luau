-- Time-ordered cue list. update(t) fires every cue whose time has been reached, in order, exactly
-- once, even when a long frame jumps over several. Pure Lua (no Roblox APIs): unit-tested offline.
local Timeline = {}
Timeline.__index = Timeline

-- cues: { { t = seconds, name = "label", run = function(timeline, cue) ... end }, ... }
function Timeline.new(cues, onError)
	local list = {}
	for i, cue in ipairs(cues) do
		assert(type(cue.t) == "number", "cue " .. i .. " has no time")
		list[#list + 1] = { t = cue.t, name = cue.name or ("cue" .. i), run = cue.run, order = i, data = cue }
	end
	table.sort(list, function(a, b)
		if a.t == b.t then
			return a.order < b.order
		end
		return a.t < b.t
	end)
	return setmetatable({ cues = list, nextIndex = 1, time = 0, fired = {}, onError = onError }, Timeline)
end

function Timeline:update(t)
	self.time = t
	local cues = self.cues
	while self.nextIndex <= #cues and cues[self.nextIndex].t <= t do
		local cue = cues[self.nextIndex]
		self.nextIndex = self.nextIndex + 1
		self.fired[#self.fired + 1] = cue.name
		if cue.run then
			local ok, err = pcall(cue.run, self, cue.data)
			if not ok and self.onError then
				self.onError(cue.name, err)
			end
		end
	end
end

function Timeline:done()
	return self.nextIndex > #self.cues
end

function Timeline:duration()
	local last = self.cues[#self.cues]
	return last and last.t or 0
end

-- Names of the cues that have not fired yet (used when skipping, to run only "always" cues).
function Timeline:pending()
	local out = {}
	for i = self.nextIndex, #self.cues do
		out[#out + 1] = self.cues[i]
	end
	return out
end

return Timeline
