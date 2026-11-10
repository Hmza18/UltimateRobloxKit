--!strict
-- Leaderboard screen: LeaderboardRows ordered by ScreensLogic.leaderboard (highest first, equal
-- values share a rank), optional tabs, and the local player's row pinned under the list when it
-- is not among the visible rows. On TabChanged the game sends that board's entries with
-- screen:update({ entries = ... }).
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local ROW_H = 52

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({
		title = props.title,
		headerPalette = "blue",
		tabs = props.tabs,
		tab = props.tab,
		onTab = function(id: string)
			shell.props.tab = id
			shell:fire("TabChanged", id)
		end,
	})
	local rows: { any } = {}
	local ids: { any } = {}
	local pinned: any = nil

	local function rowProps(row: ScreensLogic.Rank): { [string]: any }
		return {
			rank = row.rank,
			title = row.name,
			value = row.value,
			format = shell.props.format,
			avatar = row.entry.avatar,
			highlight = row.highlight,
		}
	end

	local function clear()
		for _, row in ipairs(rows) do
			row:destroy()
		end
		table.clear(rows)
		table.clear(ids)
	end
	shell.trove:Add(function()
		clear()
		if pinned ~= nil then
			pinned:destroy()
		end
	end)

	local function instances(): { GuiObject }
		local out: { GuiObject } = {}
		for _, row in ipairs(rows) do
			table.insert(out, row.Instance)
		end
		return out
	end

	local function build(animate: boolean)
		local board = ScreensLogic.leaderboard(shell.props.entries, shell.props.localId, shell.props.limit)
		-- The same players in the same order: roll the numbers instead of rebuilding.
		local same = #board.rows == #ids
		for i, row in ipairs(board.rows) do
			same = same and ids[i] == row.id
		end
		if same then
			for i, row in ipairs(board.rows) do
				rows[i]:update(rowProps(row))
			end
		else
			clear()
			for i, row in ipairs(board.rows) do
				local options = rowProps(row)
				options.style = shell.styleName
				options.parent = window.content
				options.layoutOrder = i
				options.name = tostring(row.id)
				options.size = UDim2.new(1, -10, 0, ROW_H)
				table.insert(rows, Game.LeaderboardRow.new(options))
				table.insert(ids, row.id)
			end
			if animate and shell:isOpen() then
				UI.stagger(instances(), "ScrollReveal", { interval = 0.03 })
			end
		end
		-- The local player's own row, pinned when it is below the visible ones.
		if pinned ~= nil then
			pinned:destroy()
			pinned = nil
		end
		local localRow = board.localRow
		if board.pinned and localRow ~= nil then
			local footer = window.setFooter(ROW_H + 4)
			local options = rowProps(localRow)
			options.style = shell.styleName
			options.parent = footer
			options.name = "You"
			options.size = UDim2.new(1, -10, 0, ROW_H)
			pinned = Game.LeaderboardRow.new(options)
		else
			window.footer.Visible = false
		end
	end

	build(false)
	shell.onOpened = function()
		UI.stagger(instances(), "SlideInUp", { interval = 0.03 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.tab ~= nil then
				window.setTab(partial.tab)
			end
			if partial.entries ~= nil or partial.localId ~= nil or partial.limit ~= nil then
				build(true)
			end
		end,
	}
end
