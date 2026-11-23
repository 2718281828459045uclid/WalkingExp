# 0001. Engine: Godot 4.6

Status: accepted, 2026-11-22.

## Context

Requirements drawn from `plan.md`:

1. Geometry generated from code: height fields, signed distance fields, meshes processed with discrete differential geometry.
2. Shading written by hand, including the lighting equation itself.
3. A walking and climbing character driven by procedural animation and inverse kinematics.
4. Two-way communication with SuperCollider over OSC (UDP).
5. Assets replaceable without code changes.
6. Text-based project files that produce readable Git diffs.
7. Code readable by an intermediate programmer.

Software present on the development machine (Apple Silicon, macOS 15.8): Godot 4.6.2, Unity Hub, Blender, SuperCollider, Ableton Live 12 Suite.

## Options considered

| | Godot 4.6 | Unity 6 | Engine written from scratch |
|---|---|---|---|
| Scripting | GDScript (Python-like syntax), C#, C++ through GDExtension | C# | Any language |
| Procedural meshes | `ArrayMesh`, `SurfaceTool`, `MeshDataTool` | `Mesh` API, Jobs and Burst | Written by hand |
| Shaders | Godot shading language (a GLSL dialect) with a user-replaceable `light()` function; GLSL compute shaders through `RenderingDevice` | HLSL and Shader Graph; custom lighting depends on render pipeline (URP or HDRP) internals | Full control; window, swap chain, and pipeline setup written by hand |
| Physics | Jolt (selectable since 4.4) or Godot Physics | PhysX | External library to integrate |
| Inverse kinematics | `TwoBoneIK3D`, `FABRIK3D`, `CCDIK3D` (new in 4.6) | Animation Rigging package | Written by hand |
| Scene files | `.tscn` / `.tres` text; short diffs | YAML with GUID references in `.meta` files; long diffs | Own format |
| OSC | None built in. `PacketPeerUDP` plus a hand-written encoder of about 100 lines | Third-party packages or hand-written | Hand-written |
| License | MIT | Proprietary, tiered | — |

## Decision

Godot 4.6.2. GDScript as the primary language. Jolt as the physics engine. Forward+ renderer (Metal backend on macOS).

Workloads that exceed GDScript speed move to GLSL compute shaders through `RenderingDevice`. GDExtension (C++) remains available and is deferred until a measured bottleneck requires it.

## Consequences

- Measured on the development machine: the sandbox terrain (129 × 129 = 16,641 vertices) rebuilds in 75 ms in GDScript, about 4.5 µs per vertex. A 128³ SDF grid (2.1 million samples) at that rate would take about 9 s. Phase 3 therefore moves SDF sampling and meshing to a compute shader; that move is itself a lesson.
- The from-scratch option survives in reduced form: a raymarcher written as one fragment shader inside Godot (Lesson 10) carries most of its learning value without the infrastructure cost.
- Godot 4.6 IK nodes exist, but Lesson 12 has the student write a two-bone solver first and adopt `TwoBoneIK3D` afterward.
- Unity remains installed. No project file depends on it.
- The engine version is pinned by `config/features` in `game/project.godot`. An upgrade gets its own decision record.
