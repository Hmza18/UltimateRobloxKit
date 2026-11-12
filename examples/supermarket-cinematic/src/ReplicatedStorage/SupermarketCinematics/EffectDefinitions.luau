-- Effect presets: tuned numbers only, no asset IDs. Particles use the engine's default particle
-- texture (ParticleEmitter's built-in default), so nothing depends on uploaded images.
return {
	Sparkle = {
		colors = { Color3.fromRGB(255, 244, 160), Color3.fromRGB(255, 255, 255) },
		lifetime = NumberRange.new(0.35, 0.6),
		speed = NumberRange.new(3, 6),
		size = { 0.55, 0.0 },
		count = 10,
	},
	Confetti = {
		colors = { Color3.fromRGB(255, 92, 72), Color3.fromRGB(255, 214, 64), Color3.fromRGB(70, 160, 255), Color3.fromRGB(80, 210, 120), Color3.fromRGB(190, 110, 255) },
		lifetime = NumberRange.new(1.2, 1.8),
		speed = NumberRange.new(12, 18),
		size = { 0.45, 0.3 },
		count = 22, -- per colour
		gravity = Vector3.new(0, -18, 0),
	},
	ScanPulse = {
		color = Color3.fromRGB(70, 255, 130),
		lightBrightness = 4,
		duration = 0.35,
	},
	Money = {
		color = Color3.fromRGB(120, 255, 120),
		stroke = Color3.fromRGB(20, 90, 30),
		rise = 2.2, -- studs
		duration = 1.25,
	},
	ProductDrop = {
		height = 0.9, -- studs above the slot it drops from
		duration = 0.32,
		highlight = Color3.fromRGB(255, 240, 150),
	},
	-- Lighting while the cinematic plays (restored afterwards). Morning sun, soft and warm.
	Grade = {
		ClockTime = 9.3,
		GeographicLatitude = 30,
		Brightness = 2.4,
		Ambient = Color3.fromRGB(120, 116, 128),
		OutdoorAmbient = Color3.fromRGB(150, 145, 140),
		ExposureCompensation = 0.1,
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.6,
		bloom = { Intensity = 0.55, Size = 30, Threshold = 1.35 },
		color = { Brightness = 0.03, Contrast = 0.08, Saturation = 0.12, TintColor = Color3.fromRGB(255, 249, 240) },
		sunRays = { Intensity = 0.05, Spread = 0.6 },
		atmosphere = { Density = 0.26, Offset = 0.15, Color = Color3.fromRGB(230, 220, 205), Decay = Color3.fromRGB(150, 160, 190), Glare = 0.2, Haze = 1.1 },
	},
	-- Hero-shot lift for the final reveal (relative to Grade).
	Reveal = { bloom = 0.85, saturation = 0.22, exposure = 0.22, duration = 1.6 },
}
