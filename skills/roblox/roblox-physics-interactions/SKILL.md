---
name: roblox-physics-interactions
description: Physics and world interaction in Roblox - assemblies and network ownership, mover and mechanical constraints (AlignPosition, AlignOrientation, LinearVelocity, HingeConstraint, PrismaticConstraint), collision groups with PhysicsService:RegisterCollisionGroup, ProximityPrompt, Tools, raycasts, shapecasts and spatial queries such as GetPartBoundsInBox, and server validation of client-driven interactions. Use when building doors, pickups, vehicles, carried objects, hit detection or anything players touch.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [network ownership, constraint, alignposition, linearvelocity, hingeconstraint, collision group, proximityprompt, raycast, shapecast, getpartboundsinbox, tool, hitbox]
  depends: [luau-language, roblox-networking, roblox-security-anti-exploit]
---

# Roblox physics and interactions

## When to use

- Doors, levers, pickups, carryable crates, moving platforms, simple vehicles.
- Melee or projectile hit detection, area damage, triggers.
- Physics jitter, parts flying away, or exploiters moving objects they should not.

When not to use: character animation (use `roblox-animation`), NPC movement (use `roblox-npc-ai`), full anti-cheat design (use `roblox-security-anti-exploit`), destruction VFX (use `roblox-vfx`).

## Inputs

- Which parts move and who should simulate them (server, or the interacting player's client for responsiveness).
- The interaction list: trigger (prompt, touch, tool click), validation rules (distance, cooldown, ownership), and result.

## Workflow

1. **Know your assemblies.** Parts joined by welds or rigid constraints form one assembly with one root part and one network owner. Check `part.AssemblyRootPart` and `part:GetNetworkOwner()` (server only).
2. **Set ownership deliberately.** Server-owned (`SetNetworkOwner(nil)`) for anything that matters to fairness: NPCs, loot, doors. Player-owned (`SetNetworkOwner(player)`) for a vehicle the player drives, accepting that they can move it freely. Anchored parts have no owner.
3. **Move with constraints, not CFrame writes every frame**, for physical objects. Use `CFrame`/`PivotTo` or `TweenService` only for anchored parts.

   | Goal | Constraint |
   | --- | --- |
   | Pull toward a point | `AlignPosition` (Mode OneAttachment, `MaxForce`, `Responsiveness`) |
   | Hold a rotation | `AlignOrientation` |
   | Constant velocity | `LinearVelocity` (`VectorVelocity`, `MaxForce`), `AngularVelocity` |
   | Door, wheel | `HingeConstraint` (ActuatorType Servo or Motor) |
   | Slider, elevator | `PrismaticConstraint` |
   | Springy, rope | `SpringConstraint`, `RopeConstraint` |
   | Rigid join | `WeldConstraint` |

4. **Use collision groups** for "players pass through other players", "NPCs ignore debris" and so on. Register them once on the server.
5. **Gate interactions** with `ProximityPrompt` (`Triggered` fires on the server with the player) or a Tool's `Activated`. Always re-validate on the server.
6. **Detect hits with queries**: `workspace:Raycast`, `workspace:Spherecast`/`Blockcast`/`Shapecast` for thick sweeps, `GetPartBoundsInBox`/`GetPartBoundsInRadius`/`GetPartsInPart` for areas. Prefer queries over `Touched` for gameplay.

### Collision groups, a prompt-driven door and a server-validated hitbox

```luau
--!strict
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

-- 1. Collision groups (server, once at startup)
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Debris")
PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
PhysicsService:CollisionGroupSetCollidable("Debris", "Players", false)

local function setGroup(model: Model, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		setGroup(char, "Players")
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end)
	end)
end)

-- 2. Door on a servo hinge, opened by a ProximityPrompt
local function setupDoor(door: Model)
	local hinge = door:FindFirstChildWhichIsA("HingeConstraint", true) :: HingeConstraint
	local prompt = door:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt
	hinge.ActuatorType = Enum.ActuatorType.Servo
	hinge.ServoMaxTorque = 1e6
	hinge.AngularSpeed = 4
	prompt.ActionText = "Open"
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = true
	local open = false
	prompt.Triggered:Connect(function(_player: Player)
		-- the prompt already checked distance on the server; add key checks here
		open = not open
		hinge.TargetAngle = if open then 90 else 0
		prompt.ActionText = if open then "Close" else "Open"
	end)
end

for _, door in workspace:WaitForChild("Doors"):GetChildren() do
	if door:IsA("Model") then
		setupDoor(door)
	end
end

-- 3. Melee hitbox computed on the server from the server's view of the attacker
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local SWING_COOLDOWN = 0.5
local lastSwing: { [Player]: number } = {}

local function swing(player: Player): { Humanoid }
	local now = os.clock()
	if now - (lastSwing[player] or 0) < SWING_COOLDOWN then
		return {}
	end
	lastSwing[player] = now

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then
		return {}
	end
	overlap.FilterDescendantsInstances = { char }
	local boxCFrame = root.CFrame * CFrame.new(0, 0, -3)   -- 3 studs in front
	local parts = workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(5, 5, 4), overlap)

	local hit: { [Humanoid]: true } = {}
	local result = {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not hit[hum] then
			hit[hum] = true
			table.insert(result, hum)
		end
	end
	return result
end

Players.PlayerRemoving:Connect(function(p)
	lastSwing[p] = nil
end)

return { swing = swing }
```

Wire `swing` to a validated remote or `Tool.Activated` (server-side `Activated` fires on the server for tools with `ManualActivationOnly = false`). Clients may predict hits for instant feedback, but damage is applied only from the server's result.

### Validating client-driven interactions

- **Distance**: compare the server-side character position to the target; allow a small latency margin (a few studs).
- **Cooldown**: server timestamps per player per action.
- **Ownership**: the item, door key or vehicle belongs to this player.
- **Line of sight**: one server raycast for ranged interactions.
- **Projectile hits reported by a client**: check the claimed hit position is near the target's server position and along a plausible path from the shooter; reject otherwise.

### Tools

- A `Tool` in the backpack with a part named `Handle` (or `RequiresHandle = false`). Events: `Equipped`, `Unequipped`, `Activated`, `Deactivated`.
- Put the gameplay logic in a server `Script` inside the tool or in a central service listening to tools; LocalScripts only for aiming and effects.

## Outputs

- Collision group setup in a server service, interaction handlers, hitbox helpers, constraint-based props.

## Validation

1. Studio: Model tab > Collision Groups editor shows the registered groups and the matrix you expect.
2. Studio Settings > Physics > "Are Owners Shown" colors parts by network owner; confirm loot and NPCs show as server-owned.
3. Test > Clients and Servers with 2 players: each interaction works from both clients and is visible to the other.
4. From a client command bar, try moving a server-owned part (`part.Position += Vector3.new(0, 50, 0)`): other clients and the server do not see it move.
5. Constraint props settle without jitter; turn on Constraint Details visualization to check attachments.

## Pitfalls

- **Writing CFrame every frame on an unanchored part** fights the physics solver and jitters. Use `AlignPosition` or anchor it.
- **`Touched` for damage** fires many times, misses fast objects and can be triggered by exploiters moving their character. Use queries with cooldowns.
- **Forgetting new parts** (accessories, tools) when setting collision groups; listen to `DescendantAdded`.
- **Ownership flipping** when players walk near server objects: set ownership explicitly with `SetNetworkOwner(nil)`, which also disables automatic changes.
- **Massive `MaxForce` with high `Responsiveness`** launches assemblies; tune forces to the mass (`AssemblyMass`).
- **The old `PhysicsService:CreateCollisionGroup` / `SetPartCollisionGroup`** are deprecated; use `RegisterCollisionGroup` and `BasePart.CollisionGroup`.

## Limitations

- The physics solver is non-deterministic across clients; replicated physics is approximate and latency-dependent.
- Hit validation reduces cheating but cannot prove a client's view; tune tolerances with playtests.
- Collision group count is limited (verify the current limit in creator docs).
