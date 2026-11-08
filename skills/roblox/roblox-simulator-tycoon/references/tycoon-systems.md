# Tycoon systems

## Plot claiming

```lua
--!strict
-- ServerScriptService/Tycoon/PlotService.luau (ModuleScript)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local plotsFolder = Workspace:WaitForChild("Plots") :: Folder

local PlotService = {}

function PlotService.plotOf(player: Player): Model?
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

function PlotService.claim(player: Player): Model?
	local existing = PlotService.plotOf(player)
	if existing then
		return existing
	end
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == nil then
			plot:SetAttribute("OwnerUserId", player.UserId)
			return plot
		end
	end
	return nil -- server full of plots; keep plot count >= MaxPlayers
end

function PlotService.release(player: Player)
	local plot = PlotService.plotOf(player)
	if not plot then
		return
	end
	plot:SetAttribute("OwnerUserId", nil)
	local built = plot:FindFirstChild("Built")
	if built then
		built:ClearAllChildren() -- purchased items are rebuilt from save on next claim
	end
end

Players.PlayerRemoving:Connect(PlotService.release)

return PlotService
```

## Dropper loop with a cap

```lua
--!strict
-- One loop per server, not one per dropper, keeps scheduling cheap.
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local MAX_DROPS_PER_PLOT = 40
local INTERVAL = 1.5

local liveDrops: { [Model]: { BasePart } } = {}

local function spawnDrop(plot: Model, dropper: BasePart)
	local list = liveDrops[plot] or {}
	liveDrops[plot] = list
	if #list >= MAX_DROPS_PER_PLOT then
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local drop = Instance.new("Part")
	drop.Size = Vector3.new(1, 1, 1)
	drop.CFrame = dropper.CFrame * CFrame.new(0, -1.5, 0)
	drop:SetAttribute("Value", (dropper:GetAttribute("DropValue") :: number?) or 1)
	drop:SetAttribute("OwnerUserId", plot:GetAttribute("OwnerUserId"))
	drop.Parent = plot
	table.insert(list, drop)
	Debris:AddItem(drop, 30) -- safety net if it falls off the map
end

task.spawn(function()
	while true do
		for _, plot in (Workspace:WaitForChild("Plots")):GetChildren() do
			if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") then
				for _, d in plot:GetDescendants() do
					if d:IsA("BasePart") and d:HasTag("Dropper") then
						spawnDrop(plot, d)
					end
				end
			end
		end
		task.wait(INTERVAL)
	end
end)
```

Collector: on `Touched`, if the part has a `Value` attribute and its `OwnerUserId` equals the plot's, add the value to the owner's coins, then destroy the part. Ignore anything else. Conveyors: an anchored part with `AssemblyLinearVelocity` set (the classic conveyor trick) moves unanchored drops; verify the behaviour after physics engine updates.

Caching the dropper list on purchase instead of scanning descendants every loop is cheaper once plots grow.

## Offline earnings

```lua
--!strict
local CAP_SECONDS = 8 * 3600
local OFFLINE_RATE = 0.5

local function offlineEarnings(lastSeen: number, now: number, incomePerSecond: number): number
	local elapsed = math.clamp(now - lastSeen, 0, CAP_SECONDS) -- future lastSeen (clock skew) gives 0
	return math.floor(elapsed * incomePerSecond * OFFLINE_RATE)
end

return offlineEarnings
```

Save `lastSeen = os.time()` on leave and on each autosave. Show the result in a welcome-back panel with the cap stated plainly.

## Rebirth

Server checks `coins >= req(rebirths)`, then resets coins and soft upgrades, increments `rebirths`, and keeps pets, gamepasses and Robux purchases. Confirm with the player first in UI, listing exactly what resets.
