--!strict
-- CombatProgression screen: level and XP, stat chips, and the skill list in unlock order. A
-- skill whose level is reached shows an unlock button that raises UnlockRequested(id); the
-- server decides. When an update marks a skill unlocked, its row pulses.
--
-- NOT run in Studio: see README.md.

local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local ROW_H = 76

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local window = shell:window({ title = props.title, headerPalette = "red" })
	local ink = ScreenKit.ink(shell.style, "inset", "left")
	local xp = shell:own(Game.XPBar.new({
		style = shell.styleName,
		parent = window.content,
		layoutOrder = 1,
		level = props.level,
		value = (props.xp or {}).value or 0,
		max = (props.xp or {}).max or 1,
		palette = "red",
		size = UDim2.fromOffset(320, 44),
	}))
	local statsHolder, statsLayout = ScreenKit.grid(window.content, "Stats", 2)
	local chips: { any } = {}
	local objects: { any } = {}
	local rowsById: { [string]: any } = {}
	local unlocked: { [string]: boolean } = {}

	local function clearChips()
		for _, chip in ipairs(chips) do
			chip:destroy()
		end
		table.clear(chips)
	end
	local function clearSkills()
		for _, object in ipairs(objects) do
			object:destroy()
		end
		table.clear(objects)
		table.clear(rowsById)
	end
	shell.trove:Add(function()
		clearChips()
		clearSkills()
	end)

	local function buildStats()
		clearChips()
		for i, stat in ipairs(shell.props.stats or {}) do
			table.insert(
				chips,
				Game.StatChip.new({
					style = shell.styleName,
					parent = statsHolder,
					layoutOrder = i,
					name = tostring(stat.id or i),
					icon = stat.icon,
					image = stat.image,
					value = stat.value,
					format = stat.format,
					prefix = stat.prefix,
					suffix = stat.suffix,
					palette = stat.palette,
				})
			)
		end
	end

	local function buildSkills(announce: boolean)
		clearSkills()
		local focus: { GuiObject } = {}
		local fresh: { GuiObject } = {}
		for i, row in ipairs(ScreensLogic.skills(shell.props.skills, shell.props.level)) do
			local skill = row.skill
			local id = tostring(skill.id or i)
			local panel = Game.Panel.new({
				style = shell.styleName,
				parent = window.content,
				layoutOrder = i + 2,
				name = "Skill_" .. id,
				surface = if row.state == "locked" then "dark" else "inset",
				shadow = false,
				radius = "md",
				outline = "regular",
				size = UDim2.new(1, -10, 0, ROW_H),
			})
			table.insert(objects, panel)
			rowsById[id] = panel
			local inner: Instance = panel.Content or panel.Instance
			local rowInk = if row.state == "locked" then ScreenKit.ink(shell.style, "dark", "left") else ink
			local image = Instance.new("ImageLabel")
			image.Name = "Icon"
			image.BackgroundTransparency = 1
			image.AnchorPoint = Vector2.new(0, 0.5)
			image.Position = UDim2.new(0, 8, 0.5, 0)
			image.Size = UDim2.fromOffset(52, 52)
			image.ScaleType = Enum.ScaleType.Fit
			image.ImageTransparency = if row.state == "locked" then 0.5 else 0
			image.Parent = inner
			ScreenKit.icon(image, skill.icon or (if skill.image == nil then "energy-color" else nil), skill.image)
			table.insert(
				objects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = tostring(skill.title or id),
					role = "label",
					color = rowInk.color,
					stroke = false,
					align = "left",
					position = UDim2.fromOffset(70, 8),
					size = UDim2.new(1, -70 - 150, 0, 26),
				})
			)
			table.insert(
				objects,
				Game.GameText.new({
					style = shell.styleName,
					parent = inner,
					text = tostring(skill.description or ""),
					role = "caption",
					color = rowInk.color,
					stroke = false,
					align = "left",
					position = UDim2.fromOffset(70, 36),
					size = UDim2.new(1, -70 - 150, 0, 22),
				})
			)
			if row.state == "available" then
				local button = Game.CartoonButton.new({
					style = shell.styleName,
					parent = inner,
					name = "Unlock_" .. id,
					kind = "buy",
					text = "UNLOCK",
					anchor = Vector2.new(1, 0.5),
					position = UDim2.new(1, -8, 0.5, 0),
					size = UDim2.fromOffset(134, 48),
				})
				table.insert(objects, button)
				table.insert(focus, button.Instance)
				button.Activated:Connect(function()
					shell:fire("UnlockRequested", skill.id or i)
				end)
			else
				table.insert(
					objects,
					Game.GameText.new({
						style = shell.styleName,
						parent = inner,
						text = if row.state == "unlocked" then "UNLOCKED" else "LEVEL " .. tostring(skill.level or 1),
						role = "caption",
						color = rowInk.color,
						stroke = false,
						align = "right",
						anchor = Vector2.new(1, 0.5),
						position = UDim2.new(1, -12, 0.5, 0),
						size = UDim2.fromOffset(134, 24),
					})
				)
			end
			if announce and row.state == "unlocked" and unlocked[id] == false then
				table.insert(fresh, panel.Instance)
			end
			unlocked[id] = row.state == "unlocked"
		end
		shell:focusables(focus)
		for _, instance in ipairs(fresh) do
			UI.animate(instance, "UpgradePulse")
		end
	end

	shell:onLayout(function(_env: ScreensLogic.Env)
		local body = window.body()
		local width = ScreenKit.innerWidth(window.content, body.content.w)
		xp:update({ size = UDim2.fromOffset(math.min(width, 420), 44) })
		ScreenKit.applyGrid(
			statsLayout,
			ScreensLogic.grid(width, { minCell = 120, maxCell = 150, aspect = 3.4, gap = 6, count = #chips })
		)
	end)

	buildStats()
	buildSkills(false)
	shell.onOpened = function()
		local instances: { GuiObject } = {}
		for _, chip in ipairs(chips) do
			table.insert(instances, chip.Instance)
		end
		UI.stagger(instances, "BadgePop", { interval = 0.04 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.level ~= nil or partial.xp ~= nil then
				local state: any = shell.props.xp or {}
				xp:update({ level = shell.props.level, value = state.value or 0, max = state.max or 1 })
			end
			if partial.stats ~= nil then
				buildStats()
				shell:relayout()
			end
			if partial.skills ~= nil or partial.level ~= nil then
				buildSkills(true)
			end
		end,
		methods = {
			-- Plays an XP gain on the bar (with level-ups) for an amount the server granted.
			gain = function(amount: number)
				xp:gain(amount)
			end,
		},
	}
end
