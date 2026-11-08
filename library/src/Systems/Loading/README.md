# Loading

A loading screen controller: waits for `game.Loaded`, preloads assets with `ContentProvider:PreloadAsync` in batches, smooths the progress bar, keeps the screen up for a minimum time, offers a skip button after a delay and closes on a timeout. It renders nothing; you draw the screen from the callbacks.

| File | Runs on | Role |
| --- | --- | --- |
| `LoadingLogic.luau` | anywhere (pure) | batching, progress tracking, bar smoothing, skip, timeout and dismissal rules |
| `LoadingClient.luau` | client (ReplicatedFirst) | default screen removal, `game.Loaded`, PreloadAsync batches, callbacks |
| `LoadingConfig.luau` | anywhere | defaults |

There is no server adapter.

## Where to put it

`ReplicatedFirst` runs before the rest of the game replicates, so `ReplicatedStorage.UltimateRobloxKit` may not exist yet. Copy `LoadingClient.luau`, `LoadingLogic.luau` and `LoadingConfig.luau` into a folder in `ReplicatedFirst` (they only require each other), build your loading GUI in the same LocalScript, and parent it to `PlayerGui` yourself.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `LoadingLogic.resolveConfig(overrides?)` | `Config` | |
| `batches(items, batchSize)` | `{ { any } }` | order kept |
| `newTracker(total, now)`, `markLoaded(t, n, now)`, `markFailed(t, n, now)` | | counts never exceed the total |
| `progress(t)`, `isLoaded(t)`, `weighted({ { weight, progress } })` | | failed assets count as finished |
| `displayProgress(shown, target, dt, speed)` | number | never moves backwards |
| `canSkip(t, now, config)`, `skip(t, now, config)` | boolean | after `skipAfter`, once |
| `timedOut`, `status(t, now, config)`, `shouldDismiss` | | status: loading, ready, done, skipped, timeout |
| `formatPercent(progress)` | `"42%"` | |
| `LoadingClient.start(options?)` | `Handle` | `handle:skip()`, `handle:progress()`, `handle:finished()`, `handle:destroy()` |

Options: `assets`, `config`, `onProgress(progress, status)`, `onSkipAvailable()`, `onFinished(status)`, `removeDefault` (default true).

## Config (`LoadingConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `batchSize` | 10 | instances per PreloadAsync call |
| `minDisplayTime` | 2 | seconds the screen stays up at least |
| `allowSkip` / `skipAfter` | true / 5 | skip button rules |
| `maxWait` | 30 | close anyway after this many seconds (0 = never) |
| `displaySpeed` | 1.5 | bar catch-up speed per second |

## Example

```lua
-- ReplicatedFirst/Loading.client.luau
local LoadingClient = require(script.Parent.Loading.LoadingClient)
local gui = script.LoadingGui:Clone()
gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

local handle = LoadingClient.start({
	assets = { gui, workspace:WaitForChild("Lobby") },
	onProgress = function(progress) gui.Bar.Fill.Size = UDim2.fromScale(progress, 1) end,
	onSkipAvailable = function() gui.Skip.Visible = true end,
	onFinished = function() gui:Destroy() end,
})
gui.Skip.Activated:Connect(function() handle:skip() end)
```

## Events

Callbacks only: `onProgress`, `onSkipAvailable`, `onFinished`.

## Persistence

None.

## Limitations

- Progress moves per batch, not per asset, because PreloadAsync's callback reports content ids rather than instances. Use smaller batches for a smoother bar.
- Preloading many large assets delays play; preload what the first screen needs and let the rest stream.
- Skipping closes the screen but preloading continues in the background.

## Needs a Studio playtest

`RemoveDefaultLoadingScreen`, `game.Loaded`, PreloadAsync timing and the RenderStepped loop are unverified outside Studio (test with a published place and a slow network setting). Lune tests cover `LoadingLogic`.
