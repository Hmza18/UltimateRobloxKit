---
name: roblox-vfx
description: Visual effects in Roblox - ParticleEmitter (Emit bursts, flipbooks), Beam, Trail, Attachments, Highlight, and Lighting post-processing (Bloom, ColorCorrection, DepthOfField, SunRays), spawned on clients from server events, pooled, and kept inside mobile budgets. Use when adding hit sparks, explosions, auras, trails, beams, outlines, screen grading or any particle effect.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [vfx, particle, particleemitter, beam, trail, highlight, bloom, colorcorrection, flipbook, explosion effect, post-processing]
  depends: [roblox-networking, roblox-performance]
---

# Roblox VFX

## When to use

- Hit sparks, muzzle flashes, explosions, pickups, level-up bursts, auras.
- Beams (lasers, tethers, lightning), Trails (swords, dashes, projectiles).
- Highlight outlines for selection or targets, and Lighting post-processing for mood.

**Check the kit's preset library first.** If the project has the kit's `Visuals` module (UltimateVisualsKit), most effects below already exist as presets with budgets, quality levels and cleanup: read `uvk-vfx-presets` and search `catalog/visuals.json` before authoring an emitter by hand. Use this skill for effects the library lacks and for understanding the engine objects underneath.

When not to use: sounds belong in `roblox-audio`; animated rigs in `roblox-animation`; camera shake in `roblox-camera-input`; gameplay hit detection in `roblox-physics-interactions` (VFX never decides a hit).

## Inputs

- What triggers the effect (server event, local input, state change) and who must see it.
- Target devices (mobile lowers every budget below).
- Texture asset ids (flipbook sheets must be square power-of-two, laid out as 2x2, 4x4 or 8x8).

## Workflow

1. **Author templates once.** Build each effect as a folder or Part under `ReplicatedStorage.VFX` with Attachments holding emitters, beams and trails. Set emitters `Enabled = false` and `Rate = 0` for burst-only effects.
2. **Server announces, client renders.** The server fires one remote (or sets an attribute) with the minimum data: effect name and position or target instance. Each client spawns visuals locally. Never create particles on the server for one-shot effects; that replicates every instance to every client.
3. **Use `Emit(n)` for bursts**, `Enabled` for continuous effects. `Emit` respects the emitter's own properties and costs nothing until called.
4. **Pool** frequently used effects (see code). Re-parenting and toggling is far cheaper than `Clone` + `Destroy` every hit.
5. **Flipbooks:** set `FlipbookLayout` (`Enum.ParticleFlipbookLayout.Grid4x4` etc.), `FlipbookMode` (`Loop`, `OneShot`, `PingPong`, `Random`) and `FlipbookFramerate`. `OneShot` plays the sheet once over the particle's lifetime.
6. **Beams/Trails** need two Attachments (`Attachment0`, `Attachment1`). For a trail, put the attachments on the moving part and set `Lifetime` short (0.1-0.4 s). For beams set `Segments` low (1 for straight lasers, 10-20 for curves via `CurveSize0/1`).
7. **Highlight**: parent to (or `Adornee`) a Model. Only a limited number of Highlights render at once (31 as documented at time of writing; verify in creator docs), so reuse one Highlight and move its `Adornee`.
8. **Post-processing** lives in `Lighting` (or `Camera` for a local-only effect): `BloomEffect`, `ColorCorrectionEffect`, `DepthOfFieldEffect`, `SunRaysEffect`, `BlurEffect`. Tween them on the client for hit flashes or menus, and keep a base state to restore.
9. **Budget for mobile** (rule of thumb, measure on device): under ~500 live particles on screen, fewer than ~10 continuously emitting emitters per player, `LightEmission` instead of many overlapping transparent layers, and `Lifetime` as short as reads well.

### Client effect player with pooling

```lua
--!strict
-- StarterPlayerScripts/VfxPlayer.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local templates = ReplicatedStorage:WaitForChild("VFX") :: Folder
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayVfx") :: RemoteEvent

local POOL_SIZE = 8
local pools: { [string]: { BasePart } } = {}
local cursor: { [string]: number } = {}

local container = Instance.new("Folder")
container.Name = "ClientVFX"
container.Parent = Workspace

local function buildPool(name: string): { BasePart }?
	local template = templates:FindFirstChild(name)
	if not template or not template:IsA("BasePart") then
		warn("Unknown VFX", name)
		return nil
	end
	local list = {}
	for i = 1, POOL_SIZE do
		local copy = template:Clone()
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Transparency = 1
		copy.Parent = container
		list[i] = copy
	end
	pools[name] = list
	cursor[name] = 0
	return list
end

local function play(name: string, cframe: CFrame)
	local list = pools[name] or buildPool(name)
	if not list then
		return
	end
	local index = (cursor[name] % #list) + 1 -- round-robin reuse
	cursor[name] = index
	local part = list[index]
	part.CFrame = cframe
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local count = (d:GetAttribute("EmitCount") :: number?) or 10
			d:Emit(count)
		end
	end
end

remote.OnClientEvent:Connect(function(name: unknown, position: unknown)
	if typeof(name) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	-- Skip effects far from the camera: nobody sees them, and they cost fill rate.
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > 250 then
		return
	end
	play(name, CFrame.new(position))
end)
```

Server side, one line per event: `PlayVfx:FireAllClients("HitSpark", hitPosition)`. For a nearby-only effect, loop players and `FireClient` those within range.

More recipes (screen flash, trail toggle, beam lightning, emitter property cheat sheet): [references/vfx-recipes.md](references/vfx-recipes.md).

## Outputs

- `ReplicatedStorage.VFX` templates, one client VFX player script, one server-to-client remote.
- Optional `Lighting` post-processing objects with a documented base state.

## Validation

1. Play Solo, then **Test > Clients and Servers** with 2+ clients: every client sees the burst once, the server's Workspace has no particle instances added at runtime.
2. Developer Console (F9) > Memory: `GraphicsParticles` should stay flat during repeated effects (no leak from un-destroyed clones).
3. MicroProfiler (Ctrl+Alt+F6 to toggle, verify the shortcut in Studio) during a heavy fight: look for `Particles` and `Render` costs.
4. Studio device emulator at a low-end phone profile, then a real phone if available.

## Pitfalls

- **Effect plays twice**: both the server and client spawn it. Pick one (client).
- **Particles visible through walls / sorting wrong**: adjust `ZOffset`, or lower `LightEmission`, which renders additively.
- **Trail never appears**: attachments on the same position, or `Lifetime` 0, or the part never moves.
- **Flipbook shows the whole sheet**: `FlipbookLayout` left at `None`.
- **Effect emitted at old position**: emitters emit in world space at the current attachment position; set `CFrame` before `Emit`.
- **Bloom blows out UI-heavy scenes**: keep `BloomEffect.Threshold` high (around 0.9-1.0) and `Intensity` modest.
- **Highlight limit**: extra highlights silently stop rendering; reuse one per purpose.
- **`Debris:AddItem` for every hit** creates GC churn; pool instead.

## Limitations

- Particle counts and costs above are guidance, not engine guarantees; only device profiling proves a budget.
- This skill does not author textures or flipbook sheets; it consumes uploaded asset ids. The kit's generated VFX textures are described in `docs/workflows/visual-assets.md`.
- Exact Highlight and particle limits change between engine releases; verify in creator docs.
