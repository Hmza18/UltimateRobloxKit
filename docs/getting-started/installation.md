# Installation reference

`scripts/install/install.py` (wrappers: `install.sh`, `install.ps1`). Python 3.9+, standard library only.

## Where things go

| Item | Project install (`--target DIR`) | User install (`--user`) |
|---|---|---|
| Skills | `DIR/.claude/skills/<name>/` | `~/.claude/skills/<name>/` |
| Subagents | `DIR/.claude/agents/urk-*.md` | `~/.claude/agents/` |
| Slash commands | `DIR/.claude/commands/urk-*.md` | `~/.claude/commands/` |
| Kit scripts, tools, templates (`$URK`) | `DIR/.claude/ultimate-roblox-kit/` | `~/.claude/ultimate-roblox-kit/` |
| Manifest | `DIR/.claude/ultimate-roblox-kit.json` | `~/.claude/ultimate-roblox-kit.json` |
| MCP servers (`--with-mcp`) | merged into `DIR/.mcp.json` | not supported; use `claude mcp add` |
| Instructions (`--with-claude-md`) | block in `DIR/CLAUDE.md` | block in `~/.claude/CLAUDE.md` |

Pick one scope per machine where possible. If both scopes have the same skill, Claude Code sees two copies.

## Options

| Option | Effect |
|---|---|
| `--dry-run` | Print every action, including conflicts, and write nothing |
| `--skills a,b` | Only these skills, plus dependencies, `roblox-kit-router` and `kit-conventions` |
| `--category roblox,modeling` | Whole categories (see `--list`) |
| `--no-agents`, `--no-commands` | Skip those parts |
| `--update` | Re-install over an earlier install. Kit files that were not edited are replaced. Skills you deselected are removed if unmodified |
| `--uninstall` | Remove what the manifest lists. Edited files are kept and reported. `CLAUDE.md` and `.mcp.json` entries are removed, and the files are deleted only if the kit created them and they are now empty |
| `--force` | Allow replacing files the kit does not own, or that you edited. Originals go to `.claude/.urk-backup/<timestamp>/` |
| `--require-version 0.1.0` | Refuse unless the checked-out kit is that version |
| `--list` | Show categories and skills |

## Version pinning

Clone a tag (`git clone --branch v0.1.0 ...`) and pass `--require-version 0.1.0` in scripts so a different checkout cannot install by accident. The manifest records the version and commit.

## Third-party skills

```bash
python3 scripts/install/third_party.py list
```

```bash
python3 scripts/install/third_party.py install el4cteo-blender-skills --target ~/games/MyGame --skills blender-core,blender-asset-qa
```

This clones the pinned commit into `~/.cache/ultimate-roblox-kit`, runs nothing, and copies the skill with `UPSTREAM_LICENSE` and `UPSTREAM_SOURCE`. Repositories marked `link` cannot be installed this way.
