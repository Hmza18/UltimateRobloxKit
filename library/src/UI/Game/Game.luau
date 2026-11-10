--!strict
-- Game-style component kit (cartoon / simulator look). Components load on first use:
--   local Game = require(path.to.UI.Game.Game)
--   local card = Game.ProductCard.new({ palette = "purple", title = "TRIPLE HATCH", ... })
--
-- Game.Intent carries intents raised while UrkUI is not running (UrkUI.Intent otherwise).
-- Game.Style is Style/Style; Game.MotionPresets is Core/MotionPresets. See Game/README.md.
--
-- The components from PremiumButton on take their motion from Visuals/UI (UIAnimations presets).

local loaders: { [string]: () -> any } = {
	GameText = function(): any
		return require("./GameText")
	end,
	Panel = function(): any
		return require("./Panel")
	end,
	CartoonButton = function(): any
		return require("./CartoonButton")
	end,
	IconButton = function(): any
		return require("./IconButton")
	end,
	Badge = function(): any
		return require("./Badge")
	end,
	ProductCard = function(): any
		return require("./ProductCard")
	end,
	PromoBanner = function(): any
		return require("./PromoBanner")
	end,
	GameWindow = function(): any
		return require("./GameWindow")
	end,
	Section = function(): any
		return require("./Section")
	end,
	Grid = function(): any
		return require("./Grid")
	end,
	CurrencyCounter = function(): any
		return require("./CurrencyCounter")
	end,
	LevelBar = function(): any
		return require("./LevelBar")
	end,
	ProgressBar = function(): any
		return require("./ProgressBar")
	end,
	Timer = function(): any
		return require("./Timer")
	end,
	Toggle = function(): any
		return require("./Toggle")
	end,
	Slider = function(): any
		return require("./Slider")
	end,
	Dropdown = function(): any
		return require("./Dropdown")
	end,
	RarityFrame = function(): any
		return require("./RarityFrame")
	end,
	RewardPopup = function(): any
		return require("./RewardPopup")
	end,
	PremiumButton = function(): any
		return require("./PremiumButton")
	end,
	TabBar = function(): any
		return require("./TabBar")
	end,
	Modal = function(): any
		return require("./Modal")
	end,
	Tooltip = function(): any
		return require("./Tooltip")
	end,
	XPBar = function(): any
		return require("./XPBar")
	end,
	InventorySlot = function(): any
		return require("./InventorySlot")
	end,
	PetCard = function(): any
		return require("./PetCard")
	end,
	RarityBadge = function(): any
		return require("./RarityBadge")
	end,
	RewardPanel = function(): any
		return require("./RewardPanel")
	end,
	QuestCard = function(): any
		return require("./QuestCard")
	end,
	AchievementCard = function(): any
		return require("./AchievementCard")
	end,
	Notification = function(): any
		return require("./Notification")
	end,
	LeaderboardRow = function(): any
		return require("./LeaderboardRow")
	end,
	LoadingScreen = function(): any
		return require("./LoadingScreen")
	end,
	SelectionCard = function(): any
		return require("./SelectionCard")
	end,
	HotbarSlot = function(): any
		return require("./HotbarSlot")
	end,
	StatChip = function(): any
		return require("./StatChip")
	end,
	PurchaseBridge = function(): any
		return require("./PurchaseBridge")
	end,
	Style = function(): any
		return require("../Style/Style")
	end,
	MotionPresets = function(): any
		return require("../Core/MotionPresets")
	end,
	Intent = function(): any
		return require("./Kit").Intent
	end,
}

local COMPONENTS = {
	"GameText",
	"Panel",
	"CartoonButton",
	"IconButton",
	"Badge",
	"ProductCard",
	"PromoBanner",
	"GameWindow",
	"Section",
	"Grid",
	"CurrencyCounter",
	"LevelBar",
	"ProgressBar",
	"Timer",
	"Toggle",
	"Slider",
	"Dropdown",
	"RarityFrame",
	"RewardPopup",
	"PremiumButton",
	"TabBar",
	"Modal",
	"Tooltip",
	"XPBar",
	"InventorySlot",
	"PetCard",
	"RarityBadge",
	"RewardPanel",
	"QuestCard",
	"AchievementCard",
	"Notification",
	"LeaderboardRow",
	"LoadingScreen",
	"SelectionCard",
	"HotbarSlot",
	"StatChip",
}

local Game = {}

-- The component module names, in the contract's order.
function Game.names(): { string }
	return table.clone(COMPONENTS)
end

setmetatable(Game, {
	__index = function(self: any, key: string): any
		local loader = loaders[key]
		if loader == nil then
			return nil
		end
		local module = loader()
		rawset(self, key, module)
		return module
	end,
})

return Game :: any
