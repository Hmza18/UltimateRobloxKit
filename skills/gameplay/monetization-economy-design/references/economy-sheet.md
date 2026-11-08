# Economy sheet

Build this as `docs/economy.csv` (or a spreadsheet). Three tables.

## 1. Currencies

| currency | type (soft/premium/token) | tradeable | earned by Robux? | cap |
|---|---|---|---|---|
| Coins | soft | no | yes (packs) | none |
| Gems | premium-ish | no | yes | 1,000,000 |

## 2. Sources and sinks

| currency | flow (source/sink) | name (analytics SKU) | stage | amount per event | events per minute (avg player) | per minute | notes |
|---|---|---|---|---|---|---|---|
| Coins | source | ore_sell | 1 | 5 | 6 | 30 | |
| Coins | source | daily_reward | all | 500 | per day | - | |
| Coins | sink | pick_upgrade_2 | 1 | 600 | once | - | |
| Coins | sink | potion_speed | 2+ | 250 | 0.1 | 25 | consumable sink |

## 3. Stage model

| stage | income/min (free) | income/min (all passes) | next goal | cost | minutes to goal (free) | minutes to goal (passes) | target minutes |
|---|---|---|---|---|---|---|---|
| 1 | 30 | 60 | Pick 2 | 600 | 20 | 10 | 2-5 (fails: lower cost or raise income) |
| 2 | | | | | | | |

Formulas:

- minutes to goal = cost / income per minute
- net flow per minute = sum(sources) - sum(sinks used per minute)
- inflation check: cost(stage n+1) / cost(stage n) >= income(n+1) / income(n)
- stacked multiplier = product of all active multipliers; set a cap and a diminishing formula, for example `effective = 1 + (raw - 1) ^ 0.8`

Review the sheet after every content update and against live economy events weekly.
