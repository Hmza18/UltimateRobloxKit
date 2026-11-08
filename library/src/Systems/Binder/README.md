# Binder

Binds a class to a CollectionService tag. Every tagged instance gets `class.new(instance)`. The object is destroyed when the tag is removed, the instance is destroyed or streamed out, or the instance leaves the allowed ancestors. This is the same idea as Nevermore's Binder, written from scratch. `BinderLogic` is a pure registry and state machine with injected callbacks, and holds every rule. `Binder` wires it to CollectionService and `AncestryChanged`, on the server or on a client.

## BinderLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `new(hooks)` | `State` | hooks: `construct(key) -> object` (required), `destroy(object, key)?` (default `object:Destroy()`), `added(key, object)?`, `removing(key, object)?` |
| `tag(state, key, passes?)` | `Result` | the key gained the tag; `passes` is the filter result (default true) |
| `untag(state, key)` | `Result` | the key lost the tag, was destroyed or streamed out |
| `setFilter(state, key, passes)` | `Result` | the filter result changed (for example the instance's ancestry changed) |
| `retry(state, key)` | `Result` | runs construct again after a failure |
| `get(state, key)` | `object?` | only bound objects |
| `getAll(state)` / `keys(state)` / `count(state)` | | in bind order |
| `isTagged(state, key)` / `phase(state, key)` | | phase is `"waiting"`, `"constructing"` or `"bound"` |
| `destroyAll(state)` | `number` | destroys newest first and refuses further tags |

`Result = { status, object?, error? }`. The statuses are:

| Status | When |
| --- | --- |
| `bound` | constructed (an `error` here means `added` raised) |
| `duplicate` | `tag` on a key that is already tagged; nothing is constructed |
| `filtered` | tagged, but the filter fails, so the key waits |
| `failed` | construct raised or returned nil; the key stays tagged and waits for `retry` or a filter change |
| `unbound` | the object was destroyed |
| `untagged` | the tag was removed from a key that had no object |
| `unknown` | `untag` or `setFilter` on a key that was never tagged. This covers a remove that arrives before its add |
| `deferred` | untag or filter-out while construct is running for that key; the object is destroyed as soon as construct returns |
| `unchanged` | nothing to do |

Every hook runs in `pcall`, so one bad object never breaks the registry. Hooks may call back into the registry for the same key (an untag inside `construct`, a tag inside `construct`). `removing` runs only for objects that `added` announced.

## Adapter

`Binder.new(tag, class, options?)` takes a class `{ new(instance) -> object }`, where the object should have `Destroy()`.

| Option | Default | Meaning |
| --- | --- | --- |
| `workspaceOnly` | false | only bind instances inside Workspace |
| `ancestors` | anywhere in the game | only bind inside one of these instances |
| `className` | any | only bind instances that `IsA` this class |
| `filter(instance)` | none | extra check, re-run when ancestry changes |

Methods: `start()` (connects, then binds the instances that are already tagged; call it after connecting the events), `get(instance)`, `getAll()`, `bind(instance)` and `unbind(instance)` (add or remove the tag), `retry(instance)` and `destroy()`.

Events: `ClassAdded(object, instance)` and `ClassRemoving(object, instance)`. `ClassRemoving` fires before the object is destroyed.

## Example

```luau
local Binder = require(Kit.Systems.Binder.Binder)

local Spinner = {}
Spinner.__index = Spinner
function Spinner.new(part: BasePart)
	local self = setmetatable({ part = part }, Spinner)
	self.connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
		part.CFrame *= CFrame.Angles(0, dt, 0)
	end)
	return self
end
function Spinner:Destroy()
	self.connection:Disconnect()
end

local spinners = Binder.new("Spinner", Spinner, { workspaceOnly = true, className = "BasePart" })
spinners.ClassAdded:Connect(function(spinner, part)
	print("spinning", part:GetFullName())
end)
spinners:start()
```

## Limitations

- `class.new` should not yield. If it yields, the instance stays in the `constructing` phase until it returns, and an untag in the meantime is only applied afterwards (`deferred`).
- The filter is only re-checked on `AncestryChanged`. A `filter` that reads attributes is not re-run when they change, so call `binder:unbind` and `binder:bind`, or re-tag the instance.
- Server and client binders are separate. A tag added on the server replicates, so a client binder binds its own object for the same instance.
- There is no persistence: objects are rebuilt from tags every session.

## Needs a Studio playtest

Lune covers `BinderLogic` in `tests/sys_binder.spec.luau`. Not verified: the CollectionService added and removed signals (including for destroyed instances and StreamingEnabled stream-out on clients), `AncestryChanged` re-filtering, tags already present when `start` runs, and replication of tags to clients.
