--!strict
-- Settings screen: rows built from a UI/Core/SettingsSchema schema with the Game Toggle, Slider
-- and Dropdown components, plus a Visuals section (effects quality, intensity, reduced motion,
-- reduced flashing) that is applied at once, the way Visuals.Configure applies it.
--
-- Game settings are only reported: Changed(key, value, values). Saving them, or sending them to
-- the server, is the game's job.
--
-- NOT run in Studio: see README.md. Dropdown menus opening inside the scrolling list in
-- particular need a look.

local Host = require("../Runtime/Host")
local ScreenKit = require("./ScreenKit")
local ScreensLogic = require("./ScreensLogic")
local SettingsSchema = require("../../UI/Core/SettingsSchema")

local Game = ScreenKit.Game
local UI = ScreenKit.UI

local ROW_H = 56

return function(shell: ScreenKit.Shell, props: { [string]: any })
	local problems = SettingsSchema.validate(props.schema or {})
	if #problems > 0 then
		error("Settings: " .. table.concat(problems, "; "), 0)
	end
	local window = shell:window({ title = props.title, headerPalette = "gray" })
	local ink = ScreenKit.ink(shell.style, "inset", "left")
	local objects: { any } = {}
	local controls: { [string]: any } = {}
	local rows: { GuiObject } = {}
	local schema: { any } = {}
	local values: { [string]: any } = {}

	local function clear()
		for _, object in ipairs(objects) do
			object:destroy()
		end
		table.clear(objects)
		table.clear(controls)
		table.clear(rows)
	end
	shell.trove:Add(clear)

	local function changed(entry: any, value: any)
		local nextValues, ok = SettingsSchema.applyChange(schema, values, entry.key, value)
		if not ok then
			return
		end
		values = nextValues
		local applied = values[entry.key]
		local config = ScreensLogic.visualsConfig(entry.key, applied)
		if config ~= nil then
			-- Visuals settings take effect at once. This is the call Visuals.Configure makes
			-- (requiring the facade here would be a require cycle).
			Host.configure({
				level = config.quality,
				adaptive = config.adaptive,
				reducedMotion = config.reducedMotion,
				reducedFlashing = config.reducedFlashing,
				intensity = config.intensity,
			})
		end
		shell:fire("Changed", entry.key, applied, table.clone(values))
	end

	local function control(entry: any, parent: Instance): any
		local common: { [string]: any } = {
			style = shell.styleName,
			parent = parent,
			name = entry.key,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -8, 0.5, 0),
			value = values[entry.key],
			onChanged = function(value: any)
				changed(entry, value)
			end,
		}
		if entry.kind == "toggle" then
			common.size = UDim2.fromOffset(76, 44)
			return Game.Toggle.new(common)
		elseif entry.kind == "slider" then
			common.size = UDim2.new(0.44, 0, 0, 44)
			common.min = entry.min
			common.max = entry.max
			common.step = entry.step
			return Game.Slider.new(common)
		elseif entry.kind == "dropdown" then
			common.size = UDim2.new(0.44, 0, 0, 44)
			common.options = entry.options
			return Game.Dropdown.new(common)
		end
		-- keybind: display only.
		return Game.GameText.new({
			style = shell.styleName,
			parent = parent,
			text = tostring(values[entry.key]),
			role = "price",
			color = ink.color,
			stroke = false,
			align = "right",
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -12, 0.5, 0),
			size = UDim2.new(0.3, 0, 1, 0),
		})
	end

	local function build()
		clear()
		schema = table.clone(shell.props.schema or {})
		if shell.props.visuals ~= false then
			for _, entry in ipairs(ScreensLogic.visualsSchema(Host.settings())) do
				table.insert(schema, entry)
			end
		end
		values = SettingsSchema.sanitize(schema, shell.props.values or {})
		-- The Visuals rows always show what the kit is really using.
		for _, entry in ipairs(ScreensLogic.visualsSchema(Host.settings())) do
			if shell.props.visuals ~= false then
				values[entry.key] = entry.default
			end
		end
		local order = 0
		for _, section in ipairs(SettingsSchema.sections(schema)) do
			order += 1
			table.insert(
				objects,
				Game.Section.new({
					style = shell.styleName,
					parent = window.content,
					layoutOrder = order,
					title = string.upper(section.name),
					color = ScreenKit.ink(shell.style, "window").color,
					size = UDim2.new(1, -10, 0, 40),
				})
			)
			for _, entry in ipairs(section.entries) do
				order += 1
				local row = Game.Panel.new({
					style = shell.styleName,
					parent = window.content,
					layoutOrder = order,
					name = "Row_" .. entry.key,
					surface = "inset",
					shadow = false,
					radius = "md",
					outline = "thin",
					size = UDim2.new(1, -10, 0, ROW_H),
				})
				table.insert(objects, row)
				table.insert(rows, row.Instance)
				local inner: Instance = row.Content or row.Instance
				table.insert(
					objects,
					Game.GameText.new({
						style = shell.styleName,
						parent = inner,
						text = entry.label or entry.key,
						role = "label",
						color = ink.color,
						stroke = false,
						align = "left",
						position = UDim2.fromOffset(12, 0),
						size = UDim2.new(0.5, -12, 1, 0),
					})
				)
				local made = control(entry, inner)
				controls[entry.key] = made
				table.insert(objects, made)
			end
		end
		local focus: { GuiObject } = {}
		for _, entry in ipairs(schema) do
			local made = controls[entry.key]
			if made ~= nil and entry.kind ~= "keybind" then
				table.insert(focus, made.Instance)
			end
		end
		shell:focusables(focus)
	end

	build()
	shell.onOpened = function()
		UI.stagger(rows, "ScrollReveal", { interval = 0.025 })
	end

	return {
		update = function(partial: { [string]: any })
			if partial.title ~= nil then
				window.setTitle(partial.title)
			end
			if partial.schema ~= nil or partial.visuals ~= nil then
				local issues = SettingsSchema.validate(shell.props.schema or {})
				if #issues > 0 then
					error("Settings: " .. table.concat(issues, "; "), 0)
				end
				build()
			elseif partial.values ~= nil then
				-- New values from the game (loaded data): move the controls without reporting a change.
				for key, value in pairs(partial.values) do
					local entry = SettingsSchema.find(schema, key)
					local made = controls[key]
					if entry ~= nil and made ~= nil then
						local ok, coerced = SettingsSchema.coerce(entry, value)
						if ok then
							values[key] = coerced
							made:update(
								if entry.kind == "keybind" then { text = tostring(coerced) } else { value = coerced }
							)
						end
					end
				end
			end
		end,
		methods = {
			values = function(): { [string]: any }
				return table.clone(values)
			end,
		},
	}
end
