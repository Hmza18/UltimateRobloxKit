--!strict
-- Shared helpers for the UltimateVisualsKit demos: loading the kit, cleanup scopes, a small stage
-- built from Parts, original blocky demo animals and food, and control panels made of UrkUI Game
-- components. Demo code only: nothing here is part of the library.
--
-- The demos reach the kit through its public entry points only:
--   Visuals  = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
--   UrkUI    = require(ReplicatedStorage.UltimateRobloxKit.UI.UrkUI)   (UrkUI.Game = the components)
--
-- NOT run in Studio. See README.md for the manual test checklist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Kit = ReplicatedStorage:WaitForChild("UltimateRobloxKit")
-- The kit is required through the DataModel because the demos live outside it; `any` keeps the
-- demos independent of how a type checker resolves that path.
local Visuals: any = (require :: any)(Kit:WaitForChild("Visuals"):WaitForChild("Visuals"))
local UrkUI: any = (require :: any)(Kit:WaitForChild("UI"):WaitForChild("UrkUI"))
local Game: any = UrkUI.Game

export type Scope = {
	add: <T>(item: T) -> T,
	clean: () -> (),
	isAlive: () -> boolean,
}

export type PanelOptions = {
	title: string,
	width: number?,
	height: number?,
	side: string?, -- "left" | "right" (default) | "bottom"
	palette: string?,
}

local DemoKit = {}

DemoKit.Visuals = Visuals
DemoKit.UrkUI = UrkUI
DemoKit.Game = Game

-- Cleanup ---------------------------------------------------------------------------------------

local function dispose(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "table" then
		local method = item.destroy or item.Destroy or item.cancel or item.stop or item.Disconnect
		if type(method) == "function" then
			-- Components, followers and connections are methods (object:destroy()); effect and
			-- animation handles are plain functions (handle.stop()), whose first argument means
			-- something else (restore, immediate), so they are called with none.
			if item.destroy or item.Destroy or item.Disconnect then
				method(item)
			else
				method()
			end
		end
	end
end

-- Collects everything a demo creates. clean() releases it newest first, tolerates errors in one
-- item, and is safe to call twice.
function DemoKit.scope(): Scope
	local items: { any } = {}
	local alive = true
	local scope = {} :: Scope
	function scope.add<T>(item: T): T
		if not alive then
			pcall(dispose, item)
		elseif item ~= nil then
			table.insert(items, item)
		end
		return item
	end
	function scope.clean()
		if not alive then
			return
		end
		alive = false
		for index = #items, 1, -1 do
			local ok, err = pcall(dispose, items[index])
			if not ok then
				warn("[UVK demo] cleanup failed: " .. tostring(err))
			end
		end
		table.clear(items)
	end
	function scope.isAlive(): boolean
		return alive
	end
	return scope
end

-- Bootstrap -------------------------------------------------------------------------------------

local booted = false
local syncing = false

-- Reduced motion lives in two places: UrkUI (the original components and Motion presets) and the
-- visuals kit (everything under Visuals plus the animated components). These two lines keep them
-- equal whichever side changes; `syncing` stops the echo.
local function bridgeReducedMotion()
	Visuals.Changed:Connect(function(settings: any)
		if not syncing and UrkUI.isReducedMotion() ~= settings.reducedMotion then
			syncing = true
			UrkUI.setReducedMotion(settings.reducedMotion)
			syncing = false
		end
	end)
	Visuals.Configure({ reducedMotion = UrkUI.isReducedMotion() })
end

-- Starts UrkUI once (toasts, actions, the player's Reduce Motion setting) and links the two
-- reduced-motion switches. Safe to call from every demo.
function DemoKit.bootstrap()
	if booted then
		return
	end
	booted = true
	if not UrkUI.isRunning() then
		UrkUI.start({})
	end
	local ok, err = pcall(bridgeReducedMotion)
	if not ok then
		warn("[UVK demo] reduced-motion bridge failed: " .. tostring(err))
	end
end

-- Sets reduced motion on both sides in one call.
function DemoKit.setReducedMotion(enabled: boolean)
	syncing = true
	UrkUI.setReducedMotion(enabled)
	syncing = false
	Visuals.Configure({ reducedMotion = enabled })
end

function DemoKit.playerGui(): Instance
	local player = Players.LocalPlayer
	return player:WaitForChild("PlayerGui")
end

-- A toast through UrkUI when it runs, else a stand-alone Notification component.
function DemoKit.toast(text: string, kind: string?, parent: Instance?)
	if UrkUI.isRunning() then
		UrkUI.toast(text, kind)
		return
	end
	if parent then
		Game.Notification.new({
			kind = kind or "info",
			title = text,
			parent = parent,
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, 12),
		})
	end
end

-- World helpers ---------------------------------------------------------------------------------

function DemoKit.color(hex: string): Color3
	return Color3.fromHex(hex)
end

function DemoKit.toVector(point: { x: number, y: number, z: number }): Vector3
	return Vector3.new(point.x, point.y, point.z)
end

function DemoKit.toPoint(vector: Vector3): { x: number, y: number, z: number }
	return { x = vector.X, y = vector.Y, z = vector.Z }
end

-- An anchored, non-colliding Part: the building block of every demo prop.
function DemoKit.part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- A point on the ground `distance` studs in front of the player, as a CFrame whose LookVector
-- points back at the player (so props placed with it face them).
function DemoKit.origin(distance: number, sideways: number?): CFrame
	local player = Players.LocalPlayer
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local camera = Workspace.CurrentCamera
	local from = Vector3.new(0, 5, 0)
	local look = Vector3.new(0, 0, -1)
	if root and root:IsA("BasePart") then
		from = root.Position
		look = root.CFrame.LookVector
	elseif camera then
		from = camera.CFrame.Position
		look = camera.CFrame.LookVector
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude < 0.01 then Vector3.new(0, 0, -1) else flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local point = from + flat * distance + right * (sideways or 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = Workspace:Raycast(point + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	local groundY = if hit then hit.Position.Y else from.Y - 3
	local ground = Vector3.new(point.X, groundY, point.Z)
	return CFrame.lookAt(ground, ground - flat)
end

export type Stage = {
	folder: Folder,
	origin: CFrame, -- on the ground
	top: CFrame, -- centre of the platform's top surface
	radius: number,
}

-- A small round stage: a disc, a trim ring and three soft blocks behind it. Returned folder holds
-- everything the demo puts in the world, so one Destroy removes it all.
function DemoKit.stage(scope: Scope, name: string, origin: CFrame, accent: Color3, radius: number?): Stage
	local size = radius or 7
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	scope.add(folder)

	local upright = CFrame.Angles(0, 0, math.rad(90))
	local disc = DemoKit.part(
		folder,
		"Platform",
		Vector3.new(0.6, size * 2, size * 2),
		origin * CFrame.new(0, 0.3, 0) * upright,
		Color3.fromRGB(244, 240, 232),
		Enum.PartType.Cylinder
	)
	disc.CanCollide = true
	DemoKit.part(
		folder,
		"Trim",
		Vector3.new(0.3, size * 2 + 1, size * 2 + 1),
		origin * CFrame.new(0, 0.15, 0) * upright,
		accent,
		Enum.PartType.Cylinder
	)
	-- Backdrop blocks sit on the far side (+Z of the origin is away from the player).
	for index = -1, 1 do
		local height = 4 + (1 - math.abs(index)) * 2
		DemoKit.part(
			folder,
			"Backdrop",
			Vector3.new(3.4, height, 1),
			origin * CFrame.new(index * 3.8, height / 2, size + 1.2) * CFrame.Angles(0, math.rad(-index * 14), 0),
			accent:Lerp(Color3.new(1, 1, 1), 0.35 + 0.15 * math.abs(index))
		)
	end
	return { folder = folder, origin = origin, top = origin * CFrame.new(0, 0.6, 0), radius = size }
end

-- A demo pet from the kit's own original builder (Parts only), placed with its feet on `at`.
function DemoKit.pet(parent: Instance, at: CFrame, color: Color3, variant: number?, name: string?): Model
	local model: Model = Visuals.Pets.demoPet({ color = color, variant = variant or 1, name = name or "DemoPet" })
	model:PivotTo(at)
	model.Parent = parent
	return model
end

-- An original blocky animal: a rounded-box body, a head, ears or a bill, four stubby feet and a
-- tail. "hopper" has long ears; "waddler" has a flat bill and a crest. Faces -Z; pivot at its feet.
function DemoKit.animal(
	parent: Instance,
	at: CFrame,
	kind: string,
	bodyColor: Color3,
	accent: Color3,
	name: string
): Model
	local model = Instance.new("Model")
	model.Name = name
	local dark = Color3.fromRGB(40, 36, 48)
	local origin = CFrame.new()
	local body = DemoKit.part(model, "Body", Vector3.new(2.6, 2, 3.2), origin * CFrame.new(0, 1.5, 0), bodyColor)
	DemoKit.part(model, "Belly", Vector3.new(2.2, 1.2, 2.6), origin * CFrame.new(0, 1.1, -0.35), accent)
	DemoKit.part(model, "Head", Vector3.new(2.2, 1.8, 1.9), origin * CFrame.new(0, 3, -1.3), bodyColor)
	for side = -1, 1, 2 do
		DemoKit.part(model, "Eye", Vector3.new(0.34, 0.5, 0.2), origin * CFrame.new(side * 0.55, 3.2, -2.28), dark)
		DemoKit.part(
			model,
			"Shine",
			Vector3.new(0.12, 0.16, 0.06),
			origin * CFrame.new(side * 0.6, 3.34, -2.4),
			Color3.new(1, 1, 1)
		)
		DemoKit.part(model, "FootFront", Vector3.new(0.7, 0.5, 0.9), origin * CFrame.new(side * 0.85, 0.25, -1), accent)
		DemoKit.part(model, "FootBack", Vector3.new(0.7, 0.5, 0.9), origin * CFrame.new(side * 0.85, 0.25, 1), accent)
		if kind == "hopper" then
			DemoKit.part(
				model,
				"Ear",
				Vector3.new(0.5, 1.7, 0.4),
				origin * CFrame.new(side * 0.6, 4.6, -1.1) * CFrame.Angles(0, 0, math.rad(-side * 10)),
				bodyColor
			)
		end
	end
	if kind == "hopper" then
		DemoKit.part(
			model,
			"Nose",
			Vector3.new(0.4, 0.3, 0.2),
			origin * CFrame.new(0, 2.85, -2.3),
			Color3.fromRGB(240, 130, 150)
		)
		DemoKit.part(
			model,
			"Tail",
			Vector3.new(0.9, 0.9, 0.9),
			origin * CFrame.new(0, 1.7, 1.9),
			accent,
			Enum.PartType.Ball
		)
	else
		DemoKit.part(
			model,
			"Bill",
			Vector3.new(1.3, 0.35, 0.9),
			origin * CFrame.new(0, 2.75, -2.6),
			Color3.fromRGB(255, 176, 64)
		)
		DemoKit.part(
			model,
			"Crest",
			Vector3.new(0.4, 0.7, 1.1),
			origin * CFrame.new(0, 4.15, -1.2) * CFrame.Angles(math.rad(-18), 0, 0),
			accent
		)
		DemoKit.part(
			model,
			"Tail",
			Vector3.new(1.2, 0.4, 0.9),
			origin * CFrame.new(0, 1.9, 1.9) * CFrame.Angles(math.rad(25), 0, 0),
			accent
		)
	end
	-- Feet on the ground: the pivot is the model origin, under the body's centre.
	body.PivotOffset = body.CFrame:ToObjectSpace(origin)
	model.PrimaryPart = body
	model:PivotTo(at)
	model.Parent = parent
	return model
end

-- A piece of demo food as one Part: "ball" berry, "wedge" carrot, "disc" cookie.
function DemoKit.food(parent: Instance, at: CFrame, shape: string, color: Color3, name: string): Part
	if shape == "wedge" then
		local wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Size = Vector3.new(0.5, 0.5, 1.3)
		wedge.Color = color
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.CFrame = at
		wedge.Parent = parent
		return wedge :: any
	elseif shape == "disc" then
		return DemoKit.part(
			parent,
			name,
			Vector3.new(0.3, 1, 1),
			at * CFrame.Angles(0, 0, math.rad(90)),
			color,
			Enum.PartType.Cylinder
		)
	end
	return DemoKit.part(parent, name, Vector3.new(0.9, 0.9, 0.9), at, color, Enum.PartType.Ball)
end

-- Interface helpers -----------------------------------------------------------------------------

function DemoKit.screen(scope: Scope, parent: Instance, name: string, displayOrder: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 20
	gui.Parent = parent
	scope.add(gui)
	return gui
end

-- A Game.Panel docked to one side with a title and a vertical list. Returns the list frame that
-- buttons and labels go into.
function DemoKit.panel(scope: Scope, gui: Instance, options: PanelOptions): ScrollingFrame
	local width = options.width or 250
	local height = options.height or 420
	local side = options.side or "right"
	local position: UDim2, anchor: Vector2
	if side == "left" then
		position, anchor = UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5)
	elseif side == "bottom" then
		position, anchor = UDim2.new(0.5, 0, 1, -12), Vector2.new(0.5, 1)
	else
		position, anchor = UDim2.new(1, -12, 0.5, 0), Vector2.new(1, 0.5)
	end
	local panel = Game.Panel.new({
		name = "DemoPanel",
		surface = if options.palette then nil else "window",
		palette = options.palette,
		size = UDim2.fromOffset(width, height),
		position = position,
		anchor = anchor,
		parent = gui,
	})
	scope.add(panel)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, -20, 1, -20)
	list.Position = UDim2.fromOffset(10, 10)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = panel.Content
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	DemoKit.text(scope, list, options.title, "heading", 0)
	return list
end

-- Outlined game text. `role` is a GameText role: display, title, heading, label, caption.
function DemoKit.text(scope: Scope, parent: Instance, text: string, role: string?, order: number?, align: string?): any
	return scope.add(Game.GameText.new({
		text = text,
		size = role or "label",
		align = align or "center",
		wrap = true,
		layoutOrder = order,
		parent = parent,
	}))
end

-- A CartoonButton that fills the list width. `kind` is a CartoonButton kind (primary, buy,
-- neutral, danger) or a palette name when it starts with "@" ("@purple").
function DemoKit.button(
	scope: Scope,
	parent: Instance,
	text: string,
	kind: string?,
	order: number?,
	onClick: () -> ()
): any
	local palette: string? = nil
	local buttonKind = kind or "primary"
	if string.sub(buttonKind, 1, 1) == "@" then
		palette = string.sub(buttonKind, 2)
		buttonKind = "primary"
	end
	local button = Game.CartoonButton.new({
		text = text,
		kind = buttonKind,
		palette = palette,
		size = UDim2.new(1, -4, 0, 46),
		layoutOrder = order,
		parent = parent,
	})
	scope.add(button)
	scope.add(button.Activated:Connect(function()
		onClick()
	end))
	return button
end

-- A labelled Toggle row.
function DemoKit.toggle(
	scope: Scope,
	parent: Instance,
	text: string,
	value: boolean,
	order: number?,
	onChanged: (value: boolean) -> ()
): any
	local row = Instance.new("Frame")
	row.Name = "ToggleRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -4, 0, 44)
	row.LayoutOrder = order or 0
	row.Parent = parent
	scope.add(Game.GameText.new({
		text = text,
		size = UDim2.new(1, -86, 1, 0),
		role = "label",
		align = "left",
		parent = row,
	}))
	local toggle = Game.Toggle.new({
		value = value,
		onChanged = onChanged,
		anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, 0, 0.5, 0),
		parent = row,
	})
	scope.add(toggle)
	return toggle
end

-- A small rolling log: returns print(message). Shows the last `lines` messages.
function DemoKit.log(scope: Scope, parent: Instance, lines: number?, order: number?): (message: string) -> ()
	local count = lines or 5
	local label = Instance.new("TextLabel")
	label.Name = "Log"
	label.BackgroundColor3 = Color3.fromRGB(20, 22, 36)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(226, 232, 255)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Size = UDim2.new(1, -4, 0, count * 17 + 10)
	label.LayoutOrder = order or 0
	label.Text = ""
	label.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.Parent = label
	local history: { string } = {}
	return function(message: string)
		if not scope.isAlive() then
			return
		end
		table.insert(history, message)
		while #history > count do
			table.remove(history, 1)
		end
		label.Text = table.concat(history, "\n")
	end
end

-- A HUD counter: a dark pill with a coloured dot and a number label. Returns the frame and the
-- TextLabel, which is what Visuals.UI.countTo and flyTo want as their target.
function DemoKit.counter(
	scope: Scope,
	parent: Instance,
	name: string,
	color: Color3,
	position: UDim2
): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = position
	frame.Size = UDim2.fromOffset(170, 44)
	frame.BackgroundColor3 = Color3.fromRGB(26, 28, 46)
	frame.BackgroundTransparency = 0.15
	frame.Parent = parent
	scope.add(frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 8, 0.5, 0)
	dot.Size = UDim2.fromOffset(28, 28)
	dot.BackgroundColor3 = color
	dot.Parent = frame
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(44, 0)
	label.Size = UDim2.new(1, -54, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "0"
	label.Parent = frame
	return frame, label
end

return DemoKit
