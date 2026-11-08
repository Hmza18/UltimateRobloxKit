---
name: lighting-atmosphere
description: Sets up Roblox lighting and mood - Lighting service technology (Future, ShadowMap, Voxel), Atmosphere, Sky, Clouds, post-processing effects, time-of-day and day-night cycles, light budgets for shadow-casting lights, consistent colour and material palettes, and ready presets for day, night, interior, horror and stylized-bright looks. Includes a Luau day-night cycle module synced across clients. Use when a scene looks flat, dark, washed out or inconsistent, when adding a day-night cycle, or when tuning lighting performance on mobile.
license: MIT
metadata:
  category: environments
  version: 1.0.0
  triggers: [lighting, atmosphere, skybox, day night cycle, clocktime, bloom, colorcorrection, fog, mood, future lighting, shadowmap]
  depends: [map-world-building, roblox-performance]
---

# Lighting and atmosphere

## When to use

- Choosing the look of a map or zone, or making zones feel distinct.
- Adding a day-night cycle, weather mood, or interior/exterior transitions.
- Fixing scenes that are too dark, foggy, blown out or slow on phones.

When not to use: particles, beams and effects (use `roblox-vfx`), map layout (use `map-world-building`), lighting for Blender renders (use a Blender skill).

## Inputs

- Art direction: stylized or realistic, reference mood images (described in words).
- Target devices; mobile share decides the light budget.
- Whether time of day changes, and whether players go indoors.

## Workflow

1. **Pick the technology** in `Lighting.Technology`:
   - `Future`: per-pixel lights with shadows from local lights, best for interiors and night scenes. Lower graphics levels fall back automatically.
   - `ShadowMap`: sun/moon shadows, local lights unshadowed. Good default for outdoor daytime games.
   - `Voxel`: cheapest, coarse shadows. `Legacy` and `Compatibility` are deprecated and map to Voxel.
   Players on low graphics quality see a reduced version whatever you pick, so test at quality 1.
2. **Set the base Lighting properties**: `ClockTime`, `GeographicLatitude`, `Brightness` (sun intensity, 1-3 typical), `Ambient` (unlit indoor fill, keep dark), `OutdoorAmbient` (sky fill), `EnvironmentDiffuseScale` and `EnvironmentSpecularScale` (sky reflections onto PBR, 0.5-1 for realistic, lower for flat stylized), `ExposureCompensation`, `GlobalShadows = true`, `ShadowSoftness`.
3. **Atmosphere** (child of Lighting) replaces old `FogStart`/`FogEnd` for outdoors: `Density` (0.25-0.4 typical), `Offset`, `Color`, `Decay`, `Glare`, `Haze`. Fog properties are ignored while an Atmosphere exists.
4. **Sky**: a `Sky` under Lighting with six `Skybox*` faces, or keep the default procedural sky; `SunAngularSize`, `MoonAngularSize`, `StarCount`, `CelestialBodiesShown`.
5. **Clouds**: a `Clouds` instance under `Workspace.Terrain` with `Cover`, `Density`, `Color`. Requires Terrain; animate `Cover` slowly for weather.
6. **Post effects** (children of Lighting or the Camera): `ColorCorrectionEffect` (Brightness, Contrast, Saturation, TintColor), `BloomEffect` (Intensity, Size, Threshold), `SunRaysEffect`, `DepthOfFieldEffect`, `BlurEffect` (menus only). A `ColorGradingEffect` with tonemapper choices was added more recently; verify in creator docs before relying on it. Use one ColorCorrection per mood, swap by tweening, never stack many.
7. **Apply a preset** from [references/presets.md](references/presets.md), then tune by eye with a fixed test camera and a grey character.
8. **Palette and materials.** Keep one palette: 2 dominant hues, 1 accent for interactives, neutrals for ground. Interactive objects should be the most saturated or emissive thing in view. Use the same `MaterialVariant`s across zones and vary lighting, not materials, to separate moods.
9. **Light budget.** Local lights (`PointLight`, `SpotLight`, `SurfaceLight`) with `Shadows = true` are the expensive ones under Future. Rules of thumb (verify on your target devices):
   - At most about 4-8 shadow-casting local lights visible at once; 0-2 on mobile-heavy games.
   - Keep `Range` small (8-24 studs); large ranges overlapping many parts cost more.
   - Fake fill with unshadowed lights, `Neon` parts or `SurfaceLight`s with Shadows off.
   - Disable lights in streamed-out or far zones; turn off flicker scripts when not visible.
10. **Interiors.** Lower `Ambient`, add one key light per room plus bounce fill. When the player enters, tween `ExposureCompensation` up slightly and Atmosphere `Density` down, from a client zone trigger.
11. **Day-night cycle** with the module below. The server only publishes the cycle start time; each client computes the clock, so there is no per-frame replication.

### Day-night cycle module

```lua
--!strict
-- ReplicatedStorage/Shared/DayNight.lua
-- Server: DayNight.publish(600). Client: local stop = DayNight.run(DayNight.defaultKeys())
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type Key = {
	clock: number, -- 0..24
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	exposure: number,
	atmosphereColor: Color3,
	atmosphereDensity: number,
}

local DayNight = {}

function DayNight.publish(cycleSeconds: number, startClock: number?)
	assert(RunService:IsServer(), "publish is server only")
	Lighting:SetAttribute("CycleSeconds", cycleSeconds)
	Lighting:SetAttribute("CycleStartClock", startClock or 8)
	Lighting:SetAttribute("CycleEpoch", Workspace:GetServerTimeNow())
end

local function lerpKey(a: Key, b: Key, t: number): Key
	return {
		clock = a.clock + (b.clock - a.clock) * t,
		brightness = a.brightness + (b.brightness - a.brightness) * t,
		ambient = a.ambient:Lerp(b.ambient, t),
		outdoorAmbient = a.outdoorAmbient:Lerp(b.outdoorAmbient, t),
		exposure = a.exposure + (b.exposure - a.exposure) * t,
		atmosphereColor = a.atmosphereColor:Lerp(b.atmosphereColor, t),
		atmosphereDensity = a.atmosphereDensity + (b.atmosphereDensity - a.atmosphereDensity) * t,
	}
end

-- keys must be sorted by clock ascending; wraps from the last key to the first.
function DayNight.sample(keys: { Key }, clock: number): Key
	local n = #keys
	for i = 1, n do
		local a = keys[i]
		local b = keys[i % n + 1]
		local bClock = if i == n then b.clock + 24 else b.clock
		local c = if clock < a.clock and i == n then clock + 24 else clock
		if c >= a.clock and c < bClock then
			return lerpKey(a, b, (c - a.clock) / (bClock - a.clock))
		end
	end
	return keys[1]
end

function DayNight.clockNow(): number?
	local cycle = Lighting:GetAttribute("CycleSeconds")
	local epoch = Lighting:GetAttribute("CycleEpoch")
	local start = Lighting:GetAttribute("CycleStartClock")
	if typeof(cycle) ~= "number" or typeof(epoch) ~= "number" or typeof(start) ~= "number" then
		return nil
	end
	local elapsed = Workspace:GetServerTimeNow() - epoch
	return (start + (elapsed % cycle) / cycle * 24) % 24
end

function DayNight.run(keys: { Key }, hz: number?): () -> ()
	assert(RunService:IsClient(), "run is client only")
	local interval = 1 / (hz or 10)
	local accumulator = interval
	local conn = RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0
		local clock = DayNight.clockNow()
		if not clock then
			return
		end
		local k = DayNight.sample(keys, clock)
		Lighting.ClockTime = clock
		Lighting.Brightness = k.brightness
		Lighting.Ambient = k.ambient
		Lighting.OutdoorAmbient = k.outdoorAmbient
		Lighting.ExposureCompensation = k.exposure
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			atmosphere.Color = k.atmosphereColor
			atmosphere.Density = k.atmosphereDensity
		end
	end)
	return function()
		conn:Disconnect()
	end
end

function DayNight.defaultKeys(): { Key }
	local rgb = Color3.fromRGB
	return {
		{ clock = 0, brightness = 0.5, ambient = rgb(20, 22, 40), outdoorAmbient = rgb(40, 45, 80), exposure = 0, atmosphereColor = rgb(60, 70, 110), atmosphereDensity = 0.35 },
		{ clock = 6, brightness = 1.5, ambient = rgb(60, 45, 40), outdoorAmbient = rgb(150, 110, 90), exposure = 0, atmosphereColor = rgb(230, 160, 120), atmosphereDensity = 0.35 },
		{ clock = 12, brightness = 2.5, ambient = rgb(70, 70, 70), outdoorAmbient = rgb(130, 130, 140), exposure = 0, atmosphereColor = rgb(200, 215, 235), atmosphereDensity = 0.28 },
		{ clock = 18, brightness = 1.5, ambient = rgb(60, 40, 45), outdoorAmbient = rgb(160, 100, 90), exposure = 0, atmosphereColor = rgb(240, 140, 110), atmosphereDensity = 0.35 },
	}
end

return DayNight
```

Gameplay that depends on night (spawns, shop hours) should read `DayNight.clockNow()` on the server, never trust a client clock.

## Outputs

- Lighting, Atmosphere, Sky, Clouds and post effects configured in the place (or as Rojo `.model.json` under `Lighting`).
- `ReplicatedStorage/Shared/DayNight.lua` plus a server call to `publish` and a client call to `run`.
- A short `docs/lighting.md` noting the preset, palette hex values and light budget.

## Validation

1. Screenshot the same three fixed camera spots at clock 6, 12, 18 and 0; check readability of characters and interactives.
2. Test at graphics quality 1 and 10 and in the Device Emulator for a low-end phone; interactives must remain visible at quality 1.
3. Count shadow-casting lights per view: run `#` over `workspace:GetDescendants()` filtered to `Light` with `Shadows`, within a radius of the camera.
4. Check client MicroProfiler frame time with and without post effects.
5. Run two clients: the clock must match within a fraction of an hour.

## Pitfalls

- Setting `ClockTime` on the server every frame floods replication; publish an epoch instead.
- Extreme `Brightness` plus Bloom makes UI-like neon unreadable; cap Bloom `Intensity` around 0.5-1.
- `Ambient` too bright flattens interiors; most mood comes from contrast.
- Atmosphere `Density` near 1 hides the map on mobile view distances and looks like a bug.
- Pure black nights frustrate players; keep `OutdoorAmbient` high enough to navigate and give light sources.
- Horror games: darkness is not tension. Use pools of light, sound and sightlines; keep a brightness option.

## Limitations

- Cannot see the result; all values need checking by eye in Studio on real devices.
- Graphics quality fallbacks and the exact cost of lights vary by device and engine version; measure.
- Newer effects and properties (for example colour grading options) may change; verify in creator docs.
