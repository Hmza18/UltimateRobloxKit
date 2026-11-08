# Beginner setup

This walks through a working Roblox + Claude Code environment from nothing. Each step says how to check it.

## 1. Python and git

macOS: `python3 --version` (install Xcode Command Line Tools if missing: `xcode-select --install`). Windows: install Python from python.org and tick "Add to PATH", then `py -3 --version`. Install git from git-scm.com.

## 2. Roblox Studio

Download from create.roblox.com and sign in yourself. Agents never sign in for you.

## 3. Rokit and the code tools

Rokit installs and pins Rojo, Selene, StyLua, Lune and the rest per project.

1. Download the release for your OS from https://github.com/rojo-rbx/rokit/releases (version 1.2.0 was reviewed), unzip it, and run `./rokit self-install` (Windows: `rokit.exe self-install`). Open a new terminal.
2. Create a game from a template (step 5), then run `rokit install` inside it. That installs the pinned tools.
3. Check: `python3 scripts/install/doctor.py --project <your game>` shows `ok` for rojo, selene, stylua and lune.

## 4. Rojo in Studio

In the project run `rojo plugin install` once, then `rojo serve`. In Studio, open a new place, then go to Plugins → Rojo → Connect. Edits to files now sync into Studio.

## 5. A game from a template

```bash
python3 UltimateRobloxKit/scripts/automation/new_project.py --template starter-game --name MyGame --out ~/games/MyGame
```

```bash
python3 UltimateRobloxKit/scripts/install/install.py --target ~/games/MyGame --with-claude-md
```

## 6. Blender (only for 3D assets)

Install Blender 4.2 LTS or newer from blender.org. The kit finds it in the default location, or set `BLENDER=/path/to/blender`. Check by running `python3 scripts/install/doctor.py`, which should show `ok blender`.

## 7. First conversation

Open Claude Code in the game folder and ask for something small, such as "add a coins leaderstat that saves". Claude should pick up `roblox-data-persistence` and `roblox-architecture`, then follow their validation steps.

Stuck? See [troubleshooting](../troubleshooting/README.md).
