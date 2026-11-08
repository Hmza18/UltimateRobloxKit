--!strict
-- Bridge to the kit's icon catalogue at src/Icons/Icons.luau (maintained separately).
-- The module is loaded lazily and guarded, so UrkUI still works (without icons) if it is missing.
-- Expected API: Icons.get(name), Icons.apply(label, name, options) -> boolean, Icons.has(name).

export type IconOptions = { color: Color3?, size: number? }

local IconBridge = {}

local loaded = false
local icons: any = nil

local function load(): any
	if not loaded then
		loaded = true
		local ok, result = pcall(function(): any
			return require("../../Icons/Icons")
		end)
		if ok and type(result) == "table" then
			icons = result
		else
			warn("[UrkUI] Icons module not available; UrkIcon and component icons are skipped: " .. tostring(result))
		end
	end
	return icons
end

function IconBridge.available(): boolean
	return load() ~= nil
end

function IconBridge.has(name: string?): boolean
	local module = load()
	if module == nil or name == nil or name == "" then
		return false
	end
	local ok, result = pcall(module.has, name)
	return ok and result == true
end

-- Applies icon `name` to an ImageLabel or ImageButton. Returns false when the icon is unknown.
function IconBridge.apply(label: ImageLabel | ImageButton, name: string?, options: IconOptions?): boolean
	local module = load()
	if module == nil or name == nil or name == "" then
		return false
	end
	local ok, result = pcall(module.apply, label, name, options)
	if not ok then
		warn("[UrkUI] Icons.apply failed for " .. name .. ": " .. tostring(result))
		return false
	end
	return result == true
end

return IconBridge
