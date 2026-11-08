--!strict
-- Table-based localisation with locale fallback, {placeholder} interpolation, format specs inside
-- placeholders ("{cash:abbrev}") and plural forms through a rule hook. Pure Luau.
--
-- Entries are strings, or plural tables keyed by CLDR category: { one = "1 coin", other = "{count} coins" }.
-- Lookup order for locale "pt-br" with fallback "en": "pt-br", "pt", "en". A key missing everywhere
-- returns the key itself, so untranslated text is visible in playtests instead of blank.

local Format = require("./Format")

export type PluralRule = (count: number) -> string
export type Entries = { [string]: any }

export type Options = {
	locale: string?,
	fallback: string?,
	tables: { [string]: Entries }?,
	pluralRules: { [string]: PluralRule }?,
	onMissing: ((key: string, locale: string) -> ())?,
}

export type Localizer = {
	t: (self: Localizer, key: string, args: { [string]: any }?) -> string,
	has: (self: Localizer, key: string) -> boolean,
	setLocale: (self: Localizer, locale: string) -> (),
	getLocale: (self: Localizer) -> string,
	addTable: (self: Localizer, locale: string, entries: Entries) -> (),
	chain: (self: Localizer) -> { string },
}

local Localizer = {}

function Localizer.normalize(locale: string): string
	local lowered = string.lower(locale)
	local normalized = string.gsub(lowered, "_", "-")
	return normalized
end

-- "pt-br" + "en" -> { "pt-br", "pt", "en" } without duplicates.
function Localizer.chain(locale: string, fallback: string?): { string }
	local list: { string } = {}
	local function push(value: string)
		if value ~= "" and table.find(list, value) == nil then
			table.insert(list, value)
		end
	end
	local normalized = Localizer.normalize(locale)
	push(normalized)
	local language = string.match(normalized, "^([%a]+)%-")
	if language then
		push(language)
	end
	if fallback then
		local fallbackNormalized = Localizer.normalize(fallback)
		push(fallbackNormalized)
		local fallbackLanguage = string.match(fallbackNormalized, "^([%a]+)%-")
		if fallbackLanguage then
			push(fallbackLanguage)
		end
	end
	return list
end

local function oneOther(count: number): string
	return if count == 1 then "one" else "other"
end

local function french(count: number): string
	return if count >= 0 and count < 2 then "one" else "other"
end

local function onlyOther(_count: number): string
	return "other"
end

local function slavic(count: number): string
	if count % 1 ~= 0 then
		return "other"
	end
	local mod10 = count % 10
	local mod100 = count % 100
	if mod10 == 1 and mod100 ~= 11 then
		return "one"
	end
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) then
		return "few"
	end
	return "many"
end

local function polish(count: number): string
	if count % 1 ~= 0 then
		return "other"
	end
	if count == 1 then
		return "one"
	end
	local mod10 = count % 10
	local mod100 = count % 100
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14) then
		return "few"
	end
	return "many"
end

-- Built-in rules by language. Anything else uses one/other. Pass pluralRules to add or override.
local BUILTIN_RULES: { [string]: PluralRule } = {
	fr = french,
	ru = slavic,
	uk = slavic,
	pl = polish,
	ja = onlyOther,
	zh = onlyOther,
	ko = onlyOther,
	th = onlyOther,
	vi = onlyOther,
	id = onlyOther,
	tr = oneOther,
}

-- CLDR plural category for `count` in `locale`, using `rules` before the built-ins.
function Localizer.pluralCategory(locale: string, count: number, rules: { [string]: PluralRule }?): string
	local normalized = Localizer.normalize(locale)
	local language = string.match(normalized, "^([%a]+)") or normalized
	local rule: PluralRule = BUILTIN_RULES[language] or oneOther
	if rules then
		local custom = rules[normalized] or rules[language]
		if custom then
			rule = custom
		end
	end
	local ok, category = pcall(rule, math.abs(count))
	if ok and type(category) == "string" then
		return category
	end
	return "other"
end

-- Replaces {name} and {name:spec} with values from `args`; "{{" and "}}" are literal braces.
-- Placeholders without a value are left as they are.
function Localizer.interpolate(template: string, args: { [string]: any }?): string
	local values: { [string]: any } = args or {}
	local escaped = string.gsub(template, "{{", "\1")
	escaped = string.gsub(escaped, "}}", "\2")
	local replaced = string.gsub(escaped, "(%b{})", function(token: string): string
		local inner = string.sub(token, 2, -2)
		local name, spec = string.match(inner, "^([%w_]+):?(.*)$")
		if name == nil then
			return token
		end
		local value = values[name]
		if value == nil then
			return token
		end
		if spec ~= nil and spec ~= "" then
			return Format.apply(spec, value)
		end
		return tostring(value)
	end)
	replaced = string.gsub(replaced, "\1", "{")
	replaced = string.gsub(replaced, "\2", "}")
	return replaced
end

function Localizer.new(options: Options?): Localizer
	local opts: Options = options or {}
	local locale = Localizer.normalize(opts.locale or "en")
	local fallback = Localizer.normalize(opts.fallback or "en")
	local tables: { [string]: Entries } = {}
	local pluralRules = opts.pluralRules
	local onMissing = opts.onMissing
	local cachedChain: { string } = Localizer.chain(locale, fallback)

	if opts.tables then
		for name, entries in opts.tables do
			tables[Localizer.normalize(name)] = table.clone(entries)
		end
	end

	local function find(key: string): (any, string?)
		for _, name in cachedChain do
			local entries = tables[name]
			if entries ~= nil and entries[key] ~= nil then
				return entries[key], name
			end
		end
		return nil, nil
	end

	local localizer: Localizer = {
		t = function(_self: Localizer, key: string, args: { [string]: any }?): string
			local entry, foundIn = find(key)
			if entry == nil then
				if onMissing then
					onMissing(key, locale)
				end
				return key
			end
			if type(entry) == "table" then
				local count = if args then args.count else nil
				local category = "other"
				if type(count) == "number" then
					category = Localizer.pluralCategory(foundIn or locale, count, pluralRules)
				end
				local text = entry[category] or entry.other or entry.one
				if type(text) ~= "string" then
					return key
				end
				return Localizer.interpolate(text, args)
			end
			return Localizer.interpolate(tostring(entry), args)
		end,

		has = function(_self: Localizer, key: string): boolean
			local entry = find(key)
			return entry ~= nil
		end,

		setLocale = function(_self: Localizer, newLocale: string)
			locale = Localizer.normalize(newLocale)
			cachedChain = Localizer.chain(locale, fallback)
		end,

		getLocale = function(_self: Localizer): string
			return locale
		end,

		addTable = function(_self: Localizer, name: string, entries: Entries)
			local normalized = Localizer.normalize(name)
			local merged = tables[normalized] or {}
			for key, value in entries do
				merged[key] = value
			end
			tables[normalized] = merged
		end,

		chain = function(_self: Localizer): { string }
			return table.clone(cachedChain)
		end,
	}
	return localizer
end

return Localizer
