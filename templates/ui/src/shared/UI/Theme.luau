--!strict
-- Design tokens for every UI component. Change values here rather than in individual screens.
-- Every text/background pair below meets WCAG AA (4.5:1). Components re-check contrast at runtime.

local Theme = {
	Colors = {
		Background = Color3.fromRGB(16, 18, 26),
		Surface = Color3.fromRGB(30, 34, 48),
		SurfaceRaised = Color3.fromRGB(44, 50, 70),
		Primary = Color3.fromRGB(255, 196, 0), -- pairs with TextDark
		Secondary = Color3.fromRGB(40, 90, 200), -- pairs with Text
		Danger = Color3.fromRGB(200, 40, 40), -- pairs with Text
		Success = Color3.fromRGB(40, 150, 80),
		Text = Color3.fromRGB(245, 247, 250),
		TextMuted = Color3.fromRGB(170, 178, 196),
		TextDark = Color3.fromRGB(20, 20, 24),
		Stroke = Color3.fromRGB(0, 0, 0),
	},
	Fonts = { Heading = Enum.Font.GothamBlack, Body = Enum.Font.GothamMedium, Button = Enum.Font.GothamBold },
	-- Sizes in pixels at the Responsive reference resolution (1280 x 720).
	TextSize = { Caption = 16, Body = 18, Button = 20, Title = 28, Display = 40 },
	MinTextSize = 16, -- smallest text size components allow; still 12.8 px at the minimum UI scale
	MinTouchTarget = 44, -- smallest button side in pixels, for touch screens
	MinContrast = 4.5, -- WCAG AA for normal text
	Radius = UDim.new(0, 12),
	Padding = 12,
	StrokeThickness = 2,
	Motion = { Fast = 0.1, Normal = 0.2, Slow = 0.35 }, -- tween durations in seconds
}

return Theme
