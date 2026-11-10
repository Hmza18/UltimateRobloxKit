# Visuals.Screens

Reusable, configurable, animated screen templates. Every screen is built only from the UrkUI Game
components (`UI/Game`), the active style's tokens, `Visuals.UI` animations and the other Visuals
modules, so it follows the style or theme you give it.

Screens raise **intents** and show what they are told. They never decide a gameplay result,
charge a price or grant a reward: a button press becomes a Signal, your code asks the server, and
you call `screen:update(...)` (or a method such as `spin(index)`) with the answer.

```lua
local Visuals = require(ReplicatedStorage.UltimateRobloxKit.Visuals.Visuals)
local Screens = Visuals.Screens

local daily = Screens.create("DailyRewards", {
	parent = playerGui,
	style = "vibrant",
	days = { "100 Coins", "250 Coins", { text = "Rare Egg", icon = "egg-color", premium = true } },
	today = 2,
})
daily.Claimed:Connect(function(day)
	ClaimDaily:FireServer(day)                 -- the server grants the reward
end)
DailyClaimed.OnClientEvent:Connect(function()
	daily:update({ claimed = true })           -- the tick pops in, the button turns off
end)
daily:open()
```

## Files

| File | Runs in | Purpose |
|---|---|---|
| `Screens.luau` | Roblox client | `create`, `names`, `register`, `describe`, `registry` |
| `ScreensData.luau` | anywhere (pure) | The 25 screens as data: kind, props, intents, methods, usage; the registry |
| `ScreensLogic.luau` | anywhere (pure) | Layout maths, prop validation, per-screen view models, focus order, animation choice |
| `ScreenKit.luau` | Roblox client | Shared runtime: root, window frame, tabs, card grids, open / close, focus, cleanup |
| `<Name>.luau` | Roblox client | One file per screen, loaded on first use |

## API

| Call | Result |
|---|---|
| `Screens.create(name, props)` | A Screen. Errors with every problem when `props` do not match the screen's definition (missing, mistyped or unknown props) |
| `Screens.names()` | Names that can be created, in build order, then registered game screens |
| `Screens.has(name)` | Whether `create` knows the name |
| `Screens.describe(name)` | The registry entry: description, params, usage, and `data` with the full prop, intent and method lists |
| `Screens.register(name, builder, metadata)` | Adds a game screen (or replaces a built-in one) |
| `Screens.registry` | `Core/Registry` of kind `screen`; also listed by `Visuals.Presets` |
| `Screens.Logic`, `Screens.Data`, `Screens.Kit` | The modules above |

A Screen:

| Member | Meaning |
|---|---|
| `screen.Instance` | The ScreenGui (or the root Frame when `parent` is a GuiObject or ScreenGui) |
| `screen:open()` / `screen:close()` | Play the entrance / exit through `Visuals.UI`; `Closed` fires when the exit finished |
| `screen:isOpen()` | |
| `screen:update(partial)` | Merge props and redraw what changed. Checked like `create` |
| `screen:destroy()` | Trove cleanup: instances, connections, clock jobs, running animations. Safe to call twice |
| `screen.<Intent>` | One Signal per intent in the table below (`Selected`, `Confirmed`, `Claimed`, `Closed` ...) |
| `screen.Intent` | A Signal that fires `(name, ...)` for every intent |
| `screen:<method>(...)` | The screen's own methods, listed below |

Props every screen accepts: `parent` (PlayerGui by default; a ScreenGui or GuiObject embeds the
screen), `style` (UrkUI style name), `theme` (Visuals theme id, used when no style is given),
`displayOrder`, `startOpen`, `insets` (`{ top, left, right, bottom }`, only needed when embedding)
and `input` (`"mouse"`, `"touch"`, `"gamepad"`; detected by default).

## Screens

All 25 planned screens exist. "Implemented, not run in Studio" means the file is complete and
passes the static checks, its pure half is covered by Lune specs, and nothing that creates
Instances has been executed.

| # | Screen | Kind | Status | Intents | Methods |
|---|---|---|---|---|---|
| 1 | `PetSelection` | fullscreen | implemented, not run in Studio | `Selected(id)`, `Confirmed(id)`, `Closed()` | `select(id)`, `confirm()`, `selected()` |
| 2 | `EggHatching` | window | implemented, not run in Studio | `Selected(eggId)`, `HatchRequested(eggId, count)`, `AutoToggled(eggId, on)`, `Closed()` | `hatch(config)` |
| 3 | `RewardReveal` | overlay | implemented, not run in Studio | `Claimed(rewards)`, `Closed()` | `skip()` |
| 4 | `TappingHud` | hud | implemented, not run in Studio | `Tapped(position)`, `Selected(id)`, `RebirthRequested()` | `reward(amount, currencyId?, from?)`, `counter(currencyId)` |
| 5 | `AnimalInteraction` | sheet | implemented, not run in Studio | `Selected(foodId)`, `ThrowRequested(foodId)`, `Closed()` | `react(kind, context?)` |
| 6 | `PetInventory` | window | implemented, not run in Studio | `Selected(id)`, `EquipRequested(id)`, `UnequipRequested(id)`, `FilterChanged(filter)`, `Closed()` |  |
| 7 | `Shop` | window | implemented, not run in Studio | `Purchased(id, price)`, `Selected(id)`, `TabChanged(id)`, `Closed()` |  |
| 8 | `PremiumShop` | window | implemented, not run in Studio | `Purchased(id, price)`, `Confirmed(id)`, `Closed()` |  |
| 9 | `DailyRewards` | window | implemented, not run in Studio | `Claimed(day)`, `Closed()` |  |
| 10 | `SpinWheel` | window | implemented, not run in Studio | `SpinRequested()`, `Landed(index)`, `Claimed(index)`, `Closed()` | `spin(index, options?)`, `isSpinning()` |
| 11 | `QuestLog` | window | implemented, not run in Studio | `Claimed(id)`, `TabChanged(id)`, `Closed()` |  |
| 12 | `Achievements` | window | implemented, not run in Studio | `Selected(id)`, `Closed()` |  |
| 13 | `Settings` | window | implemented, not run in Studio | `Changed(key, value, values)`, `Closed()` | `values()` |
| 14 | `Leaderboard` | window | implemented, not run in Studio | `TabChanged(id)`, `Closed()` |  |
| 15 | `Rebirth` | dialog | implemented, not run in Studio | `Confirmed()`, `Celebrated()`, `Closed()` | `celebrate(context?)` |
| 16 | `LevelUp` | overlay | implemented, not run in Studio | `Claimed(level)`, `Closed()` |  |
| 17 | `Loading` | fullscreen | implemented, not run in Studio | `Closed()` | `setProgress(ratio)`, `finish()` |
| 18 | `Welcome` | fullscreen | implemented, not run in Studio | `Confirmed()`, `Selected(id)`, `Closed()` |  |
| 19 | `Tutorial` | overlay | implemented, not run in Studio | `StepChanged(index)`, `Completed(index)`, `Skipped(index)`, `Closed()` | `step()`, `refresh()` |
| 20 | `AreaUnlock` | banner | implemented, not run in Studio | `Confirmed()`, `Closed()` | `celebrate(context?)` |
| 21 | `Collection` | window | implemented, not run in Studio | `Selected(id, discovered)`, `Closed()` |  |
| 22 | `UpgradeShop` | window | implemented, not run in Studio | `Purchased(id, cost)`, `Closed()` | `pulse(id)` |
| 23 | `Trading` | window | implemented, not run in Studio | `Selected(id)`, `ReadyToggled(ready)`, `Confirmed()`, `Cancelled()`, `Closed()` |  |
| 24 | `AbilityHotbar` | hud | implemented, not run in Studio | `Selected(id, ready)`, `Ready(id)` | `startCooldown(id, seconds)`, `setCooldown(id, remaining, duration?)`, `clearCooldown(id)`, `isReady(id)` |
| 25 | `CombatProgression` | window | implemented, not run in Studio | `UnlockRequested(id)`, `Closed()` | `gain(amount)` |

Intent names follow the plan (`Purchased`, `Claimed`). They report what the player asked for:
`Purchased(id, price)` is a purchase request, `Claimed(day)` a claim request. Robux prices on
ProductCards and banners also raise the component's own `Purchase` intent, which
`Game.PurchaseBridge` turns into Roblox's purchase prompt.

## What every screen does

- **Style.** Components get the screen's style; plain text on a surface uses that surface's text
  colour, so dark styles stay readable.
- **Layout.** All numbers come from `ScreensLogic`: the window rectangle (`window`), where tabs go
  (`navigation`: top tabs, a bottom bar on portrait phones, a sidebar on landscape phones and for
  six or more tabs on wide screens), card grids (`cards`, `grid`), two-pane splits (`split`) and
  HUD regions (`hud`). Screens are laid out for 1920x1080, 1366x768, 1024x768, 844x390 and
  390x844, and re-laid out when the viewport changes. The ScreenGui uses `DeviceSafeInsets`
  (`CoreUISafeInsets` for HUDs), so the root already sits inside the safe area.
- **Scrolling.** Content lives in ScrollingFrames with an automatic canvas, so long lists and
  grids scroll instead of overflowing.
- **Touch targets.** Grid cells, tabs, HUD buttons, the close button and footer buttons are at
  least 44 px (`ScreensLogic.MIN_TOUCH`).
- **HUDs.** `ScreensLogic.hud` keeps the centre of the screen clear and, on touch, leaves the
  bottom corners to the thumbstick and the jump button.
- **Focus.** Each screen registers its focusable objects; `ScreensLogic.focus` (on
  `UI/Core/SpatialNav`) links them for keyboard and gamepad from where they are on screen, and the
  first one is selected when a gamepad is in use. Gamepad B closes screens that can close.
  PetSelection uses the focus handling of `Pets.selection`.
- **Open and close.** `ScreensLogic.animation` picks the `Visuals.UI` preset per kind: window
  `ModalIn` / `ModalOut`, dialog `PopIn` / `PopOut`, hud `SlideInUp` / `SlideOutDown`, sheet
  `DrawerIn` / `DrawerOut`, banner `SlideInDown` / `SlideOutUp`, overlay and fullscreen
  `FadeIn` / `FadeOut`. Under reduced motion every screen fades. Windows, dialogs and sheets dim
  the game behind them (`UI.backdrop`).
- **Press feedback.** Buttons are Game components (their press animation starts on the same
  frame); custom hit areas use `UI.bind` or play a press preset.
- **Cleanup.** Everything a screen creates is in its Trove; `destroy()` also stops its clock jobs
  and animations.

## Props, intents and examples

### PetSelection

Choose-your-starter screen: wraps Pets.selection (live 3D previews, focus, confirm).

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `pets` | list | required | Entries { id, name, description?, rarity?, model?, color?, palette?, stats? }; two or more |
| `title` | string | `Choose your pet` | Title above the cards |
| `subtitle` | string |  | Line under the title |
| `selected` | string |  | Id selected when the screen opens |
| `confirmText` | string | `CHOOSE` | Confirm button text |
| `palette` | string | `purple` | Backdrop palette |
| `closeOnConfirm` | boolean | `true` | Close after the confirm intent |
| `worldPosition` | any |  | Vector3 where confetti plays on confirm |

- `Selected(id)`: A card was picked
- `Confirmed(id)`: The player confirmed the pick; the server decides what it means
- `Closed()`: The screen finished closing

```lua
Screens.create("PetSelection", { parent = playerGui, pets = starters }):open()
```

### EggHatching

Egg stand: egg cards, the selected egg's odds and hatch x1 / x3 / auto buttons that raise intents.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `eggs` | list | required | Entries { id, name?, icon?, image?, rarity?, price?, currency?, palette?, odds = { { name, chance, rarity?, icon? } } } |
| `selected` | string |  | Egg id shown first (default: the first egg) |
| `title` | string | `EGGS` | Window title |
| `counts` | list |  | Hatch sizes offered, default { 1, 3 } |
| `auto` | boolean | `true` | Show the auto hatch toggle |
| `autoActive` | boolean | `false` | Whether auto hatch is on (the caller sets it) |
| `balance` | any |  | Number, or currency -> amount: buttons the player cannot afford are disabled |
| `currencyIcon` | string | `coin-color` | Icon shown next to prices |

- `Selected(eggId)`: Another egg was picked
- `HatchRequested(eggId, count)`: A hatch button was pressed; the server rolls and charges
- `AutoToggled(eggId, on)`: The auto hatch toggle was pressed
- `Closed()`: The screen finished closing

```lua
local stand = Screens.create("EggHatching", { parent = playerGui, eggs = eggs })
```

### RewardReveal

Reward reveal overlay: wraps Rewards.reveal for one reward and Rewards.batch for several.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `rewards` | list | required | One or more { rarity, name, amount?, icon?, image?, model?, subtitle? } |
| `position` | any |  | Vector3, CFrame or Instance: where the rarity VFX plays in the world |
| `compact` | boolean | `false` | Smaller card |
| `skippable` | boolean | `true` | A tap skips to the result |
| `autoDismiss` | boolean | `true` | Dismiss after the rarity's hold time |
| `threshold` | string | `Epic` | Batches: rarities at or above this get a full reveal |
| `hint` | string |  | Text under the card (default: Tap to continue) |

- `Claimed(rewards)`: The reveal finished normally (the rewards were already granted by the server)
- `Closed()`: The screen finished closing

```lua
Screens.create("RewardReveal", { parent = playerGui, rewards = { { rarity = "Legendary", name = "Sun Fox" } } }):open()
```

### TappingHud

Clicker HUD: big tap button, currency counters, multiplier chip, rebirth bar and side menu buttons.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `currencies` | list | required | Counters { id, icon?, image?, value, format?, palette? } |
| `tapText` | string | `TAP` | Tap button label |
| `tapIcon` | string |  | Tap button icon |
| `tapPalette` | string | `gold` | Tap button colour |
| `multiplier` | number | `1` | Shown in the multiplier chip |
| `rebirth` | table |  | { value, max, label? }: the rebirth progress bar (hidden when nil) |
| `menu` | list |  | Side buttons { id, icon, label?, palette?, badge? } |
| `popups` | boolean | `true` | Show a floating number for each reward() |

- `Tapped(position)`: The tap button was pressed (Vector2 in screen pixels)
- `Selected(id)`: A menu button was pressed
- `RebirthRequested()`: The full rebirth bar was pressed

```lua
local hud = Screens.create("TappingHud", { parent = playerGui, currencies = { { id = "coins", icon = "coin-color", value = 0 } } })
```

### AnimalInteraction

Feeding panel: animal card with mood and hunger bars, a food tray, a throw button and a reaction area.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `animal` | table | required | { name, mood (0..1), hunger (0..1), icon?, image?, moodText?, rarity? } |
| `foods` | list | required | Tray items { id, name?, icon?, image?, count? } |
| `selectedFood` | string |  | Food id selected first (default: the first one in stock) |
| `canThrow` | boolean | `true` | false disables the throw button (cooldown, out of range) |
| `throwText` | string | `THROW` | Throw button label |
| `title` | string | `FEED` | Panel title |

- `Selected(foodId)`: A food was picked in the tray
- `ThrowRequested(foodId)`: The throw button was pressed; the server validates the throw
- `Closed()`: The screen finished closing

```lua
local feed = Screens.create("AnimalInteraction", { parent = playerGui, animal = cow, foods = foods })
```

### PetInventory

Pet grid with rarity filters, equip and unequip, and a detail panel with a preview.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `pets` | list | required | Pets { id, name?, rarity?, icon?, image?, model?, equipped?, stats = { { text or value, icon?, prefix?, suffix? } }, palette? } |
| `selected` | any |  | Id of the pet shown in the detail panel |
| `filter` | string | `all` | Rarity shown: all, or a rarity present in the list |
| `equipMax` | number | `3` | Team size: equip is disabled when it is full |
| `title` | string | `PETS` | Window title |

- `Selected(id)`: A pet card was pressed
- `EquipRequested(id)`: Equip was pressed for the selected pet; the server owns the team
- `UnequipRequested(id)`: Unequip was pressed for the selected pet
- `FilterChanged(filter)`: Another rarity tab was opened
- `Closed()`: The screen finished closing

```lua
Screens.create("PetInventory", { parent = playerGui, pets = ownedPets, equipMax = 4 }):open()
```

### Shop

Tabbed shop with a grid of product cards.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `products` | list | required | Cards { id, tab?, title, subtitle?, icon?, image?, price?, badge?, rarity?, owned?, palette? } |
| `tabs` | list |  | Tabs { id, text?, icon? }; products without a tab show in every tab |
| `tab` | string |  | Active tab id (default: the first tab) |
| `title` | string | `SHOP` | Window title |

- `Purchased(id, price)`: A product was pressed: a purchase request for the server (or PurchaseBridge), nothing is granted
- `Selected(id)`: An owned product was pressed
- `TabChanged(id)`: Another tab was opened
- `Closed()`: The screen finished closing

```lua
Screens.create("Shop", { parent = playerGui, tabs = tabs, products = products }):open()
```

### PremiumShop

Robux store with a featured banner, bundles and premium buttons.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `bundles` | list | required | Cards { id, title, subtitle?, icon?, image?, price, badge?, owned?, gift?, palette? } |
| `featured` | table |  | Banner { id?, title, subtitle?, icon?, image?, price, badge?, timer?, palette? } |
| `cta` | table |  | Premium button under the grid { id?, text, icon?, palette? } |
| `title` | string | `PREMIUM` | Window title |

- `Purchased(id, price)`: The banner or a bundle was pressed: a purchase request, nothing is granted
- `Confirmed(id)`: The premium button was pressed
- `Closed()`: The screen finished closing

```lua
Screens.create("PremiumShop", { parent = playerGui, featured = starterPack, bundles = bundles }):open()
```

### DailyRewards

Seven-day reward track where today pulses and can be claimed.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `days` | list | required | The track: each { text?, amount?, icon?, image?, premium?, palette? } or a string |
| `today` | number | `1` | The day that can be claimed (wraps around the track) |
| `claimed` | boolean | `false` | Whether today's reward was already claimed |
| `streak` | number |  | Days in a row, shown above the track (default: from today) |
| `claimText` | string | `CLAIM` | Claim button text |
| `title` | string | `DAILY REWARDS` | Window title |

- `Claimed(day)`: The claim button was pressed; the server grants the reward
- `Closed()`: The screen finished closing

```lua
Screens.create("DailyRewards", { parent = playerGui, days = track, today = 3 }):open()
```

### SpinWheel

Prize wheel that lands on the segment the caller supplies, then reveals the reward.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `segments` | list | required | Segments { text?, amount?, icon?, image?, palette?, weight?, rarity?, reward? } or strings; weight only changes the drawn width |
| `spins` | number |  | Spins left: shown on the button, which is disabled at 0 (nil: always enabled) |
| `spinText` | string | `SPIN` | Spin button text |
| `reveal` | boolean | `true` | After landing, show the segment's `reward` with Rewards.reveal |
| `title` | string | `LUCKY WHEEL` | Window title |

- `SpinRequested()`: The spin button was pressed; the server picks the segment and the game calls spin(index)
- `Landed(index)`: The wheel stopped on the segment it was told to
- `Claimed(index)`: The reward reveal after a spin was dismissed
- `Closed()`: The screen finished closing

```lua
local wheel = Screens.create("SpinWheel", { parent = playerGui, segments = prizes, spins = 1 })
```

### QuestLog

Daily and weekly quest lists with claim buttons.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `quests` | list | required | Quests { id, tab?, title, description?, value, max, rewards?, state?, claimText?, palette? } |
| `tabs` | list |  | Tabs { id, text?, icon? }, default daily and weekly; quests without a tab show in every tab |
| `tab` | string |  | Active tab id (default: the first tab) |
| `emptyText` | string | `No quests here yet` | Shown when the tab has no quests |
| `title` | string | `QUESTS` | Window title |

- `Claimed(id)`: A quest's claim button was pressed; the server grants the reward
- `TabChanged(id)`: Another tab was opened
- `Closed()`: The screen finished closing

```lua
Screens.create("QuestLog", { parent = playerGui, quests = quests }):open()
```

### Achievements

Achievement cards with a progress summary.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `achievements` | list | required | Cards { id, title, description?, icon?, image?, tier?, maxTier?, value?, max?, unlocked?, palette? } |
| `title` | string | `ACHIEVEMENTS` | Window title |

- `Selected(id)`: An achievement card was pressed
- `Closed()`: The screen finished closing

```lua
Screens.create("Achievements", { parent = playerGui, achievements = achievements }):open()
```

### Settings

Game settings plus the Visuals quality, reduced motion, reduced flashing and intensity controls.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `schema` | list |  | UI/Core/SettingsSchema entries { key, kind (toggle, slider, dropdown, keybind), label, default, section?, min?, max?, step?, options? } |
| `values` | table |  | Current values by key (missing keys use the schema defaults) |
| `visuals` | boolean | `true` | Add the Visuals section (quality, intensity, reduced motion, reduced flashing) |
| `title` | string | `SETTINGS` | Window title |

- `Changed(key, value, values)`: A setting changed; Visuals settings are already applied, game settings are the game's to save
- `Closed()`: The screen finished closing

```lua
Screens.create("Settings", { parent = playerGui, schema = settingsSchema, values = saved }):open()
```

### Leaderboard

Ranked rows with tabs and the local player pinned.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `entries` | list | required | Rows { id, name, value, avatar? } in any order |
| `localId` | any |  | The local player's id: that row is highlighted, and pinned when it is not visible |
| `limit` | number | `50` | Rows shown |
| `format` | string | `abbrev` | Core/Format spec for the values |
| `tabs` | list |  | Tabs { id, text?, icon? }: one board each |
| `tab` | string |  | Active tab id (default: the first tab) |
| `title` | string | `LEADERBOARD` | Window title |

- `TabChanged(id)`: Another board was opened; send its entries with update({ entries = ... })
- `Closed()`: The screen finished closing

```lua
Screens.create("Leaderboard", { parent = playerGui, entries = topCoins, localId = player.UserId }):open()
```

### Rebirth

Rebirth cost and progress, multiplier preview and a hold or double confirm.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `current` | number | required | What the player has of the rebirth currency |
| `cost` | number | required | What a rebirth costs |
| `multiplier` | number | `1` | The multiplier now |
| `nextMultiplier` | number |  | The multiplier after the rebirth (default: one more) |
| `keeps` | list |  | Names of what the player keeps |
| `loses` | list |  | Names of what the player loses |
| `confirm` | string | `hold` | hold (hold the button) or double (press twice) |
| `holdSeconds` | number | `1.2` | How long the button must be held |
| `confirmText` | string | `REBIRTH` | Confirm button text |
| `title` | string | `REBIRTH` | Window title |

- `Confirmed()`: The hold or double press completed; the server checks the cost and performs the rebirth
- `Celebrated()`: celebrate() was called after the server confirmed
- `Closed()`: The screen finished closing

```lua
Screens.create("Rebirth", { parent = playerGui, current = coins, cost = 1e6, multiplier = 2 }):open()
```

### LevelUp

Level-up overlay with animated text, an XP bar fill and a rewards row.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `level` | number | required | The level just reached |
| `fromLevel` | number |  | The level before (default: one less) |
| `xp` | table |  | { value, max, from?, fromMax? }: bar state after and before the level up |
| `rewards` | list |  | Reward tiles { icon?, image?, amount?, rarity? } with a claim button |
| `claimText` | string | `AWESOME` | Claim button text |
| `duration` | number | `2.5` | Seconds before the overlay closes itself when there are no rewards (0 keeps it) |
| `title` | string | `LEVEL UP!` | Headline |

- `Claimed(level)`: The claim button was pressed (the rewards were already granted by the server)
- `Closed()`: The screen finished closing

```lua
Screens.create("LevelUp", { parent = playerGui, level = 12, rewards = { { icon = "coin-color", amount = "x500" } } }):open()
```

### Loading

Loading screen with a progress bar and rotating tips.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `title` | string |  | Game title |
| `logo` | string |  | Logo image id |
| `icon` | string |  | Icon used when there is no logo |
| `tips` | list |  | Strings shown in turn |
| `tipInterval` | number | `4` | Seconds per tip |
| `progress` | number | `0` | Bar fill from 0 to 1 |
| `palette` | string | `green` | Bar colour |

- `Closed()`: The screen finished closing

```lua
local loading = Screens.create("Loading", { parent = playerGui, title = "PET WORLD", tips = tips, startOpen = true })
```

### Welcome

Title screen with a play button and news cards.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `title` | string | `WELCOME` | The game's title |
| `subtitle` | string |  | Line under the title |
| `logo` | string |  | Logo image id (shown above the title) |
| `icon` | string |  | Icon used when there is no logo |
| `playText` | string | `PLAY` | Play button text |
| `news` | list |  | News cards { id, title, text?, palette?, badge = { kind, text? } } |

- `Confirmed()`: The play button was pressed
- `Selected(id)`: A news card was pressed
- `Closed()`: The screen finished closing

```lua
Screens.create("Welcome", { parent = playerGui, title = "PET WORLD", news = news, startOpen = true })
```

### Tutorial

Step-by-step coach marks with a highlight cutout, next and skip.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `steps` | list | required | Steps { text, title?, target? (a GuiObject or { x, y, w, h } in screen pixels), padding? } |
| `step` | number | `1` | The step shown first |
| `nextText` | string | `NEXT` | Next button text |
| `doneText` | string | `GOT IT` | Next button text on the last step |
| `skipText` | string | `SKIP` | Skip button text |

- `StepChanged(index)`: The player moved to another step
- `Completed(index)`: The last step was confirmed
- `Skipped(index)`: Skip was pressed at this step
- `Closed()`: The screen finished closing

```lua
Screens.create("Tutorial", { parent = playerGui, steps = { { text = "Tap here to earn coins", target = hud:counter("coins") } } }):open()
```

### AreaUnlock

Area banner with its cost and an unlock button.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `area` | table | required | { name, description?, icon?, image? } |
| `cost` | number | `0` | Price shown on the unlock button |
| `balance` | any |  | Number, or currency -> amount: the button is disabled when it does not cover the cost |
| `currency` | string |  | Key into a balance table |
| `currencyIcon` | string | `coin-color` | Icon on the unlock button |
| `unlockText` | string | `UNLOCK` | Unlock button text |
| `palette` | string | `teal` | Banner colour |

- `Confirmed()`: The unlock button was pressed; the server checks the cost and unlocks the area
- `Closed()`: The screen finished closing

```lua
Screens.create("AreaUnlock", { parent = playerGui, area = { name = "Volcano" }, cost = 5000, balance = coins }):open()
```

### Collection

Index grid with discovered and undiscovered entries and a completion percentage.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `entries` | list | required | Index entries { id, name?, icon?, image?, rarity?, discovered? } |
| `title` | string | `COLLECTION` | Window title |

- `Selected(id, discovered)`: A tile was pressed
- `Closed()`: The screen finished closing

```lua
Screens.create("Collection", { parent = playerGui, entries = petIndex }):open()
```

### UpgradeShop

Upgrade rows with level pips, cost and an upgrade button.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `upgrades` | list | required | Rows { id, title, description?, icon?, image?, level, maxLevel, cost or costs = { per level }, currency?, currencyIcon? } |
| `balance` | any |  | Number, or currency -> amount: decides which buttons are enabled |
| `currencyIcon` | string | `coin-color` | Icon on the cost buttons |
| `title` | string | `UPGRADES` | Window title |

- `Purchased(id, cost)`: An upgrade button was pressed: a request; the server checks the cost and raises the level
- `Closed()`: The screen finished closing

```lua
Screens.create("UpgradeShop", { parent = playerGui, upgrades = upgrades, balance = coins }):open()
```

### Trading

Two offer panels with ready states and a countdown confirm (presentation only).

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `mine` | list |  | Your offer { id, icon?, image?, count?, rarity? } |
| `theirs` | list |  | Their offer, same shape |
| `partner` | table |  | { name }: shown above their offer |
| `myReady` | boolean | `false` | Your ready flag, as the server reports it |
| `theirReady` | boolean | `false` | Their ready flag |
| `countdown` | number | `0` | Seconds to wait once both are ready before confirm is offered |
| `title` | string | `TRADE` | Window title |

- `Selected(id)`: An item in your offer was pressed (for example to remove it)
- `ReadyToggled(ready)`: The ready button was pressed
- `Confirmed()`: Confirm was pressed after the countdown; the server performs the trade
- `Cancelled()`: Cancel was pressed (the screen then closes)
- `Closed()`: The screen finished closing

```lua
local trade = Screens.create("Trading", { parent = playerGui, partner = { name = other.DisplayName }, mine = {}, theirs = {} })
```

### AbilityHotbar

Row of ability slots with cooldowns, keybind labels and a ready pulse.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `slots` | list | required | Slots { id, icon?, image?, keybind? (label), keyCode? (Enum.KeyCode that activates it), palette?, enabled?, remaining?, duration? } |

- `Selected(id, ready)`: A slot was pressed or its key was hit; the server decides whether the ability runs
- `Ready(id)`: A slot's cooldown ended

```lua
local bar = Screens.create("AbilityHotbar", { parent = playerGui, slots = abilities, startOpen = true })
```

### CombatProgression

Level and XP, stat chips and the skill unlock list.

| Prop | Type | Default | Meaning |
|---|---|---|---|
| `level` | number | required | The player's level |
| `xp` | table |  | { value, max }: progress to the next level |
| `stats` | list |  | Chips { id, icon?, image?, value, format?, prefix?, suffix?, palette? } |
| `skills` | list |  | Skills { id, title, description?, icon?, image?, level (required level), unlocked? } |
| `title` | string | `PROGRESSION` | Window title |

- `UnlockRequested(id)`: The unlock button of an available skill was pressed; the server decides
- `Closed()`: The screen finished closing

```lua
Screens.create("CombatProgression", { parent = playerGui, level = 6, xp = { value = 40, max = 200 }, skills = skills }):open()
```

## Your own screens

```lua
Screens.register("Codes", function(shell, props)
	local window = shell:window({ title = props.title, kind = "dialog" })
	local redeem = shell:button(window.content, { text = "REDEEM", kind = "buy", size = UDim2.new(1, -10, 0, 52) })
	shell.trove:Add(redeem.Activated:Connect(function()
		shell:fire("Confirmed", "FREEPET")
	end))
	shell:focusables({ redeem.Instance })
	return { update = function(partial) if partial.title then window.setTitle(partial.title) end end }
end, {
	kind = "dialog", category = "system", description = "Redeem a promo code.",
	props = { "title: string = CODES | Window title" },
	intents = { "Confirmed(code) | A code was entered", "Closed() | The screen finished closing" },
})
local codes = Screens.create("Codes", { parent = playerGui })
```

The builder gets a `ScreenKit.Shell` (`window`, `text`, `button`, `frame`, `own`, `fire`,
`onLayout`, `focusables`, `trove`, `style`, `props`) and returns `{ update?, methods? }`. Props are
written `"name: type = default | description"` (`*` after the type marks a required prop) and
intents `"Name(payload) | description"`.

## Performance notes

- Screens do no per-frame work while idle. Clock jobs run only during a wheel spin, a rebirth
  hold, a trade countdown and component cooldowns, and end by themselves.
- TappingHud folds counter updates that arrive within 0.08 s into one roll, uses one `UI.bind`
  for the tap button, and relies on the pooled popups of `Visuals.UI`.
- Card grids rebuild when their item list changes. Leaderboard and Achievements update rows in
  place when the same entries arrive in the same order. Keep very long lists (hundreds of cards)
  paged on your side.
- Screen files and the modules they wrap (Pets, Eggs, Rewards, Feedback) load on first use.

## Verification

| Part | Verified by |
|---|---|
| `ScreensLogic.luau`, `ScreensData.luau` | `luau-analyze --mode=strict` and `tests/visuals_screens.spec.luau`: layout on the five viewports (no overflow, 44 px targets, columns), HUD regions, prop validation and view models for all 25 screens, spin-wheel angles and deceleration, daily-reward states, leaderboard order, hotbar cooldown fractions, registry metadata, and `Screens.names()` against the files |
| Preset and icon names used in the screen files | The same spec reads the sources and checks every literal against `UIPresets` and `IconData` |
| `Screens.luau`, `ScreenKit.luau`, every `<Name>.luau` | StyLua, Selene and `luau-lsp` with Roblox type definitions only |

## Not verified in Studio

**Nothing in this folder that creates Instances has been run in Studio.** Every screen NEEDS
MANUAL REVIEW in a playtest before you rely on it. Things to look at first:

- window and pane sizes on real devices, text fitting, and the scroll bars;
- components inside `UIGridLayout` cells (the cards are given the cell size as an offset size);
- SpinWheel: descendants turning with the disc, petal sizes for 3 to 12 segments;
- Tutorial: the four dim frames around the hole and the bubble position when the target moves;
- Settings: dropdown menus opening inside the scrolling list;
- Rebirth: the hold fill and `InputEnded` on touch;
- gamepad focus links (`NextSelection*`) and the gamepad B close;
- PetSelection, RewardReveal and Loading, which hand over to `Pets.selection`, `Rewards` and
  `LoadingScreen` and report `Closed` from their signals or a short timer.
