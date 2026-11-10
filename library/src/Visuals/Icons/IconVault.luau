--!strict
-- Visuals.Icons: imported icon packs in the game. One call works for pack icons and the kit's own
-- icons:
--
--   local Icons = Visuals.Icons
--   Icons.register("mypack", require(ReplicatedStorage.Shared.MypackIcons)) -- from `vault.py registry`
--   Icons.apply(imageLabel, "mypack:sword")                 -- a pack icon, in its own colours
--   Icons.apply(imageLabel, "coin", { color = gold })       -- not in a pack: the kit's tintable glyph
--   local tile = Icons.container("mypack:sword", { size = 72, palette = "purple", parent = row })
--   local pulse = Icons.animated("mypack:gem", "Pulse", { parent = hud })
--   local picker = Icons.picker({ parent = playerGui, onPick = function(id) print(id) end })
--
-- Pack icons are never recoloured: ImageColor3 stays white unless options.tint is given. Theming
-- happens around the icon (container background, gradient and outline from the active UrkUI
-- style), and animation moves the container Frame, not the image.
--
-- NOT run in Studio: everything below that creates Instances is NEEDS MANUAL REVIEW. The pure
-- rules (lookup, search, grid maths) are in IconVaultLogic and are Lune-tested.

local IconVaultLogic = require("./IconVaultLogic")
local Signal = require("../../Util/Signal")
local Style = require("../../UI/Style/Style")
local Trove = require("../../Util/Trove")

export type Entry = IconVaultLogic.Entry

export type ApplyOptions = {
	size: number?, -- pixels; sets the label to a square of this size
	tint: Color3?, -- recolours ANY icon, pack icons included. Leave nil to keep a pack icon's own colours
	color: Color3?, -- tint for the kit's white glyphs only; ignored for pack icons
	transparency: number?,
	style: string?, -- kit icons: "glyph" | "color"
}

export type ContainerOptions = {
	size: number?, -- pixels, default 64
	padding: number?, -- fraction of the container left around the icon, default 0.16
	palette: string?, -- a palette of the active style ("purple", "gold", ...)
	surface: string?, -- used when no palette is given: "inset" (default) | "window" | "dark"
	gradient: boolean?, -- default true
	stroke: boolean?, -- default true
	outline: string?, -- outline weight: "thin" (default) | "regular" | "thick" | "heavy"
	radius: string?, -- radius token, default "md"; "pill" makes a circle
	button: boolean?, -- true builds a TextButton root so it can be clicked and bound
	style: string?, -- UrkUI style name; default is the active style
	tint: Color3?,
	color: Color3?,
	iconStyle: string?,
	parent: Instance?,
	name: string?,
	layoutOrder: number?,
	position: UDim2?,
	anchor: Vector2?,
	animation: { [string]: any }?, -- animated(): options passed to UI.animate
	bind: (string | boolean)?, -- animated(): also wire hover / press states with UI.bind (true or a style name)
}

export type Container = {
	Instance: GuiObject,
	Icon: ImageLabel,
	name: string,
	setIcon: (self: Container, name: string) -> boolean,
	restyle: (self: Container, styleName: string?) -> (),
	stop: (self: Container) -> (),
	cancel: (self: Container) -> (),
	destroy: (self: Container) -> (),
	Destroy: (self: Container) -> (),
}

export type PickerProps = {
	parent: Instance,
	title: string?,
	pack: string?, -- only this pack
	category: string?, -- start on this category
	query: string?,
	cell: number?, -- cell size in pixels, default 76
	gap: number?, -- default 8
	size: UDim2?, -- default 560 x 440
	position: UDim2?,
	anchor: Vector2?,
	style: string?,
	closeOnPick: boolean?, -- destroy the picker after a choice
	onPick: ((id: string, entry: Entry) -> ())?,
}

export type Picker = {
	Instance: GuiObject,
	Picked: Signal.Signal, -- (id, entry)
	setQuery: (self: Picker, text: string) -> (),
	setCategory: (self: Picker, category: string?) -> (),
	refresh: (self: Picker) -> (),
	selected: (self: Picker) -> string?,
	destroy: (self: Picker) -> (),
	Destroy: (self: Picker) -> (),
}

local IconVault = {}

IconVault.Logic = IconVaultLogic

-- Passthroughs to the pure registry.
IconVault.register = IconVaultLogic.register
IconVault.unregister = IconVaultLogic.unregister
IconVault.get = IconVaultLogic.get
IconVault.search = IconVaultLogic.search
IconVault.categories = IconVaultLogic.categories
IconVault.list = IconVaultLogic.list
IconVault.autocomplete = IconVaultLogic.autocomplete
IconVault.packs = IconVaultLogic.packs
IconVault.info = IconVaultLogic.info
IconVault.assetId = IconVaultLogic.assetId
IconVault.missingAssetIds = IconVaultLogic.missingAssetIds
IconVault.setAssetIds = IconVaultLogic.setAssetIds
IconVault.setSheetIds = IconVaultLogic.setSheetIds
IconVault.setDefaultPack = IconVaultLogic.setDefaultPack
IconVault.defaultPack = IconVaultLogic.defaultPack

local WHITE = Color3.new(1, 1, 1)

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[Visuals.Icons] " .. message)
	end
end

-- The kit's own icon module, loaded on first use. `kitOriginal` holds its untouched functions so
-- the bridge below can wrap them without ever calling itself.
local kitLoaded = false
local kitModule: any = nil
local kitOriginal: { apply: any, has: any, get: any }? = nil

local function kit(): any
	if not kitLoaded then
		kitLoaded = true
		local ok, result = pcall(function(): any
			return require("../../Icons/Icons")
		end)
		if ok and type(result) == "table" then
			kitModule = result
		else
			warnOnce("kit", "the kit Icons module is not available: " .. tostring(result))
		end
	end
	return kitModule
end

local function kitHas(name: string): boolean
	local module = kit()
	if module == nil then
		return false
	end
	local has = if kitOriginal then kitOriginal.has else module.has
	local ok, result = pcall(has, name)
	return ok and result == true
end

local function kitApply(label: ImageLabel | ImageButton, name: string, options: ApplyOptions?): boolean
	local module = kit()
	if module == nil then
		return false
	end
	local apply = if kitOriginal then kitOriginal.apply else module.apply
	local opts: ApplyOptions = options or {}
	local ok, result = pcall(apply, label, name, {
		color = opts.tint or opts.color,
		size = opts.size,
		transparency = opts.transparency,
		style = opts.style,
	})
	return ok and result == true
end

-- Applies settings in one call: { defaultPack = "mypack", assetIds = { mypack = { sword = 123 } },
-- sheets = { mypack = { "rbxassetid://1", "rbxassetid://2" } } }.
function IconVault.configure(options: {
	defaultPack: string?,
	assetIds: { [string]: { [string]: any } }?,
	sheets: { [string]: { any } }?,
})
	if options.defaultPack then
		IconVaultLogic.setDefaultPack(options.defaultPack)
	end
	if options.assetIds then
		for pack, ids in options.assetIds do
			IconVaultLogic.setAssetIds(pack, ids)
		end
	end
	if options.sheets then
		for pack, ids in options.sheets do
			IconVaultLogic.setSheetIds(pack, ids)
		end
	end
end

-- True when the name is a pack icon or a kit icon.
function IconVault.has(name: string): boolean
	return IconVaultLogic.has(name) or kitHas(name)
end

-- Shows icon `name` on an ImageLabel or ImageButton. Pack icons come first ("pack:name" or a bare
-- name found in a pack); anything else goes to the kit's Icons module. Returns false when nothing
-- could be shown (unknown name, or a pack icon whose image has not been uploaded and mapped yet).
function IconVault.apply(label: ImageLabel | ImageButton, name: string, options: ApplyOptions?): boolean
	local opts: ApplyOptions = options or {}
	local entry = IconVaultLogic.get(name)
	if entry ~= nil then
		local image = IconVaultLogic.image(entry.id)
		if image ~= nil then
			local target = label :: any
			target.Image = image.image
			local rect = image.rect
			if rect then
				target.ImageRectOffset = Vector2.new(rect.x, rect.y)
				target.ImageRectSize = Vector2.new(rect.w, rect.h)
			else
				target.ImageRectOffset = Vector2.zero
				target.ImageRectSize = Vector2.zero
			end
			target.ScaleType = Enum.ScaleType.Fit
			-- White is "no tint": the pack icon keeps its own colours unless a tint was asked for.
			target.ImageColor3 = opts.tint or WHITE
			if opts.size then
				target.Size = UDim2.fromOffset(opts.size, opts.size)
			end
			if opts.transparency then
				target.ImageTransparency = opts.transparency
			end
			return true
		end
		warnOnce(
			"unmapped:" .. entry.id,
			entry.id .. " has no asset id yet: upload it, then run `vault.py registry --map` or call setAssetIds"
		)
		if string.find(name, ":", 1, true) ~= nil then
			return false
		end
	end
	return kitApply(label, name, opts)
end

-- A new ImageLabel showing the icon (24 px unless options.size is given).
function IconVault.create(name: string, options: ApplyOptions?): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "Icon_" .. string.gsub(name, ":", "_")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(24, 24)
	IconVault.apply(label, name, options)
	return label
end

-- Containers ---------------------------------------------------------------------------------------

local live: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local uiLoaded = false
local uiModule: any = nil

-- The UI animation library (Visuals/UI/UIAnimations), loaded on first use and guarded: without it
-- animated() still returns a working, static container.
local function animations(): any
	if not uiLoaded then
		uiLoaded = true
		local ok, result = pcall(function(): any
			return require("../UI/UIAnimations")
		end)
		if ok and type(result) == "table" then
			uiModule = result
		else
			warnOnce("ui", "UI animations are not available, icons stay static: " .. tostring(result))
		end
	end
	return uiModule
end

local function paint(root: GuiObject, parts: { [string]: any }, options: ContainerOptions, styleName: string?)
	local style = Style.get(styleName or options.style)
	local swatch = if options.palette
		then Style.palette(style, options.palette)
		else Style.surface(style, options.surface or "inset")
	local top = Color3.fromHex(swatch.top)
	local bottom = Color3.fromHex(swatch.bottom)
	local gradient: UIGradient = parts.gradient
	if options.gradient == false then
		root.BackgroundColor3 = top
		gradient.Enabled = false
	else
		root.BackgroundColor3 = WHITE
		gradient.Color = ColorSequence.new(top, bottom)
		gradient.Enabled = true
	end
	local radii = style.radius
	local radius: number = radii[options.radius or "md"] or radii.md
	local corner: UICorner = parts.corner
	corner.CornerRadius = if options.radius == "pill" then UDim.new(0.5, 0) else UDim.new(0, radius)
	local stroke: UIStroke = parts.stroke
	stroke.Enabled = options.stroke ~= false
	stroke.Color = Color3.fromHex(Style.outlineColor(style))
	stroke.Thickness = Style.outline(style, options.outline or "thin")
end

-- A themed tile holding an icon: rounded background, outline and gradient from the active UrkUI
-- style (or options.style). The icon itself is untouched, which is how pack icons follow a theme
-- without being recoloured. container:restyle() re-reads the style after a theme change.
function IconVault.container(name: string, options: ContainerOptions?): Container
	local opts: ContainerOptions = options or {}
	local trove = Trove.new()
	local size = opts.size or 64

	local root: GuiObject
	if opts.button then
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		root = button
	else
		root = Instance.new("Frame")
	end
	root.Name = opts.name or ("IconTile_" .. string.gsub(name, ":", "_"))
	root.Size = UDim2.fromOffset(size, size)
	root.BorderSizePixel = 0
	root.BackgroundTransparency = 0
	if opts.layoutOrder then
		root.LayoutOrder = opts.layoutOrder
	end
	if opts.position then
		root.Position = opts.position
	end
	if opts.anchor then
		root.AnchorPoint = opts.anchor
	end
	trove:Add(root)

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = root
	local corner = Instance.new("UICorner")
	corner.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = root
	local parts: { [string]: any } = { gradient = gradient, corner = corner, stroke = stroke }

	local inset = math.clamp(opts.padding or 0.16, 0, 0.45)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1 - 2 * inset, 1 - 2 * inset)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = root

	local applyOptions: ApplyOptions = { tint = opts.tint, color = opts.color, style = opts.iconStyle }
	local container = {} :: Container
	container.Instance = root
	container.Icon = icon
	container.name = name
	local stopAnimation: (() -> ())? = nil
	local destroyed = false

	function container.setIcon(self: Container, newName: string): boolean
		self.name = newName
		local shown = IconVault.apply(icon, newName, applyOptions)
		icon.Visible = shown
		return shown
	end

	function container.restyle(_self: Container, styleName: string?)
		if not destroyed then
			paint(root, parts, opts, styleName)
		end
	end

	-- Stops any animation started by animated(); the tile stays. Safe to call twice.
	function container.stop(_self: Container)
		local stopper = stopAnimation
		stopAnimation = nil
		if stopper then
			stopper()
		end
	end
	container.cancel = container.stop

	function container.destroy(self: Container)
		if destroyed then
			return
		end
		destroyed = true
		self:stop()
		live[self] = nil
		trove:Destroy()
	end
	container.Destroy = container.destroy

	local internal: any = container
	internal._onStop = function(stopper: () -> ())
		local previous = stopAnimation
		stopAnimation = function()
			if previous then
				previous()
			end
			stopper()
		end
	end

	paint(root, parts, opts, nil)
	container:setIcon(name)
	live[container] = true
	-- A tile destroyed from outside (its parent was destroyed) must not keep an animation running.
	trove:Connect(root.Destroying, function()
		container:destroy()
	end)
	if opts.parent then
		root.Parent = opts.parent
	end
	return container
end

-- Re-reads the active style for every live container. Call it after switching the UrkUI style or
-- the Visuals theme.
function IconVault.refresh()
	for container in live do
		container:restyle()
	end
end

-- A container whose Frame plays a UI animation preset (Visuals.UI.animate). The image asset is
-- never animated or altered; the tile around it moves. With options.bind the tile is built as a
-- button and gets hover / press states from Visuals.UI.bind. container:stop() ends the animation.
function IconVault.animated(name: string, presetId: string?, options: ContainerOptions?): Container
	local opts: ContainerOptions = if options then table.clone(options) else {}
	if opts.bind then
		opts.button = true
	end
	local container = IconVault.container(name, opts)
	local ui = animations()
	if ui == nil then
		return container
	end
	local onStop = (container :: any)._onStop
	if presetId ~= nil and type(ui.animate) == "function" then
		local ok, handle = pcall(ui.animate, container.Instance, presetId, opts.animation)
		if ok and type(handle) == "table" then
			onStop(function()
				local stop = handle.stop or handle.cancel
				if type(stop) == "function" then
					-- UI handles take stop(restore?), not a self argument: put the tile back at rest.
					pcall(stop, true)
				end
			end)
		elseif not ok then
			warnOnce("preset:" .. presetId, "UI.animate failed for " .. presetId .. ": " .. tostring(handle))
		end
	end
	if opts.bind and type(ui.bind) == "function" then
		local bindStyle = if type(opts.bind) == "string" then opts.bind else nil
		-- UI.bind returns a binding (a table with destroy that can also be called); older shapes
		-- returned a plain cleanup function. Both are handled.
		local ok, binding = pcall(ui.bind, container.Instance, bindStyle)
		if ok and binding ~= nil then
			onStop(function()
				if type(binding) == "table" and type(binding.destroy) == "function" then
					pcall(binding.destroy, binding)
				else
					pcall(binding)
				end
			end)
		elseif not ok then
			warnOnce("bind", "UI.bind failed: " .. tostring(binding))
		end
	end
	return container
end

-- Picker -------------------------------------------------------------------------------------------

type Cell = { button: TextButton, icon: ImageLabel, label: TextLabel, index: number, connection: any }

-- An in-game icon picker: search box, category tabs and a scrolling grid. The grid is virtualised
-- (cells exist only for the rows near the viewport and are recycled while scrolling), so an
-- 800-icon pack costs a few dozen instances. Built on the UrkUI Game components (Panel,
-- CartoonButton, GameText). picker.Picked fires with (id, entry); props.onPick is called too.
function IconVault.picker(props: PickerProps): Picker
	local Game: any = require("../../UI/Game/Game")
	local style = Style.get(props.style)
	local trove = Trove.new()
	local cellSize = math.max(40, props.cell or 76)
	local gap = math.max(0, props.gap or 8)
	local destroyed = false

	local panel = Game.Panel.new({
		surface = "window",
		style = props.style,
		size = props.size or UDim2.fromOffset(560, 440),
		position = props.position or UDim2.fromScale(0.5, 0.5),
		anchor = props.anchor or Vector2.new(0.5, 0.5),
		name = "IconPicker",
		padding = "md",
	})
	trove:Add(panel)
	local content: Instance = panel.Content
	local windowText = Color3.fromHex(Style.surface(style, "window").text)
	local insetSwatch = Style.surface(style, "inset")
	local radii = style.radius

	local headerHeight = 0
	if props.title and props.title ~= "" then
		headerHeight = 34
		local title = Game.GameText.new({
			text = props.title,
			role = "heading",
			align = "left",
			size = UDim2.new(1, 0, 0, 28),
			parent = content,
			name = "Title",
		})
		trove:Add(title)
	end

	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Size = UDim2.new(1, 0, 0, 36)
	search.Position = UDim2.fromOffset(0, headerHeight)
	search.BackgroundColor3 = Color3.fromHex(insetSwatch.top)
	search.TextColor3 = Color3.fromHex(insetSwatch.text)
	search.PlaceholderColor3 = Color3.fromHex(insetSwatch.text):Lerp(Color3.fromHex(insetSwatch.top), 0.45)
	search.PlaceholderText = "Search icons"
	search.Text = props.query or ""
	search.ClearTextOnFocus = false
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.TextSize = Style.textSize(style, "label")
	search.Font = Enum.Font.GothamMedium
	search.BorderSizePixel = 0
	search.Parent = content
	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, radii.sm or radii.md)
	searchCorner.Parent = search
	local searchPadding = Instance.new("UIPadding")
	searchPadding.PaddingLeft = UDim.new(0, 10)
	searchPadding.PaddingRight = UDim.new(0, 10)
	searchPadding.Parent = search

	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Categories"
	tabs.Size = UDim2.new(1, 0, 0, 40)
	tabs.Position = UDim2.fromOffset(0, headerHeight + 44)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.ScrollBarThickness = 0
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new()
	tabs.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabs

	local top = headerHeight + 92
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.new(1, 0, 1, -top)
	scroll.Position = UDim2.fromOffset(0, top)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = content

	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Size = UDim2.new(1, 0, 0, 40)
	empty.Position = UDim2.fromOffset(0, top + 8)
	empty.TextColor3 = windowText
	empty.TextSize = Style.textSize(style, "label")
	empty.Font = Enum.Font.GothamMedium
	empty.TextWrapped = true
	empty.Visible = false
	empty.Parent = content

	local picker = {} :: Picker
	picker.Instance = panel.Instance
	picker.Picked = Signal.new()

	local category: string? = props.category
	local results: { string } = {}
	local selectedId: string? = nil
	local active: { [number]: Cell } = {}
	local free: { Cell } = {}
	local tabButtons: { [string]: any } = {}

	local function choose(id: string)
		local entry = IconVaultLogic.get(id)
		if entry == nil then
			return
		end
		selectedId = id
		picker.Picked:Fire(id, entry)
		if props.onPick then
			props.onPick(id, entry)
		end
		if props.closeOnPick then
			picker:destroy()
		end
	end

	local function newCell(): Cell
		local button = Instance.new("TextButton")
		button.Name = "Cell"
		button.Text = ""
		button.AutoButtonColor = true
		button.BackgroundColor3 = Color3.fromHex(insetSwatch.top)
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(cellSize, cellSize)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radii.sm or radii.md)
		corner.Parent = button
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.Size = UDim2.fromOffset(cellSize - 30, cellSize - 30)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = button
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0, 1)
		label.Position = UDim2.new(0, 3, 1, -3)
		label.Size = UDim2.new(1, -6, 0, 18)
		label.TextColor3 = Color3.fromHex(insetSwatch.text)
		label.TextSize = 11
		label.Font = Enum.Font.Gotham
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = button
		local cell: Cell = { button = button, icon = icon, label = label, index = 0, connection = nil }
		cell.connection = button.Activated:Connect(function()
			local id = results[cell.index]
			if id then
				choose(id)
			end
		end)
		return cell
	end

	local function release(index: number)
		local cell = active[index]
		if cell then
			active[index] = nil
			cell.button.Parent = nil
			table.insert(free, cell)
		end
	end

	local layout = IconVaultLogic.gridLayout(0, 0, cellSize, gap)

	-- Creates, recycles and positions only the cells near the viewport.
	local function update()
		if destroyed then
			return
		end
		local first, last = IconVaultLogic.visibleRange(layout, scroll.CanvasPosition.Y, scroll.AbsoluteWindowSize.Y, 1)
		for index in active do
			if index < first or index > last then
				release(index)
			end
		end
		for index = first, last do
			if active[index] == nil then
				local id = results[index]
				local entry = if id then IconVaultLogic.get(id) else nil
				if entry then
					local cell = table.remove(free) or newCell()
					cell.index = index
					local x, y = IconVaultLogic.cellPosition(layout, index)
					cell.button.Position = UDim2.fromOffset(x, y)
					cell.label.Text = entry.name
					local shown = IconVault.apply(cell.icon, entry.id)
					cell.icon.Visible = shown
					-- Not uploaded yet: the cell stays pickable and shows the name only, dimmed.
					cell.button.BackgroundTransparency = if shown then 0 else 0.5
					cell.button.Parent = scroll
					active[index] = cell
				end
			end
		end
	end

	local function relayout()
		layout = IconVaultLogic.gridLayout(#results, scroll.AbsoluteWindowSize.X - 8, cellSize, gap)
		scroll.CanvasSize = UDim2.fromOffset(0, layout.height)
		for index in active do
			release(index)
		end
		update()
	end

	local function paintTabs()
		for key, button in tabButtons do
			local on = (key == "" and category == nil) or key == category
			button:update({ kind = if on then "primary" else "neutral" })
		end
	end

	function picker.refresh(_self: Picker)
		if destroyed then
			return
		end
		local query = search.Text
		local found: { string }
		if string.find(query, "%w") ~= nil then
			found = IconVaultLogic.search(if props.pack then props.pack .. ":" .. query else query)
			if category ~= nil then
				local kept: { string } = {}
				for _, id in found do
					local entry = IconVaultLogic.get(id)
					if entry and entry.category == category then
						table.insert(kept, id)
					end
				end
				found = kept
			end
		else
			found = IconVaultLogic.list({ pack = props.pack, category = category })
		end
		results = found
		empty.Visible = #results == 0
		if #results == 0 then
			empty.Text = if #IconVaultLogic.packs() == 0
				then "No icon pack is registered yet. Call Visuals.Icons.register(name, data)."
				else "No icons match."
		end
		scroll.CanvasPosition = Vector2.zero
		relayout()
	end

	function picker.setQuery(self: Picker, text: string)
		search.Text = text
		self:refresh()
	end

	function picker.setCategory(self: Picker, value: string?)
		category = value
		paintTabs()
		self:refresh()
	end

	function picker.selected(_self: Picker): string?
		return selectedId
	end

	function picker.destroy(_self: Picker)
		if destroyed then
			return
		end
		destroyed = true
		for _, cell in active do
			cell.connection:Disconnect()
			cell.button:Destroy()
		end
		for _, cell in free do
			cell.connection:Disconnect()
			cell.button:Destroy()
		end
		table.clear(active)
		table.clear(free)
		picker.Picked:DisconnectAll()
		trove:Destroy()
	end
	picker.Destroy = picker.destroy

	local function addTab(key: string, text: string, order: number)
		local button = Game.CartoonButton.new({
			text = text,
			kind = "neutral",
			size = UDim2.fromOffset(math.clamp(#text * 9 + 28, 56, 180), 32),
			layoutOrder = order,
			parent = tabs,
			style = props.style,
			radius = "sm",
			name = "Tab_" .. text,
		})
		trove:Add(button)
		tabButtons[key] = button
		button.Activated:Connect(function()
			picker:setCategory(if key == "" then nil else key)
		end)
	end

	addTab("", "All", 0)
	for order, name in IconVaultLogic.categories(props.pack) do
		addTab(name, name, order)
	end
	paintTabs()

	trove:Connect(search:GetPropertyChangedSignal("Text"), function()
		picker:refresh()
	end)
	trove:Connect(scroll:GetPropertyChangedSignal("CanvasPosition"), update)
	trove:Connect(scroll:GetPropertyChangedSignal("AbsoluteWindowSize"), relayout)

	panel.Instance.Parent = props.parent
	picker:refresh()
	return picker
end

-- UrkUI bridge -------------------------------------------------------------------------------------

local unbridge: (() -> ())? = nil

-- Makes pack icons usable by name everywhere the kit already takes an icon name: UrkUI components
-- (through UI/Runtime/IconBridge), the Game components and the UI generator's Builder all call the
-- kit Icons module, and screen specs are checked with SpecSchema.isIcon. bridge() wraps those
-- functions on the loaded modules (no file is edited):
--   * "pack:name" always shows the pack icon;
--   * a bare name shows the kit icon when the kit has one, else the pack icon;
--   * every other name behaves exactly as before.
-- UrkUI passes its text colour for glyphs; for pack icons that colour is ignored so they keep
-- their own colours. Returns a function that removes the bridge. Calling bridge() twice is fine.
function IconVault.bridge(): () -> ()
	if unbridge then
		return unbridge
	end
	local module = kit()
	if module == nil then
		return function() end
	end
	local original = { apply = module.apply, has = module.has, get = module.get }
	kitOriginal = original

	local function fromVault(name: any): boolean
		if type(name) ~= "string" or not IconVaultLogic.has(name) then
			return false
		end
		return string.find(name, ":", 1, true) ~= nil or not kitHas(name)
	end

	module.has = function(name: string): boolean
		return fromVault(name) or original.has(name)
	end
	module.apply = function(label: ImageLabel | ImageButton, name: string, options: any?): boolean
		if fromVault(name) then
			local opts = options or {}
			return IconVault.apply(
				label,
				name,
				{ size = opts.size, transparency = opts.transparency, tint = opts.tint }
			)
		end
		return original.apply(label, name, options)
	end
	module.get = function(name: string): any
		if fromVault(name) then
			local image = IconVaultLogic.image(name)
			if image == nil then
				return nil
			end
			local rect = image.rect
			return {
				Image = image.image,
				ImageRectOffset = if rect then Vector2.new(rect.x, rect.y) else Vector2.zero,
				ImageRectSize = if rect then Vector2.new(rect.w, rect.h) else Vector2.zero,
			}
		end
		return original.get(name)
	end

	-- Screen specs: accept pack icon names in `icon = "pack:name"`.
	local schema: any = nil
	local originalIsIcon: any = nil
	local ok, loaded = pcall(function(): any
		return require("../../UI/Spec/SpecSchema")
	end)
	if ok and type(loaded) == "table" and type(loaded.isIcon) == "function" then
		schema = loaded
		originalIsIcon = loaded.isIcon
		schema.isIcon = function(name: any): boolean
			return originalIsIcon(name) or (type(name) == "string" and IconVaultLogic.has(name))
		end
	end

	local function remove()
		if unbridge == nil then
			return
		end
		unbridge = nil
		module.apply = original.apply
		module.has = original.has
		module.get = original.get
		kitOriginal = nil
		if schema then
			schema.isIcon = originalIsIcon
		end
	end
	unbridge = remove
	return remove
end

-- Theme bridge: when the Visuals theme changes, live containers re-read the new default style.
-- Themes is optional and loaded guarded, like the other cross-module links.
do
	local ok, themes = pcall(function(): any
		return require("../Themes/Themes")
	end)
	if ok and type(themes) == "table" and type(themes.Changed) == "table" then
		themes.Changed:Connect(function()
			IconVault.refresh()
		end)
	end
end

return IconVault
