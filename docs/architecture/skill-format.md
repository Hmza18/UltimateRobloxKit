# Skill format

Every skill is a folder under `skills/<category>/<name>/` with a `SKILL.md`. Optional subfolders: `references/` (long material loaded only when the skill says so), `templates/` (files to copy), `scripts/` (runnable helpers).

## Frontmatter

The frontmatter is a restricted YAML subset so it parses without dependencies: `key: value` scalars, one nested `metadata:` map indented two spaces, and inline lists `[a, b, c]`. Quote a value with double quotes if it contains `: ` or starts with `[`.

```yaml
---
name: roblox-networking
description: Client/server communication in Roblox - RemoteEvents, RemoteFunctions, UnreliableRemoteEvents, attribute and value replication, server-authoritative validation and rate limiting. Use when adding any remote, syncing state to clients, or designing multiplayer features.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [remote, remoteevent, remotefunction, client server, replicate, multiplayer, network]
  depends: [luau-language, roblox-security-anti-exploit]
---
```

Rules, all checked by `tests/test_skills.py`:

- `name` equals the folder name, is lowercase kebab-case, and is unique across the kit.
- `description` is 80 to 1024 characters, says what the skill does and ends with when to use it. This is what Claude reads to decide activation, so put the trigger words in it.
- `metadata.category` equals the parent folder.
- `metadata.triggers` lists 3 or more lowercase words or phrases. The router scores tasks against these and the description.
- `metadata.depends` names skills that exist. Keep it to skills that must be read together; the router loads them.

## Body

Keep the body under about 250 lines. Put long tables, API lists and examples in `references/` and link them with a relative link. Use these sections, in this order, omitting any that do not apply:

1. **When to use** and **when not to use** (name the better skill).
2. **Inputs**: what the agent needs before starting.
3. **Workflow**: numbered steps with exact commands or code.
4. **Outputs**: files or changes produced.
5. **Validation**: how to prove it worked, commands first.
6. **Pitfalls**: real failure modes and their fixes.
7. **Limitations**: what the skill cannot do or verify.

Code is Luau with `--!strict` where practical, and uses current Roblox APIs (for example `task.wait`, not `wait`; `Players.PlayerAdded`, `Instance:GetAttribute`). Prefer server authority.

Every relative path in a skill is either relative to the skill folder (`references/x.md`) or written as a kit path in backticks starting with a top-level kit folder (`scripts/...`, `tools/...`, `templates/...`). The installer copies the kit's `scripts`, `tools` and `templates` into `.claude/ultimate-roblox-kit/` in a target project, so skills can say `python3 .claude/ultimate-roblox-kit/scripts/...` when installed; inside this repository the same files are at the top level. Use the placeholder `$URK` in commands to mean "the kit root": the repository root here, `.claude/ultimate-roblox-kit` in an installed project.
