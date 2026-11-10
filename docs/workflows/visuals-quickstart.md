# Visuals quick start

Add polish to a game with UltimateVisualsKit (UVK): feedback for gameplay events, animated UI, pets, an egg hatch and reward reveals, using presets instead of hand-written effects. The module overview is [library/src/Visuals/README.md](../../library/src/Visuals/README.md); every function is in [visuals-api.md](../references/visuals-api.md) and every preset in [visuals-presets.md](../references/visuals-presets.md).

Nothing in this guide has been run in Roblox Studio. The code uses the library's real API and the pure logic behind it passes its Lune specs, but how it looks and feels is `NEEDS MANUAL REVIEW` until you play it. The last section lists what to check.

## 1. Install

```bash
python3 urk.py add Visuals --project ~/games/MyGame
```

The module lands in `src/shared/Urk/Visuals` with the library modules it requires. With Claude Code, the `/urk-visuals <task>` command finds presets for a described task and `/urk-visuals-audit` reviews existing visuals.

## 2. Find a preset before writing anything

The catalog lists every preset with its params, cost and a usage line.

```bash
grep -n -i '"id": ".*coin' catalog/visuals.json
```

In a project the file is at `.claude/ultimate-roblox-kit/catalog/visuals.json`. At run time the same search is:

```lua
for _, entry in Visuals.Presets.search("coin") do
	print(entry.kind, entry.id, Visuals.Presets.usage(entry.kind, entry.id))
end
```

## 3. Configure once on the client

```lua
--!strict
-- src/client/Visuals.client.luau
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Visuals = require(ReplicatedStorage.Shared.Urk.Visuals.Visuals)

Visuals:Configure({
	theme = "VibrantSimulator",
	reducedMotion = GuiService.ReducedMotionEnabled,
	-- quality is chosen from the device and adapts under load unless you set it
})
```

Give players a settings screen for quality, reduced motion, reduced flashing and intensity, and pass the values to `Visuals:Configure`.

## 4. Feedback for gameplay events

The server decides; the client presents. One call runs the burst, the coins flying to the counter, the counter roll and the sound cue, with throttling for rapid events.

```lua
-- Server
CollectRemote.OnServerEvent:Connect(function(player, coinId)
	local coin = validateAndCollect(player, coinId)
	if coin then
		CoinCollected:FireClient(player, { position = coin.position, amount = coin.value, total = wallet(player) })
	end
end)
```

```lua
-- Client
CoinCollected.OnClientEvent:Connect(function(data)
	Visuals.Feedback:Fire("CollectCoin", {
		position = data.position,
		amount = data.amount,
		total = data.total,
		counter = coinLabel,
	})
end)
```

Built-in events include `Tap`, `CollectCoin`, `CollectGem`, `LevelUp`, `QuestComplete`, `Purchase`, `Error`, `EquipPet`, `UnlockArea`, `RebirthDone` and `DailyReward`; the full list with the context each one reads is in the preset reference. Define your own with `Visuals.Feedback:Define(event, recipe)`.

## 5. Animated UI

```lua
local UI = Visuals.UI

local binding = UI.bind(shopButton, "BouncyPress", { onActivated = openShop })
UI.show(shopPanel, "PopIn")
UI.hide(shopPanel, "PopOut")
UI.stagger(tiles, "BadgePop", { interval = 0.08, order = "center" })
UI.countTo(coinLabel, 2400, { format = "abbrev" })
UI.popup(125, hitPosition, { style = "crit" })
```

For whole screens, build from the animated components in `UI/Game` (PremiumButton, TabBar, Modal, XPBar, PetCard, RewardPanel and the rest): see [the component README](../../library/src/UI/Game/README.md).

## 6. Pets

```lua
local Pets = Visuals.Pets

local animator = Pets.animator(petModel)            -- idle: bob, breathing, sway
animator:react("HappyReaction")
local follower = Pets.follow(character, { petA, petB, petC }, { mode = "arc" })

local screen = Pets.selection({
	parent = playerGui,
	title = "Choose your starter",
	pets = {
		{ id = "ember", name = "Ember", rarity = "Rare", color = "#FF8A3D" },
		{ id = "moss", name = "Moss", color = "#58C26A" },
		{ id = "drift", name = "Drift", color = "#5AB0FF" },
	},
	onConfirm = function(id)
		chooseStarter:FireServer(id)                -- the server decides what the choice means
	end,
})
```

## 7. Egg hatch and reward reveal

```lua
local results = hatchRemote:InvokeServer(eggId, 3)   -- the server rolls and saves first
if results then
	local hatch = Visuals.Eggs:Hatch({ eggs = results })   -- { { rarity, name, pet = Model?, isNew? }, ... }
	hatch.Completed:Connect(function(_, skipped)
		refreshInventory()
	end)
end
```

```lua
RewardGranted.OnClientEvent:Connect(function(reward)
	Visuals.Rewards:Reveal(reward.rarity, { name = reward.name, amount = reward.amount, icon = reward.icon })
end)
```

Rarity decides the size of the moment: a Common reveal is a 1.2 s pop, a Legendary adds anticipation, rays, a soft flash, a small shake, a beam and confetti. Both can be skipped, and `cancel()` removes everything.

## 8. Camera and sequences

```lua
Visuals.Camera.shake("SoftImpact")
Visuals.Camera.punchFov(6)

Visuals.Sequence()
	:Call(function() Visuals.Objects.animate(chest, "Shake") end)   -- anticipation
	:Wait(0.4)
	:Play("TreasureOpen", chest)
	:Sound("success")
	:Wait(0.15)
	:Play("CoinBurst", chest)
	:Start()
```

## 9. Clean up

Every call returns a handle with `stop()` and `cancel()`. Stop loops with their owner:

```lua
local aura = Visuals:Attach("RarityAura", petModel, { rarity = "Epic", owner = petModel })
-- later
Visuals:StopAll(petModel)
animator:destroy()
follower:destroy()
binding.destroy()
```

## 10. Check

```bash
lune run tests/urk/run tests/urk
```

```bash
python3 urk.py check ~/games/MyGame
```

Then in Studio, with the stats overlay open (`Visuals.Debug.overlay()`):

- [ ] Each effect appears at Low and High quality and ends by itself.
- [ ] Buttons respond on the input frame with mouse, touch and gamepad.
- [ ] The selection screen works on a phone in portrait and landscape and with a gamepad only.
- [ ] The hatch and the reveal can be skipped and cancelled, and the camera and HUD are restored.
- [ ] With `reducedMotion = true` there are no loops, shakes or travel; with `reducedFlashing = true` no full-screen flash.
- [ ] After `Visuals:StopAll()`, `Visuals:Stats()` shows zero effects and zero jobs.
- [ ] Frame time holds on a phone profile during the heaviest moment (write the number down).

## Going further

- The design principles and the quality checklist the kit was built to: [research notes](../research/visuals/README.md) and [design-principles.md](../research/visuals/design-principles.md).
- Sharper effect shapes with the kit's generated textures: [visual-assets.md](visual-assets.md).
- A purchased icon pack: [icon-pack-import.md](icon-pack-import.md).
- Architecture and rules for contributors: [visuals.md](../architecture/visuals.md).
