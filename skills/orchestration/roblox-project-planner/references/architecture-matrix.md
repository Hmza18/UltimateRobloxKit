# Architecture decision matrix

| Need | Default in the kit | Choose instead when |
|---|---|---|
| Project layout | `templates/starter-game` (Rojo, services and controllers, Loader) | You already use a framework such as Knit (archived) or Nevermore; keep it and add library systems |
| Genre base | `simulator`, `tycoon`, `obby` overlays | Other genres start from `starter-game` plus library systems |
| Remotes | `Net` in the template (validated, rate-limited) | Very high-frequency traffic (combat, physics sync): Blink or Zap code-generated buffers |
| Persistence | Library `Systems/SaveData` with an injected store | Production games with trading or many writes: ProfileStore (session locking, battle-tested) as the store |
| Game state replication | Attributes plus the owner's remote events | Large shared state trees: a replica library, or ECS (jecs) for simulation-heavy games |
| UI | `UrkUI` (tags, attributes, components, themes) | A team already fluent in React-Lua, Fusion or Vide; keep UrkUI's Store, Localizer and icons as utilities |
| Icons | URK Icons (MIT) plus imported packs | Brand art: draw your own and import with `tools/icons/import_pack.py` |
| Assets | `scripts/export/asset_batch.py` procedural pipeline | Organic characters: hand modelling (`characters-rigging`) |
| Testing | Lune specs for pure logic, Studio playtests for adapters | In-engine automated tests: jest-roblox with Open Cloud Luau execution |
| Deploy | Studio publish by the user | Teams: Rojo build plus Open Cloud place publishing in CI (`roblox-publishing-liveops`) |

## Server size and authority

- 1-12 players: one server, everything authoritative there.
- Lobbies and matches: `Systems/Matchmaking` with reserved servers.
- Large social spaces (50+): budget remotes per second, use StreamingEnabled, and avoid per-player per-frame server work.
