---
name: roblox-audio
description: Sound in Roblox - Sound, SoundGroup and SoundService, the newer Audio API (AudioPlayer, AudioEmitter, AudioListener, AudioDeviceOutput and Wire) with a status caveat, music playlists and crossfades, spatial 3D audio, SFX pooling, player volume settings, preloading and audio asset permissions and privacy. Use when adding music, sound effects, ambience or volume sliders, or when sounds do not play, are silent for others, or cut out.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [sound, soundgroup, soundservice, music, sfx, audioplayer, audioemitter, audiolistener, spatial audio, volume slider, audio permission]
  depends: [luau-language, roblox-architecture, roblox-data-persistence]
---

# Roblox audio

## When to use

- Background music with playlists and crossfades per area or game state.
- Sound effects: UI clicks, footsteps, hits, pickups, positional ambience.
- Volume settings saved per player.
- Debugging silent sounds, sounds only one player hears, or "asset is not approved" errors.

When not to use: licensing and crediting third-party sounds (see `roblox-publishing-liveops`), voice chat moderation policy, animation-driven footstep timing (markers are in `roblox-animation`).

## Inputs

- Audio asset ids (`rbxassetid://...`) that the experience is allowed to use.
- A list of sound categories (Music, SFX, UI, Ambience) to map to groups.

## Workflow

1. **Create one SoundGroup per category** under `SoundService` (`Music`, `SFX`, `UI`, `Ambience`) and set every `Sound.SoundGroup`. Player volume sliders change `SoundGroup.Volume` only.
2. **Choose where sounds live.**
   - Positional (3D): parent the `Sound` to a `BasePart` or `Attachment`; tune `RollOffMode`, `RollOffMinDistance`, `RollOffMaxDistance`.
   - Non-positional (music, UI): parent to `SoundService` or a client container, or use `SoundService:PlayLocalSound(sound)` for UI clicks.
3. **Play on the client when only one player should hear it** (UI, music, local feedback). A Sound played by the server replicates to all clients.
4. **Preload important sounds** with `ContentProvider:PreloadAsync({ sound })` on the client during loading.
5. **Pool short SFX** that fire often (footsteps, gun shots) instead of creating and destroying Sounds each time.
6. **Save volume settings** in the player profile (see `roblox-data-persistence`), sent via a validated remote, applied on join.
7. **Check asset permissions**: an audio asset must be public/shared for use or owned by the experience owner (user or group) and granted to the experience. Check creator docs (Audio assets > permissions) for current rules.

### Music manager with crossfade, SFX pool and volume groups (client)

```luau
--!strict
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local function group(name: string): SoundGroup
	local g = SoundService:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	local ng = Instance.new("SoundGroup")
	ng.Name = name
	ng.Parent = SoundService
	return ng
end

local Groups = { Music = group("Music"), SFX = group("SFX"), UI = group("UI") }

local Audio = {}

-- Volume settings: 0..1, applied to groups only.
function Audio.setVolume(category: "Music" | "SFX" | "UI", volume: number)
	Groups[category].Volume = math.clamp(volume, 0, 1)
end

-- Music: two Sounds alternate so one can fade out while the next fades in.
local musicA = Instance.new("Sound")
local musicB = Instance.new("Sound")
for _, s in { musicA, musicB } do
	s.SoundGroup = Groups.Music
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
end
local current, idle = musicA, musicB
local FADE = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

function Audio.playMusic(assetId: string, volume: number?)
	if current.SoundId == assetId and current.IsPlaying then
		return
	end
	idle.SoundId = assetId
	idle.TimePosition = 0
	idle.Volume = 0
	idle:Play()
	TweenService:Create(idle, FADE, { Volume = volume or 0.5 }):Play()
	local fadingOut = current
	local out = TweenService:Create(fadingOut, FADE, { Volume = 0 })
	out.Completed:Once(function()
		fadingOut:Stop()
	end)
	out:Play()
	current, idle = idle, current
end

-- SFX pool: reuse Sounds per asset id, up to a cap of simultaneous voices.
type Pool = { free: { Sound }, template: Sound, live: number }
local pools: { [string]: Pool } = {}
local MAX_VOICES = 8

function Audio.registerSfx(name: string, assetId: string, volume: number)
	local template = Instance.new("Sound")
	template.SoundId = assetId
	template.Volume = volume
	template.SoundGroup = Groups.SFX
	pools[name] = { free = {}, template = template, live = 0 }
	task.spawn(function()
		ContentProvider:PreloadAsync({ template })
	end)
end

-- parent: a BasePart or Attachment for 3D sound, or nil for 2D.
function Audio.playSfx(name: string, parent: Instance?, pitch: number?)
	local pool = pools[name]
	if not pool or pool.live >= MAX_VOICES then
		return
	end
	local s = table.remove(pool.free) or pool.template:Clone()
	s.PlaybackSpeed = pitch or (0.95 + math.random() * 0.1)   -- slight variation
	s.Parent = parent or SoundService
	pool.live += 1
	s.Ended:Once(function()
		pool.live -= 1
		s.Parent = nil
		table.insert(pool.free, s)
	end)
	s:Play()
end

return Audio
```

### Newer Audio API (AudioPlayer, Wires)

The Audio API models sound as a graph: an `AudioPlayer` produces audio, `Wire` instances connect it (`SourceInstance` to `TargetInstance`) to effects (`AudioFader`, `AudioEqualizer`, `AudioReverb`, ...) and to outputs: an `AudioEmitter` on a part for 3D sound heard by `AudioListener`s, or an `AudioDeviceOutput` for 2D sound. It also powers voice chat (`AudioDeviceInput`). Use it when you need effect chains, routing or voice processing; keep `Sound` for simple cases. Its feature set and some properties are still expanding; verify property names and status in creator docs.

```luau
--!strict
-- 2D music through the Audio API (client). Verify names in creator docs.
local player = Instance.new("AudioPlayer")
player.Asset = "rbxassetid://0"      -- placeholder id
player.Looping = true
local fader = Instance.new("AudioFader")
fader.Volume = 0.5
local out = Instance.new("AudioDeviceOutput")

local function wire(a: Instance, b: Instance)
	local w = Instance.new("Wire")
	w.SourceInstance = a
	w.TargetInstance = b
	w.Parent = b
end

for _, inst in { player, fader, out } do
	inst.Parent = game:GetService("SoundService")
end
wire(player, fader)
wire(fader, out)
player:Play()
```

### Privacy and permissions

- Uploaded audio is private to its owner by default; group experiences need the audio uploaded to (or shared with) the group.
- Other creators' audio works only if they made it available for use; otherwise it is silent with an Output warning.
- Uploads are moderated and subject to monthly upload limits; verify current limits in creator docs.
- Licensed music from the Creator Store's audio library can be used in experiences per its terms; do not upload copyrighted music you do not have rights to.

## Outputs

- `SoundGroup`s under SoundService, an `AudioController` client module, a sound id config table, saved volume settings.

## Validation

1. Play: Output has no "Failed to load sound" or permission warnings.
2. Move sliders: the right category changes and nothing else.
3. Test > Clients and Servers: a server-played 3D sound is heard by both clients near the source, a client-played UI sound only by that client.
4. Fire 50 SFX in a second: voices are capped, no Sound instances accumulate (Explorer or `#SoundService:GetDescendants()`).
5. Walk away from a positional sound; it fades out by `RollOffMaxDistance`.

## Pitfalls

- **Silent sound**: not `Playing`, `Volume` 0, group volume 0, wrong parent (a part not in Workspace), or missing permission.
- **Server-played UI sounds** reach every player; play UI and music on the client.
- **Creating a new Sound per footstep** churns memory; pool them.
- **Setting `Sound.Volume` from sliders** fights crossfades; use groups.
- **`Ended` never fires** for looped sounds; do not pool looped sounds this way.
- **Too many simultaneous 3D sounds** cost CPU on mobile; cap voices and stop distant ambience.

## Limitations

- Audio API classes and properties are evolving; the sketch above must be checked against creator docs.
- Permission and privacy rules for audio assets change; this skill cannot check an asset's permission state without Studio or Open Cloud.
- Real loudness and mix balance need ears and real devices, not code review.
