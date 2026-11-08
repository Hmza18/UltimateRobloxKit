# Security

## Reporting

Report vulnerabilities privately through GitHub's "Report a vulnerability" (Security tab), not in public issues.

## What the kit does to stay safe

- **No secrets in the repository.** Tests scan every file for token patterns. Open Cloud keys belong in environment variables or CI secrets (`ROBLOX_API_KEY`), and `doctor.py` only reports whether one is set.
- **No piping downloads into a shell.** Tests reject `curl ... | sh` patterns in scripts and workflows. CI downloads pinned release archives instead.
- **Pinned third-party code.** `third_party.py` refuses short or unpinned SHAs, disables git hooks, executes nothing from a clone, and copies only reviewed skills.
- **Installer containment.** It writes only inside `<target>/.claude/`, except `.mcp.json` and `CLAUDE.md` when explicitly requested. It never overwrites files it does not own unless `--force` is given, and it backs them up first.
- **Blender MCP** runs with telemetry disabled, bound to 127.0.0.1, in an isolated Blender profile. `execute_blender_code` runs arbitrary Python, so only connect agents you trust.
- **Roblox actions.** Skills forbid publishing, uploading or editing live places without explicit permission, and only the user signs in.
- **Free models.** `asset-sourcing-licensing` and `roblox-security-anti-exploit` include a backdoor scan checklist.

## Supported versions

Only the latest release receives fixes.
