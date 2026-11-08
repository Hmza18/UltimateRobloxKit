# Trading

Two-player trades of pets and chosen currencies, designed against the common scams and dupes.

- **Versioned offers.** Any change to either side bumps `session.version` and clears both acceptances. `Accept(version)` fails with `"offer changed"` when the client accepted an older offer, so nobody can swap an item out after the other player accepted.
- **Countdown.** When both accept the same version a countdown starts (default 5 s). Any change or `Unaccept` stops it.
- **Re-check at settle.** `TradingLogic.settle` calls a `verify` callback that re-reads live server data: every pet still owned and tradeable (not locked, `tradeable ~= false`) and every currency affordable. Otherwise the trade is cancelled.
- **Atomic swap.** `TradingServer` computes both new pet states and both wallets first and commits only if all succeed. Received pets get fresh ids.
- **Limits.** `maxPets` per side (default 8), tradeable `currencies` (default none), `maxCurrency`, invite lifetime 30 s, open trades time out after 300 s, a player leaving cancels.

`TradingServer.new({ trading, pets = petsServer, petsConfig, currency = currencyServer?, currencyConfig?, canTrade?, rateLimit? })`. Remotes in `URK_Trading`: `Invite(userId)`, `Respond(accept)`, `SetOffer({ pets, currency })`, `Accept(version)`, `Unaccept()`, `Cancel()`; server to client `Invited(fromUserId)` and `Update(session)`. Signal `Completed(session)`; log it for support.

`TradingLogic.fairness(session, valueOf)` gives the smaller side's value over the larger (1 = even) for an "uneven trade" warning.
