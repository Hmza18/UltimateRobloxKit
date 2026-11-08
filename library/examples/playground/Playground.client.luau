--!strict
-- UltimateRobloxKit UI playground (LocalScript). Renders the real framework: screen specs through
-- Spec/Builder, the Game components, icons, motion presets and styles. Serve it with
-- `rojo serve library/examples/playground/playground.project.json`; see README.md next to this file.
--
-- Everything here is client-side preview code. Purchases only print intents; nothing is granted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local URK = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
local UI = URK:WaitForChild("UI")
local UrkUI = require(UI:WaitForChild("UrkUI"))
local SpecFolder = UI:WaitForChild("Spec")
local Builder = require(SpecFolder:WaitForChild("Builder"))
local Icons = require(URK:WaitForChild("Icons"):WaitForChild("Icons"))
local Motion = require(UI:WaitForChild("Runtime"):WaitForChild("Motion"))
local MotionPresets = require(UI:WaitForChild("Core"):WaitForChild("MotionPresets"))
local Style = require(UI:WaitForChild("Style"):WaitForChild("Style"))

local Screens = SpecFolder:WaitForChild("Screens")
local GameFolder = UI:WaitForChild("Game")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Demo state: the specs bind to these paths, and a ticker changes them so binds visibly update.
UrkUI.start({
	state = {
		Stats = { Cash = 12500, Gems = 340, Coins = 48200, Level = { level = 7, value = 45, max = 100 } },
		Inventory = { Count = 18 },
		Achievements = { Unlocked = 12 },
		Profile = { Level = { level = 24, value = 640, max = 1000 } },
		Settings = { Music = 0.6, Sfx = 0.8, ShowPets = true, AutoEquip = true, UiSize = "Medium" },
	},
})
local store = UrkUI.store :: any

-- Colours for the playground chrome (not part of the kit's styles).
local CHROME_BG = Color3.fromRGB(24, 26, 44)
local CHROME_PANEL = Color3.fromRGB(36, 40, 66)
local CHROME_TEXT = Color3.fromRGB(235, 238, 255)
local CHROME_MUTED = Color3.fromRGB(150, 156, 196)

local currentStyle = Style.default()

-- Chrome helpers ---------------------------------------------------------------------------------

local function make(className: string, parent: Instance?, props: { [string]: any }): any
	local instance: any = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: number)
	make("UICorner", parent, { CornerRadius = UDim.new(0, radius) })
end

local function label(parent: Instance, text: string, size: number, order: number?): TextLabel
	return make("TextLabel", parent, {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = CHROME_TEXT,
		TextSize = size,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, size + 10),
		LayoutOrder = order or 0,
	})
end

local function chromeButton(parent: Instance, text: string, order: number, onClick: () -> ()): TextButton
	local button = make("TextButton", parent, {
		BackgroundColor3 = CHROME_PANEL,
		Text = text,
		TextColor3 = CHROME_TEXT,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(150, 34),
		LayoutOrder = order,
	})
	corner(button, 8)
	button.Activated:Connect(onClick)
	return button
end

local function listLayout(parent: Instance, horizontal: boolean, gap: number)
	make("UIListLayout", parent, {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
	})
end

local function padding(parent: Instance, pixels: number)
	local pad = UDim.new(0, pixels)
	make("UIPadding", parent, { PaddingTop = pad, PaddingBottom = pad, PaddingLeft = pad, PaddingRight = pad })
end

-- Loads a Game component by name, or nil (with a reason) when it is not in this build yet.
local function gameComponent(name: string): (any, string?)
	local module = GameFolder:FindFirstChild(name)
	if module == nil then
		return nil, "Game/" .. name .. " is not in this build yet"
	end
	local ok, result = pcall(require, module)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

-- Layout -----------------------------------------------------------------------------------------

local gui = make("ScreenGui", playerGui, {
	Name = "UrkPlayground",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1,
})

make("Frame", gui, { BackgroundColor3 = CHROME_BG, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) })

local nav = make("ScrollingFrame", gui, {
	Name = "Nav",
	BackgroundColor3 = CHROME_PANEL,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(12, 12),
	Size = UDim2.new(0, 200, 1, -24),
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
})
corner(nav, 12)
padding(nav, 10)
listLayout(nav, false, 6)
label(nav, "URK PLAYGROUND", 16, 0)

local stage = make("Frame", gui, {
	Name = "Stage",
	BackgroundColor3 = Color3.fromRGB(58, 64, 104),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Position = UDim2.fromOffset(224, 12),
	Size = UDim2.new(1, -236, 1, -78),
})
corner(stage, 12)

local logLabel = make("TextLabel", gui, {
	Name = "IntentLog",
	BackgroundColor3 = CHROME_PANEL,
	TextColor3 = CHROME_MUTED,
	TextSize = 13,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "Intents appear here.",
	Position = UDim2.new(0, 224, 1, -60),
	Size = UDim2.new(1, -236, 0, 48),
})
corner(logLabel, 8)
padding(logLabel, 6)

local logLines: { string } = {}
local function log(line: string)
	table.insert(logLines, 1, line)
	while #logLines > 3 do
		table.remove(logLines)
	end
	logLabel.Text = table.concat(logLines, "\n")
end

local function describe(args: any): string
	if type(args) ~= "table" then
		return tostring(args)
	end
	local parts: { string } = {}
	for key, value in pairs(args) do
		table.insert(parts, tostring(key) .. "=" .. tostring(value))
	end
	table.sort(parts)
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Components raise purchases on UrkUI.Intent; screens raise Select / Change / Close on screen.Intent.
UrkUI.Intent:Connect(function(name: string, args: any)
	log("UrkUI.Intent  " .. name .. " " .. describe(args))
end)

-- Demo ticker so bound counters and bars move.
task.spawn(function()
	while gui.Parent do
		task.wait(1.5)
		store:update("Stats.Cash", function(cash: number?): number
			return (cash or 0) + 137
		end)
		store:update("Stats.Level", function(level: any): any
			local value = ((level and level.value) or 0) + 5
			if value > 100 then
				return { level = ((level and level.level) or 0) + 1, value = 0, max = 100 }
			end
			return { level = (level and level.level) or 0, value = value, max = 100 }
		end)
	end
end)

-- Pages ------------------------------------------------------------------------------------------

type Page = { id: string, title: string, build: (container: Frame) -> (() -> ())? }

local function showError(container: Frame, message: string)
	local text = label(container, message, 16)
	text.Position = UDim2.fromOffset(16, 16)
	text.Size = UDim2.new(1, -32, 1, -32)
	text.TextYAlignment = Enum.TextYAlignment.Top
end

-- Builds a spec ModuleScript into the stage and logs its intents.
local function screenPage(moduleName: string): (container: Frame) -> (() -> ())?
	return function(container: Frame): (() -> ())?
		local module = Screens:FindFirstChild(moduleName)
		if module == nil then
			showError(container, "Screens/" .. moduleName .. ".json is missing")
			return nil
		end
		local ok, result = pcall(Builder.build, module, {
			parent = container,
			store = store,
			style = currentStyle,
			writeBinds = true,
			startOpen = true,
		})
		if not ok then
			showError(container, "Could not build " .. moduleName .. ":\n" .. tostring(result))
			return nil
		end
		local screen = result
		screen.Intent:Connect(function(name: string, args: any, elementId: string?)
			log(moduleName .. ".Intent  " .. name .. " " .. describe(args) .. " from " .. tostring(elementId))
		end)
		return function()
			screen:destroy()
		end
	end
end

local TINTS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 196, 0),
	Color3.fromRGB(76, 217, 100),
	Color3.fromRGB(61, 139, 255),
	Color3.fromRGB(168, 85, 247),
	Color3.fromRGB(255, 59, 107),
}

local function iconGallery(container: Frame): (() -> ())?
	local root = make("Frame", container, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	padding(root, 12)
	local bar = make("Frame", root, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })
	listLayout(bar, true, 8)
	local search = make("TextBox", bar, {
		PlaceholderText = "Search icons (name or tag)",
		Text = "",
		ClearTextOnFocus = false,
		TextSize = 16,
		Font = Enum.Font.Gotham,
		TextColor3 = CHROME_TEXT,
		BackgroundColor3 = CHROME_PANEL,
		Size = UDim2.fromOffset(280, 36),
		LayoutOrder = 1,
	})
	corner(search, 8)
	local tint = TINTS[1]
	local glyphs: { ImageLabel } = {}
	for index, color in ipairs(TINTS) do
		local swatch = make("TextButton", bar, {
			Text = "",
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(36, 36),
			LayoutOrder = 10 + index,
		})
		corner(swatch, 18)
		swatch.Activated:Connect(function()
			tint = color
			for _, glyph in ipairs(glyphs) do
				glyph.ImageColor3 = color
			end
		end)
	end
	local count = label(bar, "", 14, 30)
	count.Size = UDim2.fromOffset(220, 36)

	local grid = make("ScrollingFrame", root, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
	})
	make("UIGridLayout", grid, {
		CellSize = UDim2.fromOffset(150, 104),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local glyphNames: { string } = {}
	for _, name in ipairs(Icons.list()) do
		if string.sub(name, -6) ~= "-color" then
			table.insert(glyphNames, name)
		end
	end

	local function render(query: string)
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(glyphs)
		local names = if query == "" then glyphNames else Icons.search(query, 200)
		local seen: { [string]: boolean } = {}
		local shown = 0
		for order, name in ipairs(names) do
			local base = string.gsub(name, "%-color$", "")
			if seen[base] then
				continue
			end
			seen[base] = true
			local cell = make("Frame", grid, { BackgroundColor3 = CHROME_PANEL, LayoutOrder = order })
			corner(cell, 10)
			local glyph = make("ImageLabel", cell, {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(16, 8),
				Size = UDim2.fromOffset(56, 56),
				ImageColor3 = tint,
			})
			Icons.apply(glyph, base)
			table.insert(glyphs, glyph)
			local colored = make("ImageLabel", cell, {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(80, 8),
				Size = UDim2.fromOffset(56, 56),
			})
			if Icons.has(base .. "-color") then
				Icons.apply(colored, base .. "-color")
			else
				make("TextLabel", colored, {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Text = "pending",
					TextColor3 = CHROME_MUTED,
					TextSize = 12,
					Font = Enum.Font.Gotham,
				})
			end
			local caption = label(cell, base, 13)
			caption.Position = UDim2.fromOffset(8, 72)
			caption.Size = UDim2.new(1, -16, 0, 24)
			caption.TextXAlignment = Enum.TextXAlignment.Center
			shown += 1
		end
		count.Text = tostring(shown) .. " icons (glyph | -color)"
	end
	render("")
	local connection = search:GetPropertyChangedSignal("Text"):Connect(function()
		render(search.Text)
	end)
	return function()
		connection:Disconnect()
	end
end

local function animationGallery(container: Frame): (() -> ())?
	local ProductCard, problem = gameComponent("ProductCard")
	if ProductCard == nil then
		showError(container, problem or "ProductCard is missing")
		return nil
	end
	local card = ProductCard.new({
		style = currentStyle,
		parent = container,
		palette = "purple",
		icon = "egg-color",
		title = "SAMPLE CARD",
		subtitle = "Press a preset",
		price = { kind = "robux", amount = 99, gamePassId = 0 },
		size = UDim2.fromOffset(190, 250),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, -170, 0.5, 0),
	})
	local buttons = make("ScrollingFrame", container, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -360, 1, -24),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	make("UIGridLayout", buttons, {
		CellSize = UDim2.fromOffset(150, 34),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local stop: (() -> ())? = nil
	chromeButton(buttons, "STOP", 0, function()
		Motion.stop(card.Instance)
	end)
	for order, name in ipairs(MotionPresets.names()) do
		local preset = MotionPresets.get(name)
		local text = name .. (if preset.loop then " (loop)" else "")
		chromeButton(buttons, text, order, function()
			if stop then
				stop()
			end
			stop = Motion.play(card.Instance, name)
			log("Motion.play " .. name .. string.format(" %.2fs", preset.duration))
		end)
	end
	return function()
		card:destroy()
	end
end

type Field = { name: string, kind: string, options: { any }? }
type Sample = { component: string, props: { [string]: any }, fields: { Field }, height: number? }

local SAMPLES: { Sample } = {
	{
		component = "GameText",
		props = { text = "CHUNKY TITLE", role = "title", size = UDim2.fromOffset(300, 48) },
		fields = {
			{ name = "text", kind = "string" },
			{ name = "role", kind = "enum", options = { "display", "title", "heading", "label", "caption", "price" } },
			{ name = "stroke", kind = "boolean" },
		},
	},
	{
		component = "CartoonButton",
		props = { text = "BUY", kind = "buy", size = UDim2.fromOffset(200, 56) },
		fields = {
			{ name = "text", kind = "string" },
			{ name = "kind", kind = "enum", options = { "buy", "robux", "gift", "primary", "danger", "neutral" } },
			{ name = "icon", kind = "string" },
			{ name = "enabled", kind = "boolean" },
		},
	},
	{
		component = "IconButton",
		props = { icon = "shop-color", label = "Shop", palette = "orange", badge = { kind = "attention" } },
		fields = {
			{ name = "icon", kind = "string" },
			{ name = "label", kind = "string" },
			{ name = "palette", kind = "enum", options = { "orange", "blue", "green", "purple", "pink", "gray" } },
			{ name = "shape", kind = "enum", options = { "square", "circle" } },
		},
	},
	{
		component = "ProductCard",
		props = {
			title = "TRIPLE HATCH",
			subtitle = "Open 3 eggs at once",
			palette = "purple",
			icon = "egg-color",
			price = { kind = "robux", amount = 249, gamePassId = 0 },
			size = UDim2.fromOffset(170, 220),
		},
		height = 240,
		fields = {
			{ name = "title", kind = "string" },
			{ name = "subtitle", kind = "string" },
			{ name = "palette", kind = "enum", options = { "purple", "blue", "teal", "gold", "red", "green" } },
			{ name = "rarity", kind = "enum", options = { "common", "rare", "epic", "legendary", "mythic", "secret" } },
			{ name = "owned", kind = "boolean" },
			{ name = "gift", kind = "boolean" },
		},
	},
	{
		component = "PromoBanner",
		props = {
			title = "STARTER PACK",
			subtitle = "A great offer you can't refuse!",
			palette = "teal",
			icon = "star-color",
			price = { kind = "robux", amount = 99, productId = 0 },
			timer = 3600,
			size = UDim2.fromOffset(460, 110),
		},
		height = 130,
		fields = {
			{ name = "title", kind = "string" },
			{ name = "subtitle", kind = "string" },
			{ name = "palette", kind = "enum", options = { "teal", "gold", "pink", "blue" } },
			{ name = "timer", kind = "number" },
		},
	},
	{
		component = "CurrencyCounter",
		props = { icon = "cash-color", value = 12500, plus = true, size = UDim2.fromOffset(210, 52) },
		fields = { { name = "value", kind = "number" }, { name = "icon", kind = "string" } },
	},
	{
		component = "LevelBar",
		props = { level = 7, value = 45, max = 100, size = UDim2.fromOffset(360, 40) },
		fields = { { name = "level", kind = "number" }, { name = "value", kind = "number" } },
	},
	{
		component = "ProgressBar",
		props = { value = 30, max = 100, palette = "green", showText = true, size = UDim2.fromOffset(320, 28) },
		fields = {
			{ name = "value", kind = "number" },
			{ name = "palette", kind = "enum", options = { "green", "blue", "gold", "red" } },
		},
	},
	{
		component = "Timer",
		props = { seconds = 1800, format = "clock", icon = "clock-color", size = UDim2.fromOffset(170, 42) },
		fields = {
			{ name = "seconds", kind = "number" },
			{ name = "format", kind = "enum", options = { "clock", "short" } },
		},
	},
	{ component = "Toggle", props = { value = true }, fields = { { name = "value", kind = "boolean" } } },
	{
		component = "Slider",
		props = { value = 0.5, min = 0, max = 1, step = 0.05, size = UDim2.fromOffset(260, 32) },
		fields = { { name = "value", kind = "number" } },
	},
	{
		component = "Dropdown",
		props = { options = { "Small", "Medium", "Large" }, value = "Medium", size = UDim2.fromOffset(200, 40) },
		fields = { { name = "value", kind = "enum", options = { "Small", "Medium", "Large" } } },
	},
	{
		component = "Panel",
		props = { palette = "blue", gloss = true, pattern = true, size = UDim2.fromOffset(260, 90) },
		height = 100,
		fields = {
			{ name = "palette", kind = "enum", options = { "blue", "pink", "gold", "green" } },
			{ name = "pattern", kind = "boolean" },
			{ name = "gloss", kind = "boolean" },
		},
	},
	{
		component = "Section",
		props = { title = "GAMEPASSES", divider = true, size = UDim2.fromOffset(360, 48) },
		fields = { { name = "title", kind = "string" }, { name = "divider", kind = "boolean" } },
	},
}

-- One editor row: TextBox for strings and numbers, a button that flips booleans or cycles enums.
local function editor(parent: Instance, object: any, field: Field, order: number)
	local rowProps = { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order }
	local row = make("Frame", parent, rowProps)
	local name = label(row, field.name, 13)
	name.Size = UDim2.fromScale(0.4, 1)
	local current = object.props and object.props[field.name]
	local function apply(value: any)
		local ok, err = pcall(function()
			object:update({ [field.name] = value })
		end)
		log(if ok then "update " .. field.name .. " = " .. tostring(value) else "update failed: " .. tostring(err))
	end
	if field.kind == "string" or field.kind == "number" then
		local box = make("TextBox", row, {
			Text = if current == nil then "" else tostring(current),
			ClearTextOnFocus = false,
			TextSize = 13,
			Font = Enum.Font.Gotham,
			TextColor3 = CHROME_TEXT,
			BackgroundColor3 = CHROME_BG,
			Position = UDim2.fromScale(0.4, 0),
			Size = UDim2.fromScale(0.6, 1),
		})
		corner(box, 6)
		box.FocusLost:Connect(function()
			if field.kind == "number" then
				local number = tonumber(box.Text)
				if number ~= nil then
					apply(number)
				end
			else
				apply(box.Text)
			end
		end)
		return
	end
	local options: { any } = if field.kind == "boolean" then { true, false } else (field.options or {})
	local index = table.find(options, current) or 1
	local button = chromeButton(row, tostring(options[index]), 1, function() end)
	button.Position = UDim2.fromScale(0.4, 0)
	button.Size = UDim2.fromScale(0.6, 1)
	button.Activated:Connect(function()
		index = index % #options + 1
		button.Text = tostring(options[index])
		apply(options[index])
	end)
end

local function componentsShowcase(container: Frame): (() -> ())?
	local scroller = make("ScrollingFrame", container, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
	})
	padding(scroller, 12)
	listLayout(scroller, false, 12)
	local objects: { any } = {}
	for order, sample in ipairs(SAMPLES) do
		local height = math.max(sample.height or 80, #sample.fields * 32 + 36)
		local card = make("Frame", scroller, {
			BackgroundColor3 = CHROME_PANEL,
			Size = UDim2.new(1, -12, 0, height),
			LayoutOrder = order,
		})
		corner(card, 10)
		padding(card, 10)
		local view = make("Frame", card, { BackgroundTransparency = 1, Size = UDim2.fromScale(0.55, 1) })
		local title = label(view, sample.component, 15)
		title.TextColor3 = CHROME_MUTED
		local inspector = make("Frame", card, {
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.58, 0),
			Size = UDim2.fromScale(0.42, 1),
		})
		listLayout(inspector, false, 4)
		local module, problem = gameComponent(sample.component)
		if module == nil then
			label(view, problem or "missing", 13).Position = UDim2.fromOffset(0, 28)
			continue
		end
		local props = table.clone(sample.props)
		props.style = currentStyle
		props.parent = view
		props.position = UDim2.fromOffset(0, 30)
		local ok, object = pcall(module.new, props)
		if not ok then
			label(view, "new() failed: " .. tostring(object), 13).Position = UDim2.fromOffset(0, 28)
			continue
		end
		table.insert(objects, object)
		local activated = object.Activated
		if activated then
			activated:Connect(function()
				log(sample.component .. ".Activated")
			end)
		end
		for fieldOrder, field in ipairs(sample.fields) do
			editor(inspector, object, field, fieldOrder)
		end
	end
	return function()
		for _, object in ipairs(objects) do
			object:destroy()
		end
	end
end

local function themePreview(container: Frame): (() -> ())?
	local bar = make("Frame", container, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 40),
	})
	listLayout(bar, true, 8)
	local hint = label(bar, "", 14, 99)
	hint.Size = UDim2.fromOffset(360, 34)
	local holder = make("Frame", container, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
	})
	local cleanup: (() -> ())? = nil
	local function rebuild()
		if cleanup then
			cleanup()
			cleanup = nil
		end
		for _, child in ipairs(holder:GetChildren()) do
			child:Destroy()
		end
		hint.Text = "Style.default() = " .. currentStyle .. " (other pages use it too)"
		cleanup = screenPage("PetSimShop")(holder)
	end
	for order, name in ipairs(Style.names()) do
		chromeButton(bar, string.upper(name), order, function()
			Style.setDefault(name)
			currentStyle = name
			rebuild()
		end)
	end
	rebuild()
	return function()
		if cleanup then
			cleanup()
		end
	end
end

local function screenBrowser(container: Frame): (() -> ())?
	local bar = make("ScrollingFrame", container, {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 84),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	make("UIGridLayout", bar, {
		CellSize = UDim2.fromOffset(150, 34),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local holder = make("Frame", container, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 1, -100),
	})
	local cleanup: (() -> ())? = nil
	local modules = Screens:GetChildren()
	table.sort(modules, function(a: Instance, b: Instance): boolean
		return a.Name < b.Name
	end)
	for order, module in ipairs(modules) do
		chromeButton(bar, module.Name, order, function()
			if cleanup then
				cleanup()
				cleanup = nil
			end
			for _, child in ipairs(holder:GetChildren()) do
				child:Destroy()
			end
			cleanup = screenPage(module.Name)(holder)
		end)
	end
	return function()
		if cleanup then
			cleanup()
		end
	end
end

local PAGES: { Page } = {
	{ id = "shop", title = "Shop demo", build = screenPage("PetSimShop") },
	{ id = "premium", title = "Premium store", build = screenPage("PremiumStore") },
	{ id = "hud", title = "HUD demo", build = screenPage("MainHud") },
	{ id = "inventory", title = "Inventory demo", build = screenPage("Inventory") },
	{ id = "daily", title = "Daily rewards", build = screenPage("DailyRewards") },
	{ id = "screens", title = "All screens", build = screenBrowser },
	{ id = "icons", title = "Icon gallery", build = iconGallery },
	{ id = "motion", title = "Animation gallery", build = animationGallery },
	{ id = "components", title = "Components", build = componentsShowcase },
	{ id = "theme", title = "Theme preview", build = themePreview },
}

-- Navigation -------------------------------------------------------------------------------------

local currentCleanup: (() -> ())? = nil
local navButtons: { [string]: TextButton } = {}

local function openPage(page: Page)
	if currentCleanup then
		local cleanup = currentCleanup
		currentCleanup = nil
		pcall(cleanup)
	end
	for _, child in ipairs(stage:GetChildren()) do
		if not child:IsA("UICorner") then
			child:Destroy()
		end
	end
	for id, button in pairs(navButtons) do
		button.BackgroundColor3 = if id == page.id then Color3.fromRGB(61, 139, 255) else CHROME_BG
	end
	local container = make("Frame", stage, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	local ok, result = pcall(page.build, container)
	if ok then
		currentCleanup = result
	else
		showError(container, page.title .. " failed:\n" .. tostring(result))
	end
end

for order, page in ipairs(PAGES) do
	local button = chromeButton(nav, page.title, order, function()
		openPage(page)
	end)
	button.Size = UDim2.new(1, 0, 0, 36)
	button.BackgroundColor3 = CHROME_BG
	navButtons[page.id] = button
end

openPage(PAGES[1])
