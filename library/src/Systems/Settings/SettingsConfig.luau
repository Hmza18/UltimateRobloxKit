--!strict
-- Default settings schema and adapter options. Replace or extend `schema` for your game.
-- `hook` tells SettingsClient how to apply a value: "volume:<SoundGroup name in SoundService>" or
-- "attribute:<name>" (set on the LocalPlayer for your UI and effects code to read).

return {
	version = 1, -- bump when you add a migration
	remoteFolder = "UrkSettings",
	saveDelay = 5, -- seconds after the last change before saving
	requestCapacity = 10, -- updates per player in a burst
	requestRefillPerSecond = 4,
	schema = {
		MasterVolume = {
			type = "number",
			default = 1,
			min = 0,
			max = 1,
			step = 0.05,
			group = "Audio",
			hook = "volume:Master",
		},
		MusicVolume = {
			type = "number",
			default = 0.8,
			min = 0,
			max = 1,
			step = 0.05,
			group = "Audio",
			hook = "volume:Music",
		},
		EffectsVolume = {
			type = "number",
			default = 1,
			min = 0,
			max = 1,
			step = 0.05,
			group = "Audio",
			hook = "volume:Effects",
		},
		GraphicsQuality = {
			type = "enum",
			default = "Auto",
			options = { "Auto", "Low", "Medium", "High" },
			group = "Graphics",
			hook = "attribute:UrkGraphicsQuality", -- a hint for your effects; scripts cannot set the engine level
		},
		ReducedMotion = {
			type = "bool",
			default = false,
			group = "Accessibility",
			hook = "attribute:UrkReducedMotion",
		},
		ColorblindMode = {
			type = "enum",
			default = "Off",
			options = { "Off", "Protanopia", "Deuteranopia", "Tritanopia" },
			group = "Accessibility",
			hook = "attribute:UrkColorblindMode",
		},
		TextScale = {
			type = "number",
			default = 1,
			min = 0.8,
			max = 1.5,
			step = 0.1,
			group = "Accessibility",
			hook = "attribute:UrkTextScale",
		},
		InteractKey = { type = "keybind", default = "E", group = "Controls", hook = "attribute:UrkKeyInteract" },
	},
}
