# Rewards

Rarity-driven reward reveals. `RewardsLogic` holds the rarity profiles and plans the timeline; `Rewards` builds the overlay UI and runs the plan as a `Core/Sequence`, so every reveal can be skipped, cancelled and cleaned up. Reveals are cosmetic: call them after the server has granted the reward.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)

local handle = Visuals.Rewards:Reveal("Legendary", {
	name = "Dragon",
	amount = 1,
	icon = "pet", -- UrkUI icon name; or image = 1234567890, or model = dragonModel
	subtitle = "From the Fire Egg",
})
handle.Completed:Connect(function(dismissed) end)

Visuals.Rewards:Batch({
	{ rarity = "Common", reward = { name = "Coins", amount = 250 } },
	{ rarity = "Common", reward = { name = "Gems", amount = 5 } },
	{ rarity = "Mythic", reward = { name = "Phoenix" } },
})

Visuals.Rewards:RegisterRarity("Divine", { extends = "Mythic", rank = 6.5, color = "#7DF9FF" })
```

## API

| Function | Result |
|---|---|
| `Rewards.reveal(rarity, reward, options?)` | `Handle`. `reward`: `{ name, amount?, icon?, image?, model?, subtitle? }` |
| `Rewards.batch(rewards, options?)` | `Handle`. Rarest last; rarities below `options.threshold` (default `"Epic"`) share a staggered grid per rarity, the rest get a full reveal each |
| `Rewards.registerRarity(id, profile)` | Registers a custom rarity. `extends` names a base; built-in ids need `override = true`. Errors on invalid data |
| `Rewards.rarity(id)` | The profile (Common's for an unknown id) |
| `Rewards.rarities()` | Ids, lowest rank first |
| `Rewards.plan(rarity, reward?, options?)` | The plan a reveal would run |

Handle: `skip()` (first call jumps to the settled state, the next dismisses), `finish()`, `dismiss()`, `cancel()` / `stop()` (immediate, nothing left behind), `isRunning()`, `Completed` (Signal, `dismissed: boolean`).

Options: `parent`, `position` (plays the profile's VFX in the world there; otherwise everything is UI), `speed`, `skipAnticipation`, `compact`, `skippable` (default true), `autoDismiss` (default true), `displayOrder` (900), `hint`, `fastForward` (true or a factor), `threshold`, `onDismiss`. `reducedMotion` and `reducedFlashing` default to the Host settings.

Input: tap or click on the overlay, Enter, or gamepad A.

## Rarity profiles

| Rarity | Colour | Reveal | Background | Duration | Anticipation | Rays | Flash | Camera | VFX |
|---|---|---|---|---|---|---|---|---|---|
| Common | `#B8C4D0` | pop | none | 1.2 s | 0 | 0 | no | none | SparkleBurst |
| Uncommon | `#5FD35F` | bounce | dim | 1.5 s | 0.15 s | 0 | no | none | SparkleBurst, RewardGlow |
| Rare | `#3FA7FF` | flip | dim | 1.9 s | 0.3 s | 6 | no | none | RarityBurst, RewardGlow, SparkleBurst |
| Epic | `#B45CFF` | burst | rays | 2.4 s | 0.5 s | 8 | soft | Tap shake | RarityBurst, RewardGlow, SparkleBurst |
| Legendary | `#FFC02E` | beam | rays | 2.9 s | 0.75 s | 12 | soft | SoftImpact shake | RarityBeam, RarityBurst, GoldenShine, Confetti |
| Mythic | `#FF4D8D` | shatter | wash | 3.5 s | 1.0 s | 14 | soft | Impact shake, FOV punch | RarityBeam, RarityBurst, GoldenShine, Fireworks, Confetti |
| Secret | `#1B1B2F` | eclipse | starfield | 3.8 s | 1.2 s | 16 | soft | SoftImpact shake, RewardReveal cinematic, FOV punch | RarityBeam, RarityBurst, RewardGlow, GoldenShine, Fireworks, Confetti |

Duration is the time to the settled state; the hold before auto-dismiss (1.2 s to 3 s) comes after it. Duration, particle intensity and layer count never decrease with rank. At most one soft flash per reveal, and only shakes from `Tap`, `SoftImpact`, `Impact`.

Plan options and what they change: `skipAnticipation` reveals at 0; `compact` drops anticipation, rays and camera and halves settle and hold; `reducedMotion` removes shakes, camera moves, the scale punch and ray rotation and shortens the plan; `reducedFlashing` removes the flash; quality `Low` drops optional VFX and halves the rays; `fastForward` compresses time and drops cosmetic steps.

Sound cues played (silent until registered with `Visuals.Audio`): `whoosh`, `reward.reveal`, `rarity.<name>`, `ui.pop` (grid tiles), `ui.close`.

## Performance

The overlay is plain GuiObjects: no textures, no ViewportFrame unless the reward has a `model`. The ray burst is one rotating Frame holding half as many bars as rays. UI spark bursts are capped at 28 frames and scale with the quality profile. Nothing runs when no reveal is open.

## Not verified in Studio

`RewardsLogic` is covered by `tests/visuals_rewards.spec.luau` (19 tests). `Rewards.luau` and `RewardView.luau` create Instances and were NOT run in Studio: layout, text sizing, safe-area padding, the reveal styles, model previews, input handling and the camera calls are `NEEDS MANUAL REVIEW`. They pass StyLua, Selene and `luau-lsp` with Roblox types.
