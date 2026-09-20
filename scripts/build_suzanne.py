import json
from pathlib import Path

import bpy
from mathutils import Vector


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)


def clay_material():
    material = bpy.data.materials.get("OBK_Clay") or bpy.data.materials.new("OBK_Clay")
    material.diffuse_color = (0.85, 0.62, 0.38, 1.0)
    material.metallic = 0.0
    material.roughness = 0.55
    return material


def apply_material(obj, material):
    if obj.type == "MESH":
        obj.data.materials.clear()
        obj.data.materials.append(material)


def point_at(obj, target=(0.0, 0.0, 0.2)):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_camera_and_lights(collection):
    camera_data = bpy.data.cameras.new("OBK_Camera")
    camera = bpy.data.objects.new("OBK_Camera", camera_data)
    collection.objects.link(camera)
    camera_data.lens = 50
    bpy.context.scene.camera = camera

    for name, location, energy, size in (
        ("OBK_Key", (3.5, -4.5, 4.0), 900, 4.5),
        ("OBK_Fill", (-3.0, -2.0, 2.5), 400, 4.0),
        ("OBK_Rim", (0.5, 4.0, 3.0), 500, 3.5),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        light.location = location
        point_at(light)
        collection.objects.link(light)
    return camera


def build_suzanne(output_dir):
    clear_scene()
    scene = bpy.context.scene
    root = bpy.data.collections.new("OBK_SuzanneCase")
    scene.collection.children.link(root)
    material = clay_material()

    bpy.ops.mesh.primitive_monkey_add(location=(0.0, 0.0, 0.0))
    suzanne = bpy.context.object
    suzanne.name = "OBK_Suzanne"
    apply_material(suzanne, material)
    for current in list(suzanne.users_collection):
        current.objects.unlink(suzanne)
    root.objects.link(suzanne)

    camera = add_camera_and_lights(root)
    render_engines = {item.identifier for item in scene.render.bl_rna.properties["engine"].enum_items}
    scene.render.engine = next(
        engine
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH")
        if engine in render_engines
    )
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("OBK_World")
    scene.world.color = (0.04, 0.045, 0.05)

    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    views = {
        "perspective": ((4.6, -4.8, 2.6), (0.0, 0.0, 0.2)),
        "front": ((0.0, -6.2, 0.6), (0.0, 0.0, 0.2)),
        "side": ((6.2, 0.0, 0.8), (0.0, 0.0, 0.2)),
    }
    for view_name, (location, target) in views.items():
        camera.location = location
        point_at(camera, target)
        scene.render.filepath = str(output / f"suzanne-{view_name}.png")
        bpy.ops.render.render(write_still=True)

    blend_path = output / "suzanne-whitebox.blend"
    glb_path = output / "suzanne-whitebox.glb"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.export_scene.gltf(filepath=str(glb_path), export_format="GLB", export_apply=True)

    summary = {
        "collection": root.name,
        "object": suzanne.name,
        "blend": str(blend_path),
        "glb": str(glb_path),
    }
    print("OBK_SUZANNE=" + json.dumps(summary, ensure_ascii=True))
    return summary


if globals().get("BLENDER_MCP_RUN_CASE"):
    build_suzanne(globals()["BLENDER_MCP_OUTPUT_DIR"])
