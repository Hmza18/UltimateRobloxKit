# Third-party notices

This repository contains no third-party source code. It bundles CC0 art by Kenney (icons, UI Pack sprites, sounds and fonts; see `THIRD_PARTY_RESOURCES.md`) and two OFL fonts. Other third-party material reaches a project only when you run a fetch or `urk packages`, and each carries its own license:

| Component | How it arrives | License | Notice |
|---|---|---|---|
| EL4CTEO/blender-skills (https://github.com/EL4CTEO/blender-skills) | `scripts/install/third_party.py install el4cteo-blender-skills` | MIT | `UPSTREAM_LICENSE` copied into each installed skill |
| WojciechJelen/roblox-dev-kit (https://github.com/WojciechJelen/roblox-dev-kit) | `third_party.py install roblox-dev-kit` | MIT | same |
| gogolumo/rbsmithy-roblox-claude-skill (https://github.com/gogolumo/rbsmithy-roblox-claude-skill) | `third_party.py install rbsmithy` | MIT | same |
| zriptic/roclicks-skills (https://github.com/zriptic/roclicks-skills) | `third_party.py install roclicks-skills` | MIT | same |
| Fusion 0.3.0, Promise 4.0.0, ProfileStore 1.0.3 (Wally) | `python3 urk.py packages --project <dir>` | MIT, MIT, Apache-2.0 | in each package under `Packages/_Index` (not committed) |
| ahujasid/mcp-for-blender (https://github.com/ahujasid/mcp-for-blender) | `integrations/blender/setup_blender_mcp.sh` (pip, pinned commit) | MIT | in the installed package; upstream also has TERMS_AND_CONDITIONS.md |

Tools pinned in templates (Rojo, Wally, Selene, StyLua, Lune, luau-lsp, Rokit) are downloaded by Rokit under their own MIT or MPL-2.0 licenses and are not redistributed.

Fonts in `assets/fonts/` (Lilita One by Juan Montoreano, and Fredoka) are licensed under the SIL Open Font License 1.1. Each licence text sits beside its font. They are used to render HTML previews; Roblox games use Roblox's built-in fonts.

The kit's own code and documentation are MIT licensed (see `LICENSE`). Code under `tools/rbxasset/` was written for the repository owner's supermarket project and is included under the same MIT license.
