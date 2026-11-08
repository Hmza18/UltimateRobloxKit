# Troubleshooting and common errors

## Installer

| Message | Cause | Fix |
|---|---|---|
| `Refusing to overwrite files the kit does not own or that you changed` | A same-named file exists, or you edited an installed skill | Move it, or rerun with `--force` (it is backed up to `.claude/.urk-backup/`) |
| `The kit is already installed ... Use --update or --uninstall` | Manifest exists | `--update` |
| `Kit version is X, but Y was required` | Wrong checkout | `git checkout vY` |
| Skills don't show up in Claude Code | Skills load at session start | Start a new session; check `.claude/skills/<name>/SKILL.md` exists |
| Two copies of a skill | Installed in both user and project scope | Uninstall one scope |

## Router

| Symptom | Fix |
|---|---|
| `Workflows: none matched` | Rephrase with the domain noun ("inventory", "map", "props"), or name the skill |
| `Not installed here` | A selective install left out a workflow skill; `install.py --update --skills <names>` |

## Asset pipeline

| Symptom | Cause | Fix |
|---|---|---|
| `build_asset.py failed`; log says `keyword ... unrecognized` | Blender API changed | Report it. The script filters glTF options; other operators may need the same treatment |
| `Blender not found` | Not in a standard location | `export BLENDER=/path/to/blender` |
| `contact sheet: SKIPPED` | Pillow missing | `python3 -m pip install pillow`, or inspect `views/` |
| `generator_proportions: NEEDS MANUAL REVIEW` | Generator built at reference proportions then stretched | Check renders; choose sizes closer to the generator's shape |
| Dark seams or holes in renders | Open or flipped faces | Fix the generator; `validate()` must report closed and outward |
| Model 100x too big in Studio | FBX exported at scale 1.0 | Use the kit's export (0.01) |
| Model lies on its back in Studio | Transforms not applied or wrong axes | Re-export with Apply Transform; front is -Y in Blender |
| Texture missing in Studio | Importer did not link the PNG | Set `TextureID` or a SurfaceAppearance |

## Toolchain

| Symptom | Fix |
|---|---|
| `rojo: command not found` after `rokit install` | Run `rokit self-install` once and open a new terminal |
| Selene: unknown global `game` | `std = "roblox"` in `selene.toml`, then `selene generate-roblox-std` |
| luau-lsp can't resolve requires | `rojo sourcemap --watch -o sourcemap.json` |
| `lune: unknown require` | Lune resolves relative to the requiring file; use `./` and `../` paths |

## MCP

| Symptom | Fix |
|---|---|
| Server missing in Claude Code | Restart the session; approve the project server |
| Blender tools time out | Start `integrations/blender/start_blender_mcp.sh` first; free port 9876 |
| Studio `ENOENT` | Studio updated and the path changed; re-point `StudioMCP` |

## Studio and data

| Symptom | Fix |
|---|---|
| DataStore errors in Studio | Game Settings → Security → Enable Studio Access to API Services (test experience only) |
| Animations play in Studio but not live | Animation asset owner differs from the experience owner |
| Remote spam or exploits | Follow `roblox-security-anti-exploit`: validate and rate-limit on the server |
