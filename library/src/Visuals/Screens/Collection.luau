--!strict
-- Collection screen: the index. A completion summary above a grid of tiles; discovered entries
-- show their art and name, undiscovered ones a dark silhouette and "???". A newly discovered
-- entry (after screen:update) flips in.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")
local Style = require("../../UI/Style/Style")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, kind = "wide", headerPalette = "teal" })
	local summaryText = shell:text(window.content, "", "label", ScreenKit.ink(shell.style, "window", "center"))
	summaryText:update({ layoutOrder = 1 })
	local summaryBar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = window.content,
		layoutOrder = 2,
		name = "Completion",
		palette = "teal",
		value = 0,
		max = 1,
		size = UDim2.new(1, -10, 0, 24),
	}))
	local grid = ScreenKit.cards(window.content, "tile", 3)
	shell.trove:Add(grid.destroy)
	local known: { [string]: boolean } = {}
	local ink = ScreenKit.ink(shell.style, "inset", "center")

	local function tile(entry: any, index: number, size: UDim2?): any
		local discovered = entry.discovered == true
		local rarity = if discovered and type(entry.rarity) == "string" then string.lower(entry.rarity) else nil
		local panel = Game.Panel.new({
			style = shell.styleName,
			parent = grid.holder,
			layoutOrder = index,
			name = tostring(entry.id or index),
			surface = if discovered then "inset" else "dark",
			radius = "md",
			outline = "regular",
			shadow = false,
			size = size,
		})
		local inner: Instance = panel.Content or panel.Instance
		local image = Instance.new("ImageLabel")
		image.Name = "Art"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0)
		image.Position = UDim2.fromScale(0.5, 0.08)
		image.Size = UDim2.fromScale(0.64, 0.6)
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = inner
		ScreenKit.icon(image, entry.icon or (if entry.image == nil then "paw-color" else nil), entry.image)
		if not discovered then
			-- Silhouette: the art in flat black, slightly see-through.
			image.ImageColor3 = Color3.new(0, 0, 0)
			image.ImageTransparency = 0.35
		end
		local name = Game.GameText.new({
			style = shell.styleName,
			parent = inner,
			text = if discovered then tostring(entry.name or entry.id or "") else "???",
			role = "caption",
			color = if discovered then ink.color else Style.surface(shell.style, "dark").text,
			stroke = false,
			size = UDim2.fromScale(1, 0.26),
			position = UDim2.fromScale(0, 0.72),
		})
		local frame: any = nil
		if rarity ~= nil then
			frame = Game.RarityFrame.new({
				style = shell.styleName,
				parent = panel.Instance,
				rarity = rarity,
				radius = "md",
			})
		end
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 10
		hit.Parent = panel.Instance
		local binding = UI.bind(hit, "Snappy", {
			target = panel.Instance,
			onActivated = function()
				shell:fire("Selected", entry.id or index, discovered)
			end,
		})
		local destroy = panel.destroy
		panel.destroy = function(self: any)
			binding.destroy()
			name:destroy()
			if frame ~= nil then
				frame:destroy()
			end
			destroy(self)
		end
		panel.hit = hit
		return panel
	end

	local function build(announce: boolean)
		local entries: { any } = shell.props.entries
		local summary = ScreensLogic.collection(entries)
		summaryText:update({
			text = string.format("%d / %d discovered (%d%%)", summary.discovered, summary.total, summary.percent),
		})
		summaryBar:update({ value = summary.discovered, max = math.max(1, summary.total) })
		grid.set(entries, tile)
		shell:relayout()
		local focus: { GuiObject } = {}
		local fresh: { GuiObject } = {}
		for i, entry in ipairs(entries) do
			local id = tostring(entry.id or i)
			local card = grid.cards[id]
			if card ~= nil then
				table.insert(focus, card.hit)
				if entry.discovered == true and not known[id] and announce then
					table.insert(fresh, card.Instance)
				end
			end
			known[id] = entry.discovered == true
		end
		shell:focusables(focus)
		if #fresh > 0 and shell:isOpen() then
			UI.stagger(fresh, "CardFlip", { interval = 0.08 })
		end
	end

	shell:onLayout(function(_env: ScreensLogic.Env)
		local body = window.body()
		grid.layout(ScreenKit.innerWidth(window.content, body.content.w), body.content.h)
	end)
	build(false)
	shell.onOpened = function()
		grid.reveal("ScrollReveal")
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.entries ~= nil then
				build(true)
			end
		end,
	}
end
