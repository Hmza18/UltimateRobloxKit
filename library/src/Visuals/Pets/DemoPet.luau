--!strict
-- A simple original demo pet built from Parts: a round body with a lighter belly, two ears, two
-- eyes with highlights, cheeks and feet. The selection screen uses it when an entry has no model,
-- so the screen works before a game has any pet art. It faces -Z, its pivot is at its feet.
--
-- NOT run in Studio.

export type Options = {
	color: Color3?, -- body colour (default a soft blue)
	variant: number?, -- 1 round ears, 2 tall ears, 3 leaf sprout (cycles)
	size: number?, -- body diameter in studs (default 2)
	name: string?,
}

local DemoPet = {}

local function ball(name: string, size: Vector3, offset: Vector3, color: Color3, parent: Instance, origin: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = origin * CFrame.new(offset)
	part.Parent = parent
	return part
end

local function shade(color: Color3, amount: number): Color3
	return color:Lerp(if amount >= 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(amount))
end

function DemoPet.build(options: Options?): Model
	local opts: Options = options or {}
	local color = opts.color or Color3.fromRGB(96, 170, 255)
	local d = math.max(0.5, opts.size or 2)
	local variant = ((opts.variant or 1) - 1) % 3 + 1
	local model = Instance.new("Model")
	model.Name = opts.name or "DemoPet"
	local centre = CFrame.new(0, d * 0.55, 0)
	local dark = Color3.fromRGB(34, 34, 48)
	local white = Color3.new(1, 1, 1)

	local body = ball("Body", Vector3.new(d, d * 0.92, d), Vector3.zero, color, model, centre)
	ball("Belly", Vector3.new(d * 0.62, d * 0.56, d * 0.4), Vector3.new(0, -d * 0.14, -d * 0.33), shade(color, 0.55), model, centre)
	for _, side in { -1, 1 } do
		local x = side * d * 0.2
		ball("Eye", Vector3.new(d * 0.16, d * 0.22, d * 0.1), Vector3.new(x, d * 0.12, -d * 0.45), dark, model, centre)
		ball("EyeShine", Vector3.one * d * 0.06, Vector3.new(x - d * 0.03, d * 0.17, -d * 0.49), white, model, centre)
		ball("Cheek", Vector3.new(d * 0.14, d * 0.09, d * 0.06), Vector3.new(side * d * 0.34, -d * 0.02, -d * 0.4), shade(color, 0.35), model, centre)
		ball("Foot", Vector3.new(d * 0.3, d * 0.18, d * 0.36), Vector3.new(side * d * 0.24, -d * 0.46, -d * 0.06), shade(color, -0.18), model, centre)
		if variant == 1 then
			ball("Ear", Vector3.one * d * 0.34, Vector3.new(side * d * 0.36, d * 0.42, 0), shade(color, -0.1), model, centre)
		elseif variant == 2 then
			local ear = ball("Ear", Vector3.new(d * 0.2, d * 0.6, d * 0.16), Vector3.new(side * d * 0.26, d * 0.62, 0), shade(color, -0.1), model, centre)
			ear.CFrame *= CFrame.Angles(0, 0, math.rad(-side * 14))
		end
	end
	if variant == 3 then
		ball("Stem", Vector3.new(d * 0.07, d * 0.3, d * 0.07), Vector3.new(0, d * 0.56, 0), Color3.fromRGB(88, 160, 84), model, centre)
		for _, side in { -1, 1 } do
			local leaf = ball("Leaf", Vector3.new(d * 0.34, d * 0.1, d * 0.2), Vector3.new(side * d * 0.15, d * 0.72, 0), Color3.fromRGB(120, 204, 104), model, centre)
			leaf.CFrame *= CFrame.Angles(0, 0, math.rad(side * 24))
		end
	end
	model.PrimaryPart = body
	-- Pivot at the feet so scaling and ground alignment keep it planted.
	body.PivotOffset = centre:Inverse()
	return model
end

return DemoPet
