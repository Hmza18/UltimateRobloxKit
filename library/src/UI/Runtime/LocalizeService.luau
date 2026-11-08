--!strict
-- Localisation at runtime: the pure Localizer for game-provided tables, optionally preferring
-- Roblox's own translator (LocalizationService:GetTranslatorForPlayerAsync) for keys that exist
-- in the experience's cloud localisation table. Fires Changed when the locale or translator
-- changes so every UrkLocalize label re-applies.

local LocalizationService = game:GetService("LocalizationService")

local Localizer = require("../Core/Localizer")
local Signal = require("../../Util/Signal")

export type Config = {
	locale: string?,
	fallback: string?,
	tables: { [string]: Localizer.Entries }?,
	pluralRules: { [string]: Localizer.PluralRule }?,
	useRobloxTranslator: boolean?,
	player: Player?,
	debug: boolean?,
}

local LocalizeService = {}

function LocalizeService.new(config: Config?)
	local cfg: Config = config or {}
	local service = {}
	service.Changed = Signal.new()
	local translator: Translator? = nil
	local destroyed = false

	local initialLocale = cfg.locale
	if initialLocale == nil and cfg.player then
		initialLocale = cfg.player.LocaleId
	end

	local onMissing: ((key: string, locale: string) -> ())? = nil
	if cfg.debug then
		onMissing = function(key: string, locale: string)
			warn("[UrkUI] missing translation " .. key .. " for " .. locale)
		end
	end

	local localizer = Localizer.new({
		locale = initialLocale or "en",
		fallback = cfg.fallback or "en",
		tables = cfg.tables,
		pluralRules = cfg.pluralRules,
		onMissing = onMissing,
	})
	service.localizer = localizer

	if cfg.useRobloxTranslator and cfg.player then
		local player = cfg.player
		task.spawn(function()
			local ok, result = pcall(function(): Translator
				return LocalizationService:GetTranslatorForPlayerAsync(player)
			end)
			if destroyed then
				return
			end
			if ok then
				translator = result
				service.Changed:Fire(localizer:getLocale())
			else
				warn("[UrkUI] could not get the Roblox translator: " .. tostring(result))
			end
		end)
	end

	-- Translates `key`. The Roblox translator wins when it knows the key; otherwise the tables.
	function service.t(_self: any, key: string, args: { [string]: any }?): string
		local robloxTranslator = translator
		if robloxTranslator ~= nil and not localizer:has(key) then
			local ok, text = pcall(function(): string
				return robloxTranslator:FormatByKey(key, args or {})
			end)
			if ok and type(text) == "string" then
				return text
			end
		end
		return localizer:t(key, args)
	end

	function service.setLocale(_self: any, locale: string)
		localizer:setLocale(locale)
		service.Changed:Fire(localizer:getLocale())
	end

	function service.getLocale(_self: any): string
		return localizer:getLocale()
	end

	function service.addTable(_self: any, locale: string, entries: Localizer.Entries)
		localizer:addTable(locale, entries)
		service.Changed:Fire(localizer:getLocale())
	end

	function service.destroy(_self: any)
		destroyed = true
		service.Changed:DisconnectAll()
	end

	return service
end

return LocalizeService
