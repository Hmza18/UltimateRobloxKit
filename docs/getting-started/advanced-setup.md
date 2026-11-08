# Advanced setup

## User-wide plus project-specific

Put general skills in your user scope and domain skills in projects:

```bash
python3 scripts/install/install.py --user --category orchestration,roblox,toolchain
```

```bash
python3 scripts/install/install.py --target ~/games/Market --category modeling,blender --no-agents --no-commands
```

Do not install the same skill in both scopes.

## MCP servers

`--with-mcp` merges `integrations/mcp/mcp.example.json` into the project's `.mcp.json`, adding only missing server names and backing up the old file. Set up Blender MCP first with `integrations/blender/setup_blender_mcp.sh`. See [MCP integration](../workflows/mcp-integration.md).

## CI for your game

Copy the `luau` job from this repository's `.github/workflows/ci.yml`. It downloads pinned Selene, StyLua, Lune and `luau-analyze` binaries and runs them on `src/` and `tests/`. For publishing, see the `roblox-publishing-liveops` skill. Keep the Open Cloud key in a repository secret and gate the deploy job on a manual approval environment.

## Updating the kit

```bash
git -C UltimateRobloxKit pull
```

```bash
python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --update --dry-run
```

Read the dry-run output. Files you edited are reported as conflicts; move your changes into a separate skill, or rerun with `--force` to back them up and replace them.

## Using another agent

Run `route.py --json "<task>"` and feed the listed `SKILL.md` files to the agent. See `AGENTS.md`.

## Offline use

Everything except third-party fetching, Blender MCP setup and Rokit tool downloads works offline. `third_party.py --source <local clone>` installs from a mirror, as long as the mirror contains the pinned commit.
