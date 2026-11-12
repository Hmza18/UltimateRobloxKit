-- The film set: a bright, toy-like supermarket built locally on the client for the cinematic only.
-- Set-local space: floor at y = 0, the entrance at the origin, the shop interior toward +Z, the street
-- toward -Z. Everything is anchored, non-colliding and parented under one folder that is destroyed after.

local Products = require(script.Parent.Products)

local StoreSet = {}

local C = {
	floor = Color3.fromRGB(246, 244, 238), floorStripe = Color3.fromRGB(110, 200, 140),
	wall = Color3.fromRGB(255, 250, 240), wallTrim = Color3.fromRGB(46, 184, 92),
	facade = Color3.fromRGB(46, 184, 92), header = Color3.fromRGB(255, 255, 255),
	awningA = Color3.fromRGB(255, 92, 72), awningB = Color3.fromRGB(255, 255, 255),
	glass = Color3.fromRGB(170, 220, 255), frame = Color3.fromRGB(60, 70, 90),
	sidewalk = Color3.fromRGB(214, 214, 220), road = Color3.fromRGB(70, 74, 84), grass = Color3.fromRGB(110, 200, 90),
	shelf = Color3.fromRGB(255, 255, 255), shelfSide = Color3.fromRGB(255, 92, 72), shelfBack = Color3.fromRGB(235, 240, 245),
	counter = Color3.fromRGB(255, 196, 46), counterTop = Color3.fromRGB(250, 250, 250), belt = Color3.fromRGB(45, 48, 56),
	crate = Color3.fromRGB(196, 140, 86), box = Color3.fromRGB(214, 168, 112), tape = Color3.fromRGB(240, 220, 170),
}
StoreSet.COLORS = C

-- Marks (set-local). Facing: +Z = into the shop.
local function lookAt(x, z, fx, fz)
	return CFrame.lookAt(Vector3.new(x, 3, z), Vector3.new(x + fx, 3, z + fz))
end
StoreSet.MARKS = {
	EmployeeGreet = lookAt(5.4, -2.6, 0, -1),
	EmployeeBackroom = lookAt(-11.5, 6.4, 1, 0.2),
	EmployeeAtBox = lookAt(-3.0, 8.4, 0, 1),
	EmployeeStock = lookAt(0, 10.55, 0, 1),
	EmployeeAside = lookAt(-11.5, 8.0, 1, 0.3),
	CustomerOutside = lookAt(-1.3, -9.5, 0, 1),
	Cashier = lookAt(11, 7.2, 0, -1),
	CustomerCheckout = lookAt(11.25, 3.75, 0, 1),
	ShopperA = lookAt(-15, 14.3, 1, 0),
	ShopperB = lookAt(12.5, 14.4, 0, 1),
}
StoreSet.SHELF_A = { x0 = -7, x1 = 7, front = 12.0, depth = 1.6, boards = { 0.6, 2.0, 3.7 }, top = 5.4 }
StoreSet.COUNTER = { x0 = 7.8, x1 = 14.6, z0 = 5.0, z1 = 6.5, top = 2.5 }
StoreSet.CRATE_TOP = 1.25

local function part(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function box(parent, name, x0, y0, z0, x1, y1, z1, origin, color, material, extra)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	local center = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return part(parent, name, size, origin * CFrame.new(center), color, material, extra)
end

local function textSurface(p, face, text, color, font, stroke)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.FredokaOne
	label.TextColor3 = color
	if stroke then
		local s = Instance.new("UIStroke")
		s.Thickness = 4
		s.Color = stroke
		s.Parent = label
	end
	label.Parent = gui
	gui.Parent = p
	return gui, label
end

-- Shelf unit facing -Z (its front at z = front), filled with fillers when `fill` is true.
local function shelfUnit(parent, origin, name, x0, x1, front, fill, lowQuality)
	local model = Instance.new("Model")
	model.Name = name
	local depth, top = 1.6, 5.4
	box(model, "Back", x0, 0, front + depth - 0.15, x1, top, front + depth, origin, C.shelfBack)
	box(model, "SideL", x0 - 0.25, 0, front - 0.05, x0, top + 0.2, front + depth, origin, C.shelfSide)
	box(model, "SideR", x1, 0, front - 0.05, x1 + 0.25, top + 0.2, front + depth, origin, C.shelfSide)
	box(model, "Kick", x0, 0, front, x1, 0.6, front + depth, origin, C.shelfSide)
	local header = box(model, "Header", x0 - 0.25, top + 0.2, front - 0.1, x1 + 0.25, top + 1.1, front + 0.2, origin, C.wallTrim)
	textSurface(header, Enum.NormalId.Front, "FRESH DEALS", Color3.new(1, 1, 1), nil, Color3.fromRGB(20, 110, 60))
	for i, y in ipairs({ 0.6, 2.0, 3.7 }) do
		box(model, "Board" .. i, x0, y - 0.12, front, x1, y, front + depth - 0.15, origin, C.shelf)
		box(model, "PriceRail" .. i, x0, y - 0.3, front - 0.06, x1, y, front, origin, Color3.fromRGB(255, 230, 90))
	end
	if fill then
		local keys = Products.ORDER
		local step = lowQuality and 1.5 or 1.0
		for row, y in ipairs({ 0.6, 2.0, 3.7 }) do
			local x, k = x0 + 0.7, row * 3
			while x < x1 - 0.5 do
				k = k % #keys + 1
				local key = keys[k]
				local p = Products.filler(key, 1.0)
				local gap = (row == 1 and 1.25) or 1.5
				if p.Size.Y > gap then
					p.Size = Vector3.new(p.Size.X, gap, p.Size.Z)
				end
				p.CFrame = origin * CFrame.new(x, y + p.Size.Y / 2, front + 0.55)
				p.Parent = model
				x = x + step
			end
		end
	end
	model.Parent = parent
	return model
end

-- Builds the whole set under `parent` at `origin`. Returns a table of handles the director uses.
function StoreSet.build(parent, origin, opts)
	opts = opts or {}
	local lowQuality = opts.lowQuality
	local set = { origin = origin, marks = {}, parts = {} }
	for name, cf in pairs(StoreSet.MARKS) do
		set.marks[name] = origin * cf
	end
	local env = Instance.new("Folder")
	env.Name = "Environment"
	env.Parent = parent
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = parent
	set.envFolder, set.propsFolder = env, props

	-- ground ---------------------------------------------------------------------------------------
	box(env, "Grass", -90, -1.2, -70, 90, -0.12, 70, origin, C.grass, Enum.Material.Grass)
	box(env, "Road", -90, -1.1, -34, 90, -0.3, -14, origin, C.road, Enum.Material.Asphalt)
	for i = -4, 4 do
		box(env, "RoadLine", i * 10 - 2.5, -0.3, -24.25, i * 10 + 2.5, -0.28, -23.75, origin, Color3.fromRGB(255, 255, 255))
	end
	box(env, "Sidewalk", -40, -1, -14, 40, 0, 0, origin, C.sidewalk, Enum.Material.Concrete)
	box(env, "Curb", -40, -1, -14.6, 40, 0.05, -14, origin, Color3.fromRGB(190, 190, 196), Enum.Material.Concrete)
	box(env, "Lot", -40, -1, 0, 40, -0.05, 44, origin, C.sidewalk, Enum.Material.Concrete)

	-- building shell ------------------------------------------------------------------------------
	box(env, "Floor", -18, -0.4, 0, 18, 0, 30, origin, C.floor, Enum.Material.SmoothPlastic)
	for i = 0, 5 do
		box(env, "FloorStripe", -18, 0, 2 + i * 5, 18, 0.02, 2.4 + i * 5, origin, C.floorStripe)
	end
	box(env, "WallBack", -18, 0, 30, 18, 14, 31, origin, C.wall)
	box(env, "WallL", -19, 0, 0, -18, 14, 31, origin, C.wall)
	box(env, "WallR", 18, 0, 0, 19, 14, 31, origin, C.wall)
	box(env, "TrimBack", -18, 6, 29.9, 18, 7, 30, origin, C.wallTrim)
	box(env, "Ceiling", -19, 14, -1, 19, 15, 31, origin, Color3.fromRGB(250, 250, 250))
	-- front wall: piers, low walls and header around big windows and the entrance gap (x -3.5..3.5)
	box(env, "FrontPierL", -19, 0, -1, -17, 14, 0, origin, C.facade)
	box(env, "FrontPierR", 17, 0, -1, 19, 14, 0, origin, C.facade)
	box(env, "FrontPierDoorL", -4.5, 0, -1, -3.5, 10, 0, origin, C.facade)
	box(env, "FrontPierDoorR", 3.5, 0, -1, 4.5, 10, 0, origin, C.facade)
	box(env, "SillL", -17, 0, -1, -4.5, 1.5, 0, origin, C.facade)
	box(env, "SillR", 4.5, 0, -1, 17, 1.5, 0, origin, C.facade)
	box(env, "Header", -19, 10, -1.2, 19, 14.6, 0, origin, C.facade)
	local glassProps = { Transparency = 0.55, Reflectance = 0.15, CastShadow = false }
	box(env, "WindowL", -17, 1.5, -0.6, -4.5, 10, -0.4, origin, C.glass, Enum.Material.Glass, glassProps)
	box(env, "WindowR", 4.5, 1.5, -0.6, 17, 10, -0.4, origin, C.glass, Enum.Material.Glass, glassProps)
	for _, x in ipairs({ -10.75, 10.75 }) do
		box(env, "Mullion", x - 0.15, 1.5, -0.7, x + 0.15, 10, -0.3, origin, C.frame)
	end
	box(env, "DoorFrameTop", -3.5, 9, -1, 3.5, 10, 0, origin, C.frame)

	-- sliding doors (closed at start) -------------------------------------------------------------
	local doorL = box(props, "DoorL", -3.5, 0, -0.55, 0, 9, -0.45, origin, C.glass, Enum.Material.Glass, glassProps)
	local doorR = box(props, "DoorR", 0, 0, -0.65, 3.5, 9, -0.55, origin, C.glass, Enum.Material.Glass, glassProps)
	for _, d in ipairs({ doorL, doorR }) do
		local handle = part(d, "Handle", Vector3.new(0.15, 1.8, 0.25), d.CFrame * CFrame.new(d == doorL and 1.5 or -1.5, 0, -0.1), C.frame)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = d, handle
		w.Parent = handle
		handle.Anchored = false
	end
	set.parts.doorL, set.parts.doorR = doorL, doorR
	set.doorClosed = { L = doorL.CFrame, R = doorR.CFrame }
	set.doorOpen = { L = doorL.CFrame * CFrame.new(-3.3, 0, 0), R = doorR.CFrame * CFrame.new(3.3, 0, 0) }

	-- sign ---------------------------------------------------------------------------------------------
	local signBoard = box(env, "SignBoard", -11, 10.6, -1.6, 11, 13.9, -1.2, origin, C.header)
	local sign = box(props, "SignLetters", -10.5, 10.75, -1.75, 10.5, 13.75, -1.6, origin, C.header, Enum.Material.SmoothPlastic, { Transparency = 1 })
	local _, signLabel = textSurface(sign, Enum.NormalId.Front, opts.storeName or "SUPER MART", Color3.fromRGB(120, 140, 130), Enum.Font.FredokaOne, Color3.fromRGB(20, 110, 60))
	signLabel.Parent.LightInfluence = 1
	local signLight = Instance.new("SurfaceLight")
	signLight.Face = Enum.NormalId.Front
	signLight.Range = 14
	signLight.Angle = 80
	signLight.Brightness = 0
	signLight.Color = Color3.fromRGB(255, 240, 200)
	signLight.Parent = signBoard
	set.parts.sign, set.parts.signLabel, set.parts.signLight, set.parts.signBoard = sign, signLabel, signLight, signBoard

	-- awnings over the windows: alternating stripes, slanted ------------------------------------
	for side = -1, 1, 2 do
		local x0, x1 = side < 0 and -17 or 4.5, side < 0 and -4.5 or 17
		local n = 0
		local x = x0
		while x < x1 - 0.01 do
			local w = math.min(1.25, x1 - x)
			n = n + 1
			local col = (n % 2 == 0) and C.awningB or C.awningA
			part(env, "Awning", Vector3.new(w, 0.25, 3), origin * CFrame.new(x + w / 2, 9.6, -2.1) * CFrame.Angles(math.rad(-22), 0, 0), col)
			x = x + w
		end
	end

	-- outside dressing: planters, lamps, balloons, a bench, carts ----------------------------------
	for _, x in ipairs({ -8, 8 }) do
		box(env, "Planter", x - 1.6, 0, -3.6, x + 1.6, 1.4, -2.2, origin, C.facade)
		for i = -1, 1 do
			part(env, "Bush", Vector3.new(1.6, 1.6, 1.6), origin * CFrame.new(x + i * 1.0, 1.9, -2.9), Color3.fromRGB(70, 170, 80), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
		end
	end
	for _, x in ipairs({ -22, 22 }) do
		box(env, "LampPost", x - 0.25, 0, -11.25, x + 0.25, 11, -10.75, origin, C.frame)
		local lamp = part(env, "LampHead", Vector3.new(1.4, 0.8, 1.4), origin * CFrame.new(x, 11.2, -11), Color3.fromRGB(255, 245, 210), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Range = 10
		l.Brightness = 0.8
		l.Color = Color3.fromRGB(255, 230, 180)
		l.Parent = lamp
	end
	local balloonColors = { Color3.fromRGB(255, 92, 72), Color3.fromRGB(255, 214, 64), Color3.fromRGB(70, 160, 255), Color3.fromRGB(150, 90, 230), Color3.fromRGB(80, 210, 120) }
	set.parts.balloons = {}
	for side = -1, 1, 2 do
		for i = 1, 5 do
			local a = i * 1.3
			local pos = Vector3.new(side * (5.2 + math.cos(a) * 0.6), 7.6 + (i % 3) * 0.9, -1.8 + math.sin(a) * 0.5)
			local b = part(props, "Balloon", Vector3.new(1.1, 1.3, 1.1), origin * CFrame.new(pos), balloonColors[(i + side) % 5 + 1], Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Reflectance = 0.08 })
			part(b, "String", Vector3.new(0.05, pos.Y - 1.2, 0.05), origin * CFrame.new(side * 5.0, (pos.Y - 0.6) / 2, -1.8), Color3.fromRGB(240, 240, 240))
			set.parts.balloons[#set.parts.balloons + 1] = { part = b, base = b.CFrame, phase = i + side }
		end
	end
	box(env, "BenchSeat", -14, 1.1, -6.4, -10, 1.35, -5.6, origin, Color3.fromRGB(160, 110, 70))
	box(env, "BenchLegL", -13.8, 0, -6.2, -13.4, 1.1, -5.8, origin, C.frame)
	box(env, "BenchLegR", -10.6, 0, -6.2, -10.2, 1.1, -5.8, origin, C.frame)
	for i = 0, 2 do
		local x = 12 + i * 0.7
		box(env, "CartBasket", x - 0.9, 1.2, -6.5, x + 0.9, 2.6, -4.5, origin, Color3.fromRGB(200, 205, 215), Enum.Material.DiamondPlate, { Transparency = 0.15 })
		box(env, "CartHandle", x - 0.9, 2.6, -6.6, x + 0.9, 2.8, -6.5, origin, Color3.fromRGB(255, 92, 72))
	end

	-- interior: shelves, crate + box, checkout ---------------------------------------------------
	local sa = StoreSet.SHELF_A
	set.parts.shelfA = shelfUnit(env, origin, "ShelfA", sa.x0, sa.x1, sa.front, false)
	shelfUnit(env, origin, "ShelfB", -16.5, -8, 16, true, lowQuality)
	shelfUnit(env, origin, "ShelfC", 8, 16.5, 16, true, lowQuality)
	if not lowQuality then
		shelfUnit(env, origin, "ShelfD", -12, 12, 27.8, true, lowQuality)
	end
	-- the crate the box rests on (in front of EmployeeAtBox): box centre (0, -1.30, -1.45) in its space
	local atBox = set.marks.EmployeeAtBox
	local crateCF = atBox * CFrame.new(0, -3 + StoreSet.CRATE_TOP / 2, -1.45)
	part(props, "Crate", Vector3.new(1.5, StoreSet.CRATE_TOP, 1.4), crateCF, C.crate, Enum.Material.WoodPlanks)
	local productBox = part(props, "ProductBox", Vector3.new(1.15, 0.9, 1.0), atBox * CFrame.new(0, -1.30, -1.45), C.box, Enum.Material.Cardboard)
	part(productBox, "Tape", Vector3.new(0.3, 0.92, 1.02), productBox.CFrame, C.tape).Anchored = false
	do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = productBox, productBox:FindFirstChild("Tape")
		w.Parent = productBox
		local _, lbl = textSurface(productBox, Enum.NormalId.Front, "FRAGILE • THIS SIDE UP", Color3.fromRGB(150, 90, 40), Enum.Font.GothamBold)
		lbl.Size = UDim2.fromScale(0.9, 0.25)
		lbl.Position = UDim2.fromScale(0.05, 0.1)
	end
	set.parts.productBox = productBox

	local ct = StoreSet.COUNTER
	box(env, "CounterBody", ct.x0, 0, ct.z0, ct.x1, ct.top - 0.15, ct.z1, origin, C.counter)
	box(env, "CounterTop", ct.x0 - 0.1, ct.top - 0.15, ct.z0 - 0.1, ct.x1 + 0.1, ct.top, ct.z1 + 0.1, origin, C.counterTop)
	local belt = box(env, "Belt", 12.0, ct.top, ct.z0 + 0.2, ct.x1 - 0.2, ct.top + 0.04, ct.z1 - 0.2, origin, C.belt)
	set.parts.belt = belt
	local scanner = box(props, "ScannerGlass", 10.45, ct.top, 5.45, 11.55, ct.top + 0.05, 6.15, origin, Color3.fromRGB(60, 20, 20), Enum.Material.Glass, { Transparency = 0.1 })
	local scanLight = Instance.new("PointLight")
	scanLight.Range = 5
	scanLight.Brightness = 0
	scanLight.Color = Color3.fromRGB(80, 255, 140)
	scanLight.Parent = scanner
	set.parts.scanner, set.parts.scanLight = scanner, scanLight
	local register = box(env, "Register", 8.1, ct.top, ct.z1 - 0.9, 9.0, ct.top + 1.0, ct.z1 - 0.1, origin, Color3.fromRGB(60, 64, 76))
	local screen = part(env, "RegisterScreen", Vector3.new(0.9, 0.7, 0.08), origin * CFrame.new(8.55, ct.top + 1.5, ct.z1 - 0.5) * CFrame.Angles(math.rad(-15), math.rad(180), 0), Color3.fromRGB(30, 34, 44))
	local _, total = textSurface(screen, Enum.NormalId.Back, "$0", Color3.fromRGB(120, 255, 160), Enum.Font.Code)
	set.parts.registerTotal = total
	local bag = box(props, "Bag", 9.2, ct.top, 5.35, 10.1, ct.top + 1.05, 6.15, origin, Color3.fromRGB(206, 170, 120), Enum.Material.Fabric)
	set.parts.bag = bag
	set.bagSpot = origin * CFrame.new(9.65, ct.top + 0.8, 5.75)
	local hang = part(env, "CheckoutSign", Vector3.new(4.5, 1.2, 0.2), origin * CFrame.new(11.2, 10.5, 5.75), C.wallTrim)
	textSurface(hang, Enum.NormalId.Front, "CHECKOUT", Color3.new(1, 1, 1), nil, Color3.fromRGB(20, 110, 60))
	box(env, "SignRod", 11.1, 11.1, 5.7, 11.3, 14, 5.8, origin, C.frame)

	-- interior lights (a few, warm) ----------------------------------------------------------------
	for _, p in ipairs({ Vector3.new(-9, 13.6, 8), Vector3.new(9, 13.6, 8), Vector3.new(-9, 13.6, 20), Vector3.new(9, 13.6, 20) }) do
		local panel = part(env, "LightPanel", Vector3.new(6, 0.3, 2), origin * CFrame.new(p), Color3.fromRGB(255, 252, 240), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Range = 24
		l.Brightness = 1.1
		l.Color = Color3.fromRGB(255, 244, 225)
		l.Shadows = false
		l.Parent = panel
	end
	return set
end

-- Shelf A slot for a product held at a wrist target (character space of the stocker): x/z follow the
-- hand (pushed into the shelf), the bottom sits on the nearest board below the wrist.
function StoreSet.slotFor(set, stockerCF, wristLocal, height)
	local wrist = stockerCF * wristLocal
	local localWrist = set.origin:PointToObjectSpace(wrist)
	local board = StoreSet.SHELF_A.boards[1]
	for _, y in ipairs(StoreSet.SHELF_A.boards) do
		if y <= localWrist.Y - 0.3 then
			board = y
		end
	end
	local z = math.max(localWrist.Z + 0.35, StoreSet.SHELF_A.front + 0.5)
	return set.origin * CFrame.new(localWrist.X, board + height / 2, z)
end

return StoreSet
