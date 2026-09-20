import addon_utils
import bpy


def blender_mcp_modules():
    return [
        module.__name__
        for module in addon_utils.modules(refresh=True)
        if module.bl_info.get("name") == "Blender MCP"
    ]


modules = blender_mcp_modules()
if not modules:
    raise RuntimeError("Blender MCP addon was not found")

preferred = "blender_mcp" if "blender_mcp" in modules else modules[-1]
for module_name in modules:
    if module_name != preferred:
        addon_utils.disable(module_name, default_set=True)

addon_utils.enable(preferred, default_set=True, persistent=True)
preferences = bpy.context.preferences.addons[preferred].preferences
if hasattr(preferences, "telemetry_consent"):
    preferences.telemetry_consent = False
bpy.ops.wm.save_userpref()
print(f"BLENDER_MCP_ADDON={preferred}")
print("BLENDER_MCP_TELEMETRY=OFF")
