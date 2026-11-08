--!strict
-- UrkPanel / UrkModal: registers the instance with the panel router (see Runtime/Panels).
-- Inside a panel, any GuiButton with the attribute ClosesPanel = true closes it, so a close
-- button needs no Action. Panels start hidden unless StartOpen is set.

local Panel = {}

Panel.tags = { "UrkPanel", "UrkModal" }

function Panel.bind(context: any, tag: string, instance: Instance, trove: any, values: { [string]: any })
	local id = values.PanelId
	if type(id) ~= "string" or id == "" then
		warn("[UrkUI] " .. instance:GetFullName() .. " needs a PanelId attribute")
		return
	end
	local def = {
		group = values.Group,
		exclusive = values.Exclusive,
		modal = tag == "UrkModal" or values.Modal == true,
		dismissible = values.Dismissible,
		priority = values.AdoptPriority,
	}
	local options = { transition = values.Transition, closeOnBackdrop = values.CloseOnBackdrop }
	trove:Add(context.panels:registerInstance(id, instance, def, options))

	local function wireClose(descendant: Instance)
		if descendant:IsA("GuiButton") and descendant:GetAttribute("ClosesPanel") == true then
			trove:Connect(descendant.Activated, function()
				context.panels:close(id)
			end)
		end
	end
	for _, descendant in instance:GetDescendants() do
		wireClose(descendant)
	end
	trove:Connect(instance.DescendantAdded, wireClose)

	if values.StartOpen then
		context.panels:open(id)
	end
end

return Panel
