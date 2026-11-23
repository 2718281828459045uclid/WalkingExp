# 0017. Custom lighting as an appended shader include; materials switched whole

Status: accepted, 2026-11-23 (Lesson 17).

## Context

Lesson 17 writes Godot's per-light function, `light()`, in four shading models (Lambert, wrap, Oren–Nayar, Lambert + GGX) and compares them with Godot's built-in light on the terrain (Lesson 03 shader `terrain_painted.gdshader`) and on the rocks (Lesson 09 shader `rock_weathering.gdshader`). Four constraints apply:

- The Lesson 03 and Lesson 09 shaders are explained line by line in their lessons and may not change (`CLAUDE.md`, additive evolution).
- A comparison is only fair if the surface (`fragment()`: color, roughness, normal) is the same in every model and only `light()` differs.
- A shader that defines `light()` always uses it. Inside `light()` the built-in lighting code is not reachable, so "built-in" cannot be one value of a uniform.
- Decision 0004: code does not contain asset paths; scenes assign data through exported properties.

Measured on Godot 4.6.2 (Lesson 17, README section 3.2): `LIGHT_COLOR` is the light's color × energy × π; the engine multiplies `DIFFUSE_LIGHT` by `ALBEDO` and by (1 − `METALLIC`) after `light()` and adds `SPECULAR_LIGHT` unchanged; `SPECULAR_AMOUNT` is the light's `light_specular` (1.0 by default on a `DirectionalLight3D`); the default diffuse model (no `render_mode`) is Lambert; the material's `SPECULAR` is not an input of `light()`.

## Decision

1. **`light()` lives in shader includes.** `shaders/lighting/brdf.gdshaderinc` holds the BRDF formulas as plain GLSL functions; `shaders/lighting/custom_light.gdshaderinc` holds the uniforms `light_model`, `light_term`, `light_wrap`, `light_sigma_degrees`, `light_f0` and the function `light()`. `src/render/brdf.gd` (`Brdf`) is the GDScript copy for tests.
2. **Lit shaders are generated, not copied.** `LitShader.make(base, include)` returns a new `Shader` whose code is the base shader's code followed by one line, `#include "<include's resource path>"`. The lit terrain and rock shaders therefore run the original `fragment()` unchanged. One shader is generated per base shader and cached; `LitShader.material()` copies the base material's uniform values into a new `ShaderMaterial`. Lesson 10's `SdfGlsl.splice()` builds shaders from text in the same way.
3. **Built-in versus custom is a material swap.** `ShadingSwitch` (a Node) keeps each target's original material and one lit copy per original material. Mode BUILT_IN assigns the original; the four custom modes assign the lit copy with `light_model` 0–3. On every swap the base uniforms are copied from the material shown to the material shown next, so the views set by earlier keys (Tab, V, C, U) survive. Targets are nodes whose exported `material` setter only assigns the mesh's `material_override` without rebuilding: `Terrain` (Lesson 01) and `SdfMesher` subclasses (Lessons 08–15). `BoxCourse` nodes (`Slab`, `CrawlGap`, `StepRow`) rebuild their meshes and collision when their `material` changes and are not targets; they keep the built-in light as a reference.
4. **Include paths.** Two kinds of path appear in code: the `#include "res://shaders/lighting/brdf.gdshaderinc"` line inside `custom_light.gdshaderinc`, and the line that `LitShader` writes. Decision 0004 forbids asset paths in code so that exported assets (textures, sounds, meshes) can be swapped from the Inspector. A shader include is not an asset in that sense: it is shader source, compiled together with the file that includes it, as a `preload("res://src/...")` or an `extends "res://src/..."` line in GDScript refers to other source. These code-to-code references are allowed; the Lesson 10 raymarch shader already includes `sdf_library.gdshaderinc` this way. The path that `LitShader` writes is not a literal in the code: it is the `resource_path` of a `ShaderInclude` that the scene assigns to the exported property `light_include` of `ShadingSwitch` and `ShadingGallery`, so the lit variant can be replaced from the Inspector by another include.
5. **The specular reflectance at normal incidence is a uniform.** `light_f0` (0.04) replaces the material's `SPECULAR`, which `light()` cannot read. Godot's built-in code uses f0 = 0.16 · `SPECULAR`²: 0.04 for the rocks (default `SPECULAR` 0.5), 0.0144 for the terrain (`SPECULAR` 0.3).
6. **Smith masking-shadowing: the height-correlated form, without approximation.** G2 = 1 / (1 + Λ(l) + Λ(v)) (Heitz 2014). Godot's built-in GGX uses Hammon's approximation of the same function; the separable form G1(l)·G1(v) is the alternative not taken (Lesson 17 E5).

## Consequences

- No Lesson 00–16 source or scene file changes. The Lesson 17 scene adds `Shading`, `Gallery` and `HUD/LightLabel` to a copy of the Lesson 16 scene and moves the player's spawn to face the gallery.
- Every lit material compiles its generated shader once per base shader on first use (two shaders in the scene). The shader editor cannot open the generated code; the code to read is the base shader plus the two includes.
- Ambient light, sky reflections and global illumination are added outside `light()`; the four custom models change the direct sunlight only (measured: with the sun hidden all five gallery columns read within 1 of 255 of each other, except at grazing points seen from different angles).
- On the terrain the custom GGX reflects with f0 0.04 where the built-in reflects with 0.0144; Lesson 17 O5 shows the difference.
- A new spatial shader that should take part in the comparison needs no change: a material that uses it can be added to `ShadingSwitch.targets` (through a node with a cheap `material` setter) or used as a gallery material. A shader that defines its own `light()` cannot (`LitShader.make()` refuses it with an error).
- `light()` runs once per pixel per light. The lesson takes no timing measurement; Lesson 18 measures costs.
