# Notifications

Server-to-client notifications (toasts, banners, reward pop-ups) with types, priorities, a dedupe window, per-player rate limits and a client display queue. It draws nothing: the client adapter fires `onNotify` and `onDismiss`, and your UI framework renders them.

| File | Runs on | Role |
| --- | --- | --- |
| `NotificationsLogic.luau` | anywhere (pure) | validation and trimming, priority queue, dedupe, capacity, expiry |
| `NotificationsServer.luau` | server | `notify`, `notifyMany`, `notifyAll` with per-player dedupe and rate limit |
| `NotificationsClient.luau` | client | display pacing (`maxVisible`, durations), `onNotify` / `onDismiss`, local `push` |
| `NotificationsConfig.luau` | anywhere | defaults and types |

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `NotificationsLogic.resolveConfig(overrides?)` | `Config` | invalid type definitions are dropped; the default type always exists |
| `truncate(text, maxLength)` | string or nil | UTF-8 aware, ends with `...`; nil for invalid UTF-8 |
| `normalize(input, config, now, id)` | `Notification?, reason?` | text required and non-blank; unknown kinds fall back to `defaultType` |
| `newQueue(config)`, `push(queue, input, now)` | `ok, reason, note` | reasons: duplicate, queue full, or a validation reason |
| `pop(queue, now)`, `peek(queue, now)` | `Notification?` | highest priority, then oldest; expired items are pruned first |
| `prune`, `size`, `clear` | | |
| `NotificationsServer.new(overrides?)` | `Service` | `notify(player, input) -> ok, reason`, `notifyMany(players, input)`, `notifyAll(input)`, `destroy()` |
| `NotificationsClient.new(overrides?)` | `Client` | `onNotify`, `onDismiss`, `push(input)`, `dismiss(id)`, `visible()`, `destroy()` |

Input: `{ text, title?, kind?, key?, priority?, duration?, data? }`. `data` passes through untouched (an icon id, a button action and so on).

## Config (`NotificationsConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `types` | info 1/4s, success 2/4s, reward 3/5s, warning 4/6s, error 5/8s | priority and duration per type |
| `defaultType` | `"info"` | |
| `dedupeWindow` | 3 | seconds; repeats are merged (`count` goes up) |
| `maxQueue` / `maxAge` | 20 / 30 | waiting notifications and how long they stay relevant |
| `maxTitleLength` / `maxTextLength` | 60 / 200 | characters |
| `maxVisible` | 3 | client: shown at once |
| `remoteFolder` | `"UrkNotifications"` | |
| `perPlayerCapacity` / `perPlayerRefillPerSecond` | 10 / 2 | server rate limit |

## Example

```lua
-- Server
local notifications = NotificationsServer.new()
notifications:notify(player, { kind = "reward", title = "Quest complete", text = "+50 coins", key = "quest:Slimes" })
notifications:notifyAll({ kind = "warning", text = "Server restarting in 60 seconds" })

-- Client
local toasts = NotificationsClient.new()
toasts.onNotify:Connect(function(note) ToastUI.show(note.id, note.kind, note.title, note.text) end)
toasts.onDismiss:Connect(function(note) ToastUI.hide(note.id) end)
```

## Events and remotes

- Client signals: `onNotify(notification)`, `onDismiss(notification)`.
- `ReplicatedStorage.UrkNotifications.Notify` (server to client only). There is no client-to-server remote.

## Persistence

None.

## Limitations

- Rate-limited notifications are dropped, not delayed. Use a lower-volume `key` for chatty events (for example one "coins" key per window).
- Durations use `task.delay` on the client; a dismissed notification's timer still runs but does nothing.
- `count` on merged duplicates is tracked only while the original is still waiting in a queue.

## Needs a Studio playtest

The remote, pacing with `task.delay` and UI hookup are unverified outside Studio. Lune tests cover `NotificationsLogic`.
