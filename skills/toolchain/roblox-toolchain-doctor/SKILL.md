---
name: roblox-toolchain-doctor
description: Sets up and diagnoses the Roblox code toolchain - Rokit, Rojo, Wally, Selene, StyLua, luau-lsp, Lune - plus Blender, Roblox Studio and MCP registration, with pinned versions and a doctor script that reports exactly what is missing. Use when starting a project, when "rojo isn't working", when asked whether the machine is ready, or before any install work.
license: MIT
metadata:
  category: toolchain
  version: 1.0.0
  triggers: [rokit, rojo, wally, selene, stylua, luau-lsp, lune, doctor, toolchain, setup, install tools]
  depends: []
---

# Roblox toolchain and doctor

## When to use

Project setup, broken tooling, version pinning, CI tool installs. For Studio's MCP server itself use `roblox-studio-mcp`.

## Workflow

1. Diagnose first, change nothing:
   `python3 $URK/scripts/install/doctor.py` (add `--json` for machine output, `--project <dir>` to check a Rojo project).
   It reports each tool as `ok`, `missing` or `version mismatch` against the pins in the project's `rokit.toml`, and checks Blender, Roblox Studio, `.mcp.json` and Open Cloud environment variables (presence only, never values).
2. Install Rokit, the one tool manager. Prefer a package manager over piping scripts into a shell:
   - macOS: `brew install rokit` if available, otherwise download the pinned release from github.com/rojo-rbx/rokit/releases and verify it before running.
   - Windows: the release `.zip` from the same page. Then run `rokit self-install` once to add it to PATH.
   Ask the user before installing anything system-wide.
3. Install the project's pinned tools: `rokit install` in the project folder (reads `rokit.toml`). The kit's templates pin: rojo 7.7.1, wally 0.3.2, selene 0.32.0, stylua 2.6.0, lune 0.11.1, luau-lsp 1.70.1 (verified latest releases on 2026-11-08; bump deliberately).
4. Packages: `wally install` writes `Packages/`. Add `Packages` to `default.project.json` only once it exists.
5. Editor: install the Luau Language Server extension, then `rojo sourcemap --watch -o sourcemap.json` so luau-lsp resolves Rojo paths.
6. Studio sync: install the Rojo Studio plugin (`rojo plugin install`), run `rojo serve`, click Connect in Studio.

## Validation

- `rokit list` shows every pinned tool; `doctor.py` exits 0.
- In a template project: `rojo build -o build.rbxl`, `selene src`, `stylua --check src`, `lune run tests/run` all succeed.

## Pitfalls

- Two tool managers (Aftman and Rokit) on PATH resolve different versions. Keep one.
- `luau-lsp` downloads Roblox API definitions; offline it falls back to stale types.
- `selene` needs `std = "roblox"`; the first run generates `roblox.yml`, so commit or regenerate it in CI.
- Rojo cannot sync binary models it did not create; keep `.rbxm` assets under a dedicated folder.

## Limitations

The doctor detects; it does not install. Studio is not scriptable from CI, so Studio checks are presence checks only.
