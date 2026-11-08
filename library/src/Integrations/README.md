# Integrations

Bridges to well-known community packages. The kit does not bundle them: `python3 urk.py packages --project <dir>` writes a `wally.toml`, maps `Packages` and `ServerPackages` in `default.project.json` and runs `wally install` (Wally from your Rokit toolchain).

| Module | Package | Licence | What it does |
| --- | --- | --- | --- |
| `ProfileStoreAdapter` | `lm-loleris/profilestore@1.0.3` (server) | Apache-2.0, loleris | Turns ProfileStore into the kit's `{ load, save, release }` store. `adapter.section("pets")` gives each system its own slice of one profile, so a player has one session lock |
| `FusionBridge` | `elttob/fusion@0.3.0` | MIT, Daniel P H Fox | `value(scope, store, path, default?)` mirrors a UrkUI Store path into a Fusion Value; `twoWay` also writes back (client-owned settings only) |
| (none needed) | `evaera/promise@4.0.0` | MIT, Eryn L. K. | Installed for projects that want Promise-based flows |

Both modules take the package as an argument instead of requiring it, so the library still builds without Wally and the bridge is tested in Lune with a fake.
