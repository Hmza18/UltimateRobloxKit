---
name: monetization-economy-design
description: Designs ethical Roblox monetization and balanced in-game economies - game passes, developer products, experience subscriptions, private servers, Premium Payouts and immersive or rewarded ads, disclosed odds for paid random items, no pay-to-win pressure or dark patterns, child-safety awareness; sources and sinks spreadsheets, inflation control, price ladders, AnalyticsService custom, economy and funnel events, A/B testing and KPIs such as D1/D7 retention, session length and ARPDAU with honest interpretation. Use when planning what to sell, setting prices, balancing currencies, instrumenting analytics or reading live metrics.
license: MIT
metadata:
  category: gameplay
  version: 1.0.0
  triggers: [monetization, game pass, developer product, robux pricing, economy balance, sources and sinks, inflation, analyticsservice, retention, arpdau, a/b test, paid random items]
  depends: [roblox-inventory-economy, game-design-core, roblox-security-anti-exploit]
---

# Monetization and economy design

## When to use

- Deciding what to sell and how much, before building a shop.
- Currency inflation, worthless rewards, or players stuck with nothing to spend on.
- Adding analytics or reading KPI dashboards after launch.

When not to use: inventory, purchase-receipt and currency code (use `roblox-inventory-economy`), shop screens (use `roblox-ui-systems`), event scheduling and update rollout (use `roblox-publishing-liveops`).

## Inputs

- GDD with loops and progression table (`game-design-core`).
- Audience age range and whether PvP exists.
- Current Roblox monetization policies, Community Standards and the paid random items rules; read them in the creator docs before finalising, they change and vary by region.

## Ethics rules (non-negotiable)

1. **No pay-to-win against other players.** Purchases may save time or add cosmetics, convenience or extra content; they must not decide PvP outcomes.
2. **Every gameplay goal reachable for free** in reasonable time.
3. **Paid random items** (crates, eggs bought with Robux, or with currency bought with Robux) must show odds before purchase, and must follow Roblox's current policy and regional restrictions; verify in creator docs. Prefer direct purchase or pity systems that guarantee outcomes.
4. **No dark patterns:** no fake countdowns, fake "only 2 left", confirm-shaming ("No, I like losing"), pre-selected bundles, hidden prices, misleading "free" labels, or prompts during tense gameplay.
5. **Child safety:** many players are minors. Do not pressure purchases, mention parents' cards, use gambling imagery, or reward spending socially (no "big spender" public shaming or flexing boards for Robux spent).
6. **Clear value:** the player knows exactly what they get, permanent or consumable, before the prompt.

## Workflow

1. **Choose the products.**
   | Product | Use for | Notes |
   |---|---|---|
   | Game pass | Permanent perks: cosmetics slot, 2x soft currency, VIP area, extra pet slot | Check with `MarketplaceService:UserOwnsGamePassAsync` on the server; cache per session |
   | Developer product | Consumables: currency packs, boosts, revives | Grant only in `MarketplaceService.ProcessReceipt`, idempotent by `PurchaseId`, return `PurchaseGranted` only after saving |
   | Experience subscription | Monthly perks (daily stipend, cosmetic track) | Verify current API (`GetUserSubscriptionStatusAsync`) and payout rules |
   | Private servers | Play with friends privately | Price low or free for social games |
   | Premium Payouts | Engagement-based earnings from Premium members | Earned by playtime; reward good retention, not grind |
   | Ads | Rewarded video or immersive ads where eligible | Opt-in only, never forced; eligibility is age and region gated, verify |
   Regional pricing and price optimization tools exist in the Creator Dashboard for some product types; verify current availability.
2. **Price ladder.** 3-5 tiers per currency pack, each tier with a modest bonus (for example 0%, 10%, 20%, 30%). Anchor with a mid tier as the best value for most players. Starter pack: one-time, clear, cheap. Keep game pass prices consistent across similar perks.
3. **Economy map.** List every currency, its **sources** (where it enters) and **sinks** (where it leaves) in [references/economy-sheet.md](references/economy-sheet.md). Model income per minute at each progression stage and the cost of the next goal.
4. **Inflation control.** Costs should grow at least as fast as income across the progression; add meaningful sinks (upgrades, cosmetics, rebirth resets, consumables, trading tax); avoid uncapped multipliers stacking (2x pass x boost x pet x rebirth). Cap or diminish stacked multipliers. Track total currency in circulation per active player daily.
5. **Instrument analytics** with `AnalyticsService` on the server (names as of 2026; verify in creator docs):

   ```lua
   --!strict
   -- ServerScriptService/Analytics.lua
   local AnalyticsService = game:GetService("AnalyticsService")

   local Analytics = {}

   function Analytics.currencyEarned(player: Player, currency: string, amount: number, balance: number, source: string)
   	AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, currency,
   		amount, balance, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, source)
   end

   function Analytics.currencySpent(player: Player, currency: string, amount: number, balance: number, itemSku: string)
   	AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, currency,
   		amount, balance, Enum.AnalyticsEconomyTransactionType.Shop.Name, itemSku)
   end

   function Analytics.onboardingStep(player: Player, step: number, name: string)
   	AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
   end

   function Analytics.funnelStep(player: Player, funnel: string, sessionId: string, step: number, name: string)
   	AnalyticsService:LogFunnelStepEvent(player, funnel, sessionId, step, name)
   end

   function Analytics.custom(player: Player, eventName: string, value: number?)
   	AnalyticsService:LogCustomEvent(player, eventName, value or 1)
   end

   return Analytics
   ```

   Log on the server only, after the change is committed. Keep event and SKU names stable (`snake_case`); there are limits on unique names and custom fields, verify.
6. **A/B tests.** One hypothesis, one variable, a primary metric and a guardrail (for example: price of the starter pack; primary = conversion; guardrail = D7 retention). Assign by stable hash of `UserId` (or the Creator Dashboard experiments tool where available, verify). Decide sample size and duration (at least a full week to cover weekday effects) before starting; do not stop early on a good day.
7. **KPIs and honest reading.**
   | KPI | Meaning | Read with |
   |---|---|---|
   | D1 / D7 / D30 retention | Share of new players returning on day N | Cohort by install date and source; small cohorts swing wildly |
   | Session length | Average time per session | Long sessions can mean confusion or grind; pair with funnel |
   | ARPDAU | Revenue / daily active users | Rises when you lose non-payers too; check DAU |
   | Payer conversion | Share of DAU that buys | Watch for pressure tactics creeping in |
   | ARPPU | Revenue / paying users | A few large spenders skew it |
   Compare against your own previous weeks, not rumoured platform averages. Note events, updates, holidays and featuring that coincide with changes. Correlation is not causation.

## Outputs

- `docs/monetization.md`: product list, prices, ethics checklist ticked.
- `docs/economy.csv` (from the sheet) with sources, sinks and stage model.
- `ServerScriptService/Analytics.lua` and an event naming list.
- Experiment briefs in `docs/experiments/<name>.md` with results.

## Validation

1. Ethics checklist above: every item true, reviewed by a second person.
2. Economy sheet: for each stage, minutes to next goal for a free player within the GDD targets; with all passes, still not trivial.
3. Purchase tests in Studio (test purchases are free in Studio): grants once, survives rejoin, repeated `ProcessReceipt` calls do not double grant.
4. Analytics: events appear in the Creator Dashboard after a test session (there is a delay; verify).
5. A/B results: report effect size with confidence interval and sample size, or say "inconclusive".

## Pitfalls

- Granting developer products outside `ProcessReceipt` or before saving: lost or duplicate purchases.
- Multiplier stacking that makes currency meaningless within a week.
- Selling the fun away: a pass that skips the core loop.
- Reading a revenue spike from an update as proof a price change worked.
- Changing prices often; players notice and trust drops.

## Limitations

- Policies on paid random items, ads, subscriptions and payouts change and differ by region; always verify in creator docs.
- Cannot forecast revenue; models are for balancing, not promises.
- Analytics API names and dashboard features evolve; verify before shipping.
- Not legal or financial advice.
