# AGENTS.md

Instructions for AI coding agents other than Claude Code (Codex, Cursor, Gemini CLI and others) that read `AGENTS.md`.

The skills are plain Markdown with YAML frontmatter, so any agent can use them:

1. Find the relevant skills by running `python3 scripts/automation/route.py "<task>"` (`--json` gives machine output). In an installed project, use `python3 .claude/ultimate-roblox-kit/scripts/automation/route.py`.
2. Read each listed `SKILL.md` in order, and open its `references/` files only when the skill points to them.
3. In skills, `$URK` means the kit root: this repository, or `.claude/ultimate-roblox-kit` in an installed project.
4. Follow `skills/orchestration/kit-conventions/SKILL.md`. Never publish to Roblox without explicit permission, never approve work on the user's behalf, and never report unrun checks as passed.

To work on the kit itself, follow `CLAUDE.md` in this repository, which applies to every agent.
