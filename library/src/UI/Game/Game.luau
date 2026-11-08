--!strict
-- Game-style component kit (cartoon / simulator look). Components load on first use:
--   local Game = require(path.to.UI.Game.Game)
--   local card = Game.ProductCard.new({ palette = "purple", title = "TRIPLE HATCH", ... })
--
-- Game.Intent carries intents raised while UrkUI is not running (UrkUI.Intent otherwise).
-- Game.Style is Style/Style; Game.MotionPresets is Core/MotionPresets. See Game/README.md.

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
