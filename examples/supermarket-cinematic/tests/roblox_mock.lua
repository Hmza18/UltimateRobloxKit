-- Minimal headless stand-in for the Roblox APIs the cinematic uses, so its real Luau source can run
-- frame by frame under a plain Lua 5.4 VM (tests/sim.py). This is NOT the engine: rendering, physics,
-- AnimationTracks, Sounds and GUI layout are absent. Joints are solved kinematically (Motor6D, Weld,
-- WeldConstraint) so prop/hand alignment and camera math can be measured.

local M = {}
local unpack = table.unpack

-- Vector3 ------------------------------------------------------------------------------------------
local V3 = {}
V3.__index = function(v, k)
	if k == "X" then return v[1] elseif k == "Y" then return v[2] elseif k == "Z" then return v[3]
	elseif k == "Magnitude" then return math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
	elseif k == "Unit" then local m = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2); if m == 0 then return v end return M.v3(v[1] / m, v[2] / m, v[3] / m)
	end
	return V3[k]
end
function M.v3(x, y, z) return setmetatable({ x or 0, y or 0, z or 0, __t = "Vector3" }, V3) end
local v3 = M.v3
V3.__add = function(a, b) return v3(a[1] + b[1], a[2] + b[2], a[3] + b[3]) end
V3.__sub = function(a, b) return v3(a[1] - b[1], a[2] - b[2], a[3] - b[3]) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(b[1] * a, b[2] * a, b[3] * a) end
	if type(b) == "number" then return v3(a[1] * b, a[2] * b, a[3] * b) end
	return v3(a[1] * b[1], a[2] * b[2], a[3] * b[3])
end
V3.__div = function(a, b) if type(b) == "number" then return v3(a[1] / b, a[2] / b, a[3] / b) end return v3(a[1] / b[1], a[2] / b[2], a[3] / b[3]) end
V3.__unm = function(a) return v3(-a[1], -a[2], -a[3]) end
V3.__eq = function(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
V3.__tostring = function(a) return string.format("%.3f, %.3f, %.3f", a[1], a[2], a[3]) end
function V3.Lerp(a, b, t) return a + (b - a) * t end
function V3.Dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
function V3.Cross(a, b) return v3(a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1]) end
local Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }
M.Vector3 = Vector3

-- CFrame: position + row-major 3x3 ------------------------------------------------------------------
local CF = {}
local function cf(p, r) return setmetatable({ p = p, r = r, __t = "CFrame" }, CF) end
local function mul3(a, b)
	local o = {}
	for i = 0, 2 do for j = 0, 2 do
		o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
	end end
	return o
end
local function rotv(r, v) return v3(r[1] * v[1] + r[2] * v[2] + r[3] * v[3], r[4] * v[1] + r[5] * v[2] + r[6] * v[3], r[7] * v[1] + r[8] * v[2] + r[9] * v[3]) end
local function tr(r) return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] } end
local I3 = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function fromQuat(x, y, z, w)
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	x, y, z, w = x / n, y / n, z / n, w / n
	return { 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y) }
end
local function toQuat(r)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = unpack(r)
	local t = m00 + m11 + m22
	local w, x, y, z
	if t > 0 then local s = math.sqrt(t + 1) * 2; w = s / 4; x = (m21 - m12) / s; y = (m02 - m20) / s; z = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then local s = math.sqrt(1 + m00 - m11 - m22) * 2; w = (m21 - m12) / s; x = s / 4; y = (m01 + m10) / s; z = (m02 + m20) / s
	elseif m11 > m22 then local s = math.sqrt(1 + m11 - m00 - m22) * 2; w = (m02 - m20) / s; x = (m01 + m10) / s; y = s / 4; z = (m12 + m21) / s
	else local s = math.sqrt(1 + m22 - m00 - m11) * 2; w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = s / 4 end
	return x, y, z, w
end
CF.__index = function(c, k)
	if k == "Position" then return c.p
	elseif k == "X" then return c.p[1] elseif k == "Y" then return c.p[2] elseif k == "Z" then return c.p[3]
	elseif k == "LookVector" then return v3(-c.r[3], -c.r[6], -c.r[9])
	elseif k == "RightVector" then return v3(c.r[1], c.r[4], c.r[7])
	elseif k == "UpVector" then return v3(c.r[2], c.r[5], c.r[8])
	elseif k == "Rotation" then return cf(v3(0, 0, 0), c.r)
	end
	return CF[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then return a.p + rotv(a.r, b) end
	return cf(a.p + rotv(a.r, b.p), mul3(a.r, b.r))
end
CF.__add = function(a, v) return cf(a.p + v, a.r) end
CF.__sub = function(a, v) return cf(a.p - v, a.r) end
function CF.Inverse(c) local rt = tr(c.r); return cf(-rotv(rt, c.p), rt) end
function CF.ToObjectSpace(a, b) return a:Inverse() * b end
function CF.ToWorldSpace(a, b) return a * b end
function CF.PointToObjectSpace(a, v) return rotv(tr(a.r), v - a.p) end
function CF.PointToWorldSpace(a, v) return a * v end
function CF.VectorToWorldSpace(a, v) return rotv(a.r, v) end
function CF.VectorToObjectSpace(a, v) return rotv(tr(a.r), v) end
function CF.GetComponents(c) return c.p[1], c.p[2], c.p[3], unpack(c.r) end
function CF.Lerp(a, b, t)
	local ax, ay, az, aw = toQuat(a.r)
	local bx, by, bz, bw = toQuat(b.r)
	local d = ax * bx + ay * by + az * bz + aw * bw
	if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
	local s0, s1
	if d > 0.9995 then s0, s1 = 1 - t, t else
		local th = math.acos(d); local sn = math.sin(th)
		s0, s1 = math.sin((1 - t) * th) / sn, math.sin(t * th) / sn
	end
	return cf(a.p:Lerp(b.p, t), fromQuat(ax * s0 + bx * s1, ay * s0 + by * s1, az * s0 + bz * s1, aw * s0 + bw * s1))
end
local function angles(x, y, z)
	local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
	local rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mul3(mul3(rx, ry), rz)
end
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local f = (target - at)
	if f.Magnitude < 1e-9 then return cf(at, I3) end
	f = f.Unit
	local rgt = f:Cross(up)
	if rgt.Magnitude < 1e-6 then rgt = f:Cross(v3(0, 0, 1)) end
	rgt = rgt.Unit
	local u = rgt:Cross(f)
	return cf(at, { rgt[1], u[1], -f[1], rgt[2], u[2], -f[2], rgt[3], u[3], -f[3] })
end
local CFrame = {}
function CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then return cf(v3(), I3) end
	if n == 1 then return cf(a[1], I3) end
	if n == 2 then return lookAt(a[1], a[2]) end
	if n == 3 then return cf(v3(a[1], a[2], a[3]), I3) end
	if n == 7 then return cf(v3(a[1], a[2], a[3]), fromQuat(a[4], a[5], a[6], a[7])) end
	if n == 12 then return cf(v3(a[1], a[2], a[3]), { a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] }) end
	error("CFrame.new with " .. n .. " args")
end
CFrame.Angles = function(x, y, z) return cf(v3(), angles(x, y, z)) end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.lookAt = lookAt
CFrame.identity = cf(v3(), I3)
M.CFrame = CFrame

-- value types ----------------------------------------------------------------------------------------
local C3 = {}
C3.__index = function(c, k) if k == "R" then return c[1] elseif k == "G" then return c[2] elseif k == "B" then return c[3] end return C3[k] end
local function c3(r, g, b) return setmetatable({ r or 0, g or 0, b or 0, __t = "Color3" }, C3) end
function C3.Lerp(a, b, t) return c3(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t) end
C3.__eq = function(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
M.Color3 = { new = c3, fromRGB = function(r, g, b) return c3(r / 255, g / 255, b / 255) end }

local UD2 = {}
UD2.__index = UD2
local function ud2(xs, xo, ys, yo) return setmetatable({ xs, xo, ys, yo, __t = "UDim2" }, UD2) end
function UD2.Lerp(a, b, t) local o = {}; for i = 1, 4 do o[i] = a[i] + (b[i] - a[i]) * t end return ud2(o[1], o[2], o[3], o[4]) end
M.UDim2 = { new = ud2, fromScale = function(x, y) return ud2(x, 0, y, 0) end, fromOffset = function(x, y) return ud2(0, x, 0, y) end }
M.UDim = { new = function(s, o) return { s, o, __t = "UDim" } end }
local V2 = {}
V2.__index = function(v, k) if k == "X" then return v[1] elseif k == "Y" then return v[2] end end
M.Vector2 = { new = function(x, y) return setmetatable({ x or 0, y or 0, __t = "Vector2" }, V2) end }
local function plain(tag) return { new = function(...) return { __t = tag, ... } end } end
M.NumberRange = plain("NumberRange")
M.NumberSequence = plain("NumberSequence")
M.ColorSequence = plain("ColorSequence")
M.NumberSequenceKeypoint = plain("NumberSequenceKeypoint")
M.ColorSequenceKeypoint = plain("ColorSequenceKeypoint")
M.TweenInfo = plain("TweenInfo")

-- Enum -----------------------------------------------------------------------------------------------
local enumCache = {}
local VALUES = { RenderPriority = { Camera = 200 } }
M.Enum = setmetatable({}, { __index = function(_, typeName)
	enumCache[typeName] = enumCache[typeName] or setmetatable({ __items = {} }, { __index = function(t, name)
		if name == "GetEnumItems" then
			return function()
				local out = {}
				for _, n in ipairs({ "PlayerList", "Health", "Backpack", "Chat", "All", "EmotesMenu" }) do out[#out + 1] = t[n] end
				return out
			end
		end
		local item = { Name = name, EnumType = typeName, Value = (VALUES[typeName] or {})[name] or 0, __t = "EnumItem" }
		rawset(t, name, item)
		return item
	end })
	return enumCache[typeName]
end })

-- signals --------------------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
M.liveConnections = 0
function Signal.new() return setmetatable({ handlers = {} }, Signal) end
function Signal:Connect(fn)
	local conn = { connected = true, __t = "RBXScriptConnection" }
	M.liveConnections = M.liveConnections + 1
	conn.Disconnect = function(c)
		if c.connected then c.connected = false; M.liveConnections = M.liveConnections - 1 end
	end
	self.handlers[#self.handlers + 1] = { fn = fn, conn = conn }
	return conn
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect(); fn(...) end)
	return c
end
function Signal:Fire(...)
	local list = {}
	for _, h in ipairs(self.handlers) do if h.conn.connected then list[#list + 1] = h end end
	self.handlers = list
	for _, h in ipairs(list) do if h.conn.connected then h.fn(...) end end
end
function Signal:Wait() return nil end
M.Signal = Signal

-- Instances ------------------------------------------------------------------------------------------
local ISA = {
	Part = { "BasePart", "PVInstance" }, WedgePart = { "BasePart", "PVInstance" }, MeshPart = { "BasePart", "PVInstance" },
	Model = { "PVInstance" }, Script = { "BaseScript", "LuaSourceContainer" }, LocalScript = { "BaseScript", "Script", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" }, Motor6D = { "JointInstance" }, Weld = { "JointInstance" },
	StringValue = { "ValueBase" }, IntValue = { "ValueBase" }, NumberValue = { "ValueBase" },
	ScreenGui = { "LayerCollector" }, SurfaceGui = { "LayerCollector" }, BillboardGui = { "LayerCollector" },
	Frame = { "GuiObject" }, TextLabel = { "GuiObject" }, TextButton = { "GuiObject", "GuiButton" },
	BloomEffect = { "PostEffect" }, ColorCorrectionEffect = { "PostEffect" }, SunRaysEffect = { "PostEffect" },
	PointLight = { "Light" }, SurfaceLight = { "Light" }, Folder = {},
}
local DEFAULTS = {
	BasePart = { CFrame = CFrame.identity, Size = v3(4, 1, 2), Anchored = false, Transparency = 0, CanCollide = true, Massless = false, Color = c3(0.6, 0.6, 0.6) },
	Motor6D = { C0 = CFrame.identity, C1 = CFrame.identity, Transform = CFrame.identity, Enabled = true },
	Weld = { C0 = CFrame.identity, C1 = CFrame.identity, Enabled = true },
	WeldConstraint = { Enabled = true },
	ScreenGui = { Enabled = true },
	Camera = { CFrame = CFrame.identity, FieldOfView = 70 },
	Humanoid = { Health = 100 },
	GuiObject = { BackgroundTransparency = 0, TextTransparency = 0, Visible = true },
	Light = { Brightness = 1 },
}
M.allInstances = setmetatable({}, { __mode = "k" })
M.joints = {}
local Inst = {}
local function isA(obj, cls)
	if obj.ClassName == cls or cls == "Instance" then return true end
	for _, c in ipairs(ISA[obj.ClassName] or {}) do if c == cls then return true end end
	return false
end
local SIGNALS = { Activated = true, Ended = true, Completed = true, Event = true, OnClientEvent = true, CharacterAdded = true,
	ChildAdded = true, Changed = true, PreSimulation = true, Heartbeat = true, RenderStepped = true, PlayerAdded = true, PlayerRemoving = true }
local function defaultFor(obj, k)
	local d = DEFAULTS[obj.ClassName]
	if d and d[k] ~= nil then return d[k] end
	for _, c in ipairs(ISA[obj.ClassName] or {}) do
		d = DEFAULTS[c]
		if d and d[k] ~= nil then return d[k] end
	end
	return nil
end
Inst.__index = function(obj, k)
	local props = rawget(obj, "_p")
	local v = props[k]
	if v ~= nil then return v end
	if k == "Position" and isA(obj, "BasePart") then return (props.CFrame or CFrame.identity).p end
	if Inst[k] then return Inst[k] end
	if SIGNALS[k] then local s = Signal.new(); props[k] = s; return s end
	local child = nil
	for _, c in ipairs(rawget(obj, "_c")) do if c.Name == k then child = c break end end
	if child then return child end
	return defaultFor(obj, k)
end
Inst.__newindex = function(obj, k, v)
	local props = rawget(obj, "_p")
	if k == "Parent" then
		local old = props.Parent
		if old == v then return end
		if rawget(obj, "_destroyed") and v ~= nil then error("The Parent property of " .. tostring(props.Name) .. " is locked") end
		if old then
			local list = rawget(old, "_c")
			for i, c in ipairs(list) do if c == obj then table.remove(list, i) break end end
		end
		props.Parent = v
		if v then table.insert(rawget(v, "_c"), obj) end
		return
	end
	if (k == "Part0" or k == "Part1") and obj.ClassName == "WeldConstraint" then
		props[k] = v
		local p0, p1 = props.Part0, props.Part1
		if p0 and p1 then props._offset = p0.CFrame:Inverse() * p1.CFrame end
		return
	end
	props[k] = v
end
Inst.__tostring = function(obj) return obj.Name end
function M.new(className)
	local obj = setmetatable({ _p = { ClassName = className, Name = className }, _c = {}, __t = "Instance" }, Inst)
	M.allInstances[obj] = true
	if className == "Motor6D" or className == "Weld" or className == "WeldConstraint" then table.insert(M.joints, obj) end
	return obj
end
function Inst.IsA(obj, cls) return isA(obj, cls) end
function Inst.GetChildren(obj) local o = {}; for i, c in ipairs(rawget(obj, "_c")) do o[i] = c end return o end
function Inst.GetDescendants(obj)
	local o = {}
	local function walk(x) for _, c in ipairs(rawget(x, "_c")) do o[#o + 1] = c; walk(c) end end
	walk(obj)
	return o
end
function Inst.FindFirstChild(obj, name, recursive)
	for _, c in ipairs(rawget(obj, "_c")) do if c.Name == name then return c end end
	if recursive then for _, c in ipairs(rawget(obj, "_c")) do local f = c:FindFirstChild(name, true); if f then return f end end end
	return nil
end
Inst.WaitForChild = function(obj, name) return obj:FindFirstChild(name) end
function Inst.FindFirstChildOfClass(obj, cls) for _, c in ipairs(rawget(obj, "_c")) do if c.ClassName == cls then return c end end end
function Inst.FindFirstChildWhichIsA(obj, cls, recursive)
	for _, c in ipairs(rawget(obj, "_c")) do if isA(c, cls) then return c end end
	if recursive then for _, c in ipairs(rawget(obj, "_c")) do local f = c:FindFirstChildWhichIsA(cls, true); if f then return f end end end
end
function Inst.Destroy(obj)
	if rawget(obj, "_destroyed") then return end
	for _, c in ipairs(obj:GetChildren()) do c:Destroy() end
	-- like the engine: connections to a destroyed instance's own events are disconnected
	for _, v in pairs(rawget(obj, "_p")) do
		if getmetatable(v) == Signal then
			for _, h in ipairs(v.handlers) do h.conn:Disconnect() end
		end
	end
	obj.Parent = nil
	rawset(obj, "_destroyed", true)
end
function Inst.IsDescendantOf(obj, anc) local p = obj.Parent; while p do if p == anc then return true end p = p.Parent end return false end
function Inst.Clone(obj)
	local map = {}
	local function copy(src)
		local n = M.new(src.ClassName)
		map[src] = n
		for k, v in pairs(rawget(src, "_p")) do if k ~= "Parent" and getmetatable(v) ~= Signal then rawget(n, "_p")[k] = v end end
		for _, c in ipairs(rawget(src, "_c")) do copy(c).Parent = n end
		return n
	end
	local root = copy(obj)
	for src, n in pairs(map) do
		for k, v in pairs(rawget(n, "_p")) do if map[v] then rawget(n, "_p")[k] = map[v] end end
	end
	return root
end
function Inst.GetAttribute(obj, k) return (rawget(obj, "_a") or {})[k] end
function Inst.SetAttribute(obj, k, v) local a = rawget(obj, "_a") or {}; rawset(obj, "_a", a); a[k] = v end
function Inst.GetAttributes(obj) local o = {}; for k, v in pairs(rawget(obj, "_a") or {}) do o[k] = v end return o end
local function parts(obj) local o = {}; if isA(obj, "BasePart") then o[1] = obj end for _, d in ipairs(obj:GetDescendants()) do if isA(d, "BasePart") then o[#o + 1] = d end end return o end
function Inst.GetPivot(obj) if isA(obj, "BasePart") then return obj.CFrame end local pp = obj.PrimaryPart or parts(obj)[1]; return pp and pp.CFrame or CFrame.identity end
function Inst.PivotTo(obj, target)
	local delta = target * obj:GetPivot():Inverse()
	for _, p in ipairs(parts(obj)) do p.CFrame = delta * p.CFrame end
end
function Inst.GetBoundingBox(obj)
	local lo, hi = v3(math.huge, math.huge, math.huge), v3(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts(obj)) do
		local c, s = p.CFrame.p, p.Size * 0.5
		lo = v3(math.min(lo[1], c[1] - s[1]), math.min(lo[2], c[2] - s[2]), math.min(lo[3], c[3] - s[3]))
		hi = v3(math.max(hi[1], c[1] + s[1]), math.max(hi[2], c[2] + s[2]), math.max(hi[3], c[3] + s[3]))
	end
	return CFrame.new((lo + hi) * 0.5), hi - lo
end
function Inst.GetScale(obj) return rawget(obj, "_scale") or 1 end
function Inst.ScaleTo(obj, s)
	local k = s / obj:GetScale()
	local pivot = obj:GetPivot()
	for _, p in ipairs(parts(obj)) do
		local rel = pivot:ToObjectSpace(p.CFrame)
		p.Size = p.Size * k
		p.CFrame = pivot * CFrame.new(rel.p * k) * rel.Rotation
	end
	rawset(obj, "_scale", s)
end
M.emitted = 0
function Inst.Emit(obj, n) M.emitted = M.emitted + n end
M.soundsPlayed = {}
function Inst.Play(obj) if obj.ClassName == "Sound" then M.soundsPlayed[#M.soundsPlayed + 1] = obj.Name; obj.IsPlaying = true elseif obj.ClassName == "Tween" then obj._p.Completed:Fire() end end
function Inst.Stop(obj) obj.IsPlaying = false end
function Inst.Pause(obj) obj.IsPlaying = false; obj.IsPaused = true end
function Inst.Resume(obj) obj.IsPaused = false; obj.IsPlaying = true end
function Inst.LoadAnimation() error("AnimationTracks are not simulated") end
function Inst.Fire(obj, ...) obj.Event:Fire(...) end
function Inst.FireClient(obj, _, ...) obj.OnClientEvent:Fire(...) end
function Inst.GetPlayers(obj) return { obj.LocalPlayer } end

-- kinematic joint solve: anchored parts drive their joint chains (several passes for depth)
function M.solveJoints()
	for _ = 1, 6 do
		for _, j in ipairs(M.joints) do
			if not rawget(j, "_destroyed") and j.Parent then
				local p0, p1 = j.Part0, j.Part1
				if p0 and p1 then
					if j.ClassName == "Motor6D" then
						rawget(p1, "_p").CFrame = p0.CFrame * j.C0 * j.Transform * j.C1:Inverse()
					elseif j.ClassName == "Weld" then
						rawget(p1, "_p").CFrame = p0.CFrame * j.C0 * j.C1:Inverse()
					elseif j.ClassName == "WeldConstraint" then
						local off = rawget(j, "_p")._offset
						if off then
							if p1.Anchored and not p0.Anchored then
								rawget(p0, "_p").CFrame = p1.CFrame * off:Inverse()
							else
								rawget(p1, "_p").CFrame = p0.CFrame * off
							end
						end
					end
				end
			end
		end
	end
end

M.Instance = { new = function(cls, parent) local o = M.new(cls); if parent then o.Parent = parent end return o end }
return M
