# Shop

A catalog priced in any Currency currency, with global stock, per-player purchase limits and timed sales, plus an idempotent Robux developer product receipt handler. `ShopLogic` is pure: `purchase` validates the request, recomputes the price on the server, checks limits and stock and pays through `CurrencyLogic.spendMany` in one atomic step. `ShopServer` commits the result, calls your `grant` callback and refunds if the grant fails.

## ShopLogic API

| Function | Returns | Notes |
| --- | --- | --- |
| `newCatalog(items)` | `Catalog` | item: `{ id, prices, stock?, perPlayerLimit?, maxQuantity? = 99, sales? }`. Errors on bad data. |
| `getItem(catalog, id)` | `Item?` | |
| `newStock(catalog)` | `Stock` | remaining global stock per item that has one |
| `activeDiscount(item, now)` | `number` | best sale with `startsAt <= now < endsAt` |
| `priceFor(catalog, id, now, quantity?)` | `({ [currency]: n }?, reason?)` | unit price rounded half up after the discount, times quantity |
| `remaining(catalog, stock, history, id)` | `number?` | units still buyable; `nil` = unlimited |
| `purchase(catalog, currencyConfig, stock, history, wallet, request)` | `PurchaseResult` | request: `{ itemId, quantity? = 1, now }` |
| `deserializeHistory(raw)` | `History` | `{ [itemId]: count }` |
| `newReceiptHistory(max? = 100)`, `hasReceipt`, `recordReceipt` | | bounded set of processed PurchaseIds |
| `serializeReceipts(h)` / `deserializeReceipts(raw, max?)` | | array of ids, oldest first |
| `processReceipt(receipt, deps)` | `(decision, reason)` | decision: `"PurchaseGranted"` or `"NotProcessedYet"` |

`PurchaseResult = { ok, reason?, quantity, cost, wallet, stock, history }`; on failure the inputs come back unchanged. Reasons: `"invalid request"`, `"unknown item"`, `"invalid quantity"`, `"out of stock"`, `"limit reached"`, `"insufficient funds"`.

### Receipts

`processReceipt` takes `deps = { loadHistory(userId) -> ReceiptHistory?, grant(userId, productId, receipt) -> boolean, commit(userId, history) -> boolean }`:

1. Malformed receipt, or player data not loaded in this server: `NotProcessedYet` (Roblox retries later, including when the player rejoins).
2. PurchaseId already in the history: `PurchaseGranted` without granting again.
3. `grant` fails or errors: `NotProcessedYet`.
4. `commit` stores the new history. Return true only once the history sits in the same session data as the granted effect (for example the same ProfileStore profile). Otherwise `NotProcessedYet`.

The handler never double-grants as long as `commit` writes the history into memory before it returns, even when the save itself is still pending.

## Server config

| Key | Default | Meaning |
| --- | --- | --- |
| `catalog`, `currencyConfig` | required | |
| `currency` | required | object with `getWallet(player)` and `setWallet(player, wallet)` (a CurrencyServer) |
| `grant` | required | `(player, item, quantity) -> boolean` |
| `store` | `nil` | saves `{ h = history, r = receiptIds }` per player |
| `products` | `nil` | `{ [productId]: (player, receipt) -> boolean }` |
| `receiptHistorySize` | `100` | |
| `remoteFolderName` | `"URK_Shop"` | contains RemoteFunctions `Purchase(itemId, quantity?)` and `GetCatalog()` |
| `rateLimit` | `{ capacity = 5, refillPerSecond = 2 }` | |
| `bindProcessReceipt` | `true` when `products` is set | sets `MarketplaceService.ProcessReceipt` |

Server methods: `purchase(player, itemId, quantity?) -> (ok, reason?)`, `describe(player)`, `processReceipt(receipt)`, `loadPlayer`, `unloadPlayer`, `savePlayer`, `destroy`.

## Events

`Purchased(player, itemId, quantity, cost)` and `ReceiptGranted(player, productId, purchaseId)`.

## Example

```luau
local shop = ShopServer.new({
	catalog = ShopLogic.newCatalog({
		{ id = "Potion", prices = { Coins = 50 } },
		{ id = "Crown", prices = { Gems = 10 }, perPlayerLimit = 1, sales = { { discount = 0.2, endsAt = 1767225600 } } },
	}),
	currencyConfig = currencyConfig,
	currency = currencyServer,
	grant = function(player, item, quantity)
		return inventory:give(player, item.id, quantity) == 0
	end,
	products = {
		[123456789] = function(player, receipt) -- your developer product id
			return currencyServer:add(player, "Gems", 100, "robux") ~= nil
		end,
	},
})
```

Client: `ReplicatedStorage.URK_Shop.Purchase:InvokeServer("Potion", 2)` returns `ok, reason`.

## Persistence shape

```luau
{ h = { Potion = 4, Crown = 1 }, r = { "purchase-id-1", "purchase-id-2" } }
```

## Limitations

- Global stock is per server. Cross-server stock needs MemoryStoreService (not included).
- If `grant` fails after payment the wallet is refunded with `"refund"` log entries; a grant that partly succeeds before failing is not undone.
- Only one `MarketplaceService.ProcessReceipt` callback can exist per place. If several systems sell products, route them all through one `products` table.
- In the example, `grant` returning false when the inventory is full triggers the refund.

## Needs a Studio playtest

RemoteFunction calls, the refund path, and real developer product purchases (test purchases in Studio). Lune covers `ShopLogic`. Verify `MarketplaceService.ProcessReceipt`, `Enum.ProductPurchaseDecision` and the receipt fields (`PurchaseId`, `PlayerId`, `ProductId`) against the creator docs.
