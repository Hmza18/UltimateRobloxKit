# Quick start (5 minutes)

You need Python 3.9 or newer and Claude Code. Everything else is optional.

1. Get the kit, pinned to a release:
   ```bash
   git clone --branch v0.1.0 https://github.com/Hmza18/UltimateRobloxKit.git
   ```
   Until the first release is tagged, clone `main` without `--branch`.
2. Preview what would be installed in your project:
   ```bash
   python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --dry-run
   ```
3. Install:
   ```bash
   python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --with-claude-md
   ```
4. Start a **new** Claude Code session in `~/games/MyGame`, because skills load at session start.
5. Try it:
   - `/urk-doctor` reports what tools are missing.
   - `/urk-route build a simulator with pets` shows a plan.
   - `/urk-new-game simulator ClickQuest` scaffolds a Rojo project.

Next: [beginner setup](beginner-setup.md) installs Rojo and friends; [advanced setup](advanced-setup.md) covers user-wide installs, selective skills, MCP and CI.
