--!strict
-- Roblox adapter for Core/Engine: turns property values into number arrays and back, so one engine
-- animates GUI objects, parts, models, lights, emitters and the camera.
--
-- Real properties are read by name. Virtual properties cover things that are not one property:
--   "Scale" on a GuiObject      its "UrkScale" UIScale child (shared with UrkUI's Motion), so
--                               scale effects never fight the object's Size
--   "Pivot" on a Model / part   position {x, y, z} through PivotTo, keeping rotation
--   "PivotCFrame"               full CFrame through PivotTo (position + rotation)
--   "ModelScale" on a Model     ScaleTo / GetScale
--   "GroupFade" on a GuiObject  GroupTransparency on a CanvasGroup (fades children too; prefer
--                               this); otherwise the object's own Background, Image and Text
--                               transparency, leaving children and strokes alone

local SCALE_NAME = "UrkScale"

local Props = {}

local function scaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChild(SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = SCALE_NAME
	scale.Parent = object
	return scale
end
Props.scaleOf = scaleOf

-- CFrames travel as position plus axis-angle scaled by the angle, which interpolates rotations
-- sensibly for the small moves effects make.
local function packCFrame(cf: CFrame): { number }
	local axis, angle = cf:ToAxisAngle()
	return { cf.X, cf.Y, cf.Z, axis.X * angle, axis.Y * angle, axis.Z * angle }
end

local function unpackCFrame(v: { number }): CFrame
	local rotation = Vector3.new(v[4], v[5], v[6])
	local angle = rotation.Magnitude
	if angle < 1e-6 then
		return CFrame.new(v[1], v[2], v[3])
	end
	return CFrame.new(v[1], v[2], v[3]) * CFrame.fromAxisAngle(rotation.Unit, angle)
end

-- Converts a Roblox value to numbers. Returns nil for types that cannot be animated.
function Props.pack(value: any): { number }?
	local kind = typeof(value)
	if kind == "number" then
		return { value }
	elseif kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif kind == "UDim" then
		return { value.Scale, value.Offset }
	elseif kind == "Vector3" then
		return { value.X, value.Y, value.Z }
	elseif kind == "Vector2" then
		return { value.X, value.Y }
	elseif kind == "Color3" then
		return { value.R, value.G, value.B }
	elseif kind == "CFrame" then
		return packCFrame(value)
	elseif kind == "NumberRange" then
		return { value.Min, value.Max }
	elseif kind == "boolean" then
		return nil
	end
	return nil
end

function Props.unpack(kind: string, v: { number }): any
	if kind == "number" then
		return v[1]
	elseif kind == "UDim2" then
		return UDim2.new(v[1], v[2], v[3], v[4])
	elseif kind == "UDim" then
		return UDim.new(v[1], v[2])
	elseif kind == "Vector3" then
		return Vector3.new(v[1], v[2], v[3])
	elseif kind == "Vector2" then
		return Vector2.new(v[1], v[2])
	elseif kind == "Color3" then
		return Color3.new(math.clamp(v[1], 0, 1), math.clamp(v[2], 0, 1), math.clamp(v[3], 0, 1))
	elseif kind == "CFrame" then
		return unpackCFrame(v)
	elseif kind == "NumberRange" then
		return NumberRange.new(math.min(v[1], v[2]), math.max(v[1], v[2]))
	end
	return nil
end

local function readFade(object: GuiObject): number
	if object:IsA("CanvasGroup") then
		return object.GroupTransparency
	elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
		return object.ImageTransparency
	elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		return object.TextTransparency
	end
	return object.BackgroundTransparency
end

local function writeFade(object: GuiObject, value: number)
	local t = math.clamp(value, 0, 1)
	if object:IsA("CanvasGroup") then
		object.GroupTransparency = t
		return
	end
	local any: any = object
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		any.ImageTransparency = t
	elseif object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		any.TextTransparency = t
	end
	-- A fully transparent background stays transparent; a visible one fades with the content.
	local stored = object:GetAttribute("UvkBaseBackground")
	local base: number = if type(stored) == "number" then stored else object.BackgroundTransparency
	if stored == nil then
		object:SetAttribute("UvkBaseBackground", base)
	end
	object.BackgroundTransparency = base + (1 - base) * t
end

local function read(target: any, property: string): { number }?
	if typeof(target) ~= "Instance" then
		-- Plain tables (state objects) animate too: numbers or arrays of numbers.
		local value = target[property]
		if type(value) == "number" then
			return { value }
		elseif type(value) == "table" then
			return table.clone(value)
		end
		return Props.pack(value)
	end
	if property == "Scale" and target:IsA("GuiObject") then
		return { scaleOf(target).Scale }
	elseif property == "GroupFade" and target:IsA("GuiObject") then
		return { readFade(target) }
	elseif property == "Pivot" and target:IsA("PVInstance") then
		local position = target:GetPivot().Position
		return { position.X, position.Y, position.Z }
	elseif property == "PivotCFrame" and target:IsA("PVInstance") then
		return packCFrame(target:GetPivot())
	elseif property == "ModelScale" and target:IsA("Model") then
		return { target:GetScale() }
	end
	local ok, value = pcall(function(): any
		return (target :: any)[property]
	end)
	if not ok then
		return nil
	end
	return Props.pack(value)
end

local function write(target: any, property: string, value: { number })
	if typeof(target) ~= "Instance" then
		target[property] = if type(target[property]) == "table" then table.clone(value) else value[1]
		return
	end
	if property == "Scale" and target:IsA("GuiObject") then
		scaleOf(target).Scale = math.max(0, value[1])
	elseif property == "GroupFade" and target:IsA("GuiObject") then
		writeFade(target, value[1])
	elseif property == "Pivot" and target:IsA("PVInstance") then
		local pivot = target:GetPivot()
		target:PivotTo(pivot.Rotation + Vector3.new(value[1], value[2], value[3]))
	elseif property == "PivotCFrame" and target:IsA("PVInstance") then
		target:PivotTo(unpackCFrame(value))
	elseif property == "ModelScale" and target:IsA("Model") then
		target:ScaleTo(math.max(0.001, value[1]))
	else
		local object: any = target
		object[property] = Props.unpack(typeof(object[property]), value)
	end
end

-- Instances that were in the tree and then left it (destroyed or removed) are dead. An instance
-- that has not been parented yet may still be animated (build, animate, then parent), but only for
-- a short grace period so a forgotten object cannot keep a looping track alive forever.
local parented: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local firstSeen: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local UNPARENTED_GRACE = 10

local function alive(target: any): boolean
	if typeof(target) ~= "Instance" then
		return target ~= nil
	end
	if target.Parent ~= nil or target:IsA("Camera") then
		parented[target] = true
		return true
	end
	if parented[target] then
		return false
	end
	local seen = firstSeen[target]
	if seen == nil then
		firstSeen[target] = os.clock()
		return true
	end
	return os.clock() - seen < UNPARENTED_GRACE
end

Props.adapter = { read = read, write = write, alive = alive }

-- Goal tables given by callers hold Roblox values; the engine wants numbers.
function Props.packAll(values: { [string]: any }?): { [string]: { number } }?
	if values == nil then
		return nil
	end
	local out: { [string]: { number } } = {}
	for property, value in values do
		local packed = Props.pack(value)
		if packed then
			out[property] = packed
		end
	end
	return out
end

return Props
