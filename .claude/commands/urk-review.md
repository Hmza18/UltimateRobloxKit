---
description: Review Roblox Luau changes for exploits, data loss, crashes and performance
argument-hint: [path or git range]
---
Review $ARGUMENTS (default: uncommitted changes, `git diff`). Load `roblox-security-anti-exploit`, `roblox-networking`, `roblox-data-persistence` and `roblox-performance` only as the changed code needs. Check every remote handler for server-side validation and rate limiting, DataStore calls for retries, session locking and BindToClose, and per-frame loops for cost. Report findings by severity with file:line and a concrete fix. Run `selene` and `stylua --check` when available, and say if they are not.
