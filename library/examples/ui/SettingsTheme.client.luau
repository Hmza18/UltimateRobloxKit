--!strict
-- Example 3: a settings window generated from a schema, with live theme, language, motion and
-- text size switching. Changes are validated by the schema and sent to the server to save
-- (the server should run SettingsSchema.sanitize on them before storing).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
local UrkUI = require(Kit:WaitForChild("UI"):WaitForChild("UrkUI"))

UrkUI.start({
	translations = {
		en = { Settings = "Settings", Display = "Display", Audio = "Audio", On = "On", Off = "Off" },
		fr = { Settings = "Parametres", Display = "Affichage", Audio = "Son", On = "Oui", Off = "Non" },
		es = { Settings = "Ajustes", Display = "Pantalla", Audio = "Sonido", On = "Si", Off = "No" },
	},
})

local schema = {
	{
		key = "Theme",
		kind = "dropdown",
		label = "Theme",
		default = "dark",
		options = { "dark", "light", "highContrast" },
		section = "Display",
	},
	{ key = "ReducedMotion", kind = "toggle", label = "Reduce motion", default = false, section = "Display" },
	{ key = "TextSize", kind = "slider", label = "Minimum text size", default = 12, min = 10, max = 20, step = 1 },
	{ key = "UIScale", kind = "slider", label = "Interface size", default = 1, min = 0.8, max = 1.4, step = 0.1 },
	{ key = "Language", kind = "dropdown", label = "Language", default = "en", options = { "en", "fr", "es" } },
	{ key = "Music", kind = "toggle", label = "Music", default = true, section = "Audio" },
	{
		key = "Volume",
		kind = "slider",
		label = "Volume",
		default = 0.8,
		min = 0,
		max = 1,
		step = 0.05,
		section = "Audio",
	},
	{ key = "Interact", kind = "keybind", label = "Interact", default = "E", section = "Controls" },
}

local saveRemote = ReplicatedStorage:FindFirstChild("SaveSettings")

local window = UrkUI.Components.Window.new({
	id = "Settings",
	title = "Settings",
	titleKey = "Settings",
	size = Vector2.new(540, 480),
})

UrkUI.Components.SettingsPanel.new({
	schema = schema,
	parent = window.Content,
	onChanged = function(key: string, value: any, values: { [string]: any })
		if key == "Theme" then
			UrkUI.setTheme(value)
		elseif key == "ReducedMotion" then
			UrkUI.setReducedMotion(value)
		elseif key == "TextSize" then
			UrkUI.setMinTextSize(value)
		elseif key == "UIScale" then
			UrkUI.setUIScale(value)
		elseif key == "Language" then
			UrkUI.setLocale(value)
		elseif key == "Volume" then
			UrkUI.Sounds.setVolume(value)
		end
		if saveRemote and saveRemote:IsA("RemoteEvent") then
			saveRemote:FireServer(values)
		end
	end,
})

-- An open button on the HUD; the same could be a Studio button tagged UrkButton with
-- Action = "TogglePanel:Settings".
local hud = UrkUI.Components.Hud.new({ name = "SettingsHud" })
UrkUI.Components.Button.new({
	text = "Settings",
	variant = "secondary",
	size = "sm",
	action = "TogglePanel:Settings",
	tooltip = "Open settings (B / Esc closes)",
	parent = hud:rail("topLeft"),
})
