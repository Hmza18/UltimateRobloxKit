# Input

One action map for keyboard, mouse, gamepad and touch. Each action lists its keyboard keys, gamepad buttons and an optional on-screen touch button. Rebinding is pure and tested (slots, conflict detection, swapping, saved overrides). The client adapter binds everything through ContextActionService, creates mobile touch buttons and tracks the active device.

| File | Runs on | Role |
| --- | --- | --- |
| `InputLogic.luau` | anywhere (pure) | map validation, reverse lookup, conflicts, rebind, overrides, device detection, display names |
| `InputClient.luau` | client | ContextActionService bindings, touch buttons, device tracking, runtime rebinding |

There is no server adapter: input is local. Send intents to the server through your own validated remotes.

## Action map

```lua
local actions = {
	Jump = { keyboard = { "Space" }, gamepad = { "ButtonA" }, touch = { title = "Jump", position = { x = 0.85, y = 0.6 } } },
	Sprint = { keyboard = { "LeftShift" }, gamepad = { "ButtonL3" } },
	Interact = { keyboard = { "E" }, gamepad = { "ButtonX" }, touch = { title = "Use" }, priority = 3000 },
	Shoot = { keyboard = { "MouseButton1" }, gamepad = { "ButtonR2" }, touch = { image = "rbxassetid://0" } },
}
```

Names are `Enum.KeyCode` names, or `Enum.UserInputType` names for mouse buttons. Up to 3 keys per device per action.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `InputLogic.validateMap(map)` | `ok, errors` | names, key lists, duplicates, priority |
| `cloneMap`, `bindingsFor(map, action, device)`, `reverseLookup(map, device)`, `findConflicts(map, device)` | | |
| `rebind(map, action, device, slot, key, { swap?, allowConflicts? })` | `ok, reason, newMap?, otherAction?` | reasons: unknown action, only keyboard and gamepad can be rebound, invalid key, invalid slot, conflict |
| `unbind(map, action, device, slot)`, `resetAction(map, defaults, action)` | new map | |
| `overrides(map, defaults)` / `applyOverrides(defaults, saved)` | data / `map, skipped` | only changed actions are saved |
| `detectDevice(userInputTypeName)`, `preferredToDevice(preferredInputName)` | `"keyboard"`, `"gamepad"`, `"touch"` or nil | |
| `displayName(key)` | label | `LeftShift` -> `Left Shift`, `ButtonA` -> `A` |
| `InputClient.new({ actions, overrides?, sink? })` | `Client` | `triggered`, `deviceChanged`, `overridesChanged`, `device()`, `isDown(action)`, `map()`, `rebind(...)`, `resetAction`, `displayKeys(action)`, `destroy()` |

## Config

| Option | Default | Meaning |
| --- | --- | --- |
| `actions` | required | the default map |
| `overrides` | nil | saved data from `overridesChanged` |
| `sink` | true | bound inputs do not reach lower-priority bindings |
| per action `priority` | `Enum.ContextActionPriority.Default.Value` | |

## Example

```lua
local input = InputClient.new({ actions = actions, overrides = savedBindings })
input.triggered:Connect(function(action, state)
	if action == "Interact" and state == "Begin" then interactRemote:FireServer() end
end)
input.deviceChanged:Connect(function(device) Prompts.setStyle(device) end)
input.overridesChanged:Connect(function(overrides) settingsRemote:FireServer("InputBindings", overrides) end)

-- in a rebinding menu, after the player presses a key:
local ok, reason, other = input:rebind("Interact", "keyboard", 1, keyCode.Name, { swap = true })
```

## Events

`triggered(action, state, inputObject)` with state `Begin`, `Change`, `End` or `Cancel`; `deviceChanged(device)`; `overridesChanged(overrides)`.

## Persistence shape

`{ [action] = { keyboard = { keys }?, gamepad = { buttons }? } }` holding only actions that differ from the defaults. Store it with your player data (the Settings system's keybind type covers single keys; for full maps save this table).

## Limitations

- Touch buttons are ContextActionService buttons; restyle them with `ContextActionService:GetButton` or replace them with your own UI that fires the same actions.
- Thumbstick and trigger analog values arrive through `triggered` with state `Change`; read `inputObject.Position`.
- Binding the same key to two actions only works with `allowConflicts`, and then the higher priority action wins (with `sink`).

## Verify in the Roblox docs

- `UserInputService.PreferredInput` and `Enum.PreferredInput` (`KeyboardAndMouse`, `Gamepad`, `Touch`) are newer APIs; the adapter reads them inside `pcall` and falls back to `LastInputTypeChanged`.
- `ContextActionService:SetPosition` expects a UDim2 within the default touch button frame.

## Needs a Studio playtest

ContextActionService bindings, touch buttons on a phone or the device emulator, gamepad input and device switching are unverified outside Studio. Lune tests cover `InputLogic`.
