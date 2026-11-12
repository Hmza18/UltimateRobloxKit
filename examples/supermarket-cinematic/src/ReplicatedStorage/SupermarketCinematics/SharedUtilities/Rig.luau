-- Cast rigs. Preferred: authentic R15 avatars the server builds from HumanoidDescriptions
-- (ReplicatedStorage.SupermarketCinematics.CastTemplates). Fallback: a block R15 built here with the
-- exact part sizes and joint frames make-anim measured for the blocky R15 (BodyTypeScale 0,
-- ProportionScale 0), so the authored clips land on the same proportions either way.

local Rig = {}

local PARTS = {
	HumanoidRootPart = Vector3.new(2, 2, 1),
	LowerTorso = Vector3.new(2, 0.4, 1),
	UpperTorso = Vector3.new(2, 1.6, 1),
	Head = Vector3.new(1.2, 1.2, 1.2),
}
-- { joint name, Part0, Part1, C0 position, C1 position } (identity rotations, as measured)
local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, -1, 0), Vector3.new(0, -0.2, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", Vector3.new(0, 0.2, 0), Vector3.new(0, -0.8, 0) },
	{ "Neck", "UpperTorso", "Head", Vector3.new(0, 0.8, 0), Vector3.new(0, -0.586, 0) },
}
for _, side in ipairs({ "Right", "Left" }) do
	local s = side == "Right" and 1 or -1
	PARTS[side .. "UpperArm"] = Vector3.new(1, 1.169, 1)
	PARTS[side .. "LowerArm"] = Vector3.new(1, 1.052, 1)
	PARTS[side .. "Hand"] = Vector3.new(1, 0.3, 1)
	PARTS[side .. "UpperLeg"] = Vector3.new(1, 1.217, 1)
	PARTS[side .. "LowerLeg"] = Vector3.new(1, 1.193, 1)
	PARTS[side .. "Foot"] = Vector3.new(1, 0.3, 1)
	local j = {
		{ side .. "Shoulder", "UpperTorso", side .. "UpperArm", Vector3.new(s, 0.563, 0), Vector3.new(-0.5 * s, 0.394, 0) },
		{ side .. "Elbow", side .. "UpperArm", side .. "LowerArm", Vector3.new(0, -0.334, 0), Vector3.new(0, 0.259, 0) },
		{ side .. "Wrist", side .. "LowerArm", side .. "Hand", Vector3.new(0, -0.501, 0), Vector3.new(0, 0.125, 0) },
		{ side .. "Hip", "LowerTorso", side .. "UpperLeg", Vector3.new(0.5 * s, -0.2, 0), Vector3.new(0, 0.421, 0) },
		{ side .. "Knee", side .. "UpperLeg", side .. "LowerLeg", Vector3.new(0, -0.401, 0), Vector3.new(0, 0.379, 0) },
		{ side .. "Ankle", side .. "LowerLeg", side .. "Foot", Vector3.new(0, -0.547, 0), Vector3.new(0, 0.102, 0) },
	}
	for _, e in ipairs(j) do
		JOINTS[#JOINTS + 1] = e
	end
end
Rig.PARTS = PARTS
Rig.JOINTS = JOINTS
Rig.HIP_HEIGHT = 3 -- HumanoidRootPart centre above the floor at rest

-- Role looks: body colours plus simple prop accessories (no catalog assets required).
Rig.LOOKS = {
	Employee = { skin = Color3.fromRGB(255, 204, 153), shirt = Color3.fromRGB(46, 184, 92), pants = Color3.fromRGB(52, 73, 112), hat = "cap", hatColor = Color3.fromRGB(255, 92, 72), apron = Color3.fromRGB(255, 92, 72) },
	Cashier = { skin = Color3.fromRGB(196, 136, 92), shirt = Color3.fromRGB(46, 184, 92), pants = Color3.fromRGB(52, 73, 112), hat = "visor", hatColor = Color3.fromRGB(255, 196, 46), apron = Color3.fromRGB(255, 196, 46) },
	Customer = { skin = Color3.fromRGB(234, 184, 146), shirt = Color3.fromRGB(255, 140, 50), pants = Color3.fromRGB(70, 120, 210), hat = "hair", hatColor = Color3.fromRGB(92, 58, 36) },
	Shopper = { skin = Color3.fromRGB(160, 112, 80), shirt = Color3.fromRGB(150, 90, 230), pants = Color3.fromRGB(60, 60, 70), hat = "hair", hatColor = Color3.fromRGB(30, 30, 34) },
	Shopper2 = { skin = Color3.fromRGB(255, 220, 180), shirt = Color3.fromRGB(70, 200, 220), pants = Color3.fromRGB(230, 220, 200), hat = "hair", hatColor = Color3.fromRGB(230, 170, 60) },
}

local function bodyColor(look, partName)
	if partName:find("Leg") or partName:find("Foot") or partName == "LowerTorso" then
		return look.pants
	elseif partName == "UpperTorso" or partName:find("UpperArm") then
		return look.shirt
	end
	return look.skin
end

local function addFace(head)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CinematicFace"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 1
	local function eye(x)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(0.12, 0.2)
		f.Position = UDim2.fromScale(x, 0.3)
		f.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		f.Parent = gui
	end
	eye(0.28)
	eye(0.6)
	local smile = Instance.new("Frame")
	smile.Size = UDim2.fromScale(0.36, 0.2)
	smile.Position = UDim2.fromScale(0.32, 0.55)
	smile.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 30, 36)
	stroke.Parent = smile
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = smile
	local mask = Instance.new("Frame") -- hides the top half of the ring: leaves a smile
	mask.Size = UDim2.new(1, 8, 0.55, 0)
	mask.Position = UDim2.new(0, -4, 0, -4)
	mask.BorderSizePixel = 0
	mask.BackgroundColor3 = head.Color
	mask.ZIndex = 2
	mask.Name = "SmileMask"
	mask.Parent = smile
	smile.Parent = gui
	gui.Parent = head
	return gui
end

local function weldTo(part, target, offset)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = target.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = target
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	part.Parent = target.Parent
	return part
end

local function block(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = true
	return p
end

-- Simple outfit pieces: a cap / visor / hair block and an apron, welded on (visual only).
function Rig.dress(model, look)
	local head = model:FindFirstChild("Head")
	local chest = model:FindFirstChild("UpperTorso")
	if head and look.hat == "cap" then
		weldTo(block("CinematicCap", Vector3.new(1.3, 0.35, 1.3), look.hatColor), head, CFrame.new(0, 0.62, 0))
		weldTo(block("CinematicCapBrim", Vector3.new(1.2, 0.1, 0.6), look.hatColor), head, CFrame.new(0, 0.48, -0.85))
	elseif head and look.hat == "visor" then
		weldTo(block("CinematicVisor", Vector3.new(1.32, 0.18, 1.32), look.hatColor), head, CFrame.new(0, 0.42, 0))
		weldTo(block("CinematicVisorBrim", Vector3.new(1.2, 0.08, 0.55), look.hatColor), head, CFrame.new(0, 0.38, -0.88))
		weldTo(block("CinematicHair", Vector3.new(1.28, 0.3, 1.28), Color3.fromRGB(40, 28, 22)), head, CFrame.new(0, 0.66, 0.05))
	elseif head and look.hat == "hair" then
		weldTo(block("CinematicHair", Vector3.new(1.3, 0.38, 1.3), look.hatColor), head, CFrame.new(0, 0.6, 0.05))
		weldTo(block("CinematicHairBack", Vector3.new(1.3, 0.8, 0.2), look.hatColor), head, CFrame.new(0, 0.25, 0.58))
	end
	if chest and look.apron then
		weldTo(block("CinematicApron", Vector3.new(1.5, 1.45, 0.08), look.apron), chest, CFrame.new(0, -0.1, -0.52))
		weldTo(block("CinematicNameTag", Vector3.new(0.45, 0.22, 0.05), Color3.fromRGB(255, 255, 255)), chest, CFrame.new(0.42, 0.42, -0.58))
	end
end

-- Block R15 with Motor6Ds, a Humanoid and an Animator. Anchored root: the cinematic moves it.
function Rig.buildBlock(name, look)
	local model = Instance.new("Model")
	model.Name = name
	local parts = {}
	for partName, size in pairs(PARTS) do
		local p = block(partName, size, bodyColor(look, partName))
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		if partName == "HumanoidRootPart" then
			p.Transparency = 1
			p.Anchored = true
			p.CastShadow = false
		end
		parts[partName] = p
		p.Parent = model
	end
	for _, j in ipairs(JOINTS) do
		local m = Instance.new("Motor6D")
		m.Name = j[1]
		m.Part0 = parts[j[2]]
		m.Part1 = parts[j[3]]
		m.C0 = CFrame.new(j[4])
		m.C1 = CFrame.new(j[5])
		m.Parent = parts[j[3]]
	end
	-- lay the parts out at rest so welds made before the first frame are in the right place
	local root = parts.HumanoidRootPart
	local function place(partName)
		for _, j in ipairs(JOINTS) do
			if j[3] == partName then
				parts[partName].CFrame = parts[j[2]].CFrame * CFrame.new(j[4]) * CFrame.new(j[5]):Inverse()
			end
		end
	end
	for _, j in ipairs(JOINTS) do
		place(j[3])
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.EvaluateStateMachine = false
	Instance.new("Animator").Parent = humanoid
	humanoid.Parent = model
	model.PrimaryPart = root
	addFace(parts.Head)
	Rig.dress(model, look)
	return model
end

-- An authentic template if the server provided one, otherwise the block rig.
function Rig.make(role, templates)
	local look = Rig.LOOKS[role] or Rig.LOOKS.Customer
	local template = templates and templates:FindFirstChild(role)
	if template and template:IsA("Model") then
		local model = template:Clone()
		local root = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if root and humanoid and model:FindFirstChild("RightHand") and model:FindFirstChild("LeftHand") then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				elseif d:IsA("BaseScript") then
					d:Destroy()
				end
			end
			root.Anchored = true
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.EvaluateStateMachine = false
			if not humanoid:FindFirstChildOfClass("Animator") then
				Instance.new("Animator").Parent = humanoid
			end
			model.PrimaryPart = root
			model.Name = role
			if not model:GetAttribute("Dressed") then
				Rig.dress(model, look)
			end
			return model, "template"
		end
		model:Destroy()
	end
	return Rig.buildBlock(role, look), "block"
end

return Rig
