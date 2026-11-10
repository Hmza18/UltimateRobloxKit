--!strict
-- QuestLog screen: QuestCards in tabs (daily / weekly by default). Claimable quests come first,
-- then the ones closest to done, then claimed ones. A card's claim button raises Claimed(id);
-- after the server confirms, update the quest with state = "claimed".
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local DEFAULT_TABS = { { id = "daily", text = "DAILY" }, { id = "weekly", text = "WEEKLY" } }
local CARD_H = 104

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local tabs: { any } = props.tabs or DEFAULT_TABS
	local current: string? = props.tab or (if tabs[1] then tabs[1].id else nil)
	local cards: { any } = {}
	local build: (animate: boolean) -> ()
	local window = shell:window({
		title = props.title,
		headerPalette = "green",
		tabs = tabs,
		tab = current,
		onTab = function(id: string)
			current = id
			shell.props.tab = id
			build(true)
			shell:fire("TabChanged", id)
		end,
	})
	local empty = shell:text(window.content, props.emptyText, "label", ScreenKit.ink(shell.style, "window", "center"))

	local function clear()
		for _, card in ipairs(cards) do
			card:destroy()
		end
		table.clear(cards)
	end
	shell.trove:Add(clear)

	build = function(animate: boolean)
		clear()
		local rows = ScreensLogic.quests(shell.props.quests, if #tabs > 0 then current else nil)
		local instances: { GuiObject } = {}
		for i, row in ipairs(rows) do
			local quest = row.quest
			local card = Game.QuestCard.new({
				style = shell.styleName,
				parent = window.content,
				layoutOrder = i,
				name = tostring(quest.id),
				title = quest.title,
				description = quest.description,
				value = quest.value,
				max = quest.max,
				rewards = quest.rewards,
				state = row.state,
				claimText = quest.claimText,
				palette = quest.palette,
				size = UDim2.new(1, -10, 0, CARD_H),
			})
			card.Claimed:Connect(function()
				shell:fire("Claimed", quest.id)
			end)
			table.insert(cards, card)
			table.insert(instances, card.Instance)
		end
		empty:update({ visible = #rows == 0, layoutOrder = 0 })
		shell:focusables(instances)
		if animate and shell:isOpen() then
			UI.stagger(instances, "ScrollReveal", { interval = 0.04 })
		end
	end

	build(false)
	shell.onOpened = function()
		local instances: { GuiObject } = {}
		for _, card in ipairs(cards) do
			table.insert(instances, card.Instance)
		end
		UI.stagger(instances, "SlideInUp", { interval = 0.05 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.tab ~= nil then
				current = partial.tab
				window.setTab(partial.tab)
			end
			if partial.quests ~= nil or partial.tab ~= nil then
				build(false)
			end
		end,
	}
end
