# 0018. Shadow and GI configurations as preset Resources; measured by frame time and screen probes

Status: accepted, 2026-11-23 (Lesson 18).

## Context

Lesson 18 compares the sun's shadow configurations (cascade layout, range, atlas size, filter, sun size) and the global illumination techniques of Godot 4.6.2 Forward+ (SSAO, SSIL, SDFGI, VoxelGI, LightmapGI) in the Lesson 17 scene, and produces a table of cost against quality. Constraints and measured facts:

- Decision 0004: code does not contain asset paths or tuning values that belong in data; scenes assign `.tres` files.
- The settings live in four places: the `DirectionalLight3D` (mode, splits, range, blend, bias, angular size), the `Environment` (SSAO, SSIL, SDFGI), a `VoxelGI` node, and two project settings (`rendering/lights_and_shadows/directional_shadow/size` and `.../soft_shadow_filter_quality`) that `RenderingServer.directional_shadow_atlas_set_size()` and `directional_soft_shadow_filter_set_quality()` change at run time.
- `RenderingServer.viewport_get_measured_render_time_gpu()` returns 0 on the Metal backend (Lesson 10, measured again in Lesson 18). Frame time with vsync off and the render-info counters (draw calls and primitives per pass) are available.
- The terrain and the rocks are generated at run time into internal children (decision 0009 and Lesson 01); no mesh of the scene is saved, and none carries a second UV set (`Mesh.ARRAY_FORMAT_TEX_UV2` absent, measured on the terrain mesh).
- `LightmapGI` has no `bake()` method in ClassDB (Godot 4.6.2); baking runs in the editor through its plugin, and needs UV2 on every static mesh.
- `VoxelGI.bake()` is in ClassDB and works in a running game: 336–340 ms for a 44 × 18 × 40 m box at 128 subdivisions on the scene (windowed). Headless, it returns empty data without an error (the dummy renderer keeps no mesh arrays).
- With SDFGI switched on, Godot 4.6.2 on Metal fails to build pipelines for shaders that write `DEPTH` (the Lesson 10 raymarch shader): "depthAttachmentPixelFormat is not valid and shader writes to depth", once per raymarched volume, and "Invalid Task ID" errors when the game quits. Hiding or detaching the volumes does not prevent it; freeing them does (measured).

## Decision

1. **A preset is a Resource.** `LightPreset` (`src/render/light_preset.gd`) holds every value the lesson varies. Its defaults are the Lesson 17 scene's values, so a new preset changes only what is set on it. The presets are `.tres` files in `game/data/lighting/`.
2. **One node applies them.** `LightPresetSwitch` (`src/render/light_preset_switch.gd`) is given the sun, the `WorldEnvironment`, the `VoxelGI` node and an array of presets through exported properties. `apply(i)` writes every value of preset i; F8 steps through the array. A bias override (F9) is kept apart from the presets, so that the acne and peter-panning study works on top of any preset.
3. **VoxelGI is baked at run time, once, on first use.** The scene saves the `VoxelGI` node without data. No `VoxelGIData` file is stored in the repository; the bake matches whatever the scene generated.
4. **SDFGI frees the raymarched formations.** The switch's `sdfgi_conflicts` list holds the three `RaymarchVolume` nodes; the first preset with SDFGI frees them for the rest of the session. SDFGI voxelizes meshes, and the mesh of a raymarched volume is its bounding box, so SDFGI could not have used them.
5. **LightmapGI is not a preset.** Baking needs the editor and UV2 on generated meshes; Lesson 18 leaves it to an exercise (E7), and its row of the measured table stays empty.
6. **Measurement.** `tools/light_perf.sh` (with `tools/godot/light_perf.gd`) runs the scene in a window with vsync off, at four fixed camera views, measures every preset for a number of frames in several interleaved rounds, and reports the median and the 95th and 99th percentiles of the frame time, the draw calls and triangles of the shadow pass and of the main pass, and quality probes read from screenshots at known world points (screen value of the climbing face and of the gap's floor, width and contrast of a shadow edge relative to the preset without sun shadow).

## Consequences

- No Lesson 00–17 code changes. The Lesson 18 scene is the Lesson 17 scene plus `VoxelGI` and `Lighting`; `test_17_light_scene.gd` hands its `run/main_scene` check to `test_18_light_presets.gd`.
- The atlas size and filter quality are renderer-wide: a preset that changes them affects every viewport until another preset sets them back, and the project file keeps its values.
- After an SDFGI preset the formations of Lesson 10 are gone until the scene is reloaded; key Z then toggles an empty node.
- Frame times include the CPU's work; the table compares presets on one machine and does not give GPU milliseconds per technique.
- The quality probes are screen values after tonemapping (AgX), comparable between presets of one run, not radiometric quantities. Lesson 18 uses a separate scratch measurement in linear units (float viewport, Linear tonemapping) where the rendering equation is compared with the engine.
