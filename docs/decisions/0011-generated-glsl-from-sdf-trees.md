# 0011. Raymarching shaders generated from SDF resource trees

Status: accepted, 2026-11-22 (Lesson 10).

## Context

Lesson 10 draws signed distance fields in a fragment shader by sphere tracing. The fields exist as GDScript resource trees (`src/sdf/`, decision 0008), evaluated on the CPU by the slices, the mesher and the curvature code. A shader cannot call GDScript. The rocks are edited as `.tres` files; a second, hand-written description of each rock in GLSL would drift from the first. `FastNoiseLite`, used by `SdfDisplace`, has no GLSL counterpart in Godot.

## Decision

1. **Formulas by hand, composition generated.** `shaders/sdf/sdf_library.gdshaderinc` holds one GLSL function per primitive and operator, each a line-by-line copy of the GDScript `evaluate()` it names. `SdfGlsl` (`src/sdf/sdf_glsl.gd`) walks a resource tree and writes `float sdf_map(vec3 p0)` as a sequence of calls with the tree's numbers as literals.
2. **One template shader.** `shaders/sdf/raymarch.gdshader` holds the march, the normals, the depth output and the coloring, and a stub `sdf_map()` between the markers `// SDF_MAP_BEGIN` and `// SDF_MAP_END`. `RaymarchVolume` copies the template's code, replaces the stub, and compiles a new `Shader` per volume at load time. The template compiles on its own.
3. **Noise baked into a 3D texture.** Each distinct `FastNoiseLite` met in the tree is sampled on a 0.1 m grid over the union of the regions its `SdfDisplace` nodes need (child bounds plus 0.5 m) and stored as an `ImageTexture3D` (FORMAT_RF). The shader reads it with trilinear filtering.
4. **Step scale from the CPU library.** The shader steps by f · (1 / L) with L = `shape.lipschitz_bound()`. An infinite bound is replaced by 2 with a warning.
5. **A proxy box in the node's frame.** The box mesh has its vertices at `shape.bounds()` (grown 0.05 m) in the node's local frame, so `MODEL_MATRIX` is the node's transform and the march needs no extra offset. It is drawn with `cull_front` and casts no shadow.

## Consequences

- Editing a rock `.tres` changes the slices, the mesh and the raymarched copy alike. Editing a formula changes it in two files; tests check that every class translates and that the result compiles, not that the two copies agree numerically. Lesson 10 O2 compares silhouettes in a window.
- The noise is an approximation of the CPU noise: exact at the grid points, trilinear between them, with gradient jumps at texel faces. Normals and curvature in the shader use steps of half a texel or more.
- A new SDF class needs a GLSL function and a branch in `SdfGlsl._emit_node()`; otherwise `SdfGlsl.unsupported` names it and it is drawn as empty space.
- Each volume compiles a shader and bakes its noise (about 35 ms) when it enters the tree.
- Raymarched shapes have no collision and cast no shadow.
