--!strict
-- Runtime theme: converts resolved token colours to Color3, skins instances by role, and
-- re-skins everything registered when the theme or the minimum text size changes.

local Signal = require("../../Util/Signal")
local Theme = require("../Core/Theme")
local Tokens = require("../Core/Tokens")

export type Skin = {
	Role: string?,
	TextRole: string?,
	StrokeRole: string?,
	ImageRole: string?,
	PlaceholderRole: string?,
	TransparencyRole: string?,
	TextSize: string?,
	Radius: string?,
}

export type Config = {
	theme: string?,
	themes: { [string]: Tokens.ThemeDef }?,
	tokens: Tokens.TokenSet?,
	minTextSize: number?,
	order: { string }?,
}

local ThemeService = {}

-- Text roles map to font weights.
local WEIGHTS: { [string]: Enum.FontWeight } = {
	caption = Enum.FontWeight.Regular,
	body = Enum.FontWeight.Regular,
	label = Enum.FontWeight.Medium,
	title = Enum.FontWeight.Bold,
	heading = Enum.FontWeight.Bold,
	display = Enum.FontWeight.ExtraBold,
}

local function toColor3(rgb: Theme.RGB): Color3
	return Color3.new(rgb.r, rgb.g, rgb.b)
end

function ThemeService.new(config: Config?)
	local cfg: Config = config or {}
	local themes = Theme.merge(Tokens.themes, cfg.themes)
	local tokens: Tokens.TokenSet = cfg.tokens or Tokens.defaults
	local order = cfg.order or { "dark", "light", "highContrast" }
	local minTextSize = math.max(cfg.minTextSize or tokens.text.minimum, 1)
	local registered: { [any]: (any) -> () } = {}
	local fontCache: { [string]: Font } = {}

	local service = {}
	service.Changed = Signal.new()
	service.tokens = tokens
	service.name = cfg.theme or "dark"
	service.resolved = Theme.resolve(themes, service.name)

	local function report(name: string, resolved: Theme.Resolved)
		local level = Tokens.levels[name] or "AA"
		for _, problem in Theme.validate(resolved, level) do
			warn(string.format("[UrkUI] theme %s: %s %s", name, problem.kind, problem.detail))
		end
	end
	report(service.name, service.resolved)

	function service.color(_self: any, spec: string, fallbackRole: string?): Color3
		local rgb = Theme.color(service.resolved, spec, fallbackRole)
		if rgb == nil then
			return Color3.new(1, 0, 1)
		end
		return toColor3(rgb)
	end

	function service.transparency(_self: any, role: string): number
		return Theme.transparency(service.resolved, role)
	end

	function service.textSize(_self: any, token: string | number): number
		local size = if type(token) == "number" then token else tokens.text[token] or tokens.text.body
		return math.max(size, minTextSize)
	end

	function service.font(_self: any, role: string?): Font
		local weight = WEIGHTS[role or "body"] or Enum.FontWeight.Regular
		local key = tostring(weight)
		local cached = fontCache[key]
		if cached then
			return cached
		end
		local ok, font = pcall(Font.fromName, tokens.fonts.family, weight)
		if not ok then
			ok, font = pcall(Font.fromName, tokens.fonts.fallback, weight)
		end
		local result: Font = if ok then font else Font.fromEnum(Enum.Font.Gotham)
		fontCache[key] = result
		return result
	end

	function service.radius(_self: any, token: string?): UDim
		local pixels = tokens.radius[token or "md"] or tokens.radius.md
		return UDim.new(0, pixels)
	end

	function service.spacing(_self: any, token: string?): number
		return tokens.spacing[token or "md"] or tokens.spacing.md
	end

	function service.layer(_self: any, name: string): number
		return tokens.layers[name] or 0
	end

	function service.getMinTextSize(_self: any): number
		return minTextSize
	end

	-- Applies a skin to one instance. Unknown properties are skipped, so the same skin works on
	-- frames, labels, buttons and images.
	function service.apply(self: any, instance: Instance, skin: Skin)
		local target: any = instance
		if skin.Role and instance:IsA("GuiObject") then
			target.BackgroundColor3 = self:color(skin.Role)
		end
		if skin.TransparencyRole and instance:IsA("GuiObject") then
			target.BackgroundTransparency = self:transparency(skin.TransparencyRole)
		end
		local isText = instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
		if isText then
			if skin.TextRole then
				target.TextColor3 = self:color(skin.TextRole)
			end
			if skin.TextSize then
				target.TextSize = self:textSize(skin.TextSize)
				target.FontFace = self:font(skin.TextSize)
			elseif target.TextSize < minTextSize and not target.TextScaled then
				target.TextSize = minTextSize
			end
		end
		if skin.PlaceholderRole and instance:IsA("TextBox") then
			instance.PlaceholderColor3 = self:color(skin.PlaceholderRole)
		end
		if skin.ImageRole and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
			target.ImageColor3 = self:color(skin.ImageRole)
		end
		if skin.StrokeRole then
			local stroke = instance:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = self:color(skin.StrokeRole)
			end
		end
		if skin.Radius then
			local corner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			corner.CornerRadius = self:radius(skin.Radius)
			corner.Parent = instance
		end
	end

	-- Calls `apply(service)` now and after every theme change. Returns an unregister function.
	function service.watch(_self: any, apply: (any) -> ()): () -> ()
		local key = {}
		registered[key] = apply
		apply(service)
		local function unregister()
			registered[key] = nil
		end
		return unregister
	end

	local function reskin()
		for _, apply in table.clone(registered) do
			local ok, err = pcall(apply, service)
			if not ok then
				warn("[UrkUI] re-skin failed: " .. tostring(err))
			end
		end
		service.Changed:Fire(service.name)
	end

	function service.setTheme(_self: any, name: string)
		local resolved = Theme.resolve(themes, name)
		report(name, resolved)
		service.name = name
		service.resolved = resolved
		reskin()
	end

	function service.cycle(self: any)
		self:setTheme(Theme.nextName(order, service.name))
	end

	function service.setMinTextSize(_self: any, size: number)
		minTextSize = math.max(1, size)
		reskin()
	end

	function service.names(_self: any): { string }
		local names: { string } = {}
		for name in themes do
			table.insert(names, name)
		end
		table.sort(names)
		return names
	end

	-- Button variant colours: background role, text role and stroke role.
	function service.variant(_self: any, variant: string?): Skin
		if variant == "secondary" then
			return { Role = "secondary", TextRole = "onSecondary", StrokeRole = "border" }
		elseif variant == "ghost" then
			return { Role = "surface", TextRole = "text", StrokeRole = "border", TransparencyRole = "ghost" }
		elseif variant == "danger" then
			return { Role = "danger", TextRole = "onDanger", StrokeRole = "danger" }
		end
		return { Role = "primary", TextRole = "onPrimary", StrokeRole = "primary" }
	end

	return service
end

return ThemeService
