# Roadmap

Ten phases, 34 lessons, five milestones. Each lesson produces a working change to the game and lives in `curriculum/NN-name/`. Lesson format: `curriculum/README.md`. Architectural choices behind the phases: `docs/decisions/`.

Status key: **written** = lesson text and starter code exist; *planned* = outline only.

## Dependencies

```
Phase 0 ─▶ Phase 1 (ground) ─┬─▶ Phase 2 (sound bridge) ─────────────▶ Phase 8 (music)
                             ├─▶ Phase 3 (rock / SDF) ─┬─▶ Phase 6 (DDG on meshes)
                             │                         └─▶ Phase 4, lessons 15–16
                             ├─▶ Phase 4 (body), lessons 11–14
                             ├─▶ Phase 5 (light)         may interleave with any later phase
                             └─▶ Phase 7 (water, plants) uses Phase 6 lesson 24 for flow
Phase 9 (tools, text, UI) may begin after Phase 1 and run in parallel.
```

## Phase 0. Environment

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 00 | Environment and editor tour | Godot editor, nodes, scenes, Resources, headless runs | — | Sandbox runs; controller verified; SuperCollider listening | **written** |

## Phase 1. Ground: graph surfaces

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 01 | Height-field terrain and normals | `ArrayMesh`, index winding, `@tool` scripts, Resources | Parametric surfaces, tangent vectors, normals, gradient checking, sampling (DDG 3.1–3.2, 5.4) | Terrain with three switchable normal methods | **written** |
| 02 | Walking on a surface | `CharacterBody3D`, `move_and_slide`, frame-rate-independent smoothing | Directional derivative, exponential decay, response curves | Slope-aware walker with analog speed curve | **written** |
| 03 | Painting the ground | Spatial shaders, varyings, triplanar mapping, tonemapping | `smoothstep`, contour lines with `fwidth`, color spaces | Slope and height materials; topographic overlay | **written** |

## Phase 2. Sound bridge

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 04 | OSC from Godot to SuperCollider | UDP sockets, binary encoding (big-endian, 4-byte alignment), autoloads | — | sclang prints live player state | **written** |
| 05 | Footsteps as events | Contact detection, event queues, OSC bundles with timetags | Jitter, latency compensation | Synthesized footsteps that vary with surface and slope | **written** |
| 06 | Spatial audio and ambience | Listener-relative coordinates, update rates | Spherical coordinates, distance attenuation, Ambisonics basics | Positioned wind and ambience bed | **written** |

## Phase 3. Rock: signed distance fields

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 07 | SDF primitives and composition | Sampling functions on grids, debug slices | Distance functions, smooth minimum, domain repetition and warping | Boulder shapes stored as SDF Resources | **written** |
| 08 | From field to mesh | Surface nets or marching cubes; compute shaders via `RenderingDevice` | Isosurfaces, edge interpolation | Walkable boulder meshes with collision | **written** |
| 09 | Normals and curvature of implicit surfaces | Analytic vs. numerical gradients, Hessians | n = ∇f/‖∇f‖; mean curvature as ½ div n (DDG 3.4) | Curvature-driven weathering color | **written** |
| 10 | Raymarching | Fragment-shader raymarching, depth output, mixing with raster geometry | Sphere tracing, Lipschitz bounds | Distant rock formations without meshes | **written** |

## Phase 4. Body

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 11 | A skeleton from code | `Skeleton3D`, bones, attachments | Rigid transforms, quaternions, forward kinematics | Procedural figure following the capsule | **written** |
| 12 | Feet on the ground | Raycasts; own two-bone solver, then `TwoBoneIK3D` | Law of cosines, pole vectors | Legs that conform to slopes and steps | **written** |
| 13 | Balance | Debug drawing, state machines | Center of mass, convex hull, signed distance to a polygon, inverted pendulum | Balance margin shown on screen and sent over OSC | **written** |
| 14 | Analog stances | Raw axis input, trigger input, tick rate | Response-curve design, one-pole filters, critically damped springs | Weight shift under stick and trigger control | **written** |
| 15 | Climbing | Hold detection, multi-limb IK (`FABRIK3D` or own solver) | Normal and curvature queries on SDFs, reach spheres | Climbing a boulder face | **written** |
| 16 | Crawling and scrambling | Stance transitions, four-point support | Support polygon with four contacts | Crawl through a gap; scramble up a slab | **written** |

## Phase 5. Light

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 17 | Writing `light()` | Custom lighting function in spatial shaders | Lambert, wrap lighting, Oren–Nayar, GGX microfacet model | Side-by-side shading models on rock and ground | **written** |
| 18 | Shadows and global illumination | Shadow cascades, SDFGI / VoxelGI / LightmapGI, profiling | Rendering equation (overview) | Measured cost-versus-quality table for the scene | *planned* |
| 19 | Sky, atmosphere, time of day | Sky shaders, fog, volumetrics | Rayleigh and Mie scattering approximations | Day cycle | *planned* |
| 20 | Detail normals | Normal maps, tangent space, triplanar normal blending | Tangent frames, change of basis | Rock surfaces with procedural normal detail | *planned* |

## Phase 6. Discrete differential geometry on meshes

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 21 | Halfedge mesh | Mesh data structures in GDScript | Simplicial complexes, halfedge connectivity (DDG ch. 2) | Halfedge mesh with traversal queries | *planned* |
| 22 | Discrete curvature | Per-vertex quantities, color mapping | Angle defect, cotangent mean-curvature normal (DDG ch. 5) | Curvature maps on rock meshes | *planned* |
| 23 | Laplacian smoothing and flow | Sparse matrices, iterative solvers | Cotangent Laplacian, implicit mean curvature flow (DDG ch. 6) | Rounded, weathered rock by flow | *planned* |
| 24 | Flow on surfaces | Vector field storage and display | Gradient fields, Hodge decomposition, vector field design (DDG ch. 8) | Water paths across terrain and rock | *planned* |

## Phase 7. Water and vegetation

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 25 | Flowing water | Flow-map shaders, scrolling normals | Flow along −∇h, advection | Stream following the terrain gradient | *planned* |
| 26 | Plants from rules | `MultiMeshInstance3D`, instancing | L-systems, space colonization, Poisson-disk sampling | Scrub and grass fields | *planned* |
| 27 | Wind | Vertex-shader animation, a shared wind field | Noise fields, damped oscillators | Plants and audio driven by one wind field | *planned* |

## Phase 8. Music

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 28 | Generative score | Game-state mapping layer; `Pdef` / `Pbind` control from OSC | Markov chains, constraint rules | Music that follows traversal state | *planned* |
| 29 | Mix and space | Buses, reverb zones, ducking | Convolution, impulse responses | One mix for synthesized and sampled sound | *planned* |

## Phase 9. Tools, text, UI

| # | Lesson | Engineering | Math / theory | Result | Status |
|---|---|---|---|---|---|
| 30 | Asset registry and hot reload | Resource loading, file watching, editor signals | — | Assets swapped while the game runs | *planned* |
| 31 | Editor plugins | `EditorPlugin`, gizmos, custom inspectors | — | In-editor terrain and rock authoring | *planned* |
| 32 | Dialogue boxes | `Control` nodes, signals, data-driven text | — | Text box system that reads dialogue Resources | *planned* |
| 33 | Minimal UI | Themes, pause menu, settings | — | Settings screen for analog response curves | *planned* |

## Milestones

| Milestone | After lessons | Playable result |
|---|---|---|
| M1 | 00–04 | Walk across a math-defined landscape; SuperCollider receives player state. |
| M2 | 05–08 | Synthesized footsteps that change with surface; a field of SDF boulders to walk around and on. |
| M3 | 11–14 | A procedural body whose feet conform to the ground and whose balance answers analog input. |
| M4 | 15–17 | Climb a granite formation under custom lighting. |
| M5 | 18–29 | A small complete environment: water, vegetation, wind, time of day, generative score. |
