---
name: luau-language
description: Luau language reference for Roblox code - syntax, strict type checking, generics, typeof, export type, type functions basics, table/string/buffer libraries, idioms, native codegen with @native and common runtime and type errors. Use when writing or reviewing any Luau module, fixing type errors, adding --!strict, or optimizing a hot loop.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [luau, strict mode, type annotation, generics, export type, typeof, buffer, native codegen, type error, metatable]
---

# Luau language

## When to use

- Writing any new `.luau` module, or turning an untyped module into `--!strict`.
- Reading a type checker error ("Type 'X' could not be converted into 'Y'", "Unknown global").
- Picking the right library call (`table.create`, `string.format`, `buffer.writeu16`).
- Making a hot path faster (per-frame loops, many NPCs, bulk serialization).

When not to use: project layout and module wiring (use `roblox-architecture`), frame-time profiling with the MicroProfiler (use `roblox-performance`), unit test setup (use `roblox-testing-debugging`).

## Inputs

- The script context: server `Script`, client `LocalScript`, or `ModuleScript`. Rojo file suffixes decide this: `x.server.luau`, `x.client.luau`, `x.luau`.
- Whether the project runs `luau-lsp` or Studio's script analysis (both read `--!strict`).

## Workflow

1. Put `--!strict` on line 1 of every new file. Use `--!nonstrict` only for legacy code you are migrating.
2. Declare types near the top, export the ones other modules need, and annotate every function signature.
3. Prefer plain tables and functions; use metatables only for real classes with many instances.
4. Run the checker (`luau-lsp analyze` or Studio script analysis) and fix every warning before shipping.
5. For hot code, measure first, then apply the performance idioms below.

### Types, generics and typeof

```luau
--!strict
-- Inventory.luau: a typed class with generics, unions and typeof.

export type ItemId = string
export type Rarity = "Common" | "Rare" | "Epic"   -- string singleton union

export type Stack = {
	id: ItemId,
	count: number,
	rarity: Rarity,
	meta: { [string]: string | number }?,          -- optional field
}

-- Generic helper: works for any array element type T.
local function filter<T>(list: { T }, keep: (T) -> boolean): { T }
	local out = table.create(#list) :: { T }
	for _, v in list do                            -- generalized iteration, no ipairs needed
		if keep(v) then
			table.insert(out, v)
		end
	end
	return out
end

local Inventory = {}
Inventory.__index = Inventory

-- The instance type is derived from the constructor's return value.
export type Inventory = typeof(setmetatable({} :: {
	stacks: { Stack },
	capacity: number,
}, Inventory))

function Inventory.new(capacity: number): Inventory
	local self = setmetatable({ stacks = {}, capacity = capacity }, Inventory)
	return self
end

function Inventory.add(self: Inventory, id: ItemId, count: number, rarity: Rarity): boolean
	assert(count > 0 and count % 1 == 0, "count must be a positive integer")
	if #self.stacks >= self.capacity then
		return false
	end
	table.insert(self.stacks, { id = id, count = count, rarity = rarity })
	return true
end

function Inventory.rare(self: Inventory): { Stack }
	return filter(self.stacks, function(s: Stack): boolean
		return s.rarity ~= "Common"
	end)
end

-- Type refinement: typeof() narrows unions at runtime.
local function describe(v: number | string | Instance): string
	if typeof(v) == "Instance" then
		return v:GetFullName()                     -- v is Instance here
	elseif type(v) == "number" then
		return string.format("%.2f", v)
	end
	return v                                       -- v is string here
end

return { Inventory = Inventory, describe = describe }
```

Key points:

- `typeof` (Roblox) knows Roblox types (`"Vector3"`, `"Instance"`, `"EnumItem"`); `type` only knows Lua base types.
- `::` is a type cast. Use it to type an empty table (`{} :: { string }`), never to silence a real mismatch.
- `export type` makes a type importable: `local Inv = require(path); type Inventory = Inv.Inventory`.
- `?` means `T | nil`. A function that may fail returns `T?` and callers must check it.
- `read`/`write` property modifiers and type functions belong to the new type solver. Check which solver your toolchain uses before relying on them.

### Type functions (new solver)

Type functions run at analysis time and compute types:

```luau
--!strict
type function Partial(t)
	-- turns every property of a table type into an optional one
	local out = types.newtable()
	for key, prop in t:properties() do
		out:setproperty(key, types.unionof(prop.read, types.singleton(nil)))
	end
	return out
end

type Settings = { music: number, sfx: number }
type SettingsPatch = Partial<Settings>   -- { music: number?, sfx: number? }
```

The `types` library API is still evolving; verify method names in the Luau RFCs/docs before using anything beyond `newtable`, `properties`, `setproperty`, `unionof` and `singleton`.

### Library cheat sheet

| Need | Call |
| --- | --- |
| Preallocate array | `table.create(n, fill?)` |
| Empty and reuse a table | `table.clear(t)` |
| Read-only config | `table.freeze(t)` (shallow), check with `table.isfrozen` |
| Shallow copy | `table.clone(t)` |
| Find in array | `table.find(t, v)` |
| Format | `string.format("%d/%d", a, b)`, interpolation `` `{a}/{b}` `` |
| Split | `string.split("a,b", ",")` |
| Binary data | `buffer.create(n)`, `buffer.writeu8/u16/u32/f32/f64`, `buffer.readstring`, `buffer.len` |
| Integer math | `bit32.band`, `bit32.lshift`, `math.floor(x // 1)` floor division `//` |
| Clamp/lerp | `math.clamp(x, a, b)`, `math.lerp(a, b, t)` (verify availability in your engine version; otherwise `a + (b - a) * t`) |

More idioms and a buffer serializer are in [references/idioms.md](references/idioms.md).

### Performance idioms

- `--!native` at the top of a module, or `@native` on one function, compiles it to machine code on the server (and on clients where supported). Use it for math-heavy loops; it helps little for code that mostly calls Roblox APIs.
- Keep types precise in native code: annotated `number`, `vector` and `buffer` arguments generate faster code.
- Do not create closures inside per-frame loops; hoist the function and pass data as arguments.
- Cache services and frequently used globals in locals at the top of the file.
- Reuse tables with `table.clear` instead of allocating each frame.
- Use `task.spawn`, `task.defer`, `task.delay`, `task.wait`; never `spawn`, `delay` or `wait`.

```luau
--!strict
@native
local function sumDistances(points: { Vector3 }, origin: Vector3): number
	local total = 0
	for i = 1, #points do
		total += (points[i] - origin).Magnitude
	end
	return total
end
```

## Outputs

- `.luau` files that pass the strict checker with zero warnings.

## Validation

1. `luau-lsp analyze --definitions=globalTypes.d.luau src` (or Studio: View > Script Analysis) shows no errors.
2. `selene src` (if the project uses Selene) reports no deprecated calls such as `wait(`.
3. `grep -rn "^--!strict" src | wc -l` matches the number of `.luau` files you own.

## Pitfalls

- **`attempt to index nil with 'X'`**: a `FindFirstChild` or table lookup returned nil. Check it, or use `WaitForChild` on the client for replicated objects.
- **`#t` on a dictionary** returns 0 or garbage. Count with a loop or keep a counter.
- **Arrays with holes** (`t[1] = nil` in the middle) break `#` and `ipairs`. Use `table.remove` or swap-remove.
- **Mutating a table while iterating** with `next` may skip entries. Collect keys first.
- **Integer precision**: numbers are doubles; integers are exact only up to 2^53. Currency over that needs a different design.
- **`string` vs number keys**: `t["1"]` and `t[1]` are different keys. DataStores convert number keys in mixed tables badly; keep keys strings.
- **Yielding inside a metamethod** (`__index`, `__eq`, ...) errors with a yield-across-boundary message. Yielding inside `pcall` is fine in Luau. Keep metamethods non-yielding.
- **Casting away errors** with `:: any` hides real bugs. Fix the type instead.

## Limitations

- Type functions, `read`/`write` modifiers and some refinements depend on the new type solver; behaviour differs between Studio, luau-lsp and solver versions. Verify in the Luau docs for your toolchain version.
- Native codegen availability on client platforms changes over time; treat `@native` as a server optimization unless creator docs say otherwise.
- This skill cannot run code; it relies on the checker and Studio for proof.
