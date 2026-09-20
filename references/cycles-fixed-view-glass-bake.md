# Fixed-view Cycles glass bake

Use this when the camera and the model's rest pose are fixed, and runtime only
needs one viewing direction. Bake thick-glass edges and a clear center in
Blender Cycles, then composite once in the game engine with a single-layer
projected proxy.

This note is not tied to a host game project. Do not write host paths here.

## Delivery boundary

- Blender works on a copy of the runtime mesh. Solidify, Bevel, lights, and
  reflector cards exist only for the bake.
- Keep the original glass mesh, but disable its renderer at runtime. Do not
  project a full beauty onto every face of a closed mesh.
- New look uses its own shader, material, and overlay mesh. Do not edit a
  shared glass path used by other assets.
- Write `.blend`, previews, finals, and metadata into an isolated case folder
  under this skill's `tmp/`. The engine receives the texture, proxy FBX, and a
  dedicated shader.

## Why triangle sort is not enough

Transparent triangles can be sorted by depth for a fixed camera. Sort only
changes blend order; it does not remove overlap. A closed glass shell usually
hits the same screen pixel on both front and back. If every face samples the
same full beauty, color and Alpha stack.

When diagnosing, measure:

1. Triangle-center depth along the camera back axis, and index-order breaks.
2. How many layers cover each screen pixel. If every live pixel has at least
   two layers, changing index or vertex order will not fix it.
3. Remaining projection overlap on a single facing plane. A non-convex outline
   can still cover twice even if you keep only the front.

When the view is fixed and the beauty already contains front and back glass,
use a `4 vertices / 2 triangles` proxy:

- Plane normal faces the camera.
- Place the plane at the original mesh's max depth along the camera back axis,
  plus a small epsilon, so it sits in front of interior solids.
- Width and height come from the orthographic camera framing. UVs are full
  `0..1`.
- In the engine, disable the original glass renderer. The proxy uses
  `ZWrite Off / ZTest LEqual / Cull Back` and standard Alpha blend.

Do not add a per-frame mesh sort at runtime. Fixed-view assets finish order and
framing in the DCC.

## MCP chunks

Split the work. Read objects back and save the `.blend` after each chunk:

1. Import the real mesh. Check object names, units, transforms, and face count.
2. Make a render copy. Add inward Solidify and Bevel.
3. Set up Glass BSDF, an orthographic camera, lights, and a narrow reflector card.
4. Configure the Cycles device and run a cheap preview.
5. Grade transparent PNG Alpha and composite on light and dark backgrounds.
6. Build the single-layer proxy, read back `4 vertices / 2 faces`, save, export FBX.

Do not pack device enum, a heavy scene build, and a render into one
`execute_blender_code`. On timeout, only restart an isolated Blender this task
started (PID and port already checked), then continue from the last save.

## Blender 5.1 API traps

Calling Cycles prefs `get_devices()` on a hidden GUI instance can freeze the
Blender main thread. Use:

```python
preferences = bpy.context.preferences.addons["cycles"].preferences
preferences.compute_device_type = "OPTIX"
device_list = preferences.get_device_list("OPTIX")
preferences.update_device_entries(device_list)

for device in preferences.devices:
    device.use = device.type == "OPTIX"
```

In Blender 5.1 the scene compositor entry is no longer `scene.node_tree`. The
live property is `scene.compositing_node_group`, and old types such as
`CompositorNodeMath` may be missing. For simple Alpha grade, keep the raw
Cycles PNG and do verified pixel processing. Do not retry unknown compositor
nodes.

## Render budget

First pass defaults:

- `256x256 / 16 Samples`
- Adaptive Threshold `0.1`, Min Samples `4`
- OIDN, OptiX when available
- Time cap `20s`, hard limit under one minute

Final pass: try `1024x1024 / 64 Samples`, Adaptive Threshold `0.04`, Min Samples
`8`, time cap `55s`. Record wall time. Do not start at 2048 or hundreds of
samples.

## Thickness and studio

- Solidify inward so the outer silhouette stays put. Start near `1%` of
  projected viewport width.
- Bevel from about `0.25%` of projected viewport width. Few segments; they
  only need a readable rim.
- Glass BSDF can start at IOR `1.45`, Roughness `0.01` to `0.025`.
- A large black card turns into a wide grey-black mass inside closed glass.
  For a clear look, drop wide cards; keep only a narrow side and bottom card.
- Transparent PNG viewers may show RGB and ignore Alpha. Compute Alpha stats
  and composite onto white and dark backgrounds. Do not trust a transparent
  thumbnail.

## Alpha grade

Cycles beauty RGB can keep thick rims and refraction, while physical Alpha
makes large planes too solid. Save raw RGBA first, then grade Alpha only. For
a reference-like grey rim, darken high-Alpha edges a little by original
coverage.

Verified starting formula for clear glass, `a` = original Alpha, `L` = screen
luminance:

```text
darkness = max(0, (0.70 - L) / 0.70)
coverage = min(1, 4 * a)
alpha_final = min(1, 0.08*a + 0.44*a^3 + 0.34*darkness*coverage)
edge_mix = 0.78*a^2
```

`edge_mix` only pulls bright high-Alpha edges toward neutral grey. The formula
is not an art constant. Record body center, rim, base, image mean, and max,
then judge against the reference and the game background.

## Proxy construction

Transform Blender camera local X/Y/Z into model space to get
`right / up / back`:

```text
depth = max(dot(vertex, back)) + epsilon
center_u = dot(camera_position, right)
center_v = dot(camera_position, up)
height = camera.ortho_scale
width = height * render_aspect
center = right*center_u + up*center_v + back*depth
```

The four corners are `center +/- right*width/2 +/- up*height/2`. Counterclockwise
from the camera, UVs `(0,0) (1,0) (1,1) (0,1)`, triangles `(0,1,2)` and
`(0,2,3)`.

## Blender FBX units

Do not judge export size from the FBX Geometry AABB alone. A Blender meter
scene exported with `global_scale=1` into a centimeter FBX can keep meter-scale
Geometry while Model `Lcl Scaling` is `100`. Final size is the product.

- Read `UnitScaleFactor`, Geometry vertices, and Model `Lcl Scaling` together.
- Compare combined world size to the source mesh. Do not set
  `global_scale=100` just because Geometry looks 100× too small.
- For this asset class use `axis_forward=-Z / axis_up=Y / global_scale=1`. After
  Unity import, a child X `-90` is a normal axis conversion. Do not zero it by
  hand.

## Engine hookup and save risk

- The shader samples the proxy mesh UV once. Do not store or compute
  object-space projection axes.
- Overlay renderer uses the target layer / rendering layer. Disable shadows,
  light probes, reflection probes, and motion vectors.
- The shipping prefab and the edit preview should share the overlay asset.
  The original glass renderer stays disabled.
- Saving a prefab through a blocking editor command that waits inside
  `EditorApplication.update` can time out. Queue the save onto
  `EditorApplication.delayCall` (or the engine's equivalent idle callback).
- Saving a large old scene can strip unrelated stale serialized fields. Snapshot
  files first, then full-text diff after save. Restore everything outside this
  task. Keep only the target renderer and overlay changes.

## Done when you have

- Blender MCP status, scene / object readback, viewport screenshot, and the
  saved `.blend`.
- Preview / final settings, wall time, device, and Alpha stats.
- Overlay FBX Geometry, UVs, winding, Model transform, and combined size.
- Engine shader / material / texture refs and a screenshot at target resolution.
- If unrelated compile errors block Play Mode, list those files. Static checks
  do not count as a running verify.
