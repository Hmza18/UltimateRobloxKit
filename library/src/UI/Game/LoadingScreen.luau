--!strict
-- Loading screen: a full-screen cover with a breathing logo, a title, a progress bar and tips
-- that rotate every few seconds. `screen:finish()` fills the bar, fades the whole screen out,
-- fires Closed and destroys it.
--   local loading = LoadingScreen.new({ title = "PET WORLD", logo = "rbxassetid://1", parent = playerGui,
--       tips = { "Hatch eggs to find rare pets", "Rebirth to multiply your coins" } })
--   loading:setProgress(0.4)             -- 0..1, from your own loading code
--   loading:finish()
--
-- The root is a CanvasGroup, so everything fades together. A PlayerGui parent gets a ScreenGui of
-- its own (DisplayOrder 100, IgnoreGuiInset). Put a custom logo (ViewportFrame, animated image)
-- in loading.Content. Tips swap with a fade; under reduced motion the logo stands still.

local Base = require("./Base")
local Extra = require("./Extra")
local Host = require("../../Visuals/Runtime/Host")
local Kit = require("./Kit")
local ProgressBar = require("./ProgressBar")
local Signal = require("../../Util/Signal")
local Style = require("../Style/Style")

export type Props = {
	title: string?,
	logo: string?, -- image id or content string
	icon: string?, -- catalog icon used when there is no logo
	tips: { string }?,
	tipInterval: number?, -- seconds per tip, default 4
	progress: number?, -- 0..1
	palette: string?, -- bar colour, default "green"
	background: string?, -- surface name for the backdrop gradient, default "dark"
	destroyOnClose: boolean?, -- default true
	style: string?,
	parent: Instance?,
	name: string?,
	visible: boolean?,
	[string]: any,
}

local LoadingScreen = {}

-- The tip after `index` (wraps around; 0 when there are none).
function LoadingScreen.nextTip(index: number, count: number): number
	if count <= 0 then
		return 0
	end
	return index % count + 1
end

local function build(object: any)
	local props = object.props
	local style = object.style
	local root: CanvasGroup = object.Instance
	root.Size = UDim2.fromScale(1, 1)
	root.Active = true -- swallow input while loading
	local swatch = Style.surface(style, props.background or "dark")
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = Kit.sequence(swatch.top, swatch.bottom)
	gradient.Parent = root
	object.parts:Add(gradient)

	local logo = Extra.frame(root, "Logo", {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.36),
		size = UDim2.fromOffset(180, 180),
	})
	logo:SetAttribute("UrkInternal", nil)
	object.parts:Add(logo)
	object.Content = logo
	Extra.image(logo, "Picture", props.icon, props.logo)
	Extra.own(object, Extra.UI.animate(logo, "Pulse", { speed = 0.6, intensity = 0.8 }))

	local title = Extra.label(object, root, "Title", { text = props.title or "", role = "display" }, {
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.58),
		size = UDim2.new(0.8, 0, 0, 56),
	})
	object.parts:Add(title)

	local bar = ProgressBar.new({
		value = math.clamp(props.progress or 0, 0, 1),
		max = 1,
		palette = props.palette or "green",
		style = props.style,
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.7),
		size = UDim2.new(0.5, 0, 0, 28),
		parent = root,
	})
	object.parts:Add(bar)
	object.bar = bar

	local tips: { string } = props.tips or {}
	object.tipIndex = if #tips > 0 then math.clamp(object.tipIndex or 1, 1, #tips) else 0
	local tip = Instance.new("CanvasGroup")
	tip.Name = "Tip"
	tip.BackgroundTransparency = 1
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.8)
	tip.Size = UDim2.new(0.8, 0, 0, 48)
	Kit.internal(tip)
	tip.Parent = root
	object.parts:Add(tip)
	object.tip = tip
	object.tipLabel = Extra.label(object, tip, "Text", {
		text = tips[object.tipIndex] or "",
		role = "label",
		wrap = true,
		color = swatch.text,
	})
end

local function rotate(object: any)
	local tips: { string } = object.props.tips or {}
	if object.destroyed or object.closing or #tips < 2 or object.tip == nil then
		return
	end
	local tip: CanvasGroup = object.tip
	local label: TextLabel = object.tipLabel
	object.tipIndex = LoadingScreen.nextTip(object.tipIndex, #tips)
	local text = tips[object.tipIndex]
	Extra.UI.animate(tip, "FadeOut", {
		onDone = function(completed: boolean)
			if not completed or object.destroyed or object.tip ~= tip then
				return
			end
			label.Text = text
			Extra.UI.animate(tip, "FadeIn")
		end,
	})
end

function LoadingScreen.new(props: Props)
	local copy = table.clone(props)
	local screen: ScreenGui? = nil
	if copy.parent then
		local parent, created = Kit.ensureScreen(copy.parent, "LoadingScreen", 100)
		copy.parent = parent
		screen = created
		if created then
			created.IgnoreGuiInset = true
		end
	end
	local object = Base.new({
		className = "CanvasGroup",
		name = "LoadingScreen",
		props = copy,
		build = build,
		apply = function(self: any, partial: { [string]: any }): boolean
			for key in pairs(partial) do
				if key ~= "progress" then
					return false
				end
			end
			if self.bar == nil then
				return false
			end
			self.bar:update({ value = math.clamp(self.props.progress or 0, 0, 1) })
			return true
		end,
		setup = function(self: any)
			self.Closed = Signal.new()
			self.closing = false
			local elapsed = 0
			-- One clock job turns the tips; it ends with the screen.
			local remove = Host.clock:add(function(dt: number): boolean?
				if self.destroyed or self.closing then
					return false
				end
				elapsed += dt
				if elapsed >= (self.props.tipInterval or 4) then
					elapsed = 0
					rotate(self)
				end
				return true
			end)
			self.trove:Add(remove)
			self.trove:Add(function()
				if self.tip then
					Extra.UI.stop(self.tip, false)
				end
				Extra.UI.stop(self.Instance, false)
				self.Closed:DisconnectAll()
			end)
			if screen then
				self.trove:Add(screen)
			end
		end,
	})

	function object.setProgress(self: any, ratio: number)
		self:update({ progress = ratio })
	end

	-- Fills the bar, fades out, fires Closed and (unless destroyOnClose = false) destroys.
	function object.finish(self: any)
		if self.destroyed or self.closing then
			return
		end
		self.closing = true
		if self.bar then
			self.bar:update({ value = 1 })
		end
		Extra.UI.hide(self.Instance, "FadeOut", {
			delay = 0.25,
			duration = 0.5,
			onDone = function()
				if self.destroyed then
					return
				end
				self.Closed:Fire()
				if self.props.destroyOnClose ~= false then
					self:destroy()
				end
			end,
		})
	end

	return object
end

return LoadingScreen
