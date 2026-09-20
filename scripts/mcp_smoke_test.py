import argparse
import asyncio
import base64
import json
import os
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def text_content(result):
    return "\n".join(getattr(item, "text", "") for item in result.content if hasattr(item, "text"))


async def run(args):
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ)
    environment.update(
        {
            "BLENDER_HOST": args.host,
            "BLENDER_PORT": str(args.port),
            "DISABLE_TELEMETRY": "true",
            "UV_PYTHON_PREFERENCE": "only-managed",
        }
    )
    parameters = StdioServerParameters(
        command=args.uvx,
        args=["--python", "3.11", "blender-mcp"],
        env=environment,
    )
    prompt = "Validate Blender MCP by building Suzanne and capturing a viewport screenshot."

    async with stdio_client(parameters) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            tools = await session.list_tools()
            names = {tool.name for tool in tools.tools}
            required = {
                "disable_telemetry",
                "execute_blender_code",
                "get_addon_status",
                "get_object_info",
                "get_scene_info",
                "get_viewport_screenshot",
            }
            missing = required - names
            if missing:
                raise RuntimeError(f"Missing Blender MCP tools: {sorted(missing)}")

            telemetry = await session.call_tool("disable_telemetry", {"user_prompt": prompt})
            if telemetry.isError or "now OFF" not in text_content(telemetry):
                raise RuntimeError("Blender MCP telemetry could not be disabled")
            print("TELEMETRY_OFF=1")

            addon = await session.call_tool("get_addon_status", {"user_prompt": prompt})
            addon_text = text_content(addon)
            if addon.isError or '"telemetry_consent": false' not in addon_text:
                raise RuntimeError("Blender MCP telemetry consent is still enabled")
            print("ADDON_STATUS=" + addon_text.replace("\n", " ")[:800])
            scene = await session.call_tool("get_scene_info", {"user_prompt": prompt})
            if scene.isError:
                raise RuntimeError(text_content(scene))
            print("SCENE_INFO_OK=1")

            if args.health_only:
                return

            cube_code = (
                "import bpy\n"
                "bpy.ops.mesh.primitive_cube_add(location=(0,0,0))\n"
                "bpy.context.object.name='OBK_Smoke'\n"
                "bpy.context.object.scale=(1.0,1.5,0.5)\n"
            )
            cube = await session.call_tool(
                "execute_blender_code", {"code": cube_code, "user_prompt": prompt}
            )
            if cube.isError or "Error" in text_content(cube):
                raise RuntimeError(text_content(cube))
            cube_info = await session.call_tool(
                "get_object_info", {"object_name": "OBK_Smoke", "user_prompt": prompt}
            )
            if cube_info.isError or "OBK_Smoke" not in text_content(cube_info):
                raise RuntimeError("MCP smoke object could not be read back")
            print("SMOKE_OBJECT_OK=1")

            case_source = Path(args.case_script).read_text(encoding="utf-8")
            case_code = (
                "BLENDER_MCP_RUN_CASE=True\n"
                f"BLENDER_MCP_OUTPUT_DIR={str(output_dir)!r}\n"
                + case_source
            )
            case_result = await session.call_tool(
                "execute_blender_code", {"code": case_code, "user_prompt": prompt}
            )
            case_text = text_content(case_result)
            if case_result.isError or "Error" in case_text:
                raise RuntimeError(case_text)
            print("SUZANNE_CASE_OK=1")

            monkey = await session.call_tool(
                "get_object_info", {"object_name": "OBK_Suzanne", "user_prompt": prompt}
            )
            if monkey.isError or "OBK_Suzanne" not in text_content(monkey):
                raise RuntimeError("Suzanne could not be read back")
            print("SUZANNE_READBACK_OK=1")

            screenshot = await session.call_tool(
                "get_viewport_screenshot", {"max_size": 1000, "user_prompt": prompt}
            )
            screenshot_saved = False
            for item in screenshot.content:
                data = getattr(item, "data", None)
                if data:
                    (output_dir / "suzanne-mcp-viewport.png").write_bytes(base64.b64decode(data))
                    screenshot_saved = True
                    print("MCP_VIEWPORT_OK=1")
                    break
            if screenshot.isError or not screenshot_saved:
                raise RuntimeError("MCP viewport screenshot was not returned")

    expected = [
        output_dir / "suzanne-whitebox.blend",
        output_dir / "suzanne-whitebox.glb",
        output_dir / "suzanne-perspective.png",
        output_dir / "suzanne-front.png",
        output_dir / "suzanne-side.png",
        output_dir / "suzanne-mcp-viewport.png",
    ]
    missing_outputs = [str(path) for path in expected if not path.is_file() or path.stat().st_size == 0]
    if missing_outputs:
        raise RuntimeError("Missing case outputs: " + json.dumps(missing_outputs))
    print("ALL_OUTPUTS_OK=1")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uvx", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9876)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--case-script", required=True)
    parser.add_argument("--health-only", action="store_true")
    arguments = parser.parse_args()
    asyncio.run(run(arguments))


if __name__ == "__main__":
    main()
