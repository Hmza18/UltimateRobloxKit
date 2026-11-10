# Audio

Sound cues by name. The kit bundles no sounds and references no asset ids: every module plays cues such as `coin` or `egg.crack`, and a cue is silent until the game registers a sound for it.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

Visuals:Configure({ sounds = { coin = 1234567890 } }) -- your own asset ids
Visuals.Audio:Register("tap", { id = "rbxassetid://1234567891", volume = 0.4, pitchVariance = 0.12 })
Visuals.Audio:Play("coin")
Visuals.Audio:SetVolume("ui", 0.5)
```

## API

| Function | Use |
|---|---|
| `Audio.register(cue, idOrOptions)` | An id (number, `"123"`, `"rbxassetid://123"`) or `{ id, volume, pitch, pitchVariance, cooldown, maxConcurrent, group }`. nil removes the cue. Errors on invalid input |
| `Audio.registerMany(map)` | Cue to id or options |
| `Audio.play(cue, options?)` | `Handle?`; nil when the cue is unregistered, cooling down, at its concurrency limit or muted. Options: `volume`, `pitch`, `pitchVariance`, `force`, `at` (BasePart or Attachment for a positional sound) |
| `Audio.stop(handle)` / `Audio.stopAll()` | |
| `Audio.setVolume(group or nil, volume)` | Group volume, or master when group is nil |
| `Audio.mute(bool)` / `Audio.isMuted()` | |
| `Audio.cues()` | The cue names the kit plays |
| `Audio.registered()` / `Audio.isRegistered(cue)` | |

Defaults: volume 0.6, pitch 1, pitchVariance 0, cooldown 0.03 s, maxConcurrent 4, group `ui` for `ui.*` cues and `sfx` otherwise. Pitch variation is deterministic per cue and play count.

## Cues the kit plays

`ui.hover`, `ui.press`, `ui.pop`, `ui.close`, `tap`, `coin`, `gem`, `error`, `success`, `whoosh`, `impact`, `egg.land`, `egg.wobble`, `egg.energy`, `egg.crack`, `egg.reveal`, `rarity.common`, `rarity.uncommon`, `rarity.rare`, `rarity.epic`, `rarity.legendary`, `rarity.mythic`, `rarity.secret`, `reward.reveal`, `level.up`, `quest.complete`, `pet.happy`, `food.throw`, `food.hit`.

Use sounds you have the rights to.

## Performance

Up to 12 Sound instances are pooled in a `UVKSounds` folder under SoundService and routed through a `UVK` SoundGroup with one child group per volume group. A sound is released on `Sound.Ended`, with a clock timer as a fallback.

## Not verified in Studio

`AudioLogic` is covered by `tests/visuals_audio.spec.luau` (9 tests). `Audio.luau` creates Sound and SoundGroup instances and was NOT run in Studio: playback from a Folder under SoundService, nested SoundGroup volumes, pooling and the release timing are `NEEDS MANUAL REVIEW`.
