# Analytics

A safe front end for Roblox `AnalyticsService`. Your code logs economy, funnel, onboarding, progression and custom events. The system checks each one against the documented limits, keeps funnel steps in order for each player, samples players, rate-limits, drops duplicates and sends events in batches. `AnalyticsLogic` is pure and holds every rule. `AnalyticsServer` sends the batches to `AnalyticsService`, wrapping each call in `pcall`. In Studio it prints them instead, because Roblox records analytics only in published experiences.

## AnalyticsService API used (checked against the creator docs on 2026-11-08)

| Kit event | AnalyticsService call | Verified |
| --- | --- | --- |
| `economy` | `LogEconomyEvent(player, flowType: Enum.AnalyticsEconomyFlowType, currencyType, amount, endingBalance, transactionType, itemSku?, customFields?)` | yes, reference page |
| `funnel` | `LogFunnelStepEvent(player, funnelName, funnelSessionId?, step?, stepName?, customFields?)` | yes |
| `onboarding` | `LogOnboardingFunnelStepEvent(player, step, stepName?, customFields?)` | yes |
| `progression` Start | `LogProgressionStartEvent(player, progressionPathName, level, levelName?, customFields?)` | yes |
| `progression` Complete | `LogProgressionCompleteEvent(...)`, same arguments | yes |
| `progression` Fail | `LogProgressionFailEvent(...)`, same arguments | yes |
| `custom` | `LogCustomEvent(player, eventName, value? = 1, customFields?)` | yes |
| not wrapped | `LogProgressionEvent(player, path, Enum.AnalyticsProgressionType, ...)`, `LogJourneyEvent`, `GetPlayerSegmentsAsync` | listed in the reference, not used |

Custom field keys are `Enum.AnalyticsCustomFieldKeys.CustomField01.Name` to `CustomField03.Name`, which are the strings `"CustomField01"` to `"CustomField03"`. Their values must be strings. The deprecated `Fire*Event` methods are not used.

Documented limits that the defaults follow: 3 custom fields, 8,000 combined custom field values (beyond that they show as "Other"), 10 economy resource types, 10 funnels, 100 steps per funnel, 100 custom event names, 20 transaction types and 100 item SKUs (beyond those they show as "Other"), and a global budget of `120 + 20 * CCU` requests per minute (`serverBudgetPerMinute`). The progression path cap (10) is a kit choice, because the docs give no number.

## AnalyticsLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `validateConfig(config?)` | `Settings` | errors on bad numbers, sample rates or rate options |
| `new(config?, now?)` | `State` | |
| `track(state, event, now, rng?)` | `(ok, reason?)` | the whole pipeline, see below |
| `validate(settings, event, now)` | `(Event?, reason?)` | a clean copy with no unknown keys |
| `normalizeFields(settings, raw)` | `(Fields?, reason?)` | `{ "a", 2 }` or `{ CustomField01 = "a" }` become string values |
| `checkName(settings, value, label?)` | `reason?` | |
| `dedupeKey(event)` | `string` | |
| `shouldFlush(state, now)` | `boolean` | when a batch is full or `flushInterval` has passed |
| `flush(state, sink, now)` | `(count, err?)` | always empties the queue; a failing batch is not retried |
| `tick(state, sink, now)` | `(count, err?)` | prunes dedupe entries, then flushes when due |
| `prune(state, now)` | | |
| `funnelProgress(state, userId, funnel?)` | `{ sessionId, step }?` | no funnel name means onboarding |
| `endFunnel(state, userId, funnel)` | | the next step 1 starts a new session |
| `forgetPlayer(state, userId)` | | flush first, because queued events stay |
| `serverBudgetPerMinute(ccu)` | `number` | `120 + 20 * ccu` |
| `memorySink()` | `{ events, batches, write }` | for tests |

The `track` pipeline runs these steps in order: validate, sample, order check, distinct-name cap, dedupe, queue cap and rate limit, then queue. A drop for "rate limited" or "queue full" still moves the funnel forward, because the step happened in the game, so the next step stays valid.

Event tables have `kind` and `userId`, plus the fields for their kind:

| kind | fields |
| --- | --- |
| `economy` | `flow` (`"Source"` or `"Sink"`), `currency`, `amount` (> 0), `balance` (>= 0), `transaction`, `sku?` |
| `funnel` | `funnel`, `step` (1 to 100), `stepName?`, `sessionId?` |
| `onboarding` | `step`, `stepName?` |
| `progression` | `path`, `status` (`"Start"`, `"Complete"` or `"Fail"`), `level` (whole number >= 1), `levelName?` |
| `custom` | `name`, `value?` (default 1) |
| any kind | `fields?`, up to 3 custom field values |

Drop reasons are `invalid event`, `invalid kind`, `invalid user`, `invalid <field>` (for example `invalid currency`, `invalid amount`, `invalid step`, `invalid fields`), `possible personal data`, `sampled out`, `funnel not started`, `duplicate step`, `skipped step`, `wrong session`, `too many names`, `duplicate`, `queue full` and `rate limited`. Each drop is counted in `state.stats.dropped[reason]`.

Funnel rules: step 1 starts a session, with a generated id `<sessionPrefix><n>` unless you pass `sessionId`. Each later step must be exactly the previous step plus 1. Repeating a step, going back to an earlier step or skipping a step is rejected, except that step 1 again after step 2 or later starts a new session. Onboarding runs once per player and cannot restart.

## Config (`AnalyticsLogic.Config`, passed as `logic`)

| Key | Default | Meaning |
| --- | --- | --- |
| `maxNameLength` | 50 | characters in names and labels, which must match `^[%w][%w _%-%.:]*$` |
| `maxFieldLength` | 50 | characters in a custom field value |
| `maxAmount` | 1e12 | largest amount, balance or custom value (absolute) |
| `maxLevel` | 10000 | |
| `maxSteps` | 100 | documented steps per funnel |
| `maxCustomNames` / `maxFunnels` / `maxCurrencies` / `maxPaths` | 100 / 10 / 10 / 10 | distinct names per server session; new names past the cap are dropped |
| `batchSize` | 20 | |
| `flushInterval` | 5 | seconds |
| `maxQueue` | 1000 | |
| `dedupeWindow` | 1 | seconds; 0 turns dedupe off |
| `coalesceCustom` | false | sums identical custom events (same user, name and fields) within one batch |
| `rejectLongNumbers` | true | rejects text with 7 or more digits in a row |
| `rate` | `{ capacity = 30, refillPerSecond = 0.5 }` | per player, using `Util/RateLimiter` |
| `sampleRates` | `{}` (all 1) | per kind, 0 to 1; decided once per player and kind, so funnels are never cut in half |
| `sessionPrefix` | `"s"` (the server adapter uses a random hex prefix) | |

`AnalyticsServer.new(config?)` config: `logic?`, `sink?` (default `serviceSink()`, or `debugSink()` in Studio), `debugInStudio = true`, `hasConsent(player) -> boolean?`, `tickInterval = 1`, `enabled = true`.

## Server API and events

`track(player, event)`, `logEconomy(player, flow, currency, amount, balance, transaction, sku?, fields?)`, `logFunnelStep(player, funnel, step, stepName?, fields?, sessionId?)`, `logOnboardingStep(player, step, stepName?, fields?)`, `logProgression(player, path, status, level, levelName?, fields?)`, `logCustom(player, name, value?, fields?)`, `endFunnel(player, funnel)`, `flush()` and `destroy()`. Every log method returns `(ok, reason?)`.

Event: `Dropped(player, reason)`, which is useful in Studio for spotting events with mistakes.

The server flushes when a player leaves (every AnalyticsService call needs a Player), on `BindToClose` and on `destroy`.

## Example

```luau
local AnalyticsServer = require(Kit.Systems.Analytics.AnalyticsServer)
local analytics = AnalyticsServer.new({ logic = { sampleRates = { custom = 0.25 } } })

analytics:logOnboardingStep(player, 1, "Spawned")
analytics:logFunnelStep(player, "Shop", 1, "Opened")
analytics:logEconomy(player, "Sink", "Coins", 50, 150, "Shop", "Sword", { "Weapon" })
analytics:logProgression(player, "World1", "Complete", 3, "Lava Cave")
analytics:logCustom(player, "MonsterDefeated", 1, { "Slime", "Level - 4" })

-- With the Currency system:
CurrencyServer.new({
	currency = { currencies = { Coins = {} } },
	onTransaction = function(player, entry)
		local flow = if entry.delta > 0 then "Source" else "Sink"
		analytics:logEconomy(player, flow, entry.currency, math.abs(entry.delta), entry.balance, "Gameplay", entry.tag)
	end,
})
```

`entry.tag` must pass the name rules (for example `shop:Sword` passes).

## Privacy

- Never put personal information in names or fields. That includes usernames, display names, chat text, emails, phone numbers and anything typed by the player. Names allow only letters, digits, space, `_ - . :`, which rules out `@`. Text with 7 or more digits in a row is rejected as a likely id or phone number. These are guard rails, not a guarantee, so review what you log.
- User ids are only used as the Player handle and as internal keys. Generated session ids do not contain them.
- The kit sends nothing off-platform. A custom `sink` that forwards data outside Roblox (with HttpService) must follow the Roblox Terms of Use and the privacy laws that apply to you, which may require consent and age-appropriate handling. Pass `hasConsent` to skip players who have not consented. Whether Roblox's first-party analytics needs extra consent in your region is a decision for you and your counsel. This module does not decide it.

## Limitations

- Distinct-name caps, dedupe, coalescing and funnel order are per server and per session. Two servers do not share them, and a rejoining player starts a new onboarding record. For cross-session onboarding, persist the step yourself.
- Funnel order does not survive a server restart. Pass your own `sessionId` and persist the step when that matters.
- The per-player rate limit does not enforce the global `120 + 20 * CCU` budget. Use `serverBudgetPerMinute` to size `rate`.
- A failing batch is dropped and counted in `stats.sinkErrors`. It is not retried.

## Needs a Studio playtest (and a published place)

Lune covers `AnalyticsLogic` in `tests/sys_analytics.spec.luau`. Not verified: the `AnalyticsService` calls themselves (Studio does not record them, so check the Analytics dashboard of a published place, where data can take up to 24 hours), the Enum values, flushing on `PlayerRemoving`, the `BindToClose` flush and the debug sink output.
