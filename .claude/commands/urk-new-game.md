---
description: Scaffold a new Roblox game from a kit template (starter-game, simulator, tycoon, obby, ui)
argument-hint: <template> <GameName> [output dir]
---
Arguments: $ARGUMENTS. Validate the template name with `python3 .claude/ultimate-roblox-kit/scripts/automation/new_project.py --list`. Create the project with `new_project.py --template <template> --name <GameName> --out <dir>` (default dir: `./<GameName>`). Then run the doctor on it and list the next steps from the template README: `rokit install`, `rojo serve`, and the tests. Do not overwrite an existing folder.
