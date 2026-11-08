--!strict
-- Tiny instance builder used by the services and components:
--   Create.new("Frame", { Size = size, Parent = gui, Tags = { "UrkTheme" }, Attributes = { Role = "surface" } })
-- Properties are applied before Parent, so tagged instances are bound with their final values.

local Create = {}

local function build(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local target: any = instance
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Tags" then
				for _, tag in value do
					instance:AddTag(tag)
				end
			elseif key == "Attributes" then
				for name, attribute in value do
					instance:SetAttribute(name, attribute)
				end
			else
				target[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

Create.new = build

function Create.corner(radius: UDim): UICorner
	return build("UICorner", { CornerRadius = radius })
end

function Create.stroke(color: Color3, thickness: number?, transparency: number?): UIStroke
	return build("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Create.padding(pixels: number, horizontal: number?): UIPadding
	local side = UDim.new(0, horizontal or pixels)
	local vertical = UDim.new(0, pixels)
	local props = { PaddingTop = vertical, PaddingBottom = vertical, PaddingLeft = side, PaddingRight = side }
	return build("UIPadding", props)
end

type HAlign = Enum.HorizontalAlignment
type VAlign = Enum.VerticalAlignment

function Create.list(direction: Enum.FillDirection, gap: number, horizontal: HAlign?, vertical: VAlign?): UIListLayout
	return build("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, gap),
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- A ScreenGui under PlayerGui with sensible defaults for kit-owned layers.
function Create.screen(name: string, displayOrder: number, parent: Instance): ScreenGui
	return build("ScreenGui", {
		Name = name,
		DisplayOrder = displayOrder,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
end

-- Removes every CollectionService tag from `root` and its descendants (for drag ghosts and clones).
function Create.stripTags(root: Instance)
	for _, tag in root:GetTags() do
		root:RemoveTag(tag)
	end
	for _, descendant in root:GetDescendants() do
		for _, tag in descendant:GetTags() do
			descendant:RemoveTag(tag)
		end
	end
end

return Create
