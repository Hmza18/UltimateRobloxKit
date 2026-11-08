--!strict
-- Client ghost preview for Placement. Shows a see-through copy of the item under the pointer (mouse or
-- last touch), snapped to the grid and tinted green or red using the same PlacementLogic rules the server
-- applies to the latest layout it sent. confirm() sends the request; the server has the final say.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PlacementConfig = require("./PlacementConfig")
local PlacementLogic = require("./PlacementLogic")
local Signal = require("../../Util/Signal")
local Trove = require("../../Util/Trove")

export type Options = {
	catalog: PlacementLogic.Catalog,
	templates: Instance, -- the same folder of models the server uses (replicated)
	getPlot: () -> BasePart?, -- the local player's plot part
	config: { [string]: any }?,
	validColor: Color3?,
	invalidColor: Color3?,
}

export type Client = {
	start: (self: Client, itemId: string) -> (),
	rotate: (self: Client, steps: number?) -> (),
	confirm: (self: Client) -> boolean, -- false when the ghost is in an invalid spot
	cancel: (self: Client) -> (),
	move: (self: Client, id: string, x: number, z: number, rotation: number) -> (),
	remove: (self: Client, id: string) -> (),
	isValid: (self: Client) -> boolean,
	layout: (self: Client) -> PlacementLogic.Layout,
	layoutChanged: Signal.Signal, -- (layout)
	rejected: Signal.Signal, -- (reason)
	destroy: (self: Client) -> (),
}

local PlacementClient = {}

function PlacementClient.new(options: Options): Client
	local settings: { [string]: any } = table.clone(PlacementConfig)
	for key, value in pairs(options.config or {}) do
		settings[key] = value
	end
	local config = PlacementLogic.resolveConfig(settings)
	local folder = ReplicatedStorage:WaitForChild(settings.remoteFolder)
	local placeRemote = folder:WaitForChild("Place") :: RemoteEvent
	local moveRemote = folder:WaitForChild("Move") :: RemoteEvent
	local removeRemote = folder:WaitForChild("Remove") :: RemoteEvent
	local layoutRemote = folder:WaitForChild("Layout") :: RemoteEvent
	local rejectedRemote = folder:WaitForChild("Rejected") :: RemoteEvent
	local validColor = options.validColor or Color3.fromRGB(80, 220, 120)
	local invalidColor = options.invalidColor or Color3.fromRGB(235, 70, 70)

	local trove = Trove.new()
	local layoutChanged = Signal.new()
	local rejected = Signal.new()
	trove:Add(function()
		layoutChanged:DisconnectAll()
		rejected:DisconnectAll()
	end)

	local layout = PlacementLogic.newLayout()
	local ghostTrove: Trove.Trove? = nil
	local ghost: Model? = nil
	local highlight: Highlight? = nil
	local currentItem: string? = nil
	local rotation = 0
	local valid = false
	local target: { x: number, z: number }? = nil
	local pointer = UserInputService:GetMouseLocation()

	trove:Connect(layoutRemote.OnClientEvent, function(list: any)
		local nextLayout = PlacementLogic.newLayout()
		if type(list) == "table" then
			for _, placed in list do
				if type(placed) == "table" and type(placed.id) == "string" then
					nextLayout.items[placed.id] = placed
				end
			end
		end
		layout = nextLayout
		layoutChanged:Fire(layout)
	end)
	trove:Connect(rejectedRemote.OnClientEvent, function(reason: any)
		rejected:Fire(tostring(reason))
	end)
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	local function stopGhost()
		if ghostTrove then
			ghostTrove:Clean()
			ghostTrove = nil
		end
		ghost = nil
		highlight = nil
		currentItem = nil
		target = nil
		valid = false
	end

	local function update()
		local model, itemId, plot = ghost, currentItem, options.getPlot()
		local camera = workspace.CurrentCamera
		if model == nil or itemId == nil or plot == nil or camera == nil then
			return
		end
		local entry = options.catalog[itemId]
		if entry == nil then
			return
		end
		local ray = camera:ViewportPointToRay(pointer.X, pointer.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local character = Players.LocalPlayer.Character
		params.FilterDescendantsInstances = if character then { model, character } else { model }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		if hit == nil then
			return
		end
		local localPoint = plot.CFrame:PointToObjectSpace(hit.Position)
		local x, z = PlacementLogic.snapPosition(
			localPoint.X + plot.Size.X / 2,
			localPoint.Z + plot.Size.Z / 2,
			entry.size,
			rotation,
			config
		)
		target = { x = x, z = z }
		local request = { itemId = itemId, x = x, z = z, rotation = rotation }
		local bounds = { width = plot.Size.X, depth = plot.Size.Z }
		valid = PlacementLogic.validate(layout, request, options.catalog, bounds, config, nil)
		local degrees = PlacementLogic.rotationDegrees(rotation, config.rotationSteps)
		local offset = CFrame.new(x - plot.Size.X / 2, plot.Size.Y / 2, z - plot.Size.Z / 2)
		model:PivotTo(plot.CFrame * offset * CFrame.Angles(0, math.rad(degrees), 0))
		if highlight then
			highlight.FillColor = if valid then validColor else invalidColor
		end
	end

	local client = {} :: Client
	client.layoutChanged = layoutChanged
	client.rejected = rejected

	function client.start(_self: Client, itemId: string)
		stopGhost()
		local template = options.templates:FindFirstChild(itemId)
		if template == nil or not template:IsA("Model") or options.catalog[itemId] == nil then
			return
		end
		local localTrove = Trove.new()
		ghostTrove = localTrove
		local model = template:Clone()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Transparency = math.max(descendant.Transparency, settings.ghostTransparency)
			elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end
		local tint = Instance.new("Highlight")
		tint.FillTransparency = 0.5
		tint.OutlineTransparency = 1
		tint.Parent = model
		model.Parent = workspace
		localTrove:Add(model)
		ghost = model
		highlight = tint
		currentItem = itemId
		localTrove:Connect(RunService.RenderStepped, update)
	end

	function client.rotate(_self: Client, steps: number?)
		rotation = PlacementLogic.normalizeRotation(rotation + (steps or 1), config.rotationSteps)
		update()
	end

	function client.confirm(_self: Client): boolean
		local spot = target
		if currentItem == nil or spot == nil or not valid then
			return false
		end
		placeRemote:FireServer(currentItem, spot.x, spot.z, rotation)
		return true
	end

	function client.cancel(_self: Client)
		stopGhost()
	end

	function client.move(_self: Client, id: string, x: number, z: number, step: number)
		moveRemote:FireServer(id, x, z, step)
	end

	function client.remove(_self: Client, id: string)
		removeRemote:FireServer(id)
	end

	function client.isValid(_self: Client): boolean
		return valid
	end

	function client.layout(_self: Client): PlacementLogic.Layout
		return layout
	end

	function client.destroy(_self: Client)
		stopGhost()
		trove:Clean()
	end

	return client
end

return PlacementClient
