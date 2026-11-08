--!strict
-- UrkUI: a tag- and attribute-driven UI framework for Roblox.
--
--   local UrkUI = require(ReplicatedStorage.UltimateRobloxKit.UI.UrkUI)
--   UrkUI.registerActions({ BuySword = function(action) BuyRemote:FireServer("Sword") end })
--   local ui = UrkUI.start({ theme = "dark" })
--   ui.store:set("Stats.Cash", 250)
--
-- Run it once, from a LocalScript. Tagged instances under PlayerGui are discovered with
-- CollectionService and bound automatically, including UI added later (respawn copies, clones).
-- See README.md for every tag and attribute, the component API and what needs a Studio playtest.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Actions = require("./Runtime/Actions")
local Binder = require("./Runtime/Binder")
local Breakpoints = require("./Core/Breakpoints")
local ContextMenuService = require("./Runtime/ContextMenuService")
local Context = require("./Runtime/Context")
local Contrast = require("./Core/Contrast")
local Decor = require("./Core/Decor")
local DragService = require("./Runtime/DragService")
local Easing = require("./Core/Easing")
local Focus = require("./Runtime/Focus")
local Format = require("./Core/Format")
local Layout = require("./Core/Layout")
local LocalizeService = require("./Runtime/LocalizeService")
local Localizer = require("./Core/Localizer")
local Motion = require("./Runtime/Motion")
local PanelRouter = require("./Core/PanelRouter")
local Panels = require("./Runtime/Panels")
local Path = require("./Core/Path")
local Registry = require("./Behaviours/Registry")
local Responsive = require("./Runtime/Responsive")
local SettingsSchema = require("./Core/SettingsSchema")
local Signal = require("../Util/Signal")
local SlotLogic = require("./Core/SlotLogic")
local Sounds = require("./Runtime/Sounds")
local SpatialNav = require("./Core/SpatialNav")
local Store = require("./Core/Store")
local StoreAdapter = require("./Runtime/StoreAdapter")
local TagSpec = require("./Core/TagSpec")
local Theme = require("./Core/Theme")
local ThemeService = require("./Runtime/ThemeService")
local ToastQueue = require("./Core/ToastQueue")
local ToastService = require("./Runtime/ToastService")
local Tokens = require("./Core/Tokens")
local TooltipService = require("./Runtime/TooltipService")

export type Config = {
	player: Player?,
	roots: { Instance }?, -- where tagged UI is discovered; default { PlayerGui }
	store: Store.Store?, -- bring your own store, or
	state: { [string]: any }?, -- initial state for a new store
	theme: string?, -- "dark" (default), "light", "highContrast" or a custom theme
	themes: { [string]: Tokens.ThemeDef }?,
	themeOrder: { string }?, -- order used by CycleTheme
	tokens: Tokens.TokenSet?,
	locale: string?, -- default: the player's LocaleId
	fallbackLocale: string?,
	translations: { [string]: Localizer.Entries }?,
	pluralRules: { [string]: Localizer.PluralRule }?,
	useRobloxTranslator: boolean?,
	actions: { [string]: Actions.Handler }?,
	formatters: { [string]: Format.Formatter }?,
	reducedMotion: (boolean | string)?, -- true, false or "auto" (follow the Roblox setting, default)
	minTextSize: number?,
	uiScale: number?, -- accessibility multiplier for responsive UIScale, default 1
	maxToasts: number?,
	sounds: { hover: string?, click: string? }?,
	breakpoints: Responsive.Config?,
	debug: boolean?,
}

local UrkUI = {}

-- Pure modules, usable anywhere (also on the server and in Lune tests).
UrkUI.Core = {
	Breakpoints = Breakpoints,
	Contrast = Contrast,
	Decor = Decor,
	Easing = Easing,
	Format = Format,
	Layout = Layout,
	Localizer = Localizer,
	PanelRouter = PanelRouter,
	Path = Path,
	SettingsSchema = SettingsSchema,
	SlotLogic = SlotLogic,
	SpatialNav = SpatialNav,
	Store = Store,
	TagSpec = TagSpec,
	Theme = Theme,
	ToastQueue = ToastQueue,
	Tokens = Tokens,
}

UrkUI.Tags = TagSpec.tags
UrkUI.store = nil :: Store.Store? -- the running store, set by start
UrkUI.Motion = Motion
UrkUI.Sounds = Sounds

UrkUI.Store = {
	new = Store.new,
	attributePath = Store.attributePath,
	fromAttributes = StoreAdapter.fromAttributes,
	fromFolder = StoreAdapter.fromFolder,
	deferred = StoreAdapter.deferred,
}

-- Components load lazily so requiring UrkUI stays cheap and they can require the running context.
local componentNames = {
	"Button",
	"Currency",
	"Dialog",
	"Hud",
	"InventoryGrid",
	"ProgressBar",
	"SettingsPanel",
	"ShopCard",
	"Tabs",
	"Window",
}
local componentModules: { [string]: () -> any } = {
	Button = function()
		return require("./Components/Button")
	end,
	Currency = function()
		return require("./Components/Currency")
	end,
	Dialog = function()
		return require("./Components/Dialog")
	end,
	Hud = function()
		return require("./Components/Hud")
	end,
	InventoryGrid = function()
		return require("./Components/InventoryGrid")
	end,
	ProgressBar = function()
		return require("./Components/ProgressBar")
	end,
	SettingsPanel = function()
		return require("./Components/SettingsPanel")
	end,
	ShopCard = function()
		return require("./Components/ShopCard")
	end,
	Tabs = function()
		return require("./Components/Tabs")
	end,
	Window = function()
		return require("./Components/Window")
	end,
}

UrkUI.ComponentNames = componentNames
UrkUI.Components = setmetatable({}, {
	__index = function(cache: any, name: string): any
		local loader = componentModules[name]
		if loader == nil then
			error("UrkUI has no component " .. tostring(name), 2)
		end
		local module = loader()
		rawset(cache, name, module)
		return module
	end,
})

-- Game-style layer (docs/architecture/ui-generation.md). Style and MotionPresets are pure data.
-- Game components and the screen builder load on first use, so plain UrkUI users pay nothing.
UrkUI.Style = require("./Style/Style")
UrkUI.MotionPresets = require("./Core/MotionPresets")
UrkUI.Game = setmetatable({}, {
	__index = function(cache: any, name: string): any
		local module = (require("./Game/Game") :: any)[name]
		rawset(cache, name, module)
		return module
	end,
})

-- Builds a screen from a spec (a table or a ModuleScript of a Spec/Screens/*.json file).
function UrkUI.buildScreen(spec: any, options: { [string]: any }?): any
	local Builder = require("./Spec/Builder") :: any
	local opts = options or {}
	if opts.store == nil then
		opts.store = UrkUI.store
	end
	return Builder.build(spec, opts)
end

-- Signals that exist before start, so game code can connect early.
UrkUI.Intent = Signal.new() -- (name, args, source) from the Fire action and components
UrkUI.Dropped = Signal.new() -- (payload, target, targetId) from UrkDraggable drops
UrkUI.ThemeChanged = Signal.new() -- (themeName)
UrkUI.BreakpointChanged = Signal.new() -- (breakpoint, scale)

local pendingActions: { { [string]: Actions.Handler } } = {}
local context: any = nil

-- Registers action handlers by name. Works before or after start. Returns an unregister function
-- (only after start; before start the handlers are queued).
function UrkUI.registerActions(map: { [string]: Actions.Handler }): () -> ()
	if context then
		return context.actions:register(map)
	end
	table.insert(pendingActions, map)
	local function unqueue()
		local index = table.find(pendingActions, map)
		if index then
			table.remove(pendingActions, index)
		end
	end
	return unqueue
end

-- Registers a formatter usable as Format="name" on UrkBind and "{value:name}" in translations.
function UrkUI.registerFormatter(name: string, formatter: Format.Formatter): () -> ()
	return Format.register(name, formatter)
end

local function requireContext(): any
	assert(context ~= nil, "UrkUI is not running: call UrkUI.start() on the client first")
	return context
end

local function readReducedMotion(): boolean
	local ok, value = pcall(function(): any
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

-- Starts UrkUI on the client and returns the UrkUI module (also reachable as UrkUI afterwards).
function UrkUI.start(config: Config?)
	assert(RunService:IsClient(), "UrkUI.start must run on the client (a LocalScript)")
	if context then
		warn("[UrkUI] start() called twice; returning the running instance")
		return UrkUI
	end
	local cfg: Config = config or {}
	local player = cfg.player or Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local ctx: any = {}
	context = ctx
	ctx.config = cfg
	ctx.api = UrkUI
	ctx.player = player
	ctx.playerGui = playerGui
	ctx.Intent = UrkUI.Intent
	ctx.TabChanged = Signal.new()
	ctx.ReducedMotionChanged = Signal.new()
	ctx.connections = {}
	Context.set(ctx)

	if cfg.formatters then
		for name, formatter in cfg.formatters do
			Format.register(name, formatter)
		end
	end

	ctx.store = cfg.store or Store.new(cfg.state, { scheduler = StoreAdapter.deferred })
	UrkUI.store = ctx.store
	ctx.theme = ThemeService.new({
		theme = cfg.theme,
		themes = cfg.themes,
		tokens = cfg.tokens,
		minTextSize = cfg.minTextSize,
		order = cfg.themeOrder,
	})
	local themeConnection = ctx.theme.Changed:Connect(function(name: string)
		UrkUI.ThemeChanged:Fire(name)
	end)
	table.insert(ctx.connections, themeConnection)
	Motion.setDurations(ctx.theme.tokens.motion)
	ctx.localize = LocalizeService.new({
		locale = cfg.locale,
		fallback = cfg.fallbackLocale,
		tables = cfg.translations,
		pluralRules = cfg.pluralRules,
		useRobloxTranslator = cfg.useRobloxTranslator,
		player = player,
		debug = cfg.debug,
	})
	ctx.responsive = Responsive.new(cfg.breakpoints)
	if cfg.uiScale then
		ctx.responsive:setUserScale(cfg.uiScale)
	end
	ctx.actions = Actions.new(ctx)
	ctx.focus = Focus.new(ctx)
	ctx.panels = Panels.new(ctx)
	ctx.tooltip = TooltipService.new(ctx)
	ctx.toasts = ToastService.new(ctx)
	ctx.menu = ContextMenuService.new(ctx)
	ctx.drag = DragService.new(ctx)
	local dropConnection = ctx.drag.Dropped:Connect(function(...: any)
		UrkUI.Dropped:Fire(...)
	end)
	table.insert(ctx.connections, dropConnection)
	local breakpointConnection = ctx.responsive.Changed:Connect(function(breakpoint: string, scale: number)
		UrkUI.BreakpointChanged:Fire(breakpoint, scale)
	end)
	table.insert(ctx.connections, breakpointConnection)

	-- Reduced motion: explicit true/false, or follow the Roblox accessibility setting.
	local mode = if cfg.reducedMotion == nil then "auto" else cfg.reducedMotion
	if mode == "auto" then
		Motion.setReducedMotion(readReducedMotion())
		local ok, signal = pcall(function(): any
			return GuiService:GetPropertyChangedSignal("ReducedMotionEnabled" :: any)
		end)
		if ok and signal then
			local motionConnection = signal:Connect(function()
				UrkUI.setReducedMotion(readReducedMotion())
			end)
			table.insert(ctx.connections, motionConnection)
		end
	else
		Motion.setReducedMotion(mode == true)
	end

	for _, map in pendingActions do
		ctx.actions:register(map)
	end
	table.clear(pendingActions)
	if cfg.actions then
		ctx.actions:register(cfg.actions)
	end

	local roots = cfg.roots or { playerGui }
	ctx.binder = Binder.new(roots, cfg.debug)
	for _, behaviour in Registry do
		for _, tag in behaviour.tags do
			ctx.binder:bind(tag, function(instance: Instance, trove: any)
				local values = ctx.binder:read(tag, instance)
				behaviour.bind(ctx, tag, instance, trove, values)
			end)
		end
	end
	return UrkUI
end

-- Stops UrkUI: unbinds every tag, removes kit-created ScreenGuis and disconnects everything.
function UrkUI.stop()
	local ctx = context
	if ctx == nil then
		return
	end
	ctx.binder:destroy()
	for _, connection in ctx.connections do
		connection:Disconnect()
	end
	ctx.drag:destroy()
	ctx.menu:destroy()
	ctx.toasts:destroy()
	ctx.tooltip:destroy()
	ctx.panels:destroy()
	ctx.focus:destroy()
	ctx.responsive:destroy()
	ctx.localize:destroy()
	Sounds.clear()
	context = nil
	UrkUI.store = nil
	Context.set(nil)
end

function UrkUI.isRunning(): boolean
	return context ~= nil
end

-- Panels -------------------------------------------------------------------------------------

function UrkUI.open(id: string)
	requireContext().panels:open(id)
end

function UrkUI.close(id: string)
	requireContext().panels:close(id)
end

function UrkUI.toggle(id: string)
	requireContext().panels:toggle(id)
end

function UrkUI.back(): boolean
	return requireContext().panels:back()
end

function UrkUI.closeAll(group: string?)
	requireContext().panels:closeAll(group)
end

function UrkUI.isOpen(id: string): boolean
	return requireContext().panels:isOpen(id)
end

-- Registers a panel built on first open: builder returns the (parented) panel instance.
function UrkUI.definePanel(id: string, builder: () -> Instance, def: PanelRouter.PanelDef?, transition: string?)
	requireContext().panels:define(id, builder, def, { transition = transition })
end

-- Feedback -----------------------------------------------------------------------------------

-- UrkUI.toast("Saved") or UrkUI.toast({ text = "Not enough coins", kind = "error", duration = 3 })
function UrkUI.toast(input: string | ToastQueue.ToastInput, kind: string?): string
	local toastInput: ToastQueue.ToastInput
	if type(input) == "string" then
		toastInput = { text = input, kind = kind }
	else
		toastInput = input
	end
	return requireContext().toasts:show(toastInput)
end

function UrkUI.dismissToast(id: string)
	requireContext().toasts:dismiss(id)
end

function UrkUI.confirm(props: any)
	return UrkUI.Components.Dialog.confirm(props)
end

function UrkUI.alert(props: any)
	return UrkUI.Components.Dialog.alert(props)
end

-- Opens the shared context menu at a GUI-space point or beside an object.
function UrkUI.contextMenu(items: { any }, at: Vector2 | GuiObject, source: Instance?)
	requireContext().menu:open(items, at, source)
end

-- Runs an Action spec as if a button had been pressed ("OpenPanel:Shop;PlaySound:123").
function UrkUI.run(spec: string, source: Instance?): boolean
	return requireContext().actions:run(spec, source)
end

-- Theme, locale, accessibility ---------------------------------------------------------------

function UrkUI.setTheme(name: string)
	requireContext().theme:setTheme(name)
end

function UrkUI.cycleTheme()
	requireContext().theme:cycle()
end

function UrkUI.getTheme(): string
	return requireContext().theme.name
end

function UrkUI.color(role: string): Color3
	return requireContext().theme:color(role)
end

function UrkUI.setLocale(locale: string)
	requireContext().localize:setLocale(locale)
end

function UrkUI.addTranslations(locale: string, entries: Localizer.Entries)
	requireContext().localize:addTable(locale, entries)
end

function UrkUI.t(key: string, args: { [string]: any }?): string
	return requireContext().localize:t(key, args)
end

function UrkUI.setReducedMotion(enabled: boolean)
	Motion.setReducedMotion(enabled)
	local ctx = context
	if ctx then
		ctx.ReducedMotionChanged:Fire(enabled)
	end
end

function UrkUI.isReducedMotion(): boolean
	return Motion.isReduced()
end

function UrkUI.setMinTextSize(size: number)
	requireContext().theme:setMinTextSize(size)
end

function UrkUI.setUIScale(multiplier: number)
	requireContext().responsive:setUserScale(multiplier)
end

function UrkUI.getBreakpoint(): string
	return requireContext().responsive.breakpoint
end

-- Rewires gamepad navigation (all UrkNav groups, or one) after a big layout change.
function UrkUI.refreshNavigation(container: GuiObject?)
	requireContext().focus:refresh(container)
end

return UrkUI
