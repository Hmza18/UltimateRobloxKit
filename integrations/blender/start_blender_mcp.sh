#!/usr/bin/env bash
# Launch an ISOLATED Blender with the MCP add-on listening on 127.0.0.1:9876.
# BLENDER_USER_RESOURCES redirects prefs and add-ons, so the user's normal Blender profile is untouched.
set -euo pipefail
PROJECT="${URK_PROJECT:-$PWD}"
URK_HOME="${URK_HOME:-$PROJECT/.urk/blender-mcp}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
ADDON_SRC="$("$URK_HOME/venv/bin/python" -c 'import blender_mcp, os; print(os.path.join(os.path.dirname(blender_mcp.__file__), "bundled", "addon.py"))')"
export BLENDER_USER_RESOURCES="$URK_HOME/blender_user"
mkdir -p "$BLENDER_USER_RESOURCES/scripts/addons"
cp "$ADDON_SRC" "$BLENDER_USER_RESOURCES/scripts/addons/blender_mcp_addon.py"
exec "$BLENDER" --python-expr "import addon_utils; addon_utils.enable('blender_mcp_addon', default_set=False)"
