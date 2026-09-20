import ctypes
import os
import pathlib
import time

import addon_utils
import bpy


PORT = int(os.environ.get("BLENDER_MCP_PORT", "9876"))
LOG_PATH = pathlib.Path(os.environ.get("BLENDER_MCP_LOG", "blender-mcp-startup.log"))


def log(message):
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as stream:
        stream.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")


def hide_process_windows():
    if os.name != "nt":
        return

    user32 = ctypes.windll.user32
    process_id = os.getpid()
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    def visit(window, _):
        owner = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(window, ctypes.byref(owner))
        if owner.value == process_id and user32.IsWindowVisible(window):
            user32.ShowWindow(window, 0)
        return True

    user32.EnumWindows(callback_type(visit), 0)


def start_server():
    try:
        modules = [
            module.__name__
            for module in addon_utils.modules(refresh=True)
            if module.bl_info.get("name") == "Blender MCP"
        ]
        if not modules:
            raise RuntimeError("Blender MCP addon not found")

        preferred = "blender_mcp" if "blender_mcp" in modules else modules[-1]
        addon_utils.enable(preferred, default_set=True, persistent=True)
        bpy.context.scene.blendermcp_port = PORT
        if not bpy.context.scene.blendermcp_server_running:
            bpy.ops.blendermcp.start_server()
        hide_process_windows()
        log(f"READY module={preferred} port={PORT}")
    except Exception as exc:
        log(f"FAIL {type(exc).__name__}: {exc}")
        raise
    return None


log(f"START pid={os.getpid()} port={PORT}")
bpy.app.timers.register(start_server, first_interval=1.0)
