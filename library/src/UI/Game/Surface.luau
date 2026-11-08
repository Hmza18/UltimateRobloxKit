--!strict
-- Draws the cartoon surface every container uses, inside a transparent root:
--
--   root (transparent, sized by the component)
--   ├── Shadow   dark rounded copy, offset down (ZIndex 0)
--   └── Body     white frame + vertical UIGradient (palette top -> bottom), UICorner, outline UIStroke
--       ├── Pattern   checker overlay (ZIndex 1)
--       ├── Gloss     white highlight on the top part, fading out (ZIndex 2)
--       └── Content   where the component puts its children (ZIndex 3)
--
-- Pattern: when the style (pattern.image or patternImage) or the props give an image, one
-- ImageLabel tiles it. Otherwise two overlay frames carry hard-edged UIGradient transparency
-- stripes at +45 and -45 degrees; where they cross they make the diamond checker. That is two
-- instances per panel, no images and no per-frame work. A NumberSequence holds at most 20 points,
-- so a frame shows at most 10 stripe segments: cells grow on very large panels (use an image there
-- for an exact cell size). Stripe counts are recomputed only when the panel's 1x size changes.

local Kit = require("./Kit")
local Style = require("../Style/Style")

export type Options = {
	swatch: Style.Swatch,
	radius: number, -- pixels
	outline: number?, -- pixels, 0 for none
	outlineColor: string?,
	gloss: boolean?,
	pattern: boolean?,
	patternImage: string?,
	shadow: boolean?,
	padding: number?,
}

export type Parts = {
	body: Frame,
	content: Frame,
	gradient: UIGradient,
	stroke: UIStroke?,
	shadow: Frame?,
	instances: { Instance },
	connections: { RBXScriptConnection },
}

local Surface = {}

local MAX_SEGMENTS = 10
local EDGE = 0.002

local function frame(name: string, parent: Instance): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	object.Size = UDim2.fromScale(1, 1)
	object.Parent = parent
	return object
end

-- Hard-edged stripes: `segments` equal bands alternating invisible / `alpha`.
function Surface.stripes(segments: number, alpha: number): NumberSequence
	local count = math.clamp(math.floor(segments), 2, MAX_SEGMENTS)
	local points = { NumberSequenceKeypoint.new(0, 1) }
	for index = 1, count - 1 do
		local edge = index / count
		local before = if index % 2 == 1 then 1 else alpha
		local after = if index % 2 == 1 then alpha else 1
		table.insert(points, NumberSequenceKeypoint.new(edge - EDGE, before))
		table.insert(points, NumberSequenceKeypoint.new(edge, after))
	end
	local last = if count % 2 == 1 then 1 else alpha
	table.insert(points, NumberSequenceKeypoint.new(1, last))
	return NumberSequence.new(points)
end

local function buildPattern(style: Style.StyleDef, body: Frame, options: Options, parts: Parts)
	local pattern = style.pattern or {}
	local alpha = pattern.transparency or 0.88
	local cell = math.max(4, pattern.cell or 24)
	local image = options.patternImage or pattern.image or style.patternImage
	if image then
		local tile = Instance.new("ImageLabel")
		tile.Name = "Pattern"
		tile.BackgroundTransparency = 1
		tile.Size = UDim2.fromScale(1, 1)
		tile.Image = if string.find(image, "^%d+$") then "rbxassetid://" .. image else image
		tile.ScaleType = Enum.ScaleType.Tile
		tile.TileSize = UDim2.fromOffset(cell * 2, cell * 2)
		tile.ImageTransparency = alpha
		tile.ZIndex = 1
		Kit.corner(options.radius).Parent = tile
		tile.Parent = body
		return
	end
	local gradients: { UIGradient } = {}
	for index, rotation in { 45, -45 } do
		local layer = frame("Pattern" .. index, body)
		layer.ZIndex = 1
		Kit.corner(options.radius).Parent = layer
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Parent = layer
		table.insert(gradients, gradient)
	end
	local shown = -1
	local function refresh()
		local factor = Kit.scaleFactor(body)
		local size = body.AbsoluteSize / factor
		local diagonal = math.sqrt(size.X * size.X + size.Y * size.Y)
		local segments = math.clamp(math.floor(diagonal / cell + 0.5), 2, MAX_SEGMENTS)
		if segments == shown then
			return
		end
		shown = segments
		local sequence = Surface.stripes(segments, alpha)
		for _, gradient in gradients do
			gradient.Transparency = sequence
		end
	end
	refresh()
	table.insert(parts.connections, body:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh))
end

local function buildGloss(style: Style.StyleDef, body: Frame, options: Options)
	local gloss = style.gloss or {}
	local inset = math.max(2, math.floor((options.outline or 0) / 2) + 2)
	local layer = frame("Gloss", body)
	layer.ZIndex = 2
	layer.AnchorPoint = Vector2.new(0.5, 0)
	layer.Position = UDim2.new(0.5, 0, 0, inset)
	layer.Size = UDim2.new(1, -inset * 2, gloss.heightFraction or 0.45, -inset)
	Kit.corner(math.max(0, options.radius - inset)).Parent = layer
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new(gloss.transparency or 0.78, 1)
	gradient.Parent = layer
end

-- Builds the surface into `root`. Everything created is listed in parts.instances and every
-- connection in parts.connections, so callers can clean both.
function Surface.build(style: Style.StyleDef, root: GuiObject, options: Options): Parts
	local outline = options.outline or Style.outline(style, "regular")
	local body = frame("Body", root)
	body.ZIndex = 1
	Kit.corner(options.radius).Parent = body
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = Kit.sequence(options.swatch.top, options.swatch.bottom)
	gradient.Parent = body
	local content = frame("Content", body)
	content.ZIndex = 3
	content.BackgroundTransparency = 1
	if options.padding and options.padding > 0 then
		Kit.padding(options.padding).Parent = content
	end
	local parts: Parts = { body = body, content = content, gradient = gradient, instances = { body }, connections = {} }
	if outline > 0 then
		local stroke = Kit.stroke(style, nil, options.outlineColor)
		stroke.Thickness = outline
		stroke.Parent = body
		parts.stroke = stroke
	end
	if options.shadow then
		local shadowStyle = style.shadow or {}
		local shadowColor = shadowStyle.color or "#000000"
		local shadowAlpha = shadowStyle.transparency or 0.55
		local shadow = frame("Shadow", root)
		shadow.ZIndex = 0
		shadow.BackgroundColor3 = Color3.fromHex(shadowColor)
		shadow.BackgroundTransparency = shadowAlpha
		shadow.Position = UDim2.fromOffset(0, shadowStyle.offsetY or 4)
		Kit.corner(options.radius).Parent = shadow
		if outline > 0 then
			local edge = Kit.stroke(style, nil, shadowColor)
			edge.Thickness = outline
			edge.Transparency = shadowAlpha
			edge.Parent = shadow
		end
		parts.shadow = shadow
		table.insert(parts.instances, shadow)
	end
	if options.pattern then
		buildPattern(style, body, options, parts)
	end
	if options.gloss then
		buildGloss(style, body, options)
	end
	return parts
end

-- Re-colours a built surface (palette changes, disabled state).
function Surface.paint(parts: Parts, swatch: Style.Swatch)
	parts.gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
end

-- Destroys everything a build created.
function Surface.clear(parts: Parts)
	for _, connection in parts.connections do
		connection:Disconnect()
	end
	for _, instance in parts.instances do
		instance:Destroy()
	end
	table.clear(parts.connections)
	table.clear(parts.instances)
end

return Surface
