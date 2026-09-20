---
name: open-blender-kit
description: >
  Configure, repair, launch, and use the local Blender MCP on Windows
  for procedural modeling, scene inspection, screenshots, saving, and GLB/FBX
  export. Use when working in Blender, creating or editing 3D models,
  validating a scene, rendering fixed-view Cycles glass, exporting game-engine
  assets, invoking Blender MCP tools, or troubleshooting missing uvx, addon,
  port, client configuration, or MCP connectivity. Not tied to a host game
  project.
license: MIT
metadata:
  author: MlsMoon
---

# open-blender-kit

Fix the MCP link until tools actually run, then model. A running Blender process
or a listening port is not enough.

This repository **is** the skill folder. It is not tied to any game project.
Keep the directory name, GitHub repo name, and `SKILL.md` `name` as
`open-blender-kit`. Host paths live in `local/blender.local.json`, not in this
file.

## Quick start

From this skill root:

```powershell
pwsh scripts/ensure.ps1 -CheckOnly
```

Install or repair uv, Python 3.11, the Blender addon, and Codex / Claude / Cursor
MCP config:

```powershell
pwsh scripts/ensure.ps1
```

After repair, start Blender with a hidden window:

```powershell
pwsh scripts/ensure.ps1 -Launch
```

Run an isolated real MCP modeling test (Suzanne clay mesh):

```powershell
pwsh scripts/ensure.ps1 -SmokeTest
```

`-SmokeTest` writes files and check images under `tmp/cases/` inside this skill.
It does not open or overwrite a user's current `.blend`.

## Modeling flow

1. Run `scripts/ensure.ps1 -CheckOnly`. If anything is missing, run the default
   repair. Restart the client if tools still do not appear.
2. Confirm Blender MCP tools are visible. Call `get_addon_status` and
   `get_scene_info` before writing the scene.
3. Split complex modeling into small `execute_blender_code` chunks: body,
   extras, materials, camera and lights, then save / export.
4. After each stage, read back object names, sizes, counts, and parenting with
   `get_object_info` or a scene summary.
5. Capture a screenshot at the end. Save the `.blend` where the user asked.
   Prefer `.glb` or `.fbx` when handing off to a game engine.

If you are editing an existing scene, confirm the save path and intent first.
Do not change a scene the user is editing just to test. Use an isolated Blender
instance and this skill's `tmp/`.

Fixed-view glass, Cycles / OptiX device setup, transparent Alpha, and a
single-layer proxy for a game engine follow
[`references/cycles-fixed-view-glass-bake.md`](references/cycles-fixed-view-glass-bake.md).

If a texture is already a complete glass beauty for a fixed camera, do not
project it onto every face of a closed glass mesh. Front and back surfaces
resample the same image and stack Alpha. Reordering vertices or triangles does
not remove that overlap. Use a camera-facing single-layer proxy and disable the
original glass renderer in the engine. When exporting FBX, check Geometry,
Model Scale, and units together.

## Runtime rules

- Do not host MCP with `blender --background`. The upstream addon returns to
  the main thread through `bpy.app.timers`; true background mode never handles
  commands.
- Default launch uses a normal GUI event loop with a hidden window. If hiding
  fails, minimize. Do not claim a true headless server.
- Use uv-managed Python 3.11. The MCP command is always
  `uvx --python 3.11 blender-mcp`.
- Default `DISABLE_TELEMETRY=true`. Do not enable or fill Sketchfab, Hyper3D,
  Hunyuan 3D, or similar keys unless the user asks.
- Only one Blender addon server per host/port. If a non-Blender process owns
  the port, pick a free port in 9877–9899 and update all three client configs.
- Do not kill existing Blender processes. Test scripts only stop the isolated
  instance they started.
- Machine-local paths stay in `local/blender.local.json`. Copy
  `local/blender.local.json.example` if the file is missing.

## Fault loop

Fix the error, then call MCP again. Do not blind-retry:

| Symptom | Fix |
|---|---|
| `uvx` missing | Run `scripts/ensure.ps1`. Install uv with the official installer, not `pip install uv` |
| Python / dependency clash | Pin `--python 3.11` and `UV_PYTHON_PREFERENCE=only-managed` |
| Addon missing or stale | Run `uvx blender-mcp install-addon`, re-enable the addon, restart Blender |
| 9876 in use | Identify the owner; if not Blender, pick a free port 9877–9899 and reconfigure clients |
| MCP tools missing | Check Codex, Claude, and Cursor user config, then fully restart that client |
| Connect timeout | Confirm a GUI event loop (not `--background`), then addon server and port |
| First call fails | Call status / scene tools first; only then refresh the uv cache and reinstall the addon |
| Blender 5.1 hangs after `get_devices()` | Do not retry that call. Use `get_device_list()` + `update_device_entries()`. See the glass bake reference |

## Suzanne smoke case

`scripts/build_suzanne.py` is a reusable in-Blender case. It builds Suzanne,
three check renders, a `.blend`, and a `.glb`. Use it to prove MCP can model
and export. Do not count results from an external AI asset service as success.

To inspect the exported mesh, you can follow with
[3d-model-data-reader](https://github.com/MlsMoon/3d-model-data-reader).

## Checklist

- [ ] `scripts/ensure.ps1 -CheckOnly` reports no FAIL
- [ ] `get_addon_status` and `get_scene_info` can run
- [ ] Modeling is split into small `execute_blender_code` calls with object readback
- [ ] Deliverables include a screenshot; game-engine handoff exports `.glb` / `.fbx`
- [ ] Cycles work records preview size, samples, time cap, wall time, and device fallback
- [ ] Fixed-view full beauty uses a single-layer proxy, not stacked blending on a closed mesh
- [ ] FBX size is checked with Geometry, Model Scale, UnitScaleFactor, and the engine import
- [ ] Engine saves do not drag in unrelated serialization cleanup
- [ ] The user's open `.blend` was not changed; test outputs stay in this skill's `tmp/`
