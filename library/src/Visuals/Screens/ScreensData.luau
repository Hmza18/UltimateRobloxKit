--!strict
-- The screen templates as data (pure Luau): which screens exist, what kind each is, its props,
-- the intents it raises and a usage line. Screens.luau loads `Screens/<id>.luau` for every entry
-- with `implemented = true`; the spec checks that list against the files on disk, and the
-- registry (Core/Registry, kind "screen") is built from the same entries.
--
-- Props are written "name: type = default | description"; a `*` after the type marks a required
-- prop. Types: string, number, boolean, list (an array), table, function, any.
-- Intents are written "Name(payload) | description".

local Registry = require("../Core/Registry")

export type Prop = { name: string, type: string, required: boolean, default: any, description: string }
export type Intent = { name: string, payload: string, description: string }

export type Screen = {
	id: string,
	name: string,
	kind: string, -- ScreensLogic.SCREEN_KINDS: decides the open / close animation
	category: string,
	priority: number, -- 1..25, the build order
	implemented: boolean,
	description: string,
	props: { Prop },
	intents: { Intent },
	methods: { string },
	usage: string,
}

type Source = {
	id: string,
	name: string,
	kind: string,
	category: string,
	implemented: boolean,
	description: string,
	props: { string }?,
	intents: { string }?,
	methods: { string }?,
	usage: string?,
}

local ScreensData = {}

ScreensData.PROP_TYPES = table.freeze({ "string", "number", "boolean", "list", "table", "function", "any" })

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$")) or text
end

-- "today: number = 1 | The day that can be claimed" -> Prop.
function ScreensData.parseProp(spec: string): Prop
	local head, description = string.match(spec, "^(.-)|(.+)$")
	assert(head ~= nil and description ~= nil, "prop needs a description: " .. spec)
	local name, kind, rest = string.match(trim(head), "^(%w+):%s*(%a+)(.*)$")
	assert(name ~= nil and kind ~= nil, "malformed prop: " .. spec)
	assert(table.find(ScreensData.PROP_TYPES, kind) ~= nil, "unknown prop type in: " .. spec)
	local tail: string = rest or ""
	local default: any = nil
	local text = string.match(tail, "=%s*(.+)$")
	if text ~= nil then
		local value = trim(text)
		if kind == "number" then
			default = tonumber(value)
			assert(default ~= nil, "number default expected: " .. spec)
		elseif kind == "boolean" then
			assert(value == "true" or value == "false", "boolean default expected: " .. spec)
			default = value == "true"
		elseif kind == "string" then
			default = value
		else
			error("only string, number and boolean props take a default: " .. spec)
		end
	end
	return {
		name = name,
		type = kind,
		required = string.find(tail, "*", 1, true) ~= nil,
		default = default,
		description = trim(description),
	}
end

-- "Selected(id) | The player picked a pet" -> Intent.
function ScreensData.parseIntent(spec: string): Intent
	local head, description = string.match(spec, "^(.-)|(.+)$")
	assert(head ~= nil and description ~= nil, "intent needs a description: " .. spec)
	local name, payload = string.match(trim(head), "^(%u%w*)%((.*)%)$")
	assert(name ~= nil, "malformed intent: " .. spec)
	return { name = name, payload = payload or "", description = trim(description) }
end

local CLOSED = "Closed() | The screen finished closing"

local SOURCES: { Source } = {
	{
		id = "PetSelection",
		name = "Pet selection",
		kind = "fullscreen",
		category = "pets",
		implemented = true,
		description = "Choose-your-starter screen: wraps Pets.selection (live 3D previews, focus, confirm).",
		props = {
			"pets: list* | Entries { id, name, description?, rarity?, model?, color?, palette?, stats? }; two or more",
			"title: string = Choose your pet | Title above the cards",
			"subtitle: string | Line under the title",
			"selected: string | Id selected when the screen opens",
			"confirmText: string = CHOOSE | Confirm button text",
			"palette: string = purple | Backdrop palette",
			"closeOnConfirm: boolean = true | Close after the confirm intent",
			"worldPosition: any | Vector3 where confetti plays on confirm",
		},
		intents = {
			"Selected(id) | A card was picked",
			"Confirmed(id) | The player confirmed the pick; the server decides what it means",
			CLOSED,
		},
		methods = { "select(id)", "confirm()", "selected()" },
		usage = 'Screens.create("PetSelection", { parent = playerGui, pets = starters }):open()',
	},
	{
		id = "EggHatching",
		name = "Egg hatching stand",
		kind = "window",
		category = "eggs",
		implemented = true,
		description = "Egg stand: egg cards, the selected egg's odds and hatch x1 / x3 / auto buttons that raise intents.",
		props = {
			"eggs: list* | Entries { id, name?, icon?, image?, rarity?, price?, currency?, palette?, odds = { { name, chance, rarity?, icon? } } }",
			"selected: string | Egg id shown first (default: the first egg)",
			"title: string = EGGS | Window title",
			"counts: list | Hatch sizes offered, default { 1, 3 }",
			"auto: boolean = true | Show the auto hatch toggle",
			"autoActive: boolean = false | Whether auto hatch is on (the caller sets it)",
			"balance: any | Number, or currency -> amount: buttons the player cannot afford are disabled",
			"currencyIcon: string = coin-color | Icon shown next to prices",
		},
		intents = {
			"Selected(eggId) | Another egg was picked",
			"HatchRequested(eggId, count) | A hatch button was pressed; the server rolls and charges",
			"AutoToggled(eggId, on) | The auto hatch toggle was pressed",
			CLOSED,
		},
		methods = { "hatch(config)" },
		usage = 'local stand = Screens.create("EggHatching", { parent = playerGui, eggs = eggs })',
	},
	{
		id = "RewardReveal",
		name = "Reward reveal",
		kind = "overlay",
		category = "rewards",
		implemented = true,
		description = "Reward reveal overlay: wraps Rewards.reveal for one reward and Rewards.batch for several.",
		props = {
			"rewards: list* | One or more { rarity, name, amount?, icon?, image?, model?, subtitle? }",
			"position: any | Vector3, CFrame or Instance: where the rarity VFX plays in the world",
			"compact: boolean = false | Smaller card",
			"skippable: boolean = true | A tap skips to the result",
			"autoDismiss: boolean = true | Dismiss after the rarity's hold time",
			"threshold: string = Epic | Batches: rarities at or above this get a full reveal",
			"hint: string | Text under the card (default: Tap to continue)",
		},
		intents = {
			"Claimed(rewards) | The reveal finished normally (the rewards were already granted by the server)",
			CLOSED,
		},
		methods = { "skip()" },
		usage = 'Screens.create("RewardReveal", { parent = playerGui, rewards = { { rarity = "Legendary", name = "Sun Fox" } } }):open()',
	},
	{
		id = "TappingHud",
		name = "Tapping HUD",
		kind = "hud",
		category = "hud",
		implemented = true,
		description = "Clicker HUD: big tap button, currency counters, multiplier chip, rebirth bar and side menu buttons.",
		props = {
			"currencies: list* | Counters { id, icon?, image?, value, format?, palette? }",
			"tapText: string = TAP | Tap button label",
			"tapIcon: string | Tap button icon",
			"tapPalette: string = gold | Tap button colour",
			"multiplier: number = 1 | Shown in the multiplier chip",
			"rebirth: table | { value, max, label? }: the rebirth progress bar (hidden when nil)",
			"menu: list | Side buttons { id, icon, label?, palette?, badge? }",
			"popups: boolean = true | Show a floating number for each reward()",
		},
		intents = {
			"Tapped(position) | The tap button was pressed (Vector2 in screen pixels)",
			"Selected(id) | A menu button was pressed",
			"RebirthRequested() | The full rebirth bar was pressed",
		},
		methods = { "reward(amount, currencyId?, from?)", "counter(currencyId)" },
		usage = 'local hud = Screens.create("TappingHud", { parent = playerGui, currencies = { { id = "coins", icon = "coin-color", value = 0 } } })',
	},
	{
		id = "AnimalInteraction",
		name = "Animal interaction",
		kind = "sheet",
		category = "animals",
		implemented = true,
		description = "Feeding panel: animal card with mood and hunger bars, a food tray, a throw button and a reaction area.",
		props = {
			"animal: table* | { name, mood (0..1), hunger (0..1), icon?, image?, moodText?, rarity? }",
			"foods: list* | Tray items { id, name?, icon?, image?, count? }",
			"selectedFood: string | Food id selected first (default: the first one in stock)",
			"canThrow: boolean = true | false disables the throw button (cooldown, out of range)",
			"throwText: string = THROW | Throw button label",
			"title: string = FEED | Panel title",
		},
		intents = {
			"Selected(foodId) | A food was picked in the tray",
			"ThrowRequested(foodId) | The throw button was pressed; the server validates the throw",
			CLOSED,
		},
		methods = { "react(kind, context?)" },
		usage = 'local feed = Screens.create("AnimalInteraction", { parent = playerGui, animal = cow, foods = foods })',
	},
	{
		id = "PetInventory",
		name = "Pet inventory",
		kind = "window",
		category = "pets",
		implemented = true,
		description = "Pet grid with rarity filters, equip and unequip, and a detail panel with a preview.",
		props = {
			"pets: list* | Pets { id, name?, rarity?, icon?, image?, model?, equipped?, stats = { { text or value, icon?, prefix?, suffix? } }, palette? }",
			"selected: any | Id of the pet shown in the detail panel",
			"filter: string = all | Rarity shown: all, or a rarity present in the list",
			"equipMax: number = 3 | Team size: equip is disabled when it is full",
			"title: string = PETS | Window title",
		},
		intents = {
			"Selected(id) | A pet card was pressed",
			"EquipRequested(id) | Equip was pressed for the selected pet; the server owns the team",
			"UnequipRequested(id) | Unequip was pressed for the selected pet",
			"FilterChanged(filter) | Another rarity tab was opened",
			CLOSED,
		},
		usage = 'Screens.create("PetInventory", { parent = playerGui, pets = ownedPets, equipMax = 4 }):open()',
	},
	{
		id = "Shop",
		name = "Shop",
		kind = "window",
		category = "shop",
		implemented = true,
		description = "Tabbed shop with a grid of product cards.",
		props = {
			"products: list* | Cards { id, tab?, title, subtitle?, icon?, image?, price?, badge?, rarity?, owned?, palette? }",
			"tabs: list | Tabs { id, text?, icon? }; products without a tab show in every tab",
			"tab: string | Active tab id (default: the first tab)",
			"title: string = SHOP | Window title",
		},
		intents = {
			"Purchased(id, price) | A product was pressed: a purchase request for the server (or PurchaseBridge), nothing is granted",
			"Selected(id) | An owned product was pressed",
			"TabChanged(id) | Another tab was opened",
			CLOSED,
		},
		usage = 'Screens.create("Shop", { parent = playerGui, tabs = tabs, products = products }):open()',
	},
	{
		id = "PremiumShop",
		name = "Premium shop",
		kind = "window",
		category = "shop",
		implemented = true,
		description = "Robux store with a featured banner, bundles and premium buttons.",
		props = {
			"bundles: list* | Cards { id, title, subtitle?, icon?, image?, price, badge?, owned?, gift?, palette? }",
			"featured: table | Banner { id?, title, subtitle?, icon?, image?, price, badge?, timer?, palette? }",
			"cta: table | Premium button under the grid { id?, text, icon?, palette? }",
			"title: string = PREMIUM | Window title",
		},
		intents = {
			"Purchased(id, price) | The banner or a bundle was pressed: a purchase request, nothing is granted",
			"Confirmed(id) | The premium button was pressed",
			CLOSED,
		},
		usage = 'Screens.create("PremiumShop", { parent = playerGui, featured = starterPack, bundles = bundles }):open()',
	},
	{
		id = "DailyRewards",
		name = "Daily rewards",
		kind = "window",
		category = "rewards",
		implemented = true,
		description = "Seven-day reward track where today pulses and can be claimed.",
		props = {
			"days: list* | The track: each { text?, amount?, icon?, image?, premium?, palette? } or a string",
			"today: number = 1 | The day that can be claimed (wraps around the track)",
			"claimed: boolean = false | Whether today's reward was already claimed",
			"streak: number | Days in a row, shown above the track (default: from today)",
			"claimText: string = CLAIM | Claim button text",
			"title: string = DAILY REWARDS | Window title",
		},
		intents = {
			"Claimed(day) | The claim button was pressed; the server grants the reward",
			CLOSED,
		},
		usage = 'Screens.create("DailyRewards", { parent = playerGui, days = track, today = 3 }):open()',
	},
	{
		id = "SpinWheel",
		name = "Spin wheel",
		kind = "window",
		category = "rewards",
		implemented = true,
		description = "Prize wheel that lands on the segment the caller supplies, then reveals the reward.",
		props = {
			"segments: list* | Segments { text?, amount?, icon?, image?, palette?, weight?, rarity?, reward? } or strings; weight only changes the drawn width",
			"spins: number | Spins left: shown on the button, which is disabled at 0 (nil: always enabled)",
			"spinText: string = SPIN | Spin button text",
			"reveal: boolean = true | After landing, show the segment's `reward` with Rewards.reveal",
			"title: string = LUCKY WHEEL | Window title",
		},
		intents = {
			"SpinRequested() | The spin button was pressed; the server picks the segment and the game calls spin(index)",
			"Landed(index) | The wheel stopped on the segment it was told to",
			"Claimed(index) | The reward reveal after a spin was dismissed",
			CLOSED,
		},
		methods = { "spin(index, options?)", "isSpinning()" },
		usage = 'local wheel = Screens.create("SpinWheel", { parent = playerGui, segments = prizes, spins = 1 })',
	},
	{
		id = "QuestLog",
		name = "Quest log",
		kind = "window",
		category = "progression",
		implemented = true,
		description = "Daily and weekly quest lists with claim buttons.",
		props = {
			"quests: list* | Quests { id, tab?, title, description?, value, max, rewards?, state?, claimText?, palette? }",
			"tabs: list | Tabs { id, text?, icon? }, default daily and weekly; quests without a tab show in every tab",
			"tab: string | Active tab id (default: the first tab)",
			"emptyText: string = No quests here yet | Shown when the tab has no quests",
			"title: string = QUESTS | Window title",
		},
		intents = {
			"Claimed(id) | A quest's claim button was pressed; the server grants the reward",
			"TabChanged(id) | Another tab was opened",
			CLOSED,
		},
		usage = 'Screens.create("QuestLog", { parent = playerGui, quests = quests }):open()',
	},
	{
		id = "Achievements",
		name = "Achievements",
		kind = "window",
		category = "progression",
		implemented = true,
		description = "Achievement cards with a progress summary.",
		props = {
			"achievements: list* | Cards { id, title, description?, icon?, image?, tier?, maxTier?, value?, max?, unlocked?, palette? }",
			"title: string = ACHIEVEMENTS | Window title",
		},
		intents = {
			"Selected(id) | An achievement card was pressed",
			CLOSED,
		},
		usage = 'Screens.create("Achievements", { parent = playerGui, achievements = achievements }):open()',
	},
	{
		id = "Settings",
		name = "Settings",
		kind = "window",
		category = "system",
		implemented = false,
		description = "Game settings plus the Visuals quality, reduced motion, reduced flashing and intensity controls.",
	},
	{
		id = "Leaderboard",
		name = "Leaderboard",
		kind = "window",
		category = "social",
		implemented = false,
		description = "Ranked rows with tabs and the local player pinned.",
	},
	{
		id = "Rebirth",
		name = "Rebirth",
		kind = "dialog",
		category = "progression",
		implemented = false,
		description = "Rebirth cost and progress, multiplier preview and a hold or double confirm.",
	},
	{
		id = "LevelUp",
		name = "Level up",
		kind = "overlay",
		category = "progression",
		implemented = false,
		description = "Level-up overlay with animated text, an XP bar fill and a rewards row.",
	},
	{
		id = "Loading",
		name = "Loading",
		kind = "fullscreen",
		category = "system",
		implemented = false,
		description = "Loading screen with a progress bar and rotating tips.",
	},
	{
		id = "Welcome",
		name = "Welcome",
		kind = "fullscreen",
		category = "system",
		implemented = false,
		description = "Title screen with a play button and news cards.",
	},
	{
		id = "Tutorial",
		name = "Tutorial",
		kind = "overlay",
		category = "system",
		implemented = false,
		description = "Step-by-step coach marks with a highlight cutout, next and skip.",
	},
	{
		id = "AreaUnlock",
		name = "Area unlock",
		kind = "banner",
		category = "progression",
		implemented = false,
		description = "Area banner with its cost and an unlock button.",
	},
	{
		id = "Collection",
		name = "Collection",
		kind = "window",
		category = "pets",
		implemented = false,
		description = "Index grid with discovered and undiscovered entries and a completion percentage.",
	},
	{
		id = "UpgradeShop",
		name = "Upgrade shop",
		kind = "window",
		category = "shop",
		implemented = false,
		description = "Upgrade rows with level pips, cost and an upgrade button.",
	},
	{
		id = "Trading",
		name = "Trading",
		kind = "window",
		category = "social",
		implemented = false,
		description = "Two offer panels with ready states and a countdown confirm (presentation only).",
	},
	{
		id = "AbilityHotbar",
		name = "Ability hotbar",
		kind = "hud",
		category = "combat",
		implemented = false,
		description = "Row of ability slots with cooldowns, keybind labels and a ready pulse.",
	},
	{
		id = "CombatProgression",
		name = "Combat progression",
		kind = "window",
		category = "combat",
		implemented = false,
		description = "Level and XP, stat chips and the skill unlock list.",
	},
}

local screens: { Screen } = {}
local byId: { [string]: Screen } = {}

for priority, source in ipairs(SOURCES) do
	local props: { Prop } = {}
	for _, spec in ipairs(source.props or {}) do
		table.insert(props, ScreensData.parseProp(spec))
	end
	local intents: { Intent } = {}
	for _, spec in ipairs(source.intents or {}) do
		table.insert(intents, ScreensData.parseIntent(spec))
	end
	local screen: Screen = {
		id = source.id,
		name = source.name,
		kind = source.kind,
		category = source.category,
		priority = priority,
		implemented = source.implemented,
		description = source.description,
		props = props,
		intents = intents,
		methods = source.methods or {},
		usage = source.usage or "",
	}
	assert(byId[screen.id] == nil, "duplicate screen " .. screen.id)
	byId[screen.id] = screen
	table.insert(screens, screen)
end

ScreensData.SCREENS = screens

-- Every screen of the plan, in build order (implemented or not).
function ScreensData.all(): { Screen }
	return screens
end

function ScreensData.get(id: string): Screen?
	return byId[id]
end

-- Ids of the screens that exist as `Screens/<id>.luau`, in build order.
function ScreensData.names(): { string }
	local names: { string } = {}
	for _, screen in ipairs(screens) do
		if screen.implemented then
			table.insert(names, screen.id)
		end
	end
	return names
end

-- The Core/Registry preset for a screen. Props with a string, number or boolean default become
-- registry params; the full prop and intent lists are in `data`.
function ScreensData.preset(screen: Screen): Registry.Preset
	local params: { [string]: Registry.Param } = {}
	for _, prop in ipairs(screen.props) do
		if prop.default ~= nil then
			params[prop.name] = { type = prop.type :: any, default = prop.default, description = prop.description }
		end
	end
	local intents: { string } = {}
	for _, intent in ipairs(screen.intents) do
		table.insert(intents, intent.name)
	end
	return {
		id = screen.id,
		name = screen.name,
		category = screen.category,
		description = screen.description,
		params = params,
		usage = screen.usage,
		tags = { "screen", screen.kind },
		quality = { min = "Low", cost = "medium" },
		data = {
			kind = screen.kind,
			props = screen.props,
			intents = screen.intents,
			intentNames = intents,
			methods = screen.methods,
			builtin = true,
		},
	}
end

-- Adds or replaces a game's own screen definition (Screens.register calls this).
function ScreensData.define(source: Source): Screen
	local props: { Prop } = {}
	for _, spec in ipairs(source.props or {}) do
		table.insert(props, ScreensData.parseProp(spec))
	end
	local intents: { Intent } = {}
	for _, spec in ipairs(source.intents or {}) do
		table.insert(intents, ScreensData.parseIntent(spec))
	end
	local existing = byId[source.id]
	local screen: Screen = {
		id = source.id,
		name = source.name,
		kind = source.kind,
		category = source.category,
		priority = if existing then existing.priority else #screens + 1,
		implemented = true,
		description = source.description,
		props = props,
		intents = intents,
		methods = source.methods or {},
		usage = source.usage or "",
	}
	if existing then
		screens[table.find(screens, existing) :: number] = screen
	else
		table.insert(screens, screen)
	end
	byId[screen.id] = screen
	return screen
end

local registry = Registry.new("screen")
for _, screen in ipairs(screens) do
	if screen.implemented then
		registry:register(ScreensData.preset(screen))
	end
end

ScreensData.registry = registry

return ScreensData
