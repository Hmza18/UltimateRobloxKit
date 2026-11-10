--!strict
-- UI pieces shared by reward reveals and the egg hatch result: the overlay ScreenGui, outlined
-- text, the reward tile (icon, image or 3D model), the ray burst and a small UI particle burst.
-- Everything is plain GuiObjects: no textures are required and nothing here runs per frame.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Host = require("../Runtime/Host")
local Motion = require("../Runtime/Motion")
local Props = require("../Runtime/Props")
local RewardsLogic = require("./RewardsLogic")

export type Reward = {
	name: string?,
	amount: number?,
	icon: string?, -- UrkUI icon name
	image: (string | number)?, -- asset id
	model: (Model | () -> Model?)?,
	subtitle: string?,
	rarity: string?,
	[string]: any,
}

local RewardView = {}

local kit: any = nil
local kitTried = false
local function iconKit(): any
	if not kitTried then
		kitTried = true
		local ok, module = pcall(function(): any
			return require("../../UI/Game/Kit")
		end)
		kit = if ok then module else nil
	end
	return kit
end

local pets: any = nil
local petsTried = false
local function petsModule(): any
	if not petsTried then
		petsTried = true
		local ok, module = pcall(function(): any
			return require("../Pets/Pets")
		end)
		pets = if ok then module else nil
	end
	return pets
end

function RewardView.color(value: any, fallback: Color3?): Color3
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return fallback or Color3.new(1, 1, 1)
end

-- 1250 -> "1,250"; 1250000 -> "1,250,000".
function RewardView.format(value: number): string
	local digits = tostring(math.floor(math.abs(value) + 0.5))
	local out = ""
	while #digits > 3 do
		out = "," .. string.sub(digits, -3) .. out
		digits = string.sub(digits, 1, -4)
	end
	return (if value < 0 then "-" else "") .. digits .. out
end

-- Creates the overlay ScreenGui under `parent` (a PlayerGui or any GUI container) or the local
-- player's PlayerGui. Returns nil when there is nowhere to put it (for example on the server).
function RewardView.screen(parent: Instance?, name: string, displayOrder: number): ScreenGui?
	local target: Instance? = parent
	if target == nil then
		local player = Players.LocalPlayer
		target = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	end
	if target == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = target
	return gui
end

-- A full-size transparent frame padded by the device's safe area and the top bar, so content
-- placed in it never sits under a notch while the backdrop behind it still covers the screen.
function RewardView.safeArea(gui: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Safe"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	local topLeft, bottomRight = GuiService:GetGuiInset()
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, topLeft.Y + 8)
	padding.PaddingLeft = UDim.new(0, topLeft.X + 8)
	padding.PaddingBottom = UDim.new(0, bottomRight.Y + 8)
	padding.PaddingRight = UDim.new(0, bottomRight.X + 8)
	padding.Parent = frame
	frame.Parent = gui
	return frame
end

export type TextProps = {
	text: string,
	parent: Instance,
	color: any?, -- hex or Color3 (default white)
	maxSize: number?, -- pixels (default 28)
	stroke: number?, -- outline thickness (default 2; 0 for none)
	position: UDim2?,
	size: UDim2?,
	anchor: Vector2?,
	name: string?,
	zIndex: number?,
}

-- Chunky outlined text that scales down to fit its box.
function RewardView.text(props: TextProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Text"
	label.BackgroundTransparency = 1
	label.AnchorPoint = props.anchor or Vector2.new(0.5, 0.5)
	label.Position = props.position or UDim2.fromScale(0.5, 0.5)
	label.Size = props.size or UDim2.new(1, 0, 0, 36)
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Text = props.text
	label.TextColor3 = RewardView.color(props.color)
	label.TextScaled = true
	label.ZIndex = props.zIndex or 5
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = props.maxSize or 28
	constraint.MinTextSize = 10
	constraint.Parent = label
	local thickness = props.stroke or 2
	if thickness > 0 then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = thickness
		stroke.Color = Color3.fromRGB(20, 22, 34)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end
	label.Parent = props.parent
	return label
end

-- Shows or hides a label together with its outline.
function RewardView.setTextAlpha(label: TextLabel, transparency: number)
	label.TextTransparency = transparency
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = transparency
	end
end

-- Fades a label (and its outline) in or out.
function RewardView.fadeText(label: TextLabel, transparency: number, duration: number)
	Motion.tween(label, { TextTransparency = transparency }, { duration = duration, easing = "quadOut" })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		Motion.tween(stroke, { Transparency = transparency }, { duration = duration, easing = "quadOut" })
	end
end

local function resolveModel(source: any): Model?
	local value = source
	if type(source) == "function" then
		local ok, result = pcall(source)
		value = if ok then result else nil
	end
	if typeof(value) == "Instance" and value:IsA("Model") then
		return value
	end
	return nil
end

-- Puts a copy of `model` in a ViewportFrame, framed by a camera of its own. Uses Pets.preview
-- when the Pets module is available (it adds idle motion); otherwise a still view.
local function showModel(viewport: ViewportFrame, model: Model): (() -> ())?
	local module = petsModule()
	if module and type(module.preview) == "function" then
		local ok, preview = pcall(module.preview, viewport, model, { spin = true })
		if ok and preview ~= nil then
			return function()
				local handle: any = preview
				if type(handle) == "table" then
					local stop = handle.destroy or handle.stop or handle.cancel
					if type(stop) == "function" then
						pcall(stop, handle)
					end
				end
			end
		end
	end
	local copy = model:Clone()
	local cframe, size = copy:GetBoundingBox()
	copy.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local radius = math.max(size.X, size.Y, size.Z) * 0.5
	local distance = radius / math.tan(math.rad(20)) * 1.25
	local eye = cframe.Position + (cframe.LookVector * 0.9 + Vector3.new(0.35, 0.3, 0)).Unit * distance
	camera.CFrame = CFrame.lookAt(eye, cframe.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return nil
end

-- The reward tile: a rounded card in the rarity's colours holding the reward's icon, image or
-- model. Returns the tile and a cleanup for anything that outlives the Instance (model previews).
function RewardView.tile(reward: Reward, profile: RewardsLogic.Profile, parent: Instance): (Frame, () -> ())
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(0.62, 0.62)
	tile.BackgroundColor3 = Color3.new(1, 1, 1)
	tile.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = tile
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(RewardView.color(profile.color), RewardView.color(profile.secondary))
	gradient.Rotation = 90
	gradient.Parent = tile
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = RewardView.color(profile.glow)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tile

	local cleanup: (() -> ())? = nil
	local model = resolveModel(reward.model)
	local shown = false
	if model then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Model"
		viewport.BackgroundTransparency = 1
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.5)
		viewport.Size = UDim2.fromScale(0.92, 0.92)
		viewport.ZIndex = 5
		viewport.Parent = tile
		cleanup = showModel(viewport, model)
		shown = true
	elseif reward.icon ~= nil or reward.image ~= nil then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.72, 0.72)
		image.ScaleType = Enum.ScaleType.Fit
		image.ZIndex = 5
		local asset: string? = if reward.image ~= nil then tostring(reward.image) else nil
		local helper = iconKit()
		if helper then
			local ok, applied = pcall(helper.icon, image, reward.icon, asset)
			shown = ok and applied == true
		elseif asset then
			image.Image = if string.find(asset, "^%d+$") then "rbxassetid://" .. asset else asset
			shown = true
		end
		if shown then
			image.Parent = tile
		else
			image:Destroy()
		end
	end
	if not shown then
		-- No art: the first letter of the name keeps the tile readable.
		local initial = string.upper(string.sub(reward.name or "?", 1, 1))
		RewardView.text({
			text = if initial == "" then "?" else initial,
			parent = tile,
			size = UDim2.fromScale(0.7, 0.7),
			maxSize = 96,
			stroke = 3,
			name = "Initial",
		})
	end
	tile.Parent = parent
	return tile, function()
		if cleanup then
			cleanup()
			cleanup = nil
		end
	end
end

-- A ray burst: `count` thin gradient bars through the centre of one holder Frame. Rotate the
-- holder to spin the whole burst (one property write per frame, whatever the ray count).
function RewardView.rays(parent: Instance, count: number, color: any): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(2.2, 2.2)
	holder.ZIndex = 1
	local tint = RewardView.color(color)
	-- Each bar spans the full diameter, so half as many bars draw `count` rays.
	local bars = math.max(1, math.ceil(count / 2))
	for index = 1, bars do
		local bar = Instance.new("Frame")
		bar.Name = "Ray"
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(1, if index % 2 == 0 then 0.045 else 0.07)
		bar.Rotation = (index - 1) * 180 / bars
		bar.BackgroundColor3 = tint
		bar.ZIndex = 1
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.25),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = bar
		bar.Parent = holder
	end
	holder.Parent = parent
	return holder
end

-- A soft round glow behind the tile.
function RewardView.glow(parent: Instance, color: any): Frame
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BorderSizePixel = 0
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.05, 1.05)
	glow.BackgroundColor3 = RewardView.color(color)
	glow.BackgroundTransparency = 1
	glow.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = glow
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	fade.Parent = glow
	glow.Parent = parent
	return glow
end

-- A burst of small squares flying out from the centre of `parent`, for reveals that have no
-- world position to play particles at. The count follows the quality profile and intensity.
function RewardView.burst(parent: Instance, color: any, amount: number, spread: number?)
	local settings = Host.settings()
	if settings.reducedMotion then
		return
	end
	local count = math.floor(amount * Host.profile().particleScale * Host.juice("particles") + 0.5)
	local tint = RewardView.color(color)
	local reach = spread or 0.9
	for index = 1, math.clamp(count, 0, 28) do
		local dot = Instance.new("Frame")
		dot.Name = "Spark"
		dot.BorderSizePixel = 0
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		local size = 0.035 + 0.03 * ((index * 7) % 5) / 4
		dot.Size = UDim2.fromScale(size, size)
		dot.Rotation = (index * 47) % 90
		dot.BackgroundColor3 = if index % 3 == 0 then Color3.new(1, 1, 1) else tint
		dot.ZIndex = 6
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = dot
		dot.Parent = parent
		-- Golden-angle spacing spreads the sparks evenly without a random source.
		local angle = index * 2.39996
		local distance = reach * (0.55 + 0.45 * ((index * 5) % 7) / 6)
		local duration = 0.45 + 0.25 * ((index * 3) % 4) / 3
		Motion.tween(dot, {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance),
			Rotation = dot.Rotation + 180,
			BackgroundTransparency = 1,
		}, {
			duration = duration,
			easing = "quartOut",
			onDone = function()
				dot:Destroy()
			end,
		})
	end
end

-- Sets a GuiObject's "Scale" (the shared UrkScale UIScale) without animating.
function RewardView.setScale(object: GuiObject, scale: number)
	Props.scaleOf(object).Scale = scale
end

return RewardView
