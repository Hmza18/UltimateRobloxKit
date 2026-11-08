--!strict
-- Reward reveal: a patterned card that springs in with the "reveal" preset over slowly turning
-- light rays, with a big icon, an outlined title and an amount. It closes itself after `duration`
-- seconds or when clicked, then fires Closed (and destroys itself unless destroyOnClose = false).
--   RewardPopup.new({ title = "DAILY REWARD!", icon = "gift-color", amount = "x250", palette = "gold",
--       parent = playerGui })
--
-- Rays turn on the shared ticker only while the popup shows, and stay still under reduced motion.

local Base = require("./Base")
local Decor = require("../Core/Decor")
local GameText = require("./GameText")
local Kit = require("./Kit")
local Motion = require("../Runtime/Motion")
local Panel = require("./Panel")
local Signal = require("../../Util/Signal")
local Ticker = require("./Ticker")

export type Props = {
	title: string?,
	icon: string?,
	image: string?,
	amount: string?,
	palette: string?, -- default "gold"
	rays: boolean?, -- default true
	duration: number?, -- seconds before it closes itself, default 2.5; 0 keeps it open
	destroyOnClose: boolean?, -- default true
	style: string?,
	parent: Instance?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

local RewardPopup = {}

local RAY_COUNT = 8
local RAY_SPEED = 25 -- degrees per second

local function rays(object: any, root: GuiObject)
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromScale(1.7, 1.7)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeXX
	holder.ZIndex = 0
	for index = 1, RAY_COUNT do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.12, 1)
		ray.Rotation = (index - 1) * (180 / RAY_COUNT)
		ray.ZIndex = 0
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		ray.Parent = holder
	end
	holder.Parent = root
	object.parts:Add(holder)
	if not Motion.isReduced() then
		local started = os.clock()
		object.parts:Add(Ticker.frame(function(now: number): boolean?
			if holder.Parent == nil then
				return false
			end
			if root.Visible then
				holder.Rotation = Decor.spin(now - started, { speed = RAY_SPEED })
			end
			return true
		end))
	end
end

local function label(object: any, parent: Instance, position: UDim2, size: UDim2, options: GameText.TextOptions)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = position
	text.Size = size
	text.ZIndex = 2
	GameText.decorate(text, object.style, options, object.parts)
	text.Parent = parent
end

local function build(object: any)
	local props = object.props
	local root: TextButton = object.Instance
	if typeof(props.size) ~= "UDim2" then
		root.Size = UDim2.fromOffset(300, 320)
	end
	if props.position == nil then
		root.Position = UDim2.fromScale(0.5, 0.5)
	end
	if props.anchor == nil then
		root.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	if props.rays ~= false then
		rays(object, root)
	end
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 1
	card.Parent = root
	object.parts:Add(card)
	object.card = card
	local surfaceProps: Panel.SurfaceProps = {
		palette = props.palette or "gold",
		radius = "xl",
		outline = "heavy",
		gloss = true,
		pattern = true,
		shadow = true,
	}
	local content = Panel.surface(object, card, surfaceProps).content

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0.08)
	icon.Size = UDim2.fromScale(0.5, 0.5)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	icon.ZIndex = 2
	icon.Parent = content
	if not Kit.icon(icon, props.icon, props.image) then
		icon:Destroy()
	end
	local titleOptions: GameText.TextOptions = { text = props.title or "", role = "display", maxSize = 40 }
	label(object, content, UDim2.fromScale(0.5, 0.6), UDim2.new(1, -24, 0.18, 0), titleOptions)
	if props.amount then
		local amountOptions: GameText.TextOptions = { text = props.amount, role = "price", maxSize = 36 }
		label(object, content, UDim2.fromScale(0.5, 0.78), UDim2.new(1, -24, 0.15, 0), amountOptions)
	end
end

local function close(object: any)
	if object.destroyed or not object.showing then
		return
	end
	object.showing = false
	if object.closeThread then
		pcall(task.cancel, object.closeThread)
		object.closeThread = nil
	end
	local function finish()
		object.Instance.Visible = false
		object.Closed:Fire()
		if object.props.destroyOnClose ~= false then
			object:destroy()
		end
	end
	if object.card then
		Motion.play(object.card, "close", { onDone = finish })
	else
		finish()
	end
end

local function open(object: any)
	if object.destroyed then
		return
	end
	object.showing = true
	object.Instance.Visible = true
	if object.card then
		Motion.play(object.card, "reveal")
	end
	if object.closeThread then
		pcall(task.cancel, object.closeThread)
	end
	local duration = object.props.duration or 2.5
	object.closeThread = if duration > 0 then task.delay(duration, close, object) else nil
end

function RewardPopup.new(props: Props)
	local copy = table.clone(props)
	local screen: ScreenGui? = nil
	if copy.parent then
		local parent, created = Kit.ensureScreen(copy.parent, "RewardPopup", 60)
		copy.parent = parent
		screen = created
	end
	local startHidden = copy.visible == false
	copy.visible = nil
	local object = Base.new({
		className = "TextButton",
		name = "RewardPopup",
		props = copy,
		build = build,
		setup = function(self: any)
			self.Closed = Signal.new()
			self.trove:Connect(self.Instance.Activated, function()
				close(self)
			end)
			self.trove:Add(function()
				if self.closeThread then
					pcall(task.cancel, self.closeThread)
					self.closeThread = nil
				end
				if self.card then
					Motion.stop(self.card)
				end
				self.Closed:DisconnectAll()
			end)
			if screen then
				self.trove:Add(screen)
			end
		end,
	})
	function object.open(self: any)
		open(self)
	end
	function object.close(self: any)
		close(self)
	end
	if startHidden then
		object.Instance.Visible = false
	else
		open(object)
	end
	return object
end

return RewardPopup
