--!strict
-- Roblox-facing icon API. Glyphs are white, so ImageColor3 tints them for any theme.
--
--   local Icons = require(path.to.Icons)
--   Icons.configure({ sheets = { "rbxassetid://111", "rbxassetid://222" } })
--   Icons.apply(imageLabel, "coin", { color = Color3.fromRGB(255, 200, 40) })
--   local label = Icons.create("settings", { size = 32 })

local IconCatalog = require("./IconCatalog")

export type Options = { color: Color3?, size: number?, transparency: number? }
export type IconProps = { Image: string, ImageRectOffset: Vector2, ImageRectSize: Vector2 }

local Icons = {}

Icons.configure = IconCatalog.configure
Icons.has = IconCatalog.has
Icons.search = IconCatalog.search
Icons.list = IconCatalog.list
Icons.categories = IconCatalog.categories

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[UrkIcons] " .. message)
	end
end

function Icons.get(name: string): IconProps?
	local rect = IconCatalog.rect(name)
	if not rect then
		warnOnce("missing:" .. name, "no icon named " .. name)
		return nil
	end
	if not rect.image then
		warnOnce("sheet:" .. rect.sheet, "sheet " .. rect.sheet .. " has no asset id; call Icons.configure first")
		return nil
	end
	return {
		Image = rect.image,
		ImageRectOffset = Vector2.new(rect.x, rect.y),
		ImageRectSize = Vector2.new(rect.w, rect.h),
	}
end

function Icons.apply(label: ImageLabel | ImageButton, name: string, options: Options?): boolean
	local props = Icons.get(name)
	if not props then
		return false
	end
	label.Image = props.Image
	label.ImageRectOffset = props.ImageRectOffset
	label.ImageRectSize = props.ImageRectSize
	label.ScaleType = Enum.ScaleType.Fit
	if options then
		if options.color then
			label.ImageColor3 = options.color
		end
		if options.size then
			label.Size = UDim2.fromOffset(options.size, options.size)
		end
		if options.transparency then
			label.ImageTransparency = options.transparency
		end
	end
	return true
end

function Icons.create(name: string, options: Options?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "Icon_" .. name
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(24, 24)
	Icons.apply(label, name, options)
	return label
end

return Icons
