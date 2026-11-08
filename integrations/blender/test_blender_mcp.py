"""End-to-end Blender MCP check: MCP stdio client -> server -> add-on -> Blender.

Requires start_blender_mcp.sh to be running. Run with the MCP venv's Python:
  .urk/blender-mcp/venv/bin/python integrations/blender/test_blender_mcp.py
Performs one reversible operation (add a cube, measure, delete) and prints MCP_E2E PASS or FAIL.
"""
import asyncio
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = Path(__file__).resolve().parent
CODE = """
import bpy, json
before = sorted(o.name for o in bpy.data.objects)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
dims = list(cube.dimensions)
bpy.data.objects.remove(cube, do_unlink=True)
print(json.dumps({"version": bpy.app.version_string, "dims": dims, "restored": before == sorted(o.name for o in bpy.data.objects)}))
"""


async def main() -> int:
    params = StdioServerParameters(command="bash", args=[str(HERE / "blender_mcp_server.sh")])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = sorted(t.name for t in (await session.list_tools()).tools)
            print(f"tools ({len(tools)}): {', '.join(tools)}")
            result = await session.call_tool("execute_blender_code", {"code": CODE, "user_prompt": "kit connection test"})
            text = result.content[0].text if result.content else ""
            print(text[:400])
            ok = not result.isError and '"restored": true' in text
            print("MCP_E2E", "PASS" if ok else "FAIL")
            return 0 if ok else 1


sys.exit(asyncio.run(main()))
