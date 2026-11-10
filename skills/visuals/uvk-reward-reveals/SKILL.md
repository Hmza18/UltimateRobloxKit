---
name: uvk-reward-reveals
description: Rarity-driven reward reveals with UltimateVisualsKit's Visuals.Rewards - seven built-in rarity profiles (Common to Secret) that scale anticipation, rays, flash, camera and VFX with rank, single reveals and batches (rarest last, lower tiers grouped), skip, dismiss and cancel handles, custom rarities, and the RewardPanel, RewardPopup and RarityBadge components. Use when showing what a player received from a chest, daily reward, quest, purchase or drop, or when defining a game's rarity tiers and making higher tiers feel more exciting.
license: MIT
metadata:
  category: visuals
  version: 1.0.0
  triggers: [reward reveal, reveal animation, rarity reveal, chest opening, loot reveal, daily reward reveal, legendary reveal, rarity tiers, custom rarity, reward popup, item reveal]
  depends: [uvk-visuals-kit]
---

# UVK reward reveals

Reveals are cosmetic. Call them after the server has granted the reward.

## When to use

- A single reward, or a batch, shown with ceremony that matches its rarity.
- Defining or re-skinning rarity tiers for a game.

When not to use: an egg (`uvk-egg-hatching`, which runs the rarity celebration itself); a small frequent gain such as coins from a tap (`uvk-gameplay-feedback`); deciding what the reward is (server systems).

## Inputs

- The rarity id and the reward `{ name, amount?, icon?, image?, model?, subtitle? }`.
- For world VFX, a `position`; otherwise the reveal is all UI.

## Workflow

1. **Reveal one reward.**

   ```lua
   local handle = Visuals.Rewards:Reveal("Legendary", {
   	name = "Dragon",
   	amount = 1,
   	icon = "pet",                        -- UrkUI icon name; or image = 1234567890, or model = dragonModel
   	subtitle = "From the Fire Egg",
   })
   handle.Completed:Connect(function(dismissed) end)
   ```

2. **Reveal many at once.** Rarest last; tiers below `threshold` (default `"Epic"`) share a staggered grid per rarity, the rest get a full reveal each.

   ```lua
   Visuals.Rewards:Batch({
   	{ rarity = "Common", reward = { name = "Coins", amount = 250 } },
   	{ rarity = "Common", reward = { name = "Gems", amount = 5 } },
   	{ rarity = "Mythic", reward = { name = "Phoenix" } },
   })
   ```

3. **Let the profile do the scaling.** The seven profiles are in [references/rarity-profiles.md](references/rarity-profiles.md): Common is a 1.2 s pop with sparkles; Legendary adds 0.75 s of anticipation, twelve rays, a soft flash, a `SoftImpact` shake, a beam and confetti; Secret runs 3.8 s with a starfield, a cinematic and fireworks. Duration, particle intensity and layer count never decrease with rank.

4. **Options.** `parent`, `position`, `speed`, `skipAnticipation`, `compact`, `skippable` (true), `autoDismiss` (true), `displayOrder` (900), `hint`, `fastForward`, `threshold`, `onDismiss`. `reducedMotion` and `reducedFlashing` default to the settings given to `Visuals:Configure`.

5. **Control.** `handle.skip()` jumps to the settled state and the next call dismisses; `finish()`, `dismiss()`, `cancel()` / `stop()` (nothing left behind), `isRunning()`.

6. **Custom rarities** extend a base and keep the hierarchy readable:

   ```lua
   Visuals.Rewards:RegisterRarity("Divine", { extends = "Mythic", rank = 6.5, color = "#7DF9FF" })
   Visuals.Rewards.rarities()            -- ids, lowest rank first
   Visuals.Rewards.plan("Divine", reward) -- the timeline a reveal would run, for inspection
   ```

   Built-in ids need `override = true`. Invalid profiles raise an error.

7. **Use components for the calm cases.** A claim panel is `Game.RewardPanel` (tiles pop in, then the claim button); a small popup is `Game.RewardPopup`; a tier label is `Game.RarityBadge`. See `uvk-simulator-screens`.

8. **Queue, do not overlap.** If two rewards arrive together, use `Batch`. If a second arrives during a reveal, wait for `Completed`.

## Outputs

- Reveal calls driven by server confirmations, with handles cancelled when the screen closes.
- Custom rarities registered once at client start.

## Validation

```bash
lune run tests/urk/run tests/urk
```

In the kit repository: `cd library && lune run tests/run tests visuals_rewards` (profiles, hierarchy, plans, batches, skip). In Studio (`NEEDS MANUAL REVIEW`): layout and text sizing per device, each reveal style, model previews, input (tap, Enter, gamepad A), reduced flashing on the top tier, and two reveals in quick succession.

## Pitfalls

- **Everything is Legendary.** If common drops get big reveals, rare ones mean nothing. Use `compact = true` or a feedback event for frequent rewards.
- **Colour as the only signal.** Show the rarity label too.
- **Different colours per screen.** Read rarity colours from one place (`Visuals.Themes.color("Legendary")`).
- **Unskippable reveals** in a loop the player repeats. Keep `skippable`.
- **Revealing before the grant.** Wait for the server.
- **Calling `reveal` in a loop.** Use `batch`; it groups, orders and fast-forwards.

## Limitations

- `RewardsLogic` is covered by a Lune spec. `Rewards.luau` and `RewardView.luau` build the overlay and were not run in Studio: layout, safe-area padding, reveal styles and camera calls are unverified.
- Sound cues (`reward.reveal`, `rarity.<name>`, `whoosh`) are silent until the game registers sounds.
- World VFX play only when a `position` is given.
