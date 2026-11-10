# Tapping and clicker simulators

A family of games (several share near-identical names, as one guide warns, G41) with one loop: tap to earn currency, buy eggs, equip pets that multiply each tap, rebirth for a permanent multiplier (Documented, G40, G41, G44).

**Evidence strength: thin.** Guides describe the loop, not the presentation. Source ids are in [../sources.md](../sources.md). No game in the family was played and no code was inspected.

## UI structure

- **Documented.** Clicking or tapping anywhere on the map earns currency in at least one title (G43). The whole screen is the button.
- **Documented.** Main screens across the family: tapping, egg hatching, pets, worlds, rebirth, leaderboards (G40, G41 and store descriptions summarised with them).
- **Documented (unofficial FAQ).** One title lists 13 pet rarity tiers (G42). Long ladders need more than colour to stay distinguishable.
- **Assumed.** HUD: one very large currency counter at the top centre, a prominent rebirth button with progress toward the next rebirth, side buttons for pets and shop, and an auto-tap toggle.
- **Assumed.** On mobile the tap area avoids the thumbstick and jump zones, or movement is secondary. The platform guidance to keep important UI out of the bottom corners applies (P15).

## UI animation

- **Assumed.** Each tap spawns a floating "+N" at or near the touch point that rises and fades (estimate 400 to 700 ms), with slight random horizontal offset so repeated numbers do not overlap.
- **Assumed.** The counter pulses on each increment; at high tap rates pulses are merged, otherwise the counter would never rest.
- **Assumed.** The rebirth button idles with a slow pulse or shine once affordable. This matches the platform's guidance that movement draws attention and should be used in moderation (P21).

## VFX

- **Assumed.** Tap feedback is 2D (popup, ring, small sparkle at the touch point), not 3D particles, because it fires many times per second.
- **Assumed.** Rebirth and world unlock get a full-screen moment: flash or radial burst, confetti, large text.

## Animation and game feel

- **Assumed.** Response is on the same frame as the input. The number shown is predicted locally and reconciled with the server value.
- **Assumed.** Feedback escalates with streak or multiplier: larger numbers, warmer colour, stronger pulse, capped so it stays readable.
- **Assumed.** No camera shake per tap; at most a tiny scale punch on the tapped object.

## Technical inferences

All **Assumed**.

- Tap popups come from a pool of labels with a hard cap; the oldest is recycled when the cap is reached. Forum guidance is to cap and merge floating indicators because text rendering is not cheap (F08).
- Taps are batched to the server at intervals; the client shows the optimistic total.
- Auto-tap uses the same feedback path at a lower visual rate.

## Reusable principles

1. Feedback for an action repeated many times per second must be cheap, pooled, capped and mergeable.
2. Respond on the input frame; never wait for the server to show the first sign of success.
3. Escalate feedback with value, with a ceiling.
4. Idle motion is reserved for the one thing the player should do next.
5. Save full-screen effects for rare milestones.

## Sources

G40, G41, G42, G43, G44, P15, P21, F08. See [../sources.md](../sources.md).
