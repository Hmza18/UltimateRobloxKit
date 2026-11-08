---
name: luau-debugging
description: Systematic debugging of Roblox Luau - reading Output stack traces, a table of common runtime errors and their causes, reproducing in a minimal place or a Lune test, bisecting changes, debugging client/server replication timing, remote and DataStore failures, memory leaks and infinite yields. Use when a script errors, something silently does nothing, behaves differently in Studio and live, or leaks memory.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [error, bug, stack trace, attempt to index nil, infinite yield, not working, debug, script error, output window]
  depends: [luau-language]
---

# Luau debugging

## Workflow

1. **Get the exact error** and the full stack trace from Output (Studio) or the Developer Console (F9 in a live server; Server tab for server errors). Note which side failed: client or server.
2. **Classify** with the table below. Most bugs are a nil from a race or a wrong path.
3. **Reproduce small**: if the logic is pure, write a failing Lune spec first (`library/tests/` style) and fix until it passes. Otherwise reproduce in a fresh place with only the involved scripts.
4. **Instrument**: temporary `print` with context (`print("[Shop] buy", player.Name, itemId, balance)`), or Studio breakpoints and the Watch window. For timing problems log `os.clock()` deltas.
5. **Bisect** when it used to work: `git log -p` the touched files, or comment out halves of the change until the error disappears.
6. **Fix the cause**, not the symptom (do not wrap in `pcall` to hide an error unless the failure is external: DataStore, HTTP, MarketplaceService, Teleport).
7. **Prove it**: the Lune spec passes, the repro place stops erroring, and add the case to tests where possible. Remove debug prints.

## Common errors

| Message | Usual cause | Fix |
|---|---|---|
| `attempt to index nil with 'X'` | Instance not loaded yet, wrong name, character respawned | `WaitForChild` with a timeout on the client, guard `if not x then return end`, reconnect on `CharacterAdded` |
| `Infinite yield possible on 'X:WaitForChild("Y")'` | Name typo, object only exists on the other side, or StreamingEnabled has not streamed it | Check the path in the Explorer of the right side; use `ModelStreamingMode = Persistent` or `RequestStreamAroundAsync` |
| `X is not a valid member of Y` | Typo, wrong class, or property renamed | Check the API reference; use `FindFirstChild` when it may be absent |
| `attempt to perform arithmetic on nil` | Missing data field (new field not in old saves) | Reconcile defaults on load (SaveData `reconcile`) |
| `Unable to cast value to Object` / `to Function` | Wrong argument type to an API | Check the signature; Remote args lose metatables and functions |
| `Remote event invocation queue exhausted` | Server fires to a client that has not connected `OnClientEvent` yet | Connect early; have the client request state when ready |
| `DataStore request was added to queue` / `502` / `throttled` | Budget exceeded | Retry with backoff, batch saves, check `GetRequestBudgetForRequestType` |
| `Script timeout: exhausted allowed execution time` | Tight loop without yielding | Add `task.wait()` in long loops or split work across frames |
| Works in Studio, fails live | Studio API access differences, timing (no network latency in Studio), or a client relying on server-only objects | Test with Studio's network simulation and Clients and Servers mode |
| Memory keeps growing | Connections never disconnected, tables keyed by Player never cleared | Use a Trove per object; clear player tables on `PlayerRemoving` |

## Tools

- Studio: breakpoints, Watch, Call Stack, Script Profiler, MicroProfiler (Ctrl+F6), Memory tab in the Developer Console.
- Static: `selene src` (unused or shadowed variables, wrong globals), luau-lsp strict mode type errors often point straight at the nil.
- Studio MCP (if enabled): `execute_luau` to read state in the running edit session, `get_console_output` for errors (`roblox-studio-mcp`).

## Limitations

Live-server-only bugs need the user to reproduce them in a live server and share the console; agents cannot attach to live servers.
