# Currency

Multi-currency wallets with overflow and negative protection, atomic multi-currency spending, transfers, a transaction log ring buffer tagged with sources and sinks, and number formatting. `CurrencyLogic` is pure and immutable. `CurrencyServer` keeps one wallet per player, publishes balances as player attributes (and optional leaderstats) and persists through an injected store.

## CurrencyLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `validateConfig(config)` | `Config` | errors on bad names, max, initial, logSize or overflow |
| `newWallet(config)` | `Wallet` | balances start at `initial` |
| `isCurrency(config, name)` | `boolean` | |
| `balance(wallet, name)` | `number` | 0 for unknown names |
| `canAfford(wallet, costs)` | `boolean` | costs: `{ [currency]: number }` |
| `add(config, wallet, name, amount, source?, now?)` | `TxResult` | clamps at max, or rejects when `overflow = "reject"` |
| `spend(config, wallet, name, amount, sink?, now?)` | `TxResult` | rejects when the balance is too low |
| `spendMany(config, wallet, costs, sink?, now?)` | `TxResult` | all or nothing; `amount` is the total spent |
| `transfer(config, from, to, name, amount, tag?, now?)` | `TransferResult` | fails without changes when the receiver would pass max |
| `recent(wallet, limit?)` | `{ Entry }` | newest first |
| `summarize(entries)` | `{ sources, sinks }` | totals per tag and currency |
| `abbreviate(n)` | `string` | `1234567 -> "1.23M"` (rounds down) |
| `withCommas(n)` | `string` | `1234567 -> "1,234,567"` |
| `serialize(wallet)` / `deserialize(config, raw)` | | balances only; deserialize drops unknown currencies and clamps |

`TxResult = { ok, reason?, wallet, amount }`. On failure `wallet` is the unchanged input. Reasons: `"unknown currency"`, `"invalid amount"` (not a positive whole finite number), `"insufficient funds"`, `"over max"`, `"receiver over max"`.

`Entry = { currency, delta, balance, tag, time? }`. Use tags like `"quest:Daily"` (source) or `"shop:Sword"` (sink).

## Config

| Key | Default | Meaning |
| --- | --- | --- |
| `currencies` | required | `{ [name]: { max? = 1e15, initial? = 0 } }` |
| `logSize` | `50` | entries kept per wallet; `0` disables the log |
| `overflow` | `"clamp"` | `"clamp"` adds what fits, `"reject"` refuses the whole add |

Server config: `currency` (the table above), `store?`, `attributePrefix = "Currency_"`, `leaderstats = {}` (currency names shown in the player list as NumberValues), `onTransaction(player, entry)?`, `autoLoad = true`.

Server methods: `getWallet(player)`, `setWallet(player, wallet)`, `balance(player, name)`, `add(player, name, amount, source?)`, `spend(player, name, amount, sink?)`, `loadPlayer`, `savePlayer`, `unloadPlayer`, `destroy`.

## Events

`Changed(player, currency, balance, delta)` and `Loaded(player, wallet)`.

## Example

```luau
local CurrencyServer = require(Kit.Systems.Currency.CurrencyServer)
local currency = CurrencyServer.new({
	currency = { currencies = { Coins = { initial = 50 }, Gems = { max = 100000 } } },
	leaderstats = { "Coins" },
	onTransaction = function(player, entry)
		-- Feed AnalyticsService economy events here (verify the API in the creator docs).
	end,
})
currency:add(player, "Coins", 25, "quest:Tutorial")
local result = currency:spend(player, "Coins", 10, "shop:Potion")
if result and not result.ok then print(result.reason) end
```

Clients read balances with `player:GetAttribute("Currency_Coins")` and `GetAttributeChangedSignal`.

## Persistence shape

```luau
{ v = 1, b = { Coins = 150, Gems = 3 } }
```

## Limitations

- Whole numbers only, at most 1e15 per currency (doubles lose integer precision past 2^53).
- Attributes replicate to every client, so balances are public. Use a RemoteEvent to the owner if they must be private.
- The log is per session and not saved; send entries to analytics through `onTransaction`.
- Cross-server transfers (trading between servers) need MemoryStore or a DataStore transaction, which this module does not provide.

## Needs a Studio playtest

Attribute and leaderstats updates, save on leave and BindToClose, and the analytics hook. Lune covers `CurrencyLogic`.
