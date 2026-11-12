-- Product props for the cinematic.
--
-- Real products: looked up by name (and aliases) under Configuration.ProductContainers. The original is
-- never modified: we clone it, delete every script/value object in the clone (so no gameplay code runs
-- and no configuration is read or written), weld it into one visual prop and scale the clone only.
-- Missing products: a stand-in built from the approved reference geometry
-- (examples/supermarket-reference/products.json, width x depth x height in studs) with flat colours and
-- a printed label. Nothing here touches prices, display quantities or box specifications.

local Products = {}

-- key -> { aliases, size = {w, d, h}, shape, body, band, text, textColor }
Products.CATALOG = {
	TamsCereal = { aliases = { "TamsCereal", "Tam's Cereal", "TamCereal", "Cereal" }, size = { 0.81, 0.3, 1.16 }, shape = "box", body = Color3.fromRGB(235, 64, 52), band = Color3.fromRGB(255, 214, 64), text = "TAM'S\nCEREAL", textColor = Color3.fromRGB(255, 255, 255) },
	SalsSlicedBread = { aliases = { "SalsSlicedBread", "SalsSliceBread", "Sal's Slice Bread", "Bread" }, size = { 0.74, 0.5, 1.25 }, shape = "box", body = Color3.fromRGB(250, 236, 205), band = Color3.fromRGB(60, 130, 230), text = "SAL'S\nBREAD", textColor = Color3.fromRGB(40, 70, 150) },
	Pasta = { aliases = { "Pasta", "RedPasta", "Red Pasta" }, size = { 0.8, 0.5, 1.1 }, shape = "box", body = Color3.fromRGB(214, 40, 48), band = Color3.fromRGB(255, 240, 210), text = "RED\nPASTA", textColor = Color3.fromRGB(255, 255, 255) },
	SUSUsSugar = { aliases = { "SUSUsSugar", "SusuSugar", "Susu's Sugar", "Sugar" }, size = { 0.51, 0.38, 0.72 }, shape = "box", body = Color3.fromRGB(255, 255, 255), band = Color3.fromRGB(255, 120, 170), text = "SUSU'S\nSUGAR", textColor = Color3.fromRGB(220, 60, 120) },
	BlueFlour = { aliases = { "BlueFlour", "Blue Flour", "Flour" }, size = { 0.76, 0.55, 1.15 }, shape = "box", body = Color3.fromRGB(70, 140, 235), band = Color3.fromRGB(255, 255, 255), text = "BLUE\nFLOUR", textColor = Color3.fromRGB(255, 255, 255) },
	BasmatyRice = { aliases = { "BasmatyRice", "BasmatiRice", "Basmaty Rice", "Rice" }, size = { 0.82, 0.5, 1.3 }, shape = "box", body = Color3.fromRGB(240, 200, 90), band = Color3.fromRGB(40, 150, 90), text = "BASMATY\nRICE", textColor = Color3.fromRGB(30, 100, 60) },
	CookingOil = { aliases = { "CookingOil", "Cooking Oil", "Oil" }, size = { 0.49, 0.49, 1.42 }, shape = "bottle", body = Color3.fromRGB(255, 205, 40), band = Color3.fromRGB(40, 150, 70), text = "OIL", textColor = Color3.fromRGB(255, 255, 255) },
	InstantNoodles = { aliases = { "InstantNoodles", "Instant Noodles", "Noodles" }, size = { 0.665, 0.61, 0.78 }, shape = "cup", body = Color3.fromRGB(255, 130, 40), band = Color3.fromRGB(255, 255, 255), text = "NOODLES", textColor = Color3.fromRGB(200, 40, 30) },
	OrangeJuice = { aliases = { "OrangeJuice", "Orange Juice", "OJ" }, size = { 0.78, 0.77, 1.45 }, shape = "carton", body = Color3.fromRGB(255, 150, 30), band = Color3.fromRGB(60, 170, 60), text = "ORANGE\nJUICE", textColor = Color3.fromRGB(255, 255, 255) },
	Milk = { aliases = { "Milk", "CartonMilk", "Carton Milk" }, size = { 0.78, 0.77, 1.45 }, shape = "carton", body = Color3.fromRGB(250, 250, 255), band = Color3.fromRGB(60, 120, 230), text = "MILK", textColor = Color3.fromRGB(40, 90, 200) },
}
Products.ORDER = { "TamsCereal", "SalsSlicedBread", "Pasta", "SUSUsSugar", "BlueFlour", "BasmatyRice", "CookingOil", "InstantNoodles", "OrangeJuice", "Milk" }

local resolved = {} -- key -> original Instance or false (looked up once per session)

local function findPath(path)
	local node = game
	for name in string.gmatch(path, "[^%.]+") do
		if node == game then
			local ok, svc = pcall(game.GetService, game, name)
			node = ok and svc or game:FindFirstChild(name)
		else
			node = node and node:FindFirstChild(name)
		end
		if not node then
			return nil
		end
	end
	return node
end

-- The original instance for a product key, or nil. Read-only lookup.
function Products.findOriginal(key, config)
	if resolved[key] ~= nil then
		return resolved[key] or nil
	end
	local entry = Products.CATALOG[key]
	local found = nil
	for _, path in ipairs(config.ProductContainers or {}) do
		local container = findPath(path)
		if container then
			for _, alias in ipairs(entry.aliases) do
				local hit = container:FindFirstChild(alias, true)
				if hit and (hit:IsA("Model") or hit:IsA("BasePart")) then
					found = hit
					break
				end
			end
		end
		if found then
			break
		end
	end
	resolved[key] = found or false
	return found
end

-- Makes every part of a prop one welded, non-colliding visual assembly around its primary part.
function Products.prepare(prop)
	local primary = prop:IsA("Model") and (prop.PrimaryPart or prop:FindFirstChildWhichIsA("BasePart", true)) or prop
	if prop:IsA("Model") then
		prop.PrimaryPart = primary
	end
	for _, d in ipairs(prop:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("ValueBase") or d:IsA("ProximityPrompt")
			or d:IsA("ClickDetector") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in ipairs(prop:IsA("Model") and prop:GetDescendants() or {}) do
		if d:IsA("BasePart") and d ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	primary.Anchored = true
	primary.CanCollide = false
	primary.CanQuery = false
	primary.CanTouch = false
	-- strip attributes on the clone so nothing reads it as a real product
	for name in pairs(prop:GetAttributes()) do
		prop:SetAttribute(name, nil)
	end
	prop:SetAttribute("SupermarketCinematicProp", true)
	return prop, primary
end

local function label(part, entry, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.6
	local band = Instance.new("Frame")
	band.Size = UDim2.fromScale(1, 0.42)
	band.Position = UDim2.fromScale(0, 0.3)
	band.BorderSizePixel = 0
	band.BackgroundColor3 = entry.band
	band.Parent = gui
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.9, 0.36)
	text.Position = UDim2.fromScale(0.05, 0.33)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.Text = entry.text
	text.TextColor3 = entry.textColor
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(30, 30, 40)
	stroke.Transparency = 0.4
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = part
	return gui
end

-- Stand-in prop (single part + label): front faces -Z, bottom at the pivot's -Y half height.
function Products.standIn(key, scale, withLabel)
	local entry = Products.CATALOG[key]
	local w, d, h = entry.size[1] * scale, entry.size[2] * scale, entry.size[3] * scale
	local p = Instance.new("Part")
	p.Name = key
	p.Color = entry.body
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(w, h, math.max(d, 0.2))
	if entry.shape == "bottle" or entry.shape == "cup" then
		-- bottles and cups read as a body plus a coloured cap (a block keeps the label face flat)
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Size = Vector3.new(w * 0.5, h * 0.12, d * 0.5)
		cap.Color = entry.band
		cap.Material = Enum.Material.SmoothPlastic
		cap.CanCollide = false
		cap.CanQuery = false
		cap.CanTouch = false
		cap.Massless = true
		cap.CFrame = p.CFrame * CFrame.new(0, h * 0.56, 0)
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = p
		wc.Part1 = cap
		wc.Parent = cap
		cap.Parent = p
	elseif entry.shape == "carton" then
		local roof = Instance.new("WedgePart")
		roof.Name = "Gable"
		roof.Size = Vector3.new(w, h * 0.16, d * 0.5)
		roof.Color = entry.body
		roof.CanCollide = false
		roof.CanQuery = false
		roof.CanTouch = false
		roof.Massless = true
		roof.CFrame = p.CFrame * CFrame.new(0, h * 0.58, -d * 0.25)
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = p
		wc.Part1 = roof
		wc.Parent = roof
		roof.Parent = p
	end
	if withLabel ~= false then
		label(p, entry, Enum.NormalId.Front)
	end
	return p
end

-- A prop for `key`: a scaled clone of the real product when it exists, otherwise the stand-in.
-- Returns prop (Model or Part), its primary part, its height and "real" | "standin".
function Products.make(key, config, withLabel)
	local original = Products.findOriginal(key, config)
	if original then
		local ok, clone = pcall(function()
			return original:Clone()
		end)
		if ok and clone then
			local prop, primary = Products.prepare(clone)
			local size
			if prop:IsA("Model") then
				local _, s = prop:GetBoundingBox()
				size = s
				local tallest = math.max(s.X, s.Y, s.Z)
				if tallest > 0 then
					pcall(function()
						prop:ScaleTo(prop:GetScale() * config.ProductDisplayHeight / tallest)
					end)
					local _, s2 = prop:GetBoundingBox()
					size = s2
				end
			else
				size = prop.Size
			end
			prop.Name = key
			return prop, primary, size.Y, "real"
		end
	end
	local p = Products.standIn(key, config.ProductScale, withLabel)
	return p, p, p.Size.Y, "standin"
end

-- Cheap filler for background shelves: one coloured block, no label (keeps part counts low).
function Products.filler(key, scale)
	local entry = Products.CATALOG[key]
	local p = Instance.new("Part")
	p.Name = key
	p.Size = Vector3.new(entry.size[1] * scale, entry.size[3] * scale, math.max(entry.size[2] * scale, 0.2))
	p.Color = entry.body
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

return Products
