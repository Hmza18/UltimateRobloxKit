--!strict
-- UrkLocalize (text from the Localizer with literal and Store-bound placeholders), UrkNav
-- (gamepad focus groups) and UrkResponsive (per-breakpoint attribute overrides and UIScale).

local Breakpoints = require("../Core/Breakpoints")
local Path = require("../Core/Path")
local TagSpec = require("../Core/TagSpec")

local Structure = {}

Structure.tags = { "UrkLocalize", "UrkNav", "UrkResponsive" }

local function bindLocalize(context: any, instance: Instance, trove: any, values: { [string]: any })
	local key = values.Key
	if type(key) ~= "string" or key == "" then
		return
	end
	local property: string = values.Property or "Text"
	local target: any = instance
	local storeUnsubscribers: { () -> () } = {}

	local function render()
		local attributes = instance:GetAttributes()
		local args = TagSpec.prefixed(attributes, "Arg_")
		for name, path in TagSpec.prefixed(attributes, "ArgPath_") do
			if type(path) == "string" and Path.isValid(path) then
				args[name] = context.store:get(path)
			end
		end
		local ok, err = pcall(function()
			target[property] = context.localize:t(key, args)
		end)
		if not ok then
			warn("[UrkUI] UrkLocalize cannot write " .. property .. ": " .. tostring(err))
		end
	end

	local function resubscribe()
		for _, unsubscribe in storeUnsubscribers do
			unsubscribe()
		end
		table.clear(storeUnsubscribers)
		for _, path in TagSpec.prefixed(instance:GetAttributes(), "ArgPath_") do
			if type(path) == "string" and Path.isValid(path) then
				table.insert(storeUnsubscribers, context.store:subscribe(path, render))
			end
		end
	end

	trove:Connect(context.localize.Changed, render)
	trove:Connect(instance.AttributeChanged, function(name: string)
		if string.sub(name, 1, 8) == "ArgPath_" then
			resubscribe()
			render()
		elseif string.sub(name, 1, 4) == "Arg_" then
			render()
		end
	end)
	trove:Add(function()
		for _, unsubscribe in storeUnsubscribers do
			unsubscribe()
		end
	end)
	resubscribe()
	render()
end

local function bindNav(context: any, instance: Instance, trove: any, values: { [string]: any })
	if not instance:IsA("GuiObject") then
		return
	end
	local options = { wrap = values.Wrap, autoSelect = values.AutoSelect, remember = values.Remember }
	context.focus:attachGroup(instance :: GuiObject, options, trove)
end

local function bindResponsive(context: any, instance: Instance, trove: any, values: { [string]: any })
	local target: any = instance
	local base: { [string]: any } = {}

	local function apply()
		local attributes = instance:GetAttributes()
		local breakpoint = context.responsive.breakpoint
		for _, property in Breakpoints.properties(attributes) do
			if base[property] == nil then
				local ok, current = pcall(function(): any
					return target[property]
				end)
				if ok then
					base[property] = current
				end
			end
			if base[property] ~= nil then
				local value = Breakpoints.pick(attributes, property, breakpoint, base[property])
				pcall(function()
					target[property] = value
				end)
			end
		end
		instance:SetAttribute("UrkBreakpoint", breakpoint)
	end

	if values.AutoScale and instance:IsA("GuiBase2d") then
		local scale = Instance.new("UIScale")
		scale.Name = "UrkResponsiveScale"
		scale.Parent = instance
		context.responsive:manage(scale)
		trove:Add(function()
			context.responsive:unmanage(scale)
			scale:Destroy()
		end)
	end

	trove:Connect(context.responsive.Changed, apply)
	trove:Connect(instance.AttributeChanged, function(name: string)
		if string.find(name, "^%a+_") and not string.find(name, "^Urk") then
			apply()
		end
	end)
	trove:Add(function()
		for property, value in base do
			pcall(function()
				target[property] = value
			end)
		end
	end)
	apply()
end

function Structure.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	if tag == "UrkLocalize" then
		bindLocalize(context, instance, trove, values)
	elseif tag == "UrkNav" then
		bindNav(context, instance, trove, values)
	else
		bindResponsive(context, instance, trove, values)
	end
end

return Structure
