--!strict
-- The UltimateVisuals Playground: an in-Studio tool for trying every preset in the visuals kit.
--
--   left      categories (VFX, UI animations, Objects, Camera, Pets, Rewards, Eggs, Feedback,
--             Themes, Icons, Components, Demos)
--   middle    search box and the preset list (rows exist only while they are on screen)
--   right     the selected preset: description, cost and quality, controls generated from its
--             parameter metadata, Play / Replay / Stop / Reset, and the exact Luau call
--   top       theme, quality, reduced motion and reduced flashing
--   bottom    live metrics from Visuals.Stats()
--
-- World presets play on a small stage next to the window: a target part for VFX and the camera,
-- a gift-box model for object animations and a demo pet for pet reactions.
--
-- Built with the public entry points only (Visuals, UrkUI.Game). It has the same shape as a demo,
-- `start(parent) -> stop`, so the launcher starts it like one. Everything it creates is removed
-- when it stops.
--
-- There is no pause toggle: the kit exposes no public time scale for its clock, and the
-- playground does not reach into Runtime/Host to add one.
--
-- NOT run in Studio.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DemoKit = require("../DemoKit")
local DemoLogic = require("../DemoLogic")
local PlaygroundLogic = require("./PlaygroundLogic")

local Visuals = DemoKit.Visuals
local Game = DemoKit.Game

type Demo = { title: string, description: string, start: (parent: Instance) -> () -> () }

type State = { label: string, props: { [string]: any }?, call: string?, args: { any }? }

type Sample = {
	props: { [string]: any }, -- shown in the example code
	layout: { [string]: any }?, -- size and other props that are not worth showing
	states: { State }?,
	host: string?, -- "screen": parent is the ScreenGui (windows and modals)
}

local Playground = {}

Playground.title = "Playground"
Playground.description = "Browse and tune every preset, theme, icon and component."

local DEMOS: { { module: string, demo: Demo } } = {
	{ module = "PetSelectionDemo", demo = require("../PetSelectionDemo") },
	{ module = "EggHatchingDemo", demo = require("../EggHatchingDemo") },
	{ module = "RewardRevealDemo", demo = require("../RewardRevealDemo") },
	{ module = "SimulatorFeedbackDemo", demo = require("../SimulatorFeedbackDemo") },
	{ module = "AnimalFeedingDemo", demo = require("../AnimalFeedingDemo") },
}

local ROW = 30
local TEXT = Color3.fromRGB(236, 240, 255)
local MUTED = Color3.fromRGB(170, 178, 214)
local FIELD = Color3.fromRGB(24, 26, 44)
local ACCENT = Color3.fromRGB(92, 225, 255)

local function offset(width: number, height: number): UDim2
	return UDim2.fromOffset(width, height)
end

-- One sample of every UrkUI Game component, with the states worth looking at.
local function set(label: string, props: { [string]: any }): State
	return { label = label, props = props }
end

local function call(label: string, method: string, ...: any): State
	return { label = label, call = method, args = { ... } }
end

local SAMPLE_DATA: any = {
	GameText = {
		props = { text = "GAME TEXT", size = "title" },
		states = { set("gold", { color = "#FFD43B" }), set("left", { align = "left" }) },
	},
	Panel = {
		props = { palette = "purple", pattern = true },
		layout = { size = offset(220, 120) },
		states = { set("teal", { palette = "teal" }), set("plain", { pattern = false }) },
	},
	CartoonButton = {
		props = { text = "PLAY", kind = "primary" },
		states = {
			set("buy", { kind = "buy" }),
			set("danger", { kind = "danger" }),
			set("shine", { shine = true }),
			set("disabled", { enabled = false }),
		},
	},
	IconButton = {
		props = { icon = "star-color", label = "SHOP", palette = "blue" },
		states = {
			set("orange", { palette = "orange" }),
			set("circle", { shape = "circle" }),
			set("badge", { badge = { kind = "attention" } }),
		},
	},
	Badge = {
		props = { kind = "new" },
		states = {
			set("sale", { kind = "sale", text = "-50%" }),
			set("best", { kind = "best" }),
			set("attention", { kind = "attention" }),
		},
	},
	ProductCard = {
		props = {
			palette = "purple",
			title = "TRIPLE HATCH",
			subtitle = "+50% Bonus",
			icon = "egg-color",
			price = { kind = "currency", amount = 1200 },
		},
		states = {
			set("legendary", { rarity = "legendary" }),
			set("owned", { owned = true }),
			set("badge", { badge = { kind = "sale", text = "-20%" } }),
		},
	},
	PromoBanner = {
		props = { palette = "teal", title = "STARTER PACK", subtitle = "A friendly first offer", timer = 3600 },
		layout = { size = offset(300, 110) },
		states = {
			set("orange", { palette = "orange" }),
			set("badge", { badge = { kind = "best" } }),
		},
	},
	GameWindow = {
		props = { title = "SHOP", sizeClass = "sm" },
		host = "screen",
		states = { call("open", "open"), call("close", "close") },
	},
	Section = {
		props = { title = "GAMEPASSES" },
		layout = { size = offset(300, 44) },
		states = {
			set("center", { align = "center" }),
			set("no divider", { divider = false }),
		},
	},
	Grid = {
		props = { columns = { phone = 2, tablet = 3, desktop = 3 } },
		layout = { size = offset(300, 110) },
	},
	CurrencyCounter = {
		props = { value = 1250, icon = "coin-color" },
		states = { set("98K", { value = 98000 }), set("plus", { plus = true }) },
	},
	LevelBar = {
		props = { level = 3, value = 40, max = 100 },
		layout = { size = offset(300, 40) },
		states = { set("85", { value = 85 }), set("level 4", { level = 4, value = 10 }) },
	},
	ProgressBar = {
		props = { value = 30, max = 100, showText = true },
		states = {
			set("75", { value = 75 }),
			set("orange", { palette = "orange" }),
			set("segments", { segments = 4 }),
		},
	},
	Timer = {
		props = { seconds = 125 },
		states = { set("short", { format = "short" }), set("5 s", { seconds = 5 }) },
	},
	Toggle = {
		props = { value = true },
		states = { set("off", { value = false }), set("disabled", { enabled = false }) },
	},
	Slider = {
		props = { value = 0.4 },
		states = { set("0.9", { value = 0.9 }), set("disabled", { enabled = false }) },
	},
	Dropdown = {
		props = { options = { "Low", "Medium", "High" }, value = "Medium" },
		states = { set("High", { value = "High" }), set("disabled", { enabled = false }) },
	},
	RarityFrame = {
		props = { rarity = "epic" },
		layout = { size = offset(120, 120) },
		states = {
			set("legendary", { rarity = "legendary" }),
			set("secret", { rarity = "secret" }),
		},
	},
	RewardPopup = {
		props = { title = "YOU GOT", amount = "x500", duration = 0, destroyOnClose = false },
		layout = { size = offset(220, 230) },
		states = { call("close", "close"), call("open", "open") },
	},
	PremiumButton = {
		props = { text = "CLAIM REWARD" },
		states = {
			set("purple", { palette = "purple" }),
			set("no shine", { shine = false }),
			set("disabled", { enabled = false }),
		},
	},
	TabBar = {
		props = {
			tabs = { { id = "pets", text = "PETS" }, { id = "eggs", text = "EGGS" }, { id = "shop", text = "SHOP" } },
			value = "pets",
		},
		layout = { size = offset(300, 52) },
		states = { set("eggs", { value = "eggs" }), set("shop", { value = "shop" }) },
	},
	Modal = {
		props = {
			title = "REBIRTH?",
			text = "You keep your pets and lose your coins.",
			buttons = {
				{ id = "yes", text = "REBIRTH", kind = "buy" },
				{ id = "no", text = "CANCEL", kind = "neutral" },
			},
		},
		host = "screen",
		states = { call("open", "open"), call("close", "close") },
	},
	Tooltip = {
		props = { text = "Doubles coins for 10 minutes", side = "bottom" },
		states = { call("show", "show"), call("hide", "hide") },
	},
	XPBar = {
		props = { level = 3, value = 40, max = 100 },
		states = {
			call("gain 80", "gain", 80),
			call("gain 250", "gain", 250),
		},
	},
	InventorySlot = {
		props = { icon = "sword-color", count = 12, rarity = "rare" },
		states = {
			set("selected", { selected = true }),
			set("equipped", { equipped = true }),
			set("locked", { locked = true }),
		},
	},
	PetCard = {
		props = { title = "Ember", rarity = "epic", stats = { { text = "x2.5" } } },
		states = {
			set("selected", { selected = true }),
			set("equipped", { equipped = true }),
			set("disabled", { enabled = false }),
		},
	},
	RarityBadge = {
		props = { rarity = "legendary" },
		states = {
			set("mythic", { rarity = "mythic" }),
			set("common", { rarity = "common" }),
		},
	},
	RewardPanel = {
		props = {
			title = "DAILY REWARDS",
			rewards = { { amount = "x500" }, { amount = "x1", rarity = "rare" }, { amount = "x25" } },
			revealed = false,
		},
		layout = { size = offset(300, 230) },
		states = { call("reveal", "reveal"), set("claimed", { claimed = true }) },
	},
	QuestCard = {
		props = {
			title = "EGG COLLECTOR",
			description = "Hatch 10 eggs",
			value = 4,
			max = 10,
			rewards = { { text = "500" } },
		},
		layout = { size = offset(300, 104) },
		states = {
			set("claimable", { value = 10 }),
			set("claimed", { state = "claimed" }),
		},
	},
	AchievementCard = {
		props = { title = "COLLECTOR", description = "Own 50 pets", value = 20, max = 50 },
		layout = { size = offset(300, 96) },
		states = {
			set("unlock", { tier = 1, unlocked = true, value = 50 }),
			set("tier 3", { tier = 3 }),
		},
	},
	Notification = {
		props = { kind = "success", title = "QUEST COMPLETE", text = "+500 coins", duration = 0 },
		states = {
			set("warning", { kind = "warning" }),
			set("error", { kind = "error" }),
		},
	},
	LeaderboardRow = {
		props = { rank = 1, title = "Player One", value = 1250000 },
		layout = { size = offset(300, 52) },
		states = {
			set("2.4M", { value = 2400000 }),
			set("highlight", { highlight = true }),
			set("rank 4", { rank = 4 }),
		},
	},
	LoadingScreen = {
		props = {
			title = "DEMO WORLD",
			tips = { "Hatch eggs to find rare pets", "Feed animals to make friends" },
			progress = 0.3,
			destroyOnClose = false,
		},
		states = { call("80%", "setProgress", 0.8), call("finish", "finish") },
	},
	SelectionCard = {
		props = { title = "RANGER", description = "Fast and fragile" },
		layout = { size = offset(180, 230) },
		states = {
			set("selected", { selected = true }),
			set("disabled", { enabled = false }),
		},
	},
	HotbarSlot = {
		props = { keybind = "Q" },
		states = {
			call("cooldown 4 s", "startCooldown", 4),
			set("disabled", { enabled = false }),
		},
	},
	StatChip = {
		props = { value = 120, suffix = "%" },
		states = { set("135", { value = 135 }), set("9000", { value = 9000 }) },
	},
}

local SAMPLES: { [string]: Sample } = SAMPLE_DATA

Playground.SAMPLES = SAMPLES

local function make(className: string, parent: Instance?, props: { [string]: any }): any
	local instance: any = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	return make("Frame", parent, {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
	})
end

local function plainLabel(parent: Instance, text: string, size: number, color: Color3, height: number): TextLabel
	return make("TextLabel", parent, {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, height),
	})
end

-- A gift box built from Parts: the model object animations run on. Pivot at its base.
local function giftBox(parent: Instance, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "GiftBox"
	local body = DemoKit.part(model, "Box", Vector3.new(2.4, 2, 2.4), CFrame.new(0, 1, 0), DemoKit.color("#B26BFF"))
	DemoKit.part(model, "Lid", Vector3.new(2.7, 0.5, 2.7), CFrame.new(0, 2.25, 0), DemoKit.color("#8E4FE0"))
	DemoKit.part(model, "RibbonX", Vector3.new(2.75, 2.55, 0.5), CFrame.new(0, 1.28, 0), DemoKit.color("#FFD43B"))
	DemoKit.part(model, "RibbonZ", Vector3.new(0.5, 2.55, 2.75), CFrame.new(0, 1.28, 0), DemoKit.color("#FFD43B"))
	DemoKit.part(
		model,
		"Bow",
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(0, 2.9, 0),
		DemoKit.color("#FFE680"),
		Enum.PartType.Ball
	)
	body.PivotOffset = CFrame.new(0, -1, 0)
	model.PrimaryPart = body
	model:PivotTo(at)
	model.Parent = parent
	return model
end

function Playground.start(parent: Instance): () -> ()
	DemoKit.bootstrap()
	local scope = DemoKit.scope()
	local gui = DemoKit.screen(scope, parent, "UvkPlayground", 25)

	-- Preview stage ------------------------------------------------------------------------------

	local stage = DemoKit.stage(scope, "PlaygroundStage", DemoKit.origin(18, -7), DemoKit.color("#5CE1FF"), 6)
	DemoKit.part(
		stage.folder,
		"TargetPost",
		Vector3.new(1.6, 0.5, 0.5),
		stage.top * CFrame.new(-3.2, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 126, 150),
		Enum.PartType.Cylinder
	)
	local target = DemoKit.part(
		stage.folder,
		"Target",
		Vector3.new(1.2, 1.2, 1.2),
		stage.top * CFrame.new(-3.2, 2.2, 0),
		DemoKit.color("#FFFFFF"),
		Enum.PartType.Ball
	)
	local box = giftBox(stage.folder, stage.top * CFrame.new(0, 0, 0.5))
	local pet: Model = nil :: any
	local function buildPet()
		if pet then
			pet:Destroy()
		end
		pet = DemoKit.pet(stage.folder, stage.top * CFrame.new(3.2, 0, 0), DemoKit.color("#FF8A3D"), 2, "PlaygroundPet")
	end
	buildPet()

	-- Window -------------------------------------------------------------------------------------

	local window = Game.Panel.new({
		name = "PlaygroundWindow",
		surface = "window",
		size = UDim2.new(0, 740, 0.94, 0),
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -10, 0.5, 0),
		parent = gui,
	})
	scope.add(window)
	local root = frame(window.Content, "Root", UDim2.fromOffset(10, 8), UDim2.new(1, -20, 1, -16))

	local header = frame(root, "Header", UDim2.new(), UDim2.new(1, 0, 0, 34))
	scope.add(Game.GameText.new({
		text = "ULTIMATE VISUALS PLAYGROUND",
		size = UDim2.new(1, -50, 1, 0),
		role = "heading",
		align = "left",
		parent = header,
	}))

	local settings = frame(root, "Settings", UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 44))
	settings.ZIndex = 30
	local body = frame(root, "Body", UDim2.fromOffset(0, 92), UDim2.new(1, 0, 1, -164))
	local footer = frame(root, "Footer", UDim2.new(0, 0, 1, -66), UDim2.new(1, 0, 0, 66))

	local sidebar = make("ScrollingFrame", body, {
		Name = "Categories",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 150, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
	})
	make("UIListLayout", sidebar, { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })

	local middle = frame(body, "List", UDim2.fromOffset(158, 0), UDim2.new(0, 200, 1, 0))
	local search: TextBox = make("TextBox", middle, {
		Name = "Search",
		BackgroundColor3 = FIELD,
		BackgroundTransparency = 0.2,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium,
		PlaceholderText = "Search presets",
		PlaceholderColor3 = MUTED,
		Text = "",
		TextColor3 = TEXT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 32),
	})
	make("UICorner", search, { CornerRadius = UDim.new(0, 8) })
	make("UIPadding", search, { PaddingLeft = UDim.new(0, 8) })
	local rowsFrame: ScrollingFrame = make("ScrollingFrame", middle, {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 1, -38),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
	})

	local detail = frame(body, "Detail", UDim2.fromOffset(368, 0), UDim2.new(1, -368, 1, 0))
	make("UIListLayout", detail, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })

	local metrics: TextLabel = make("TextLabel", footer, {
		Name = "Metrics",
		BackgroundColor3 = FIELD,
		BackgroundTransparency = 0.25,
		Font = Enum.Font.Code,
		Text = "",
		TextSize = 13,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(0.62, 0, 1, 0),
	})
	make("UICorner", metrics, { CornerRadius = UDim.new(0, 8) })
	make("UIPadding", metrics, { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) })
	local status: TextLabel = make("TextLabel", footer, {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "No pause toggle: the kit has no public time scale.",
		TextSize = 12,
		TextColor3 = MUTED,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0.64, 0, 0, 0),
		Size = UDim2.new(0.36, 0, 1, 0),
	})

	-- Selection state ----------------------------------------------------------------------------

	local categoryId = "vfx"
	local ids: { string } = {}
	local selectedId: string? = nil
	local rows: { [number]: TextButton } = {}
	local detailScope = DemoKit.scope()
	local active: any = nil -- the handle of what is playing
	local stopDemo: (() -> ())? = nil
	local picker: any = nil
	local feedbackTotal = 0

	local function say(message: string)
		status.Text = message
	end

	local function stopActive()
		local handle = active
		active = nil
		if handle == nil then
			return
		end
		pcall(function()
			if type(handle) == "function" then
				handle()
			elseif type(handle.cancel) == "function" and type(handle.Completed) == "table" then
				handle.cancel() -- reveals and hatches: remove everything now
			elseif type(handle.stop) == "function" then
				handle.stop()
			end
		end)
	end

	local function rarities(): { string }
		return Visuals.Rewards.rarities()
	end

	local function listFor(category: string, query: string): { string }
		local info = PlaygroundLogic.category(category)
		if info and info.kind then
			if string.match(query, "%S") then
				return PlaygroundLogic.ofKind(Visuals.Presets.search(query), info.kind)
			end
			local out: { string } = {}
			for _, entry in Visuals.Presets.list(info.kind) do
				table.insert(out, entry.id)
			end
			return out
		end
		local all: { string } = {}
		if category == "rewards" then
			all = rarities()
		elseif category == "eggs" then
			all = table.clone(PlaygroundLogic.EGG_MODES)
		elseif category == "feedback" then
			all = Visuals.Feedback.events()
		elseif category == "themes" then
			all = Visuals.Themes.names()
		elseif category == "components" then
			all = Game.names()
		elseif category == "demos" then
			for _, entry in DEMOS do
				table.insert(all, entry.demo.title)
			end
		end
		return PlaygroundLogic.filter(all, query)
	end

	-- Rows: created only for the indices near the viewport, removed when they scroll away.
	local showDetail: () -> ()

	local function paintRow(button: TextButton, id: string)
		local chosen = id == selectedId
		button.BackgroundColor3 = if chosen then ACCENT else FIELD
		button.BackgroundTransparency = if chosen then 0.1 else 0.45
		button.TextColor3 = if chosen then Color3.fromRGB(16, 24, 40) else TEXT
	end

	local function refreshRows()
		local first, last =
			PlaygroundLogic.visibleRows(rowsFrame.CanvasPosition.Y, rowsFrame.AbsoluteSize.Y, ROW, #ids, 3)
		for index, button in rows do
			if index < first or index > last then
				button:Destroy()
				rows[index] = nil
			end
		end
		for index = first, last do
			local id = ids[index]
			local existing: TextButton? = rows[index]
			local button: TextButton = existing :: TextButton
			if existing == nil then
				button = make("TextButton", rowsFrame, {
					Name = "Row" .. index,
					AutoButtonColor = false,
					BorderSizePixel = 0,
					Font = Enum.Font.GothamMedium,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(0, (index - 1) * ROW),
					Size = UDim2.new(1, -8, 0, ROW - 3),
				})
				make("UICorner", button, { CornerRadius = UDim.new(0, 6) })
				make("UIPadding", button, { PaddingLeft = UDim.new(0, 8) })
				button.Activated:Connect(function()
					selectedId = ids[index]
					for rowIndex, row in rows do
						paintRow(row, ids[rowIndex])
					end
					local ok, err = pcall(showDetail)
					if not ok then
						status.Text = "error: " .. tostring(err)
						warn("[UVK playground] " .. tostring(err))
					end
				end)
				rows[index] = button
			end
			button.Text = id
			paintRow(button, id)
		end
	end

	local function setList(list: { string })
		ids = list
		for index, button in rows do
			button:Destroy()
			rows[index] = nil
		end
		rowsFrame.CanvasSize = UDim2.fromOffset(0, #ids * ROW)
		rowsFrame.CanvasPosition = Vector2.zero
		refreshRows()
	end

	scope.add(rowsFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshRows))
	scope.add(rowsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshRows))

	-- Detail panel -------------------------------------------------------------------------------

	local function themeColors(): { string }
		local theme = Visuals.Themes.get()
		local colors: { string } = table.clone(theme.effects.particles)
		for _, role in { "accent", "primary", "secondary", "success", "warning", "error" } do
			table.insert(colors, theme.colors[role])
		end
		return colors
	end

	-- Builds one control row per parameter. `values` is written in place; onChange refreshes
	-- the example code.
	local function buildControls(
		dscope: DemoKit.Scope,
		host: Instance,
		params: PlaygroundLogic.Params,
		values: { [string]: any },
		onChange: () -> ()
	)
		for index, control in PlaygroundLogic.controls(params) do
			local row = frame(host, control.name, UDim2.new(), UDim2.new(1, 0, 0, 42))
			row.LayoutOrder = 20 + index
			-- Earlier rows draw above later ones so an open dropdown covers the rows under it.
			row.ZIndex = 20 - index
			local caption: TextLabel = plainLabel(row, control.name, 13, MUTED, 42)
			caption.Size = UDim2.new(0, 84, 1, 0)
			caption.TextYAlignment = Enum.TextYAlignment.Center
			local place = { position = UDim2.new(0, 88, 0.5, 0), anchor = Vector2.new(0, 0.5) }
			if control.kind == "slider" then
				local readout: TextLabel = plainLabel(row, PlaygroundLogic.literal(values[control.name]), 13, TEXT, 42)
				readout.Position = UDim2.new(1, -52, 0, 0)
				readout.Size = UDim2.new(0, 52, 1, 0)
				readout.TextYAlignment = Enum.TextYAlignment.Center
				dscope.add(Game.Slider.new({
					value = values[control.name],
					min = control.min,
					max = control.max,
					step = control.step,
					size = UDim2.fromOffset(190, 34),
					position = place.position,
					anchor = place.anchor,
					parent = row,
					onChanged = function(value: number)
						values[control.name] = PlaygroundLogic.clamp(control.param, value)
						readout.Text = PlaygroundLogic.literal(values[control.name])
						onChange()
					end,
				}))
			elseif control.kind == "toggle" then
				dscope.add(Game.Toggle.new({
					value = values[control.name] == true,
					position = place.position,
					anchor = place.anchor,
					parent = row,
					onChanged = function(value: boolean)
						values[control.name] = value
						onChange()
					end,
				}))
			elseif control.kind == "dropdown" then
				dscope.add(Game.Dropdown.new({
					options = control.param.options or {},
					value = values[control.name],
					size = UDim2.fromOffset(190, 38),
					position = place.position,
					anchor = place.anchor,
					parent = row,
					onChanged = function(value: string)
						values[control.name] = value
						onChange()
					end,
				}))
			elseif control.kind == "swatches" then
				local strip = frame(row, "Swatches", UDim2.fromOffset(88, 6), UDim2.new(1, -88, 0, 30))
				make("UIListLayout", strip, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) })
				local chips: { [string]: UIStroke } = {}
				local function mark()
					for hex, outline in chips do
						outline.Thickness = if string.upper(tostring(values[control.name])) == hex then 3 else 1
					end
				end
				for _, hex in PlaygroundLogic.swatches(control.param.default, themeColors(), 9) do
					local chip: TextButton = make("TextButton", strip, {
						Name = hex,
						AutoButtonColor = false,
						BackgroundColor3 = Color3.fromHex(hex),
						Text = "",
						Size = UDim2.fromOffset(26, 26),
					})
					make("UICorner", chip, { CornerRadius = UDim.new(0, 6) })
					chips[hex] = make("UIStroke", chip, {
						Color = Color3.new(1, 1, 1),
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					})
					chip.Activated:Connect(function()
						values[control.name] = hex
						mark()
						onChange()
					end)
				end
				mark()
			else
				local value: TextLabel = plainLabel(row, tostring(values[control.name]), 13, TEXT, 42)
				value.Position = UDim2.fromOffset(88, 0)
				value.Size = UDim2.new(1, -88, 1, 0)
				value.TextYAlignment = Enum.TextYAlignment.Center
			end
		end
	end

	local function codeBox(host: Instance, order: number): TextBox
		local field: TextBox = make("TextBox", host, {
			Name = "ExampleCode",
			BackgroundColor3 = FIELD,
			BackgroundTransparency = 0.15,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			Font = Enum.Font.Code,
			Text = "",
			TextSize = 13,
			TextColor3 = Color3.fromRGB(190, 240, 200),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 84),
			LayoutOrder = order,
		})
		make("UICorner", field, { CornerRadius = UDim.new(0, 8) })
		make(
			"UIPadding",
			field,
			{ PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 8) }
		)
		return field
	end

	-- Sample widgets UI animations and feedback run on. Each sits in a holder frame, and the
	-- holder is what animates, so a component's own hover motion never fights a preset.
	type Samples = { button: Frame, panel: Frame, card: Frame, text: TextLabel, counter: TextLabel }

	local function buildSamples(dscope: DemoKit.Scope, host: Instance, order: number): Samples
		local area = frame(host, "Samples", UDim2.new(), UDim2.new(1, 0, 0, 104))
		area.LayoutOrder = order
		local function holder(name: string, x: number, width: number, height: number): Frame
			return frame(area, name, UDim2.fromOffset(x, 0), UDim2.fromOffset(width, height))
		end
		local button = holder("SampleButton", 0, 110, 46)
		dscope.add(Game.CartoonButton.new({ text = "BUTTON", size = UDim2.fromScale(1, 1), parent = button }))
		local panel = holder("SamplePanel", 118, 104, 70)
		dscope.add(Game.Panel.new({ palette = "purple", size = UDim2.fromScale(1, 1), parent = panel }))
		local card = holder("SampleCard", 230, 104, 100)
		dscope.add(Game.Panel.new({ palette = "teal", pattern = true, size = UDim2.fromScale(1, 1), parent = card }))
		local text = Game.GameText.new({
			text = "SAMPLE TEXT",
			size = UDim2.fromOffset(110, 26),
			role = "label",
			position = UDim2.fromOffset(0, 52),
			parent = area,
		})
		dscope.add(text)
		local counter: TextLabel = plainLabel(area, "0", 16, TEXT, 22)
		counter.Name = "SampleCounter"
		counter.Position = UDim2.fromOffset(0, 80)
		counter.Size = UDim2.fromOffset(110, 22)
		return { button = button, panel = panel, card = card, text = text.Instance, counter = counter }
	end

	local function uiTarget(samples: Samples, group: string): GuiObject
		if group == "buttons" then
			return samples.button
		elseif group == "cards" then
			return samples.card
		elseif group == "text" then
			return samples.text
		end
		return samples.panel
	end

	local function restoreUi(samples: Samples)
		local items: { GuiObject } = { samples.button, samples.panel, samples.card, samples.text }
		for _, item in items do
			pcall(Visuals.UI.stop, item, true)
			pcall(Visuals.UI.rest, item)
			item.Visible = true
		end
	end

	local function demoReward(rarity: string): { [string]: any }
		return {
			name = "Demo reward",
			amount = 250,
			model = function(): Model
				return Visuals.Pets.demoPet({ color = DemoKit.color(DemoLogic.rarityColor(rarity)) })
			end,
		}
	end

	local function cameraMove(id: string): any
		local camera = Workspace.CurrentCamera
		if id == "Focus" then
			return Visuals.Camera.focus(target, { duration = 2.5 })
		elseif id == "Fov" then
			return Visuals.Camera.fov(45, { duration = 1.5 })
		elseif id == "Zoom" then
			return Visuals.Camera.zoom(1.6, { duration = 1.5 })
		elseif id == "Orbit" then
			return Visuals.Camera.orbit(target, { duration = 4 })
		elseif id == "Pan" and camera then
			return Visuals.Camera.pan(camera.CFrame, camera.CFrame * CFrame.new(6, 0, 0), { duration = 2 })
		elseif id == "PunchFov" then
			return Visuals.Camera.punchFov(8)
		end
		return nil
	end

	local function minimise(hidden: boolean)
		window.Instance.Visible = not hidden
	end

	local backButton: any = nil
	local function endDemo()
		local stop = stopDemo
		stopDemo = nil
		if stop then
			pcall(stop)
		end
		if backButton then
			backButton:destroy()
			backButton = nil
		end
		minimise(false)
	end

	showDetail = function()
		stopActive()
		detailScope.clean()
		detailScope = DemoKit.scope()
		local dscope = detailScope
		picker = nil
		local id = selectedId
		local category = categoryId
		if category == "icons" then
			local note = plainLabel(
				detail,
				"Kit icons and registered pack icons. Pack icons need uploaded asset ids "
					.. "(Visuals.Icons.configure) before they display.",
				12,
				MUTED,
				34
			)
			note.LayoutOrder = 1
			dscope.add(note)
			local code = codeBox(detail, 3)
			dscope.add(code)
			code.Size = UDim2.new(1, 0, 0, 50)
			code.Text = "-- pick an icon"
			local ok, result = pcall(Visuals.Icons.picker, {
				parent = detail,
				size = UDim2.new(1, 0, 1, -100),
				position = UDim2.new(),
				anchor = Vector2.zero,
				cell = 64,
				onPick = function(name: string)
					code.Text = PlaygroundLogic.exampleCode({ category = "icons", id = name })
				end,
			})
			if ok and result then
				picker = result
				result.Instance.LayoutOrder = 2
				dscope.add(result)
			else
				say("icon picker failed: " .. tostring(result))
			end
			return
		end
		if id == nil then
			return
		end

		local info = PlaygroundLogic.category(category) :: PlaygroundLogic.Category
		local title, description = id, ""
		local chips: { string } = {}
		local params: PlaygroundLogic.Params = {}
		local selection: PlaygroundLogic.Selection = { category = category, id = id }
		local group = ""

		if info.kind then
			local described = Visuals.Presets.describe(info.kind, id)
			title, description, params = described.name, described.description, described.params
			group = described.category
			chips = {
				"cost " .. tostring(described.quality.cost or "low"),
				"min " .. tostring(described.quality.min or "Low"),
				group,
			}
			selection.group = group
			if category == "vfx" then
				local preset = Visuals.VFX.registry:find(id)
				selection.looping = preset ~= nil and preset.data.looping == true
				if selection.looping then
					table.insert(chips, "looping")
				end
			end
		elseif category == "rewards" then
			local profile = Visuals.Rewards.rarity(id)
			title, description =
				profile.label,
				string.format("Reveal for the %s rarity: %.1f s, style %s.", id, profile.duration, profile.revealStyle)
			params = PlaygroundLogic.rewardParams()
			chips = { "rank " .. tostring(profile.rank), "layers " .. tostring(profile.layers) }
		elseif category == "eggs" then
			title = id .. " hatch"
			description = string.format("Visuals.Eggs.hatch with %d egg(s).", PlaygroundLogic.eggCount(id))
			params = PlaygroundLogic.eggParams(rarities())
		elseif category == "feedback" then
			local recipe = Visuals.Feedback.recipe(id) or {}
			description = string.format("Feedback event with %d step(s).", #recipe)
			params = PlaygroundLogic.feedbackParams(rarities())
			local fields = PlaygroundLogic.contextFields(recipe)
			selection.context = fields
			chips = { "context: " .. table.concat(fields, ", ") }
		elseif category == "themes" then
			local theme = Visuals.Themes.get(id)
			title, description = theme.name, theme.description
			chips = { "style " .. tostring(theme.style) }
		elseif category == "components" then
			description = "UrkUI.Game." .. id .. ": press a state to apply it with :update or a method call."
			selection.props = if SAMPLES[id] then SAMPLES[id].props else {}
		elseif category == "demos" then
			for _, entry in DEMOS do
				if entry.demo.title == id then
					description = entry.demo.description
					selection.module = entry.module
				end
			end
		end

		local values = PlaygroundLogic.defaults(params)
		selection.params = params
		selection.values = values

		dscope.add(Game.GameText.new({
			text = string.upper(title),
			size = "heading",
			align = "left",
			layoutOrder = 1,
			parent = detail,
		}))
		local about = plainLabel(detail, description, 13, MUTED, 38)
		about.LayoutOrder = 2
		dscope.add(about)
		if #chips > 0 then
			local chipRow = frame(detail, "Chips", UDim2.new(), UDim2.new(1, 0, 0, 22))
			chipRow.LayoutOrder = 3
			dscope.add(chipRow)
			make("UIListLayout", chipRow, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) })
			for _, chip in chips do
				local badge: TextLabel = make("TextLabel", chipRow, {
					BackgroundColor3 = FIELD,
					BackgroundTransparency = 0.2,
					Font = Enum.Font.GothamBold,
					Text = " " .. chip .. " ",
					TextSize = 12,
					TextColor3 = ACCENT,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 1, 0),
				})
				make("UICorner", badge, { CornerRadius = UDim.new(0, 6) })
			end
		end

		local code = codeBox(detail, 80)
		dscope.add(code)
		local function refreshCode()
			code.Text = PlaygroundLogic.exampleCode(selection)
		end

		local controlsHost = frame(detail, "Controls", UDim2.new(), UDim2.new(1, 0, 0, 0))
		controlsHost.AutomaticSize = Enum.AutomaticSize.Y
		controlsHost.LayoutOrder = 10
		controlsHost.ZIndex = 20
		dscope.add(controlsHost)
		make("UIListLayout", controlsHost, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
		buildControls(dscope, controlsHost, params, values, refreshCode)

		local samples: Samples? = nil
		if category == "ui" or category == "feedback" or category == "themes" then
			samples = buildSamples(dscope, detail, 60)
		end

		-- Components: one instance and a button per state.
		local component: any = nil
		local function buildComponent()
			if component then
				pcall(function()
					component:destroy()
				end)
				component = nil
			end
			local sample = SAMPLES[id]
			if sample == nil then
				say("no sample for " .. id)
				return
			end
			local area: any = detail:FindFirstChild("ComponentArea")
			if area == nil then
				area = frame(detail, "ComponentArea", UDim2.new(), UDim2.new(1, 0, 0, 240))
				area.LayoutOrder = 60
				dscope.add(area)
			end
			local props = table.clone(sample.props)
			for key, value in sample.layout or {} do
				props[key] = value
			end
			props.parent = if sample.host == "screen" then gui else area
			if id == "Tooltip" then
				local anchorFrame: any = area:FindFirstChild("TooltipTarget")
				if anchorFrame == nil then
					anchorFrame = make("TextLabel", area, {
						Name = "TooltipTarget",
						BackgroundColor3 = FIELD,
						Text = "tooltip target",
						TextColor3 = TEXT,
						Font = Enum.Font.GothamMedium,
						TextSize = 13,
						Size = UDim2.fromOffset(140, 40),
					})
				end
				props.target = anchorFrame
				props.parent = nil
			end
			local ok, object = pcall(Game[id].new, props)
			if not ok then
				say(id .. " failed to build: " .. tostring(object))
				return
			end
			component = object
			if id == "Grid" then
				for index = 1, 3 do
					object:add(Game.Panel.new({ palette = ({ "purple", "teal", "orange" })[index] }))
				end
			elseif id == "Tooltip" then
				object:show()
			end
		end

		if category == "components" then
			buildComponent()
			dscope.add(function()
				if component then
					pcall(function()
						component:destroy()
					end)
				end
			end)
			local sample = SAMPLES[id]
			local stateRow = frame(detail, "States", UDim2.new(), UDim2.new(1, 0, 0, 76))
			stateRow.LayoutOrder = 30
			dscope.add(stateRow)
			make(
				"UIGridLayout",
				stateRow,
				{ CellSize = UDim2.fromOffset(104, 34), CellPadding = UDim2.fromOffset(6, 6) }
			)
			for _, state in (if sample then sample.states or {} else {}) :: { State } do
				local button =
					Game.CartoonButton.new({ text = string.upper(state.label), kind = "neutral", parent = stateRow })
				dscope.add(button)
				button.Activated:Connect(function()
					if component == nil then
						return
					end
					local ok, err = pcall(function()
						if state.call then
							component[state.call](component, table.unpack(state.args or {}))
						elseif state.props then
							local update: { [string]: any } = state.props
							component:update(update)
							for key, value in update do
								values[key] = value
							end
						end
					end)
					say(
						if ok
							then id .. ": " .. state.label
							else id .. " " .. state.label .. " failed: " .. tostring(err)
					)
					refreshCode()
				end)
			end
		end

		-- Play / Replay / Stop / Reset ---------------------------------------------------------

		local function play()
			stopActive()
			local changed = PlaygroundLogic.changed(params, values)
			if category == "vfx" then
				changed.owner = stage.folder
				if selection.looping then
					active = Visuals.VFX.attach(id, target, changed)
				else
					active = Visuals.VFX.play(id, target, changed)
				end
				if active == nil then
					say(id .. " was skipped (budget, distance, throttle or quality): see rejected below")
				end
			elseif category == "ui" and samples then
				restoreUi(samples)
				active = Visuals.UI.animate(uiTarget(samples, group), id, changed)
			elseif category == "object" then
				Visuals.Objects.stop(box, true)
				active = Visuals.Objects.animate(box, id, changed)
			elseif category == "camera" then
				if group == "shake" then
					active = Visuals.Camera.shake(id, changed)
				elseif group == "cinematic" then
					active = Visuals.Camera.cinematic(id, target, changed)
				else
					active = cameraMove(id)
				end
			elseif category == "pet" then
				active = Visuals.Pets.play(id, pet, changed)
			elseif category == "rewards" then
				changed.position = target.Position
				active = Visuals.Rewards.reveal(id, demoReward(id), changed)
			elseif category == "eggs" then
				local eggs = DemoLogic.eggBatch(PlaygroundLogic.eggCount(id), values.rarity, 7)
				local batches = 0
				active = Visuals.Eggs.hatch({
					eggs = eggs,
					speed = values.speed,
					camera = values.camera,
					mode = if id == "Auto" then "auto" else nil,
					next = function(): { any }?
						batches += 1
						return if batches < 3 then DemoLogic.eggBatch(3, values.rarity, 7 + batches) else nil
					end,
				})
			elseif category == "feedback" and samples then
				feedbackTotal += values.amount
				local character = game:GetService("Players").LocalPlayer.Character
				active = Visuals.Feedback.fire(id, {
					position = target.Position,
					gui = samples.button,
					text = samples.text,
					bar = samples.panel,
					counter = samples.counter,
					total = feedbackTotal,
					amount = values.amount,
					rarity = values.rarity,
					reward = demoReward(values.rarity),
					pet = pet,
					animal = box,
					character = character,
					projectile = target,
					travel = 0.5,
					duration = 1,
					element = "fire",
					eggs = DemoLogic.eggBatch(1, values.rarity, 3),
				})
				say(string.format("%s: %d step(s) dropped", id, #active.dropped))
			elseif category == "themes" then
				Visuals.Themes.set(id)
				say(
					"theme "
						.. id
						.. ": components built from now on use it (reopen the playground to restyle its window)"
				)
				showDetail()
			elseif category == "components" then
				buildComponent()
				refreshCode()
			elseif category == "demos" then
				for _, entry in DEMOS do
					if entry.demo.title == id then
						endDemo()
						minimise(true)
						stopDemo = entry.demo.start(parent)
						backButton = Game.CartoonButton.new({
							text = "BACK TO PLAYGROUND",
							kind = "danger",
							size = UDim2.fromOffset(240, 46),
							anchor = Vector2.new(0.5, 1),
							position = UDim2.new(0.5, 0, 1, -200),
							parent = gui,
						})
						backButton.Activated:Connect(endDemo)
					end
				end
			end
		end

		local function stop()
			stopActive()
			if category == "ui" and samples then
				restoreUi(samples)
			elseif category == "object" then
				Visuals.Objects.stop(box, true)
			elseif category == "camera" then
				Visuals.Camera.restore()
			elseif category == "pet" then
				buildPet() -- a Despawn leaves the model hidden; a fresh pet is the simplest reset
			elseif category == "vfx" then
				Visuals.StopAll(stage.folder)
			end
		end

		local function guarded(action: () -> ()): () -> ()
			return function()
				local ok, err = pcall(action)
				if not ok then
					say("error: " .. tostring(err))
					warn("[UVK playground] " .. tostring(err))
				end
			end
		end

		local buttons = frame(detail, "Actions", UDim2.new(), UDim2.new(1, 0, 0, 40))
		buttons.LayoutOrder = 70
		dscope.add(buttons)
		make("UIListLayout", buttons, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) })
		local function action(text: string, kind: string, run: () -> ())
			local button =
				Game.CartoonButton.new({ text = text, kind = kind, size = UDim2.new(0.25, -3, 1, 0), parent = buttons })
			dscope.add(button)
			button.Activated:Connect(guarded(run))
		end
		action("PLAY", "buy", play)
		action("REPLAY", "primary", function()
			stop()
			play()
		end)
		action("STOP", "danger", stop)
		action("RESET", "neutral", function()
			stop()
			showDetail()
		end)
		dscope.add(stop)
		refreshCode()
	end

	-- Categories, search and settings ------------------------------------------------------------

	local categoryButtons: { [string]: any } = {}
	local function selectCategory(id: string)
		categoryId = id
		for name, button in categoryButtons do
			button:update({ kind = if name == id then "buy" else "neutral" })
		end
		search.Text = ""
		local list = listFor(id, "")
		selectedId = list[1]
		setList(list)
		showDetail()
	end

	for index, category in PlaygroundLogic.categories() do
		local button = Game.CartoonButton.new({
			text = string.upper(category.label),
			kind = "neutral",
			size = UDim2.new(1, -8, 0, 36),
			layoutOrder = index,
			parent = sidebar,
		})
		scope.add(button)
		categoryButtons[category.id] = button
		button.Activated:Connect(function()
			local ok, err = pcall(selectCategory, category.id)
			if not ok then
				say("error: " .. tostring(err))
			end
		end)
	end

	scope.add(search:GetPropertyChangedSignal("Text"):Connect(function()
		if categoryId == "icons" then
			if picker then
				picker:setQuery(search.Text)
			end
			return
		end
		local ok, list = pcall(listFor, categoryId, search.Text)
		if ok then
			setList(list)
		end
	end))

	scope
		.add(Game.CartoonButton.new({
			kind = "close",
			size = UDim2.fromOffset(34, 34),
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, 0, 0, 0),
			parent = header,
		})).Activated
		:Connect(function()
			scope.clean()
		end)

	local function caption(text: string, x: number, width: number)
		local label: TextLabel = plainLabel(settings, text, 12, MUTED, 44)
		label.Position = UDim2.fromOffset(x, 0)
		label.Size = UDim2.fromOffset(width, 44)
		label.TextYAlignment = Enum.TextYAlignment.Center
	end
	scope.add(Game.Dropdown.new({
		options = Visuals.Themes.names(),
		value = Visuals.Themes.current(),
		size = UDim2.fromOffset(190, 40),
		parent = settings,
		onChanged = function(value: string)
			Visuals.Themes.set(value)
			say("theme " .. value)
			pcall(showDetail)
		end,
	}))
	scope.add(Game.Dropdown.new({
		options = table.clone(PlaygroundLogic.QUALITY),
		value = Visuals.Settings().level,
		size = UDim2.fromOffset(120, 40),
		position = UDim2.fromOffset(198, 0),
		parent = settings,
		onChanged = function(value: string)
			Visuals.Configure({ quality = value })
			say("quality " .. value)
		end,
	}))
	caption("Reduced\nmotion", 328, 60)
	scope.add(Game.Toggle.new({
		value = Visuals.Settings().reducedMotion,
		position = UDim2.fromOffset(390, 2),
		parent = settings,
		onChanged = function(value: boolean)
			DemoKit.setReducedMotion(value)
		end,
	}))
	caption("Reduced\nflashing", 478, 60)
	scope.add(Game.Toggle.new({
		value = Visuals.Settings().reducedFlashing,
		position = UDim2.fromOffset(540, 2),
		parent = settings,
		onChanged = function(value: boolean)
			Visuals.Configure({ reducedFlashing = value })
		end,
	}))

	-- Metrics: frame times are sampled here because Visuals.Stats().frameTime only updates while
	-- the kit's own loop is running.
	local sampler = PlaygroundLogic.newSampler(90)
	local sinceRefresh = 1
	scope.add(RunService.RenderStepped:Connect(function(dt: number)
		PlaygroundLogic.sample(sampler, dt)
		sinceRefresh += dt
		if sinceRefresh >= 0.25 then
			sinceRefresh = 0
			metrics.Text = table.concat(PlaygroundLogic.metrics(Visuals.Stats(), PlaygroundLogic.fps(sampler)), "\n")
		end
	end))

	scope.add(function()
		endDemo()
		stopActive()
		detailScope.clean()
		for index, button in rows do
			button:Destroy()
			rows[index] = nil
		end
		pcall(Visuals.Camera.restore)
		Visuals.Objects.stop(box, true)
		Visuals.StopAll(stage.folder)
	end)

	local ok, err = pcall(selectCategory, "vfx")
	if not ok then
		say("error: " .. tostring(err))
	end
	return scope.clean
end

return Playground
