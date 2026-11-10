--!strict
-- Welcome screen: the title screen. Logo or title, a subtitle, a big play button and a row of
-- news cards. Play raises Confirmed; a news card raises Selected(id).
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local root = shell.root
	local backdrop = shell:own(Game.Panel.new({
		style = shell.styleName,
		parent = root,
		name = "Backdrop",
		surface = "dark",
		radius = "sm",
		outline = "thin",
		shadow = false,
		size = UDim2.fromScale(1, 1),
	}))
	backdrop.Instance.ZIndex = 0
	local column = ScreenKit.scroller(root, "Column", 14)
	column.AnchorPoint = Vector2.new(0.5, 0)
	column.ScrollBarThickness = 0
	local darkInk = ScreenKit.ink(shell.style, "dark", "center")

	local logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.BackgroundTransparency = 1
	logo.ScaleType = Enum.ScaleType.Fit
	logo.LayoutOrder = 1
	logo.Size = UDim2.fromOffset(160, 160)
	logo.Parent = column
	local title = shell:text(column, props.title, "display", { layoutOrder = 2 })
	local subtitle = shell:text(column, "", "label", { layoutOrder = 3, color = darkInk.color, stroke = false })
	local play = shell:button(column, {
		premium = true,
		name = "Play",
		text = props.playText,
		layoutOrder = 4,
		size = UDim2.fromOffset(260, 72),
	})
	local news = ScreenKit.cards(column, "news", 5)
	shell.trove:Add(news.destroy)
	local pulse: any = nil

	local function refreshHead()
		local current = shell.props
		local hasLogo = ScreenKit.icon(logo, current.icon, current.logo)
		logo.Visible = hasLogo
		title:update({ text = current.title })
		subtitle:update({ text = current.subtitle or "", visible = current.subtitle ~= nil })
		play:update({ text = current.playText })
	end

	-- A news card: an inset panel with a headline, a line of text and an optional badge.
	local function newsCard(item: any, index: number, size: UDim2?): any
		local panel = Game.Panel.new({
			style = shell.styleName,
			parent = news.holder,
			layoutOrder = index,
			name = tostring(item.id or index),
			palette = item.palette,
			surface = if item.palette == nil then "inset" else nil,
			padding = "sm",
			size = size,
		})
		local inner: Instance = panel.Content or panel.Instance
		local ink = if item.palette == nil then ScreenKit.ink(shell.style, "inset", "left") else { align = "left" }
		local parts: { any } = {
			Game.GameText.new({
				style = shell.styleName,
				parent = inner,
				text = tostring(item.title or ""),
				role = "label",
				color = ink.color,
				stroke = ink.stroke,
				align = "left",
				size = UDim2.new(1, 0, 0.36, 0),
			}),
			Game.GameText.new({
				style = shell.styleName,
				parent = inner,
				text = tostring(item.text or ""),
				role = "caption",
				color = ink.color,
				stroke = ink.stroke,
				align = "left",
				wrap = true,
				size = UDim2.new(1, 0, 0.6, 0),
				position = UDim2.fromScale(0, 0.4),
			}),
		}
		if item.badge ~= nil then
			table.insert(
				parts,
				Game.Badge.new({
					style = shell.styleName,
					parent = panel.Instance,
					kind = item.badge.kind,
					text = item.badge.text,
				})
			)
		end
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 10
		hit.Parent = panel.Instance
		local binding = UI.bind(hit, "Soft", {
			target = panel.Instance,
			onActivated = function()
				shell:fire("Selected", item.id or index)
			end,
		})
		local destroy = panel.destroy
		panel.destroy = function(self: any)
			binding.destroy()
			for _, part in ipairs(parts) do
				part:destroy()
			end
			destroy(self)
		end
		panel.hit = hit
		return panel
	end

	local function focusList(): { GuiObject }
		local objects: { GuiObject } = { play.Instance }
		for _, card in pairs(news.cards) do
			table.insert(objects, card.hit)
		end
		return objects
	end

	local function buildNews()
		news.set(shell.props.news or {}, newsCard)
		shell:relayout()
		shell:focusables(focusList())
	end

	shell.trove:Add(play.Activated:Connect(function()
		shell:fire("Confirmed")
	end))
	shell.trove:Add(function()
		if pulse ~= nil then
			pulse.stop(false)
		end
	end)

	shell:onLayout(function(env: ScreensLogic.Env)
		local width = math.min(env.safe.w - env.margin * 2, 900)
		local height = env.safe.h - env.margin * 2
		column.Size = UDim2.fromOffset(width, height)
		column.Position = UDim2.new(0.5, 0, 0, env.margin)
		-- The logo gives way first on short screens (landscape phones).
		local logoSide = math.clamp(math.floor(height * 0.28), 0, 180)
		logo.Size = UDim2.fromOffset(logoSide, logoSide)
		news.layout(width - 10)
	end)

	refreshHead()
	buildNews()
	shell.onOpened = function()
		UI.animate(title.Instance, "SlideInDown")
		UI.animate(play.Instance, "PopIn", { delay = 0.2 })
		news.reveal("SlideInUp")
		if pulse == nil then
			pulse = UI.animate(play.Instance, "Pulse", { delay = 0.8 })
		end
	end
	shell.onClosed = function()
		if pulse ~= nil then
			pulse.stop(true)
			pulse = nil
		end
	end

	return {
		update = function(partial: { [string]: any })
			refreshHead()
			if partial.news ~= nil then
				buildNews()
			end
		end,
	}
end
