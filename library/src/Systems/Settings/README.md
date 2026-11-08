# Settings

Player settings from a schema: booleans, number ranges with steps, enums and keybinds, with defaults, validation and clamping, versioned saves with migrations, and client hooks for volume groups, graphics quality hints, reduced motion, colourblind mode and text size. The server validates every change and owns persistence.

| File | Runs on | Role |
| --- | --- | --- |
| `SettingsLogic.luau` | anywhere (pure) | schema checks, coerce and clamp, apply, migrate, serialize, diff, keybind conflicts, groups |
| `SettingsServer.luau` | server | load/save through a store, validated Update remote, Snapshot replies |
| `SettingsClient.luau` | client | local mirror, optimistic changes, hooks |
| `SettingsConfig.luau` | anywhere | default schema and options |

## Schema

```lua
{
	MusicVolume = { type = "number", default = 0.8, min = 0, max = 1, step = 0.05, group = "Audio", hook = "volume:Music" },
	ReducedMotion = { type = "bool", default = false, group = "Accessibility", hook = "attribute:UrkReducedMotion" },
	ColorblindMode = { type = "enum", default = "Off", options = { "Off", "Protanopia", "Deuteranopia", "Tritanopia" } },
	InteractKey = { type = "keybind", default = "E", allowed = nil, hook = "attribute:UrkKeyInteract" },
}
```

Keybind values are `Enum.KeyCode` names (letters and digits only, starting with a letter, at most 32 characters). Use `allowed` to restrict them. Defaults must sit on the range and step; `validateSchema` reports them otherwise.

The default schema (`SettingsConfig.schema`) has MasterVolume, MusicVolume, EffectsVolume, GraphicsQuality (Auto/Low/Medium/High), ReducedMotion, ColorblindMode, TextScale (0.8 to 1.5) and InteractKey.

## API

| Function | Returns | Notes |
| --- | --- | --- |
| `SettingsLogic.validateSchema(schema)` | `ok, errors` | |
| `coerce(def, value)` | `ok, valueOrReason` | numbers are clamped and snapped to `min + n * step` |
| `defaults(schema)` | values | |
| `apply(schema, values, changes)` | `newValues, rejected` | never mutates `values`; `rejected[key] = reason` |
| `migrate(data, migrations?, currentVersion)` | `values, version` | `migrations[n]` turns version n into n + 1; a failing migration is skipped |
| `serialize(schema, values, version)` | `{ version, values }` | only non-default values |
| `deserialize(schema, data, currentVersion, migrations?)` | values | invalid values fall back to defaults, unknown keys dropped |
| `diff(a, b)`, `keybindConflicts(schema, values)`, `groups(schema)` | | for menus |
| `SettingsServer.new({ schema?, store?, version?, migrations?, config? })` | `Service` | `get(player)`, `set(player, key, value)`, `changed`, `destroy` |
| `SettingsClient.new({ schema?, hooks?, remoteFolder? })` | `Client` | `get(key)`, `all()`, `set(key, value)`, `reset(key)`, `changed`, `destroy` |

## Config (`SettingsConfig.luau`)

| Key | Default | Meaning |
| --- | --- | --- |
| `version` | 1 | save format version |
| `remoteFolder` | `"UrkSettings"` | |
| `saveDelay` | 5 | seconds after the last change before saving |
| `requestCapacity` / `requestRefillPerSecond` | 10 / 4 | per-player rate limit |
| `schema` | see above | |

## Hooks

- `volume:<name>` sets `SoundService.<name>.Volume` if that SoundGroup exists. Create `Master`, `Music` and `Effects` SoundGroups and route your sounds to them (nest Music and Effects under Master if you want a master volume).
- `attribute:<name>` sets an attribute on the LocalPlayer: `UrkGraphicsQuality`, `UrkReducedMotion`, `UrkColorblindMode`, `UrkTextScale`, `UrkKeyInteract`. Your UI framework, camera shake and particle code read these.
- `hooks = { [key] = function(value) end }` in `SettingsClient.new` for anything else (for example calling the Input system's rebind).

## Example

```lua
-- Server
local migrations = {
	[1] = function(values) values.MusicVolume = values.Music; values.Music = nil; return values end,
}
SettingsServer.new({
	version = 2,
	migrations = migrations,
	store = { load = function(p) return data[p].settings end, save = function(p, d) data[p].settings = d end },
})

-- Client
local settings = SettingsClient.new({
	hooks = { InteractKey = function(key) input:rebind("Interact", "keyboard", 1, key) end },
})
slider.Changed:Connect(function(value) settings:set("MusicVolume", value) end)
```

## Events and remotes

- `service.changed(player, keys, values)` on the server, `client.changed(keys, values)` on the client.
- `ReplicatedStorage.UrkSettings.Update` (client to server): `(key, value)`; the key must be in the schema and the value a string, number or boolean, then the schema check runs. Rate limited.
- `ReplicatedStorage.UrkSettings.Snapshot` (server to client): the accepted values.

## Persistence shape

`{ version = number, values = { [key] = value } }` with only values that differ from the defaults.

## Limitations

- Graphics quality is a hint: Roblox does not let game scripts change the user's quality level.
- The client must use the same schema as the server, or it will reject values the server accepts.
- Keybind values are names; converting them to `Enum.KeyCode` (and rejecting unknown names) is the Input system's job.

## Needs a Studio playtest

Store calls, remotes, SoundGroup volumes and attribute hooks are unverified outside Studio. Lune tests cover `SettingsLogic`.
