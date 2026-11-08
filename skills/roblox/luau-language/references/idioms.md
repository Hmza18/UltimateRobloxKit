# Luau idioms and recipes

## Swap-remove (O(1) unordered removal)

```luau
--!strict
local function swapRemove<T>(list: { T }, index: number)
	local last = #list
	list[index] = list[last]
	list[last] = nil
end
```

## Enum-like frozen tables

```luau
--!strict
local State = table.freeze({
	Idle = "Idle" :: "Idle",
	Chase = "Chase" :: "Chase",
})
export type State = typeof(State.Idle) | typeof(State.Chase)
```

## Result type instead of throwing

```luau
--!strict
export type Result<T> = { ok: true, value: T } | { ok: false, err: string }

local function parseCount(s: string): Result<number>
	local n = tonumber(s)
	if n == nil or n < 0 or n % 1 ~= 0 then
		return { ok = false, err = "not a non-negative integer" }
	end
	return { ok = true, value = n }
end

local r = parseCount("12")
if r.ok then
	print(r.value + 1)   -- refined to the ok branch
end
```

## pcall with typed returns

```luau
--!strict
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("Example")

local ok, result = pcall(function(): any
	return store:GetAsync("key")
end)
if not ok then
	warn("GetAsync failed:", result)
end
```

## Buffer serializer (fixed layout)

An id, a position and a health value in 18 bytes instead of a table of numbers.

```luau
--!strict
local Codec = {}

local SIZE = 18

function Codec.encode(id: number, pos: Vector3, health: number): buffer
	local b = buffer.create(SIZE)
	buffer.writeu16(b, 0, id)          -- 0..65535
	buffer.writef32(b, 2, pos.X)
	buffer.writef32(b, 6, pos.Y)
	buffer.writef32(b, 10, pos.Z)
	buffer.writef32(b, 14, health)
	return b
end

function Codec.decode(b: buffer): (number, Vector3, number)
	assert(buffer.len(b) == SIZE, "bad buffer length")
	local id = buffer.readu16(b, 0)
	local pos = Vector3.new(buffer.readf32(b, 2), buffer.readf32(b, 6), buffer.readf32(b, 10))
	local health = buffer.readf32(b, 14)
	return id, pos, health
end

return Codec
```

Always validate `buffer.len` before reading a buffer received from a client; out-of-range reads throw.

## Debounce per key

```luau
--!strict
local last: { [Player]: number } = {}
local function allowed(player: Player, cooldown: number): boolean
	local now = os.clock()
	local t = last[player]
	if t and now - t < cooldown then
		return false
	end
	last[player] = now
	return true
end
```

Clear `last[player]` on `Players.PlayerRemoving` to avoid leaking entries.

## Common type checker messages

| Message | Usual cause | Fix |
| --- | --- | --- |
| `Type 'nil' could not be converted into 'X'` | Optional value used without a check | `if v then ... end` or `assert(v)` |
| `Key 'k' not found in table` | Typo, or table type is sealed | Add the field to the type |
| `Unknown global 'wait'` (lint) | Deprecated global | `task.wait` |
| `Cannot call non-function` | Union includes a non-function | Refine with `type(f) == "function"` |
| `Generic type 'T' is not used` | Generic only in return | Pass a value of `T` or drop the generic |
