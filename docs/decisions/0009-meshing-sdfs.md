# 0009. Meshing SDFs by surface nets, pass 1 on the GPU with a CPU fallback

Status: accepted, 2026-11-22 (Lesson 08).

## Context

Lesson 08 turns the zero set of an `SdfShape` (decision 0008) into a render mesh and a collision shape. The shapes are evaluated in GDScript at about 5.7 µs per call. The ROADMAP asks for a compute-shader path through `RenderingDevice`. Headless runs (`tools/check.sh`) have no `RenderingDevice`. Later lessons need a mesh that is closed (collision), consistently oriented (rendering), and preferably manifold (Lesson 21, halfedge mesh).

## Decision

1. **Naive surface nets** (one vertex per cell with mixed signs, at the average of the linear edge crossings; one quad per sign-changing grid edge). Marching cubes is left to an exercise (Lesson 08 E1). Surface nets needs no case table, gives one vertex per cell (a regular, compact mesh), and its two passes separate cleanly into a fixed-size pass and a variable-size pass.
2. **Sampling stays in GDScript** through `SdfShape.evaluate()`. GPU evaluation of shape trees belongs to Lesson 10; until then the GDScript evaluator is the only one.
3. **Pass 1 (the cell table) has a CPU and a GPU implementation** (`SurfaceNets.cell_table()`, `shaders/compute/surface_nets.glsl` through `SurfaceNetsGpu`). Both write the same table of 8 floats per cell. `SdfMesher` uses the GPU when a local `RenderingDevice` exists and the compiled shader is assigned, and the CPU otherwise. The CPU path is the reference: a windowed test compares the two tables.
4. **Pass 2 (faces) runs on the CPU only.** Its output size is not known in advance; a GPU version needs atomics or a counting pass (Lesson 08 E5).
5. **Collision is a `ConcavePolygonShape3D`** from `Mesh.create_trimesh_shape()` on a `StaticBody3D`, in an internal child.
6. **The compiled shader is an exported `RDShaderFile` property** assigned in the scene (decision 0004: no asset paths in code).

## Consequences

- Rebuilding the boulder pile at 0.15 m takes about 0.92 s with the GPU pass and 1.28 s without (measured, Lesson 08 O3); sampling is about 650 ms of either. The rebuild runs on the main thread and freezes the game (Lesson 08 E4).
- GPU and CPU tables agree on every vertex cell; positions differ by at most about 1 µm (Lesson 08 O6).
- Where two stones of a union touch, the mesh can be nonmanifold (8 edges at 0.15 m) and its Euler characteristic varies with the cell size. Lesson 21's halfedge structure will need separate meshes per stone or a repair step.
- Features thinner than one cell disappear; creases are rounded (Lesson 08 E2 for dual contouring).
