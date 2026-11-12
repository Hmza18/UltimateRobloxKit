-- Minimal tween engine driven by the cinematic clock (so pause and skip stop everything at once).
-- A tween interpolates a value with an easing curve and hands it to a setter every update.
local Easing = require(script.Parent.Easing)

local Tweener = {}
Tweener.__index = Tweener

function Tweener.new()
	return setmetatable({ active = {}, count = 0 }, Tweener)
end

local function lerp(a, b, w)
	local ta = typeof and typeof(a) or type(a)
	if ta == "number" then
		return a + (b - a) * w
	end
	return a:Lerp(b, w) -- Vector3, CFrame, Color3, UDim2, Vector2
end

-- opts: { from, to, duration, ease = "outCubic", delay = 0, set = function(value, u) end, done = fn }
function Tweener:play(opts)
	local tw = {
		from = opts.from,
		to = opts.to,
		duration = math.max(opts.duration or 0.3, 1e-4),
		ease = Easing.get(opts.ease or "outCubic"),
		elapsed = -(opts.delay or 0),
		set = opts.set,
		done = opts.done,
		lerp = opts.lerp or lerp,
	}
	self.count = self.count + 1
	self.active[self.count] = tw
	return tw
end

function Tweener:update(dt)
	local keep, n = {}, 0
	for i = 1, self.count do
		local tw = self.active[i]
		if not tw.cancelled then
			tw.elapsed = tw.elapsed + dt
			if tw.elapsed >= 0 then
				local u = math.min(tw.elapsed / tw.duration, 1)
				local ok, err = pcall(tw.set, tw.lerp(tw.from, tw.to, tw.ease(u)), u)
				if not ok then
					warn("[SupermarketCinematic] tween error: " .. tostring(err))
					tw.cancelled = true
				elseif u >= 1 then
					tw.cancelled = true
					if tw.done then
						pcall(tw.done)
					end
				end
			end
			if not tw.cancelled then
				n = n + 1
				keep[n] = tw
			end
		end
	end
	self.active, self.count = keep, n
end

-- Jumps every running tween to its end state (used by skip so nothing is left half-way).
function Tweener:finishAll()
	for i = 1, self.count do
		local tw = self.active[i]
		if not tw.cancelled then
			pcall(tw.set, tw.to, 1)
			if tw.done then
				pcall(tw.done)
			end
		end
	end
	self.active, self.count = {}, 0
end

function Tweener:cancelAll()
	self.active, self.count = {}, 0
end

return Tweener
