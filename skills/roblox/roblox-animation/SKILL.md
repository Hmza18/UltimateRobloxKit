---
name: roblox-animation
description: Animation in Roblox - the Animator on Humanoid or AnimationController, loading and playing AnimationTracks, priorities and blending, keyframe markers with GetMarkerReachedSignal, R15 vs R6, animation upload and ownership rules, TweenService for props and UI, procedural animation on PreRender/RenderStepped vs Heartbeat, and the pointer to Blender export. Use when adding character or NPC animations, attack timing, door or prop motion, or when animations do not play or replicate.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [animation, animator, animationtrack, loadanimation, keyframe marker, tweenservice, r15, animationcontroller, procedural animation, ui animation, button animation, tween ui]
  depends: [luau-language, blender-roblox-export]
---

# Roblox animation

## When to use

- Playing character emotes, attack swings, tool idles, NPC walk cycles.
- Syncing gameplay to animation moments (hit frame, footstep sound).
- Moving props (doors, platforms, collectibles) or UI smoothly.
- Procedural motion: head look-at, bobbing, recoil, spinning pickups.

When not to use: authoring or exporting rigs and clips from Blender (use `blender-roblox-export`), physical movement with constraints (use `roblox-physics-interactions`), camera motion (use `roblox-camera-input`).

## Inputs

- Animation asset ids (`rbxassetid://...`) owned by the same user or group that owns the experience.
- The rig type: R15, R6, or a custom rig with an `AnimationController`.

## Workflow

1. **Find the Animator.** Characters: `Humanoid.Animator` (created automatically for player characters). NPCs and props: add an `Animator` under the `Humanoid` or under an `AnimationController`.
2. **Decide who plays it.**
   - The local player's own character: play on the client; the Animator replicates it to everyone.
   - NPCs: play on the server (replicates), or on each client for many NPCs to save server work.
3. **Load once, play many times.** Cache `Animator:LoadAnimation(animation)` results per character; loading every time leaks tracks (there is a cap of loaded tracks per Animator).
4. **Set priority and looping** in the Animation Editor when publishing, or at runtime with `track.Priority` and `track.Looped`. Priorities from low to high: `Core`, `Idle`, `Movement`, `Action`, `Action2`, `Action3`, `Action4`.
5. **Name markers** in the Animation Editor (for example `Hit`, `Footstep`) and connect with `track:GetMarkerReachedSignal("Hit")`.
6. **Animate anchored props and UI with TweenService**; animate unanchored physics props with constraints.
7. **Procedural visual motion** goes on the client in `RunService.PreRender` (formerly `RenderStepped`); gameplay logic stays on `Heartbeat` (`PostSimulation`) on the server.

### Character animation controller with markers

```luau
--!strict
-- Client: src/client/Controllers/CombatAnimController.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ANIMS = {
	Swing = "rbxassetid://0",      -- placeholder: replace with an animation your experience owner owns
	Block = "rbxassetid://0",
}

type Tracks = { [string]: AnimationTrack }

local player = Players.LocalPlayer
local tracks: Tracks = {}
local hitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SwingHit") :: RemoteEvent

local function loadTracks(character: Model)
	table.clear(tracks)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator
	for name, id in ANIMS do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		tracks[name] = track
	end
	-- The marker tells the server "the swing reached its hit frame";
	-- the server still computes the hitbox itself (see roblox-physics-interactions).
	tracks.Swing:GetMarkerReachedSignal("Hit"):Connect(function()
		hitRemote:FireServer()
	end)
end

local function playSwing()
	local track = tracks.Swing
	if track and not track.IsPlaying then
		track:Play(0.05, 1, 1.2)   -- fadeTime, weight, speed
	end
end

player.CharacterAdded:Connect(loadTracks)
if player.Character then
	task.spawn(loadTracks, player.Character)
end

return { playSwing = playSwing }
```

### TweenService for props

```luau
--!strict
local TweenService = game:GetService("TweenService")

local function bob(part: BasePart)
	-- Anchored collectible: bob up and down forever, server or client.
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(part, info, { CFrame = part.CFrame * CFrame.new(0, 1, 0) })
	tween:Play()
	return tween
end
```

Tween a `Model` by tweening a `CFrameValue` and calling `model:PivotTo(value.Value)` on `Changed`, or tween the anchored primary part with welded, unanchored children. Run cosmetic tweens on the client to keep server replication light.

### Procedural animation

```luau
--!strict
local RunService = game:GetService("RunService")

local spinning: { BasePart } = {}
RunService.PreRender:Connect(function(dt: number)
	for _, part in spinning do
		part.CFrame *= CFrame.Angles(0, dt * math.pi, 0)  -- client-only visual, anchored part
	end
end)
```

- Make motion frame-rate independent: multiply by `dt`, and smooth with `alpha = 1 - math.exp(-speed * dt)`.
- For head look-at or aim offsets, modify `Motor6D.Transform` in `RunService.PreSimulation`, which runs after animations are applied each frame (check the task scheduler page in creator docs for the current order), or use an `IKControl` instance for built-in IK.

### R15 vs R6 and ownership

- R15 has 15 parts and supports layered clothing, IKControl and most catalog animations. R6 has 6 parts and simpler, retro motion. An animation made for one rig type does not play correctly on the other. Set the avatar type in Game Settings > Avatar.
- An animation only plays in an experience if it is owned by the experience owner (the user, or the group for group games). Upload animations to the group for group games. Animations from other creators fail to load; check Output for asset permission warnings. Rules around sharing animations may change; verify current permission options in creator docs.
- Blender clips are exported per the `blender-roblox-export` skill and imported with the Animation Editor or the 3D Importer, then published.

### UI motion

UI animation in kit projects goes through presets, not ad-hoc tweens. Presets are pure data in `library/src/UI/Core/MotionPresets.luau` (`MotionPresets.get(name)`, `names()`, `sample(preset, t)` for tests); `Runtime/Motion.play(instance, presetName, options?)` plays one and returns a stop function (options: `onDone`, `fromCurrent`, `speed`, `loop`; `Motion.stop(instance)`, `Motion.isPlaying(instance)`).

| Moment | Preset |
|---|---|
| Hover / leave, press / release | `hover`, `unhover`, `press`, `release` |
| Window or popup open / close | `open`, `close` |
| Element appears, lands | `popIn`, `bounce` |
| Number counts up | `count` (CurrencyCounter does this) |
| Reward reveal, item gained | `reveal`, `acquire` |
| Purchase confirmed | `purchase` |
| Card selected, tab change | `select`, `tabSwitch` |
| Toast in / out | `toastIn`, `toastOut` |
| Bar fill | `progress` |
| Needs attention (badge, claim) | `attention`, `wiggle`, `shine` (looping) |

```lua
local Motion = require(URK.UI.Runtime.Motion)
local stop = Motion.play(claimButton, "attention")              -- loops until stopped
claimButton.Activated:Connect(function()
	stop()
	Motion.play(rewardIcon, "reveal", { onDone = showAmount })
end)
```

- **Reduced motion**: `UrkUI.setReducedMotion(true)` or the engine setting; `Motion.play` jumps to the last key and skips looping presets, so state must be readable from the final frame alone.
- **Budgets**: feedback within 100 ms (`press` is 0.08 s); transitions 0.12-0.35 s (`fast`, `normal`, `slow` tokens); celebratory reveals under 1 s; at most a few looping `attention` effects per screen.
- Starting a preset on an instance cancels the previous one; never stack your own tweens on the same object. Component presets are tuned in `design/tokens/styles.json` `motion` (see `roblox-design-system`); performance notes in `roblox-ui-performance`.

## Outputs

- Animation id table in shared config, per-character animation controllers, prop tween helpers.

## Validation

1. Play: Output shows no "Failed to load animation" or asset permission errors.
2. Test > Clients and Servers with 2 players: player A's animation is visible on player B's screen.
3. Marker callbacks fire once per play (print in the handler).
4. Developer Console > Memory: animation track count does not grow after respawning several times.
5. Lower the frame rate cap (Studio Settings > Rendering > Frame rate manager or test on a slow device): procedural motion keeps the same speed.

## Pitfalls

- **Using `Humanoid:LoadAnimation`**: deprecated; use the `Animator`.
- **Loading tracks every time you play** leaks tracks and eventually stops new ones loading.
- **Wrong priority**: an `Action` swing shows only on the upper body or gets overridden by walk; raise priority or adjust weights.
- **Playing the local player's animation from the server** adds latency; play from the client.
- **Animation owned by another account** silently fails in the live game but may work in your own Studio session.
- **Tweening unanchored parts** fights physics; anchor them or use constraints.
- **`RenderStepped` on the server** errors; it is client-only. Use `Heartbeat` there.

## Limitations

- Ownership, sharing and moderation rules for animation assets change; confirm in creator docs before shipping.
- The exact ordering of `PreAnimation`, `PreSimulation` and Motor6D updates should be verified in creator docs for advanced procedural rigs.
- Cannot preview animations without Studio; validation needs a playtest.
