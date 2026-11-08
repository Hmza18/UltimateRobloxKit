#!/usr/bin/env bash
# Create an isolated Python environment with the reviewed, pinned Blender MCP server.
# Nothing system-wide is changed: everything goes under $URK_HOME (default: <project>/.urk/blender-mcp).
# Usage: bash integrations/blender/setup_blender_mcp.sh [project_dir]
set -euo pipefail
PROJECT="${1:-$PWD}"
URK_HOME="${URK_HOME:-$PROJECT/.urk/blender-mcp}"
# Reviewed 2026-11-06 in the supermarket project; see third_party/manifest.json.
PIN="2e4b0bc294694b1570d76ed01be657c22e6d02a0"
PY="${PYTHON:-python3}"
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "mcp-for-blender needs Python 3.10+ (set PYTHON=...)")'
mkdir -p "$URK_HOME"
"$PY" -m venv "$URK_HOME/venv"
"$URK_HOME/venv/bin/pip" install --quiet "git+https://github.com/ahujasid/mcp-for-blender@${PIN}"
echo "Installed mcp-for-blender@${PIN:0:7} into $URK_HOME/venv"
echo "Add the 'blender' server from integrations/mcp/mcp.example.json to $PROJECT/.mcp.json"
