--!strict
-- Shared helpers for the game components: style lookup, colours, fonts, prices, intents, actions
-- and the pointer / touch / gamepad interaction states. Internal to UI/Game.
--
-- Components work with or without UrkUI.start(): when UrkUI is running, actions go through its
-- action registry and intents through UrkUI.Intent; otherwise intents go to Kit.Intent, so a
-- playground can listen without starting the framework.

local Context = require("../Runtime/Context")
local Format = require("../Core/Format")
local IconBridge = require("../Runtime/IconBridge")
local Motion = require("../Runtime/Motion")
local Signal = require("../../Util/Signal")
local Sounds = require("../Runtime/Sounds")
local Style = require("../Style/Style")

export type Price = {
	kind: string, -- "robux" | "currency" | "free"
	amount: number?,
	currency: string?, -- icon name of the currency
	productId: number?,
	gamePassId: number?,
}

local Kit = {}

-- Intents raised while UrkUI is not running: (name, args, source).
Kit.Intent = Signal.new()

local fontCache: { [string]: Font } = {}

function Kit.style(props: { [string]: any }): Style.StyleDef
	return Style.get(props.style)
end

function Kit.color(hex: string): Color3
	return Color3.fromHex(hex)
end

function Kit.sequence(top: string, bottom: string): ColorSequence
	return ColorSequence.new(Color3.fromHex(top), Color3.fromHex(bottom))
end

-- The swatch for a component: an explicit surface, else a palette (gray when disabled).
function Kit.swatch(style: Style.StyleDef, props: { [string]: any }, defaultPalette: string?): Style.Swatch
	if props.enabled == false then
		return Style.palette(style, "gray")
	end
	if props.surface then
		return Style.surface(style, props.surface)
	end
	return Style.palette(style, props.palette or defaultPalette)
end

local function enumFont(name: string): Font?
	local ok, font = pcall(function(): Font
		return Font.fromEnum((Enum.Font :: any)[name])
	end)
	return if ok then font else nil
end

-- Font for a text role: display / title / heading use the title family, price uses the number
-- family, everything else the body family. Tries Enum.Font first (always available), then
-- Font.fromName, then the style's fallback and finally GothamBlack.
local function familyRole(role: string?): string
	if role == "price" then
		return "number"
	elseif role == "display" or role == "title" or role == "heading" then
		return "title"
	end
	return "body"
end

function Kit.font(style: Style.StyleDef, role: string?): Font
	local family = Style.font(style, familyRole(role))
	local fallback = Style.font(style, "fallback")
	local key = family .. "|" .. fallback
	local cached = fontCache[key]
	if cached then
		return cached
	end
	local font = enumFont(family)
	if font == nil then
		local ok, named = pcall(Font.fromName, family)
		font = if ok then named else enumFont(fallback)
	end
	local result: Font = font or Font.fromEnum(Enum.Font.GothamBlack)
	fontCache[key] = result
	return result
end

-- The style's minimum text size, raised to UrkUI's accessibility minimum when it is running.
function Kit.minTextSize(style: Style.StyleDef): number
	local minimum = Style.textSize(style, "minimum")
	local context = Context.peek()
	if context and context.theme then
		minimum = math.max(minimum, context.theme:getMinTextSize())
	end
	return minimum
end

function Kit.radius(style: Style.StyleDef, token: string?): number
	local radius = style.radius
	return radius[token or "md"] or radius.md
end

function Kit.spacing(style: Style.StyleDef, token: string?): number
	local spacing = style.spacing
	return spacing[token or "md"] or spacing.md
end

-- Outline UIStroke for containers (Border mode, round joins).
function Kit.stroke(style: Style.StyleDef, weight: string?, color: string?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = Color3.fromHex(color or Style.outlineColor(style))
	stroke.Thickness = Style.outline(style, weight)
	return stroke
end

-- Marks an instance as made by a component, so rebuilds do not treat it as caller content.
function Kit.internal<T>(instance: T): T
	local object: any = instance
	object:SetAttribute("UrkInternal", true)
	return instance
end

function Kit.corner(pixels: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, pixels)
	return corner
end

function Kit.padding(pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	local value = UDim.new(0, pixels)
	padding.PaddingTop = value
	padding.PaddingBottom = value
	padding.PaddingLeft = value
	padding.PaddingRight = value
	padding:SetAttribute("UrkInternal", true)
	return padding
end

-- Applies an icon name (catalog name, "-color" names included) or an asset id to an image.
-- Returns false when nothing could be shown, so callers can fall back to text.
function Kit.icon(label: ImageLabel | ImageButton, icon: string?, image: string?): boolean
	if image and image ~= "" then
		label.Image = if string.find(image, "^%d+$") then "rbxassetid://" .. image else image
		label.ImageRectSize = Vector2.zero
		label.ScaleType = Enum.ScaleType.Fit
		return true
	end
	if icon == nil or icon == "" then
		return false
	end
	return IconBridge.apply(label, icon)
end

-- Robux artwork from props or the style (the kit ships none; see Roblox brand guidelines).
function Kit.robuxImage(style: Style.StyleDef, props: { [string]: any }): string?
	return props.robuxImage or style.robuxImage
end

-- Price text: robux "R$ 599" (or "599" when a Robux image is shown), currency "1.2K", free "FREE".
function Kit.priceText(price: Price?, withSymbol: boolean?): string
	if price == nil or price.kind == "free" then
		return "FREE"
	end
	local amount = price.amount or 0
	if price.kind == "robux" then
		local number = Format.number(amount)
		return if withSymbol == false then number else "R$ " .. number
	end
	return Format.abbrev(amount)
end

-- The running UrkUI context, or nil.
function Kit.context(): any
	return Context.peek()
end

-- Raises an intent on UrkUI.Intent when running, else on Kit.Intent.
function Kit.intent(name: string, args: { [any]: any }, source: Instance?)
	local context = Context.peek()
	if context and context.Intent then
		context.Intent:Fire(name, args, source)
	else
		Kit.Intent:Fire(name, args, source)
	end
end

-- Runs an UrkUI action spec ("OpenPanel:Shop;PlaySound:123") through the running registry.
-- Returns false when UrkUI is not running or no handler ran.
function Kit.runAction(spec: string?, source: Instance?): boolean
	if spec == nil or spec == "" then
		return false
	end
	local context = Context.peek()
	if context == nil or context.actions == nil then
		warn("[UrkUI.Game] action " .. spec .. " needs UrkUI.start(); skipped")
		return false
	end
	return context.actions:run(spec, source)
end

-- Fires the purchase intent for a price: robux -> "Purchase" { productId | gamePassId },
-- currency -> "Buy" { itemId, currency, amount }. Free prices fire nothing. Never grants.
function Kit.purchase(price: Price?, itemId: string?, source: Instance?): boolean
	if price == nil then
		return false
	end
	if price.kind == "robux" then
		if price.gamePassId then
			Kit.intent("Purchase", { gamePassId = price.gamePassId, itemId = itemId }, source)
		elseif price.productId then
			Kit.intent("Purchase", { productId = price.productId, itemId = itemId }, source)
		else
			warn("[UrkUI.Game] robux price without productId or gamePassId: " .. tostring(itemId))
			return false
		end
		return true
	end
	if price.kind == "currency" then
		Kit.intent("Buy", { itemId = itemId, currency = price.currency, amount = price.amount }, source)
		return true
	end
	return false
end

-- Applies the shared props (name, layoutOrder, size, position, anchor, visible). `size` is only
-- used when it is a UDim2, so GameText can use `size` for its text role.
function Kit.applyCommon(root: GuiObject, props: { [string]: any })
	if props.name then
		root.Name = props.name
	end
	if props.layoutOrder then
		root.LayoutOrder = props.layoutOrder
	end
	if typeof(props.size) == "UDim2" then
		root.Size = props.size
	end
	if props.position then
		root.Position = props.position
	end
	if props.anchor then
		root.AnchorPoint = props.anchor
	end
	if props.visible ~= nil then
		root.Visible = props.visible
	end
end

-- A parent that renders: a PlayerGui gets a ScreenGui of its own (returned so it can be cleaned).
function Kit.ensureScreen(parent: Instance, name: string, displayOrder: number?): (Instance, ScreenGui?)
	if parent:IsA("BasePlayerGui") then
		local gui = Instance.new("ScreenGui")
		gui.Name = name
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = displayOrder or 10
		gui.Parent = parent
		return gui, gui
	end
	return parent, nil
end

-- Product of every UIScale from `gui` up, used to turn AbsoluteSize back into 1x pixels.
function Kit.scaleFactor(gui: Instance): number
	local factor = 1
	local current: Instance? = gui
	while current do
		local scale = current:FindFirstChildOfClass("UIScale")
		if scale then
			factor *= scale.Scale
		end
		current = current.Parent
	end
	return if factor > 0 then factor else 1
end

-- Gamepad selection outline drawn around the selected object.
function Kit.selectionImage(style: Style.StyleDef, radius: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Selection"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 10, 1, 10)
	frame.Position = UDim2.fromOffset(-5, -5)
	Kit.corner(radius + 5).Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = Color3.fromHex("#FFFFFF")
	stroke.Thickness = Style.outline(style, "heavy")
	stroke.Parent = frame
	return frame
end

export type InteractOptions = {
	enabled: () -> boolean,
	onActivated: () -> (),
	scaleTarget: GuiObject?, -- object whose UIScale animates (default: the button)
	selection: boolean?, -- false keeps the engine's default selection image
	radius: number?,
}

-- Wires hover, press, release and gamepad selection feedback through MotionPresets, plus
-- Activated with sounds. Connections go into `trove`.
function Kit.interact(button: GuiButton, style: Style.StyleDef, trove: any, options: InteractOptions)
	local target = options.scaleTarget or button
	local hovered = false
	local pressed = false
	button.AutoButtonColor = false
	button.Selectable = true
	if options.selection ~= false then
		local selection = Kit.selectionImage(style, options.radius or Kit.radius(style, "md"))
		trove:Add(selection)
		button.SelectionImageObject = selection
	end

	local function sounds(): { [string]: any }
		local context = Context.peek()
		return if context and context.config and context.config.sounds then context.config.sounds else {}
	end

	local function play(name: string, onDone: (() -> ())?)
		Motion.play(target, name, { fromCurrent = true, onDone = onDone })
	end

	local function enter()
		if hovered or not options.enabled() then
			return
		end
		hovered = true
		Sounds.play(sounds().hover, 0.6)
		play("hover")
	end

	local function leave()
		if not hovered and not pressed then
			return
		end
		hovered = false
		pressed = false
		play("unhover")
	end

	local function isPress(input: InputObject): boolean
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			return true
		end
		return input.KeyCode == Enum.KeyCode.ButtonA
	end

	trove:Connect(button.MouseEnter, enter)
	trove:Connect(button.MouseLeave, leave)
	trove:Connect(button.SelectionGained, enter)
	trove:Connect(button.SelectionLost, leave)
	trove:Connect(button.InputBegan, function(input: InputObject)
		if isPress(input) and options.enabled() then
			pressed = true
			play("press")
		end
	end)
	trove:Connect(button.InputEnded, function(input: InputObject)
		if pressed and isPress(input) then
			pressed = false
			play("release", function()
				if hovered then
					play("hover")
				end
			end)
		end
	end)
	trove:Connect(button.Activated, function()
		if not options.enabled() then
			return
		end
		Sounds.play(sounds().click)
		options.onActivated()
	end)
	trove:Add(function()
		Motion.stop(target)
	end)
end

return Kit
