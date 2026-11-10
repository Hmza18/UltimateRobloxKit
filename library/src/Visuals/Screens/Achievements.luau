--!strict
-- Achievements screen: a progress summary (unlocked / total with a bar) above a list of
-- AchievementCards. Display only, plus Selected(id) when a card is pressed.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local CARD_H = 96

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, headerPalette = "gold" })
	local summaryText = shell:text(window.content, "", "label", ScreenKit.ink(shell.style, "window", "center"))
	summaryText:update({ layoutOrder = 1 })
	local summaryBar = shell:own(Game.ProgressBar.new({
		style = shell.styleName,
		parent = window.content,
		layoutOrder = 2,
		name = "Summary",
		palette = "gold",
		value = 0,
		max = 1,
		size = UDim2.new(1, -10, 0, 24),
	}))
	local cards: { [string]: any } = {}
	local order: { string } = {}
	local hits: { Instance } = {}

	local function clear()
		for _, card in pairs(cards) do
			card:destroy()
		end
		for _, hit in ipairs(hits) do
			hit:Destroy()
		end
		table.clear(cards)
		table.clear(order)
		table.clear(hits)
	end
	shell.trove:Add(clear)

	local function instances(): { GuiObject }
		local out: { GuiObject } = {}
		for _, id in ipairs(order) do
			table.insert(out, cards[id].Instance)
		end
		return out
	end

	local function summarise()
		local summary = ScreensLogic.achievements(shell.props.achievements)
		summaryText:update({
			text = string.format("%d / %d unlocked (%d%%)", summary.unlocked, summary.total, summary.percent),
		})
		summaryBar:update({ value = summary.unlocked, max = math.max(1, summary.total) })
	end

	local function cardProps(entry: any): { [string]: any }
		return {
			title = entry.title,
			description = entry.description,
			icon = entry.icon,
			image = entry.image,
			tier = entry.tier,
			maxTier = entry.maxTier,
			value = entry.value,
			max = entry.max,
			unlocked = entry.unlocked,
			palette = entry.palette,
		}
	end

	local function build()
		clear()
		for i, entry in ipairs(shell.props.achievements) do
			local id = tostring(entry.id or i)
			local options = cardProps(entry)
			options.style = shell.styleName
			options.parent = window.content
			options.layoutOrder = i + 2
			options.name = id
			options.size = UDim2.new(1, -10, 0, CARD_H)
			local card = Game.AchievementCard.new(options)
			cards[id] = card
			table.insert(order, id)
			-- AchievementCard is not a button: a transparent hit area raises Selected.
			local hit = Instance.new("TextButton")
			hit.Name = "Hit"
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = 10
			hit.Parent = card.Instance
			table.insert(hits, hit)
			hit.Activated:Connect(function()
				UI.animate(card.Instance, "BouncyPress")
				shell:fire("Selected", entry.id or i)
			end)
		end
		summarise()
		shell:focusables(hits :: any)
	end

	build()
	shell.onOpened = function()
		UI.stagger(instances(), "SlideInUp", { interval = 0.04 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.achievements == nil then
				return
			end
			-- The same achievements in the same order: update the cards in place, so a new tier
			-- plays the card's own unlock flash instead of rebuilding it.
			local list: { any } = shell.props.achievements
			local same = #list == #order
			for i, entry in ipairs(list) do
				same = same and order[i] == tostring(entry.id or i)
			end
			if same then
				for i, entry in ipairs(list) do
					cards[order[i]]:update(cardProps(entry))
				end
				summarise()
			else
				build()
			end
		end,
	}
end
