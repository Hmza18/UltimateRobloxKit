# VFX recipes

## Emitter property cheat sheet

| Property | Typical burst | Typical aura |
|---|---|---|
| `Rate` | 0 (use `Emit`) | 5-20 |
| `Lifetime` | `NumberRange.new(0.2, 0.5)` | `NumberRange.new(1, 2)` |
| `Speed` | `NumberRange.new(10, 25)` | `NumberRange.new(0.5, 2)` |
| `SpreadAngle` | `Vector2.new(180, 180)` | `Vector2.new(10, 10)` |
| `Size` | NumberSequence 1 -> 0 | NumberSequence 0.5 -> 1 -> 0 |
| `Transparency` | 0 -> 1 | 1 -> 0.3 -> 1 |
| `LightEmission` | 0.5-1 (glowy) | 0.2-0.6 |
| `Drag` | 3-6 (sparks slow down) | 0 |
| `Shape` | `Enum.ParticleEmitterShape.Sphere` | `Box` or `Cylinder` |

## Screen hit flash (client)

```lua
--!strict
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local function getGrade(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild("HitGrade")
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing
	end
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = "HitGrade"
	created.Parent = Lighting
	return created
end

local grade: ColorCorrectionEffect = getGrade()

local BASE = { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }
local flashInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function hitFlash()
	grade.TintColor = Color3.fromRGB(255, 120, 120)
	grade.Saturation = -0.3
	grade.Contrast = 0.15
	TweenService:Create(grade, flashInfo, BASE):Play()
end

return hitFlash
```

## Trail toggle for a dash

```lua
--!strict
local function setDashTrail(character: Model, on: boolean)
	local root = character:FindFirstChild("HumanoidRootPart")
	local trail = root and root:FindFirstChild("DashTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = on
	end
end
return setDashTrail
```

Build the trail once: two Attachments on `HumanoidRootPart` (one at +Y 1, one at -Y 1), Trail `Attachment0/1` set, `Lifetime = 0.25`, `WidthScale` 1 -> 0, `FaceCamera = true`.

## Beam lightning between two points

Use a Beam with `Segments = 1` per chunk and jitter intermediate Attachments each frame for 0.15 s, then hide. Keep 4-6 chunks; more segments means more vertices with little visible gain.

## Local-only post-processing

Parent a post-processing effect to `Workspace.CurrentCamera` instead of `Lighting` when only one player should see it (for example a blur behind a menu). Effects under the camera are not replicated.
