-- Screen layer: letterbox, fades, title cards, badge, skip button and the optional test panel.
-- Resolution independent (scale sizes, TextScaled with size caps, safe-area aware), animated on the
-- cinematic Tweener so pause and skip stop it with everything else.

local GuiService = game:GetService("GuiService")

local CinematicUi = {}
CinematicUi.__index = CinematicUi

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function text(parent, props)
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		TextScaled = true,
		Font = props.Font or Enum.Font.FredokaOne,
		TextColor3 = props.TextColor3 or Color3.new(1, 1, 1),
		Text = props.Text or "",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		ZIndex = props.ZIndex or 5,
		TextTransparency = props.TextTransparency or 0,
	}, parent)
	new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 96, MinTextSize = props.MinTextSize or 10 }, label)
	if props.Stroke then
		new("UIStroke", { Thickness = props.StrokeThickness or 3, Color = props.Stroke, Transparency = props.TextTransparency or 0 }, label)
	end
	return label
end

function CinematicUi.new(playerGui, tweener, config)
	local self = setmetatable({}, CinematicUi)
	self.tweener = tweener
	self.config = config
	local gui = new("ScreenGui", {
		Name = "SupermarketCinematicUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	self.gui = gui
	local bar = config.Letterbox
	self.top = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, bar), Position = UDim2.fromScale(0, -bar), ZIndex = 2 }, gui)
	self.bottom = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.fromScale(1, bar), Position = UDim2.fromScale(0, 1), ZIndex = 2 }, gui)
	self.fade = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, ZIndex = 20 }, gui)

	-- title block sits in the upper third so the store stays visible underneath
	local title = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.86, 0.3), Position = UDim2.fromScale(0.5, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }, gui)
	new("UIAspectRatioConstraint", { AspectRatio = 4.2, DominantAxis = Enum.DominantAxis.Width }, title)
	self.title = title
	self.titleWords = {}
	local words = {}
	for w in string.gmatch(config.Title, "%S+") do
		words[#words + 1] = w
	end
	-- two lines: split near the middle word
	local half = math.ceil(#words / 2)
	local lines = { {}, {} }
	for i, w in ipairs(words) do
		table.insert(lines[i <= half and 1 or 2], w)
	end
	for li, line in ipairs(lines) do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.46), Position = UDim2.fromScale(0, (li - 1) * 0.5), ZIndex = 5 }, title)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.015, 0), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		for wi, w in ipairs(line) do
			local share = (#w + 0.6) / 24
			local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(share, 1), LayoutOrder = wi, ZIndex = 5 }, row)
			local label = text(holder, { Text = w, Font = config.Font, TextColor3 = Color3.fromRGB(255, 255, 255), Stroke = Color3.fromRGB(20, 90, 50), StrokeThickness = 4, MaxTextSize = 110, TextTransparency = 1, ZIndex = 6 })
			local grad = new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 120)), ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 255, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 196, 60)) }), Rotation = 90 }, label)
			local scale = new("UIScale", { Scale = 0 }, label)
			self.titleWords[#self.titleWords + 1] = { label = label, scale = scale, grad = grad }
		end
	end
	local sub = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0.62, 0.075), Position = UDim2.fromScale(0.5, 0.37), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }, sub)
	self.subWords = {}
	local i = 0
	for w in string.gmatch(config.Subtitle, "%S+") do
		i = i + 1
		local holder = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(w == "•" and 0.04 or 0.19, 1), LayoutOrder = i, ZIndex = 5 }, sub)
		local label = text(holder, { Text = w, Font = config.Font, TextColor3 = w == "•" and Color3.fromRGB(255, 214, 64) or Color3.new(1, 1, 1), Stroke = Color3.fromRGB(30, 30, 40), StrokeThickness = 2, MaxTextSize = 48, TextTransparency = 1, ZIndex = 6 })
		self.subWords[#self.subWords + 1] = { label = label, holder = holder }
	end

	-- badge for the opening ("GRAND OPENING!")
	self.badge = new("Frame", { BackgroundColor3 = Color3.fromRGB(255, 92, 72), Size = UDim2.fromScale(0.26, 0.075), Position = UDim2.fromScale(0.5, 0.16), AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 7 }, gui)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, self.badge)
	new("UIStroke", { Thickness = 3, Color = Color3.new(1, 1, 1) }, self.badge)
	new("UIAspectRatioConstraint", { AspectRatio = 5.5 }, self.badge)
	self.badgeLabel = text(self.badge, { Text = "GRAND OPENING!", Font = config.Font, Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1), MaxTextSize = 40, ZIndex = 8 })
	self.badgeScale = new("UIScale", { Scale = 0 }, self.badge)

	-- skip button: bottom right, inside the safe area, at least 44 px tall on phones
	if config.AllowSkip then
		local inset = Vector2.new(0, 0)
		pcall(function()
			inset = GuiService:GetGuiInset()
		end)
		local skip = new("TextButton", {
			Name = "Skip",
			Text = "SKIP  ▶▶",
			Font = config.Font,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30),
			BackgroundTransparency = 0.35,
			AutoButtonColor = true,
			Size = UDim2.new(0.13, 0, 0.065, 0),
			Position = UDim2.new(0.97, -inset.X, 1 - bar - 0.02, 0),
			AnchorPoint = Vector2.new(1, 1),
			ZIndex = 15,
		}, gui)
		new("UISizeConstraint", { MinSize = Vector2.new(110, 44), MaxSize = Vector2.new(220, 64) }, skip)
		new("UICorner", { CornerRadius = UDim.new(0.3, 0) }, skip)
		new("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0) }, skip)
		self.skip = skip
	end
	return self
end

function CinematicUi:letterbox(on, duration)
	local bar = self.config.Letterbox
	local fromT, toT = self.top.Position, UDim2.fromScale(0, on and 0 or -bar)
	local fromB, toB = self.bottom.Position, UDim2.fromScale(0, on and 1 - bar or 1)
	self.tweener:play({ from = 0, to = 1, duration = duration or 0.6, ease = "inOutCubic", set = function(u)
		self.top.Position = fromT:Lerp(toT, u)
		self.bottom.Position = fromB:Lerp(toB, u)
	end })
end

-- Fade the full-screen frame to `alpha` (0 = covering, 1 = clear) with a colour.
function CinematicUi:fadeTo(alpha, duration, color, done)
	if color then
		self.fade.BackgroundColor3 = color
	end
	local from = self.fade.BackgroundTransparency
	return self.tweener:play({ from = from, to = alpha, duration = duration or 0.4, ease = "inOutSine", set = function(v)
		self.fade.BackgroundTransparency = v
	end, done = done })
end

-- A quick white flash used as a transition accent on cuts.
function CinematicUi:flash(duration)
	self.fade.BackgroundColor3 = Color3.new(1, 1, 1)
	self.fade.BackgroundTransparency = 0.25
	self:fadeTo(1, duration or 0.25)
end

function CinematicUi:showBadge(textValue, hold)
	self.badgeLabel.Text = textValue
	self.badge.Visible = true
	self.tweener:play({ from = 0, to = 1, duration = 0.35, ease = "outBack", set = function(v)
		self.badgeScale.Scale = v
	end })
	self.tweener:play({ from = 1, to = 0, duration = 0.25, delay = hold or 2, ease = "inQuad", set = function(v)
		self.badgeScale.Scale = v
	end, done = function()
		self.badge.Visible = false
	end })
end

function CinematicUi:showTitle()
	for i, w in ipairs(self.titleWords) do
		local d = (i - 1) * 0.09
		self.tweener:play({ from = 0, to = 1, duration = 0.42, delay = d, ease = "outBack", set = function(v)
			w.scale.Scale = v
		end })
		self.tweener:play({ from = 1, to = 0, duration = 0.2, delay = d, ease = "outQuad", set = function(v)
			w.label.TextTransparency = v
			local stroke = w.label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = v
			end
		end })
		-- one shine pass across each word, staggered after everything has landed
		self.tweener:play({ from = -1, to = 1, duration = 0.6, delay = 1.0 + i * 0.05, ease = "inOutSine", set = function(v)
			w.grad.Offset = Vector2.new(0, v * 0.3)
		end })
	end
	for i, w in ipairs(self.subWords) do
		local d = 0.9 + (i - 1) * 0.12
		self.tweener:play({ from = 1, to = 0, duration = 0.35, delay = d, ease = "outCubic", set = function(v)
			w.label.TextTransparency = v
			local stroke = w.label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = v
			end
			w.label.Position = UDim2.fromScale(0, 0.35 * v)
		end })
	end
end

function CinematicUi:hideTitle(duration)
	for _, w in ipairs(self.titleWords) do
		self.tweener:play({ from = 0, to = 1, duration = duration or 0.4, ease = "inQuad", set = function(v)
			w.label.TextTransparency = v
		end })
	end
	for _, w in ipairs(self.subWords) do
		self.tweener:play({ from = 0, to = 1, duration = duration or 0.4, ease = "inQuad", set = function(v)
			w.label.TextTransparency = v
		end })
	end
end

function CinematicUi:destroy()
	self.gui:Destroy()
end

-- Test panel (separate ScreenGui so it survives between plays). callbacks: replay, pause, skip.
function CinematicUi.testPanel(playerGui, callbacks)
	local gui = new("ScreenGui", { Name = "SupermarketCinematicTestPanel", ResetOnSpawn = false, DisplayOrder = 1001 }, playerGui)
	local frame = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.2, Size = UDim2.fromOffset(250, 104), Position = UDim2.fromOffset(12, 12) }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	local status = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 6), Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = "Intro cinematic: idle" }, frame)
	local function button(label, x, cb)
		local b = new("TextButton", { Text = label, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(46, 184, 92), Size = UDim2.fromOffset(72, 36), Position = UDim2.fromOffset(x, 34) }, frame)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		b.Activated:Connect(cb)
		return b
	end
	button("Replay", 8, callbacks.replay)
	local pause = button("Pause", 88, callbacks.pause)
	button("Skip", 168, callbacks.skip)
	local info = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 76), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 215), Text = "" }, frame)
	return { gui = gui, status = status, info = info, pause = pause }
end

return CinematicUi
