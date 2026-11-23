# Lesson 08. From field to mesh

Lesson scene: `game/scenes/lessons/08_field_to_mesh.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–07 are unchanged; the Lesson 07 scene shows the boulder pile only as slices.

## 1. Orientation

Lesson 07 described the boulder pile by a function f(x, y, z), negative inside the rock. A function cannot be drawn by the rasterizer and cannot be stood on by the physics engine: both want triangles. This lesson converts the zero set { p : f(p) = 0 } into a triangle mesh and a collision shape. It answers five questions:

1. How is a surface located from samples of f on a grid? (isosurfaces, sign changes)
2. Where on a grid edge does f cross zero, and how good is that estimate? (edge interpolation, error order)
3. How do the located points become triangles that face outward and close up? (surface nets, winding, Euler characteristic)
4. How does a computation move to the GPU, and what does it cost to get the data there and back? (compute shaders, `RenderingDevice`, buffers)
5. How does a mesh become ground for the capsule? (trimesh collision)

The method is naive surface nets: one vertex per grid cell that the surface passes through, one quad per grid edge that the surface pierces. Pass 1 (vertices) runs in GDScript or, when a GPU device exists, in a GLSL compute shader; the two are compared number by number. Pass 2 (faces) runs in GDScript. The result: the boulder pile of Lesson 07 as a shaded mesh with collision, which the capsule can walk onto and stand on.

Goal served (`plan.md`): "a natural environment with rocks ... all geometrically normal mapped to interact with the player"; "as much as possible I want to use (differential) geometry ... to create surfaces"; "travelling up rocky formations in a place like Joshua Tree."

Files:

| File | Role |
|---|---|
| `game/src/sdf/sdf_grid.gd` | `SdfGrid` (RefCounted): f sampled at every point of a regular grid that covers `bounds()`. |
| `game/src/sdf/surface_nets.gd` | `SurfaceNets` (RefCounted): pass 1 on the CPU (the cell table), pass 2 (faces), mesh arrays. |
| `game/shaders/compute/surface_nets.glsl` | Pass 1 as a compute shader, one invocation per cell. |
| `game/src/sdf/surface_nets_gpu.gd` | `SurfaceNetsGpu` (RefCounted): local `RenderingDevice`, buffers, dispatch, read-back. |
| `game/src/sdf/sdf_mesher.gd` | `SdfMesher` (`@tool` Node3D): runs the stages, holds the mesh and the collision shape in internal children, records timings. |
| `game/data/rocks/rock_material.tres` | `StandardMaterial3D` for the rock (one color; Lesson 09 replaces it). |
| `game/src/lessons/field_to_mesh.gd` | Scene root. Extends `sdf_primitives.gd` (Lesson 07); R and J keys; `HUD/RockLabel`. |
| `game/scenes/lessons/08_field_to_mesh.tscn` | The Lesson 07 scene plus `Rocks/Boulders` (an `SdfMesher`) and `HUD/RockLabel`. |
| `game/project.godot` | Input actions `cycle_rock_view` (R) and `toggle_mesher_backend` (J); `run/main_scene`. |
| `game/tests/test_08_*.gd` | Grid and surface nets on a sphere, GPU against CPU (windowed runs); the scene, the collision, the capsule on the rock. |
| `tools/mesher_compare.sh`, `tools/godot/mesher_compare.gd` | Windowed harness: GPU against CPU, with timings per stage. |
| `docs/decisions/0009-meshing-sdfs.md` | Why surface nets, why pass 1 on the GPU and pass 2 on the CPU, why a CPU fallback. |

No gamepad button is free (Lesson 07 took the last two), so R and J are keyboard keys only.

Reading: Sarah F. F. Gibson, "Constrained elastic surface nets" (1998), sections 1–3, the origin of surface nets. Mikola Lysenko, "Smooth voxel terrain (part 2)" (0fps.net, 2012): marching cubes and naive surface nets side by side. William E. Lorensen and Harvey E. Cline, "Marching cubes" (1987), for the method this lesson does not use (E1). DDG §2.2.1 (oriented simplicial complexes: neighboring triangles with the same orientation), §2.3 (simplicial surfaces; "three triangles meeting at an edge" is nonmanifold), Exercise 2.1 (V − E + F = 2 for a simplicial sphere) and the Euler–L'Huilier formula V − E + F = 2 − 2g stated after Exercise 2.3. Godot documentation, "Using compute shaders". Full entries: `docs/references.md`.

No earlier exercise is needed. The audio of Lessons 04–06 still runs. Footsteps on the rock are still classified by the terrain material beneath them (R3).

## 2. Predict

Work these on paper before reading the code. Notation: the grid has spacing h (`cell_size`); a grid point is "inside" when f < 0; a cell is the cube between eight neighboring grid points.

- **P1.** On one grid edge f takes the values f₀ at one end and f₁ at the other, with opposite signs. Model f on the edge as a straight line and find the parameter t ∈ [0, 1] where it is zero. For the unit sphere f = ‖p‖ − 1, take the edge from (0.7, 0.6, 0) to (0.9, 0.6, 0). Compute f₀, f₁, t, and the crossing point. Where does the sphere really cross that edge?
- **P2.** Instead of interpolating, put every crossing at the edge's midpoint (t = 1/2). How large can the error be along the edge, as a multiple of h? For linear interpolation the error comes from the curvature of f along the edge. Using Taylor's theorem with f(t) = f₀ + t f′ + ½ t² f″, guess how the error scales with h: like h, or like h²?
- **P3.** A cell whose corners are all inside, or all outside, gets no vertex. Draw a 2D grid with spacing 0.5 and a circle of radius 1 centered on a grid point. Mark the cells with mixed corners. In 2D, surface nets puts one point in each marked cell and joins the points of two cells that share an edge with a sign change. Draw the result. How many points and segments? Is the polygon closed?
- **P4.** In 3D, a grid edge along x with a sign change is shared by four cells. Why must all four have a vertex? Order those four vertices so that the quad faces outward, given that Godot shows triangles whose vertices run clockwise as seen by the camera, and that the outside lies on the side where f > 0. (Use the cyclic axis order (a, b, c) = (x, y, z), (y, z, x), (z, x, y), and e_b × e_c = e_a.)
- **P5.** DDG Exercise 2.1: V − E + F = 2 for a simplicial sphere; the text after Exercise 2.3 gives V − E + F = 2 − 2g for a closed surface with g handles. A surface nets mesh of a sphere should give 2. The boulder pile is three stones, two of which touch. What would you expect, and what would a value like −17 mean?
- **P6.** A slab 0.1 m thick lies between grid points spaced 0.15 m apart. What does the mesh show of it? What is the thinnest feature the grid always sees? Where in the boulder pile might this matter?
- **P7.** `bounds()` promises f > 0 outside its box. `SdfGrid.sample()` adds one spare layer of cells around the box. Is the spare layer needed for the mesh to close? What if `bounds()` were too small?
- **P8.** The pile's grid at h = 0.15 m has 66 × 41 × 42 = 113 652 points and 106 600 cells. One GDScript evaluation of the pile costs about 5.4 µs (Lesson 07). Estimate the sampling time. Pass 1 on the GPU uploads one 32-bit float per point and downloads eight per cell: how many bytes each way? Which stage will dominate the total?
- **P9.** Halve h. By what factor does the number of samples grow? The number of triangles? Why are the two factors different?

## 3. Read

### 3.1 `sdf_grid.gd`

Read the header. A grid is three numbers (origin, spacing, size) and one flat array. Point (i, j, k) has index i + nx (j + ny k): x varies fastest. Write the inverse, from index to (i, j, k); `test_08_surface_nets.gd` uses it.

`sample()` covers `bounds()` and adds a spare layer (P7); read its Q/A comment. `fill()` calls `evaluate()` once per point and nothing else; this is the place where all the time goes (O4). The `# EXERCISE` comment names E3, which uses the Lipschitz bound of Lesson 07 to skip most of the calls.

Values are stored as 32-bit floats (`PackedFloat32Array`). Why, when GDScript computes in 64 bits? (The GPU reads 32-bit floats, and both paths should start from identical input.)

### 3.2 Pass 1: `cell_table()` and `_write_cell()`

Read the header of `surface_nets.gd`: two passes, one shared "cell table" of 8 floats per cell. Then the corner numbering: bit 0 of the corner number is the x offset, bit 1 y, bit 2 z. `EDGES` lists the twelve pairs of corners that differ in one bit. Check that there are four along each axis.

`cell_table()` reads the eight corners, counts how many are inside, and skips the cell if the count is 0 or 8. Read the Q/A comment: what can pass through a cell whose corners all agree? (P6.)

`_write_cell()` loops over the twelve edges. For each edge with a sign change, `edge_crossing()` gives t (P1), and the crossing point is a + t (b − a) in cell units. The vertex is the average of the crossings. Is the average always inside the cell? (Each crossing lies on the cell's boundary, and the cell is convex.)

The normal comes from `trilinear_gradient()`. Read its Q/A comment. The trilinear interpolant is the function f̃(u, v, w) = Σ fₙ · (weights), a product of linear functions in u, v, w; its derivative along u at a point is a blend of the four x-edge slopes. Differentiate the trilinear formula once by hand and compare with the code. `test_08_surface_nets.gd` checks that the gradient of a linear field comes back unchanged.

### 3.3 Pass 2: `_connect_faces()` and winding

For every grid point p and every axis a, the edge from p to p + e_a is checked for a sign change. The four cells around it are p, p − e_b, p − e_b − e_c, p − e_c, where (a, b, c) is a cyclic order. Read the first Q/A comment: cyclic order gives e_b × e_c = e_a.

Read the winding comment and check it against your answer to P4. Lesson 01 met the rule for the terrain (`terrain.gd`, the comment before the index loop): Godot shows the side from which the vertices run clockwise. Here the outside can lie on either side of the edge, so the order depends on which end is inside.

DDG §2.2.1 calls a complex "oriented" when each simplex is given an orientation, and notes the convenience of neighbors sharing it. Surface nets gives every quad its orientation from the sign of f, and f has one sign on each side of the surface, so neighboring quads agree.

### 3.4 `surface_nets.glsl`

Read the shader's comments from the top. New terms: invocation, workgroup, storage buffer, `std430`, push constant. Compare `main()` with `_write_cell()` line by line. Two differences:

- The shader writes zeros for empty cells. Read why.
- The vertex position is computed as `origin + (cell + uvw) * h` in one expression; GDScript computes `cell_origin + u * h` with `cell_origin` from `grid.point()`. The same mathematics in a different order gives results that differ in the last bits (O6).

`mix(a, b, t)` is GLSL's a + t (b − a). The shader receives the grid's origin and spacing in a 32-byte push constant: an `ivec4` and a `vec4`.

### 3.5 `surface_nets_gpu.gd`

Read the header's Q/A on `RenderingDevice`. The class creates a local device once (in `_init`), compiles nothing (the importer compiled the `.glsl` to SPIR-V; `get_spirv()` returns the bytecode and any compile error), and makes a pipeline. `run()` does five things: create two storage buffers (values with data, table empty); connect them to bindings 0 and 1 in a uniform set; encode the push constant; record, submit and wait for one dispatch; read the table back and free the buffers. Each step has its own timer.

Read the Q/A on the number of workgroups. With 65 cells along x and groups of 4, how many invocations run along x, and how many return at once?

RIDs are freed by hand. `_notification(NOTIFICATION_PREDELETE)` frees the pipeline, the shader and the device when the object is released. What leaks if `run()` returns early without freeing its buffers?

### 3.6 `sdf_mesher.gd`

`SdfMesher` follows the pattern of `Terrain` (Lesson 01) and `SdfSlice` (Lesson 07): exported Resources, internal children, a deferred rebuild. Read the header's Q/A on why pass 2 stays on the CPU.

`rebuild()`: sample, pass 1 (GPU if `use_gpu` and a device exists, else CPU), pass 2, `ArrayMesh`, collision. The mesh gets no UVs and no tangents; the material does not need them yet. Read the Q/A on the collision shape: `Mesh.create_trimesh_shape()` returns a `ConcavePolygonShape3D` holding the triangles. Why can such a shape belong only to a static body? (A test of a moving concave shape against another concave shape has no fast general method; physics engines refuse it.)

`used_gpu` records what ran; `use_gpu` records what was asked. In a headless run the two differ.

### 3.7 `field_to_mesh.gd` and the scene

`Rocks/Boulders` sits beside the two slices under `Rocks`, so it meshes the same shape in the same space. R cycles: mesh only (the slices hidden), mesh and slices, slices only. Hiding the mesh does not remove its collision; why might that be confusing in the third view? J flips `use_gpu`; the setter queues a rebuild. The timings appear in `HUD/RockLabel`, a second label at the top right, because the first one reaches the bottom of the window.

## 4. Run and observe

Start the lesson scene. The boulders stand ahead and to the right of the spawn, where the slices of Lesson 07 stood.

- **O1.** Press R once to show mesh and slices together. Walk to the pile and look where the horizontal slice cuts the mesh. Does the mesh's edge follow the white zero line of the slice? Press H to move the cut. Where do mesh and zero line part most?
- **O2.** Walk into the pile from several directions. Where can the capsule climb onto rock, and how high? Where does it stop? Compare with the `floor_max_angle` of the player (Lesson 02).
- **O3.** Read `HUD/RockLabel`. Press J several times. Which numbers change between "gpu" and "cpu", which stay? How long does the game freeze during a rebuild?
- **O4.** Close the game. Select `Rocks/Boulders` in the editor and set `cell_size` to 0.3, then 0.1, then 0.075 (in the editor the mesher rebuilds; at 0.075 the editor pauses for several seconds). Record vertices, triangles, and the timings for each from the running game. Then set it back to 0.15.
- **O5.** In the editor's 3D viewport, open the Perspective menu (top left) → Display Wireframe. Look at the pile's triangles. Where are they regular, where thin or folded? Look where the perched stone rests on the large one, and where the split boulder touches the ground.
- **O6.** Run `tools/mesher_compare.sh` from the repository root. A blank window opens and closes. Read the columns: how far apart are the GPU and CPU results, and why are they not identical? Which part of the GPU time is upload, dispatch, download?

## 5. Tweak

Make each change, run, observe, and revert.

- **T1.** In `_write_cell()`, replace `edge_crossing(f0, f1)` by 0.5. Rebuild and look at the pile. Then run `test_08_surface_nets.gd`: which check fails, and by how much? Relate the result to P2.
- **T2.** In `_connect_faces()`, split each quad along the other diagonal: triangles (v0, v1, v3) and (v1, v2, v3) (and the reversed pair). Does the winding still hold? Where on the mesh can you see a difference?
- **T3.** In `SdfGrid.sample()`, replace `var box := shape.bounds()` by `var box := shape.bounds().grow(-1.0)`. What happens to the mesh, and what would a test have to count to catch it?
- **T4.** Swap the two branches of the winding `if` in `_connect_faces()`. What does the rock look like from outside? What happens when the capsule walks into it?
- **T5.** In `_write_cell()`, replace the trilinear normal by `shape.gradient()` at the vertex. (The function has no shape; pass it in, or compute normals in `SdfMesher` after `build()`.) What does it cost per rebuild? Where does the shading change?
- **T6.** In a copy of `game/`, change the shader's `local_size` to 8 × 8 × 8 and `GROUP` to 8, then to 1 and 1. Run `tools/mesher_compare.sh` against the copy (`GODOT` stays; run Godot with `--path` to the copy and the same `-s` script). Does the dispatch time change?

## 6. Exercises

- **E1 ★★ Marching cubes.** Write `MarchingCubes` with the same interface as `SurfaceNets` (`build(grid)`, `positions`, `normals`, `indices`). Use the published 256-case table (Paul Bourke's "Polygonising a scalar field" lists one). Compare on the unit sphere and on the pile: vertices, triangles, smallest triangle angle, largest |f| at a vertex, and whether the mesh is closed. Where does marching cubes leave holes, and why does surface nets not?
- **E2 ★★ Sharp features.** The split boulder's cleft is a crease, and surface nets rounds it off. Dual contouring (Ju et al., 2002) places the cell's vertex at the point that best fits the tangent planes at the edge crossings: minimize Σ (nᵢ · (x − pᵢ))², a 3 × 3 least-squares problem. Use `shape.gradient()` at each crossing for nᵢ, solve with a fallback to the average when the system is singular, and compare the cleft before and after.
- **E3 ★★ Skipping empty space.** Complete the `# EXERCISE` in `SdfGrid.fill()`. If f(p) = d and the bound is L, no surface lies within d / L of p. Sample a coarse grid first (every 8th point); where d / L exceeds the diagonal of a block, fill the block with a positive value without evaluating. Measure the number of `evaluate()` calls and the sampling time for the pile at 0.15 m and 0.075 m, and check that the mesh is unchanged (same vertex count, same cell table).
- **E4 ★ No freeze.** Move sampling and pass 1 to a `WorkerThreadPool` task, and swap the mesh in on the main thread when it is done. What must not be touched from the worker thread (the `RenderingDevice` you created? the scene tree?), and what is safe (the `SdfShape` tree, if nobody edits it meanwhile)?
- **E5 ★★★ Pass 2 on the GPU.** Write a second compute shader that emits quads. Each invocation handles one grid point's three edges and reserves space in the index buffer with `atomicAdd` on a counter. Read the counter back first to size the result, or allocate the worst case. Compare the triangle sets of the two paths (they come out in a different order: compare sorted triangles) and the timings.
- **E6 ★★ One mesh per stone.** Editing one boulder rebuilds the whole pile. Give `SdfMesher` an option to mesh each child of an `SdfUnion` separately with its own grid (and `bounds()`), and measure the rebuild after a change to the perched stone. What happens where two stones touch?

## 7. Reflect

- **R1.** Lesson 09 takes normals as ∇f / ‖∇f‖ from the field. This lesson's normals come from the trilinear interpolant of the grid, and O5's folded triangles carry them. Where on the pile would the two kinds of normal differ most, and which would you trust on a crease?
- **R2.** Sampling takes about 70 % of a GPU rebuild. Lesson 10 evaluates SDFs on the GPU. If sampling moved there, what would remain on the CPU, and how much of the 920 ms would be left? What has to exist twice, and how would `test_08_surface_nets.gd`'s comparison extend to it?
- **R3.** `FootstepReporter` (Lesson 05) asks the terrain's material which surface lies under the feet. On the boulder it still reports grass, dirt or rock of the ground below. How would the reporter learn that the foot stands on the mesh, and which signal would decide: the collision object under the ray, or f at the feet?
- **R4.** DDG §2.3 calls a mesh nonmanifold where three or more triangles meet at an edge. The pile's mesh has such edges where stones touch (O5 answer). Lesson 21 builds a halfedge mesh, which assumes a manifold surface. Which repair would you choose: separate meshes per stone (E6), a smooth union instead of a union, or a mesh repair step?
- **R5.** The capsule stands on triangles; Lesson 15 climbs on the field. For a hand reaching for a hold, which is cheaper and which is more accurate: a ray against the trimesh, or f and ∇f at the hand?

## 8. Answers

<details><summary>P1</summary>

t = f₀ / (f₀ − f₁): the line f₀ + t (f₁ − f₀) is zero there, and opposite signs make the denominator nonzero and t ∈ [0, 1]. For the sphere: f₀ = √0.85 − 1 = −0.0780, f₁ = √1.17 − 1 = 0.0817, t = 0.4887, crossing at x = 0.7 + 0.2 · 0.4887 = 0.7977. The sphere crosses at x = √(1 − 0.36) = 0.8. The error is 2.3 mm on an edge of 0.2 m, from the curvature of f along the edge.
</details>

<details><summary>P2</summary>

At the midpoint the error can reach h / 2: the true crossing may lie at either end. For linear interpolation, write f(t) = f₀ + t f′ + ½ t² f″ along the edge (t in meters). The line through the end values misses f by a term of order h² f″ between the ends, and dividing by the slope f′ turns it into a position error of order h² f″ / f′. Measured on the unit sphere, largest distance of any vertex from the sphere:

| h (m) | 0.4 | 0.2 | 0.1 | 0.05 |
|---|---|---|---|---|
| interpolated | 0.0519 | 0.0144 | 0.0036 | 0.0009 |
| midpoint (T1) | 0.200 | 0.089 | 0.047 | 0.024 |

The interpolated error falls by 4 per halving (order h²), the midpoint error by 2 (order h). The vertex is an average of crossings, not a crossing, and on a curved surface the average of points on the surface lies inside it; that adds its own h² term.
</details>

<details><summary>P3</summary>

With spacing 0.5 and the circle centered on a grid point, the grid points at distance 1 (such as (1, 0)) have f = 0, which counts as outside (f < 0 is inside). The marked cells form a ring around the circle, and joining the points of neighbors across each sign-changing edge gives one closed polygon: every point has exactly two neighbors, because each cell boundary crossed by the curve has two sign-changing edges. Count your own drawing; the 3D analogue for a sphere at h = 0.4 gives 98 vertices and 192 triangles.
</details>

<details><summary>P4</summary>

A sign change on an edge means the edge's two ends differ; each of the four cells around the edge contains both ends as corners, so each has mixed corners and a vertex. With v0 = cell(p − e_b − e_c), v1 = cell(p − e_c), v2 = cell(p), v3 = cell(p − e_b), the path v0 → v1 → v2 steps along +b then +c, which is counterclockwise seen from +a (e_b × e_c = e_a). If p is inside, the outside is toward +a; the viewer there needs clockwise: (v0, v2, v1), (v0, v3, v2). If p + e_a is inside, the viewer looks from −a, where (v0, v1, v2), (v0, v2, v3) appears clockwise. `test_08_surface_nets.gd` checks every triangle of the sphere mesh: (c − a) × (b − a) points away from the center.
</details>

<details><summary>P5</summary>

Two separate closed stones would give 2 + 2 = 4 (χ adds over components), three would give 6. Measured, the pile at h = 0.15 gives V = 4225, E = 12 742, F = 8500, χ = −17, two connected pieces, and 8 edges shared by more than two triangles. Where two stones touch, the grid cannot separate them and the surfaces fuse; at some places they fuse through a single edge or vertex (nonmanifold, DDG §2.3), elsewhere through small tunnels that count as handles. 2 − 2g does not apply to a nonmanifold mesh. The value changes with h: χ = 4 at 0.5 m, 1 at 0.3 m, −17 at 0.15 m, 5 at 0.1 m (three pieces). The sphere gives χ = 2 at every h tested (0.4 to 0.05).
</details>

<details><summary>P6</summary>

If no grid point falls inside the slab, every point is outside, no edge changes sign, and the slab is absent from the mesh. A slab whose thickness exceeds h along an axis always contains a grid point along that axis; diagonal slabs need more, up to h √3. In the pile: the cleft of the split boulder (the cutter box is thin; where the grid misses it, the cleft closes) and the gap under the perched stone. The slice of Lesson 07 shows both at its own resolution; compare O1.
</details>

<details><summary>P7</summary>

Not for a correct `bounds()`: every grid point on or outside the box has f > 0 (or f = 0, which counts as outside), so no inside point lies on the border and every crossing has its four cells. Measured: the pile meshed without the spare layer gives the same V, E, F as with it. The layer adds about 14 % samples at h = 0.15 (113 652 against 99 840 points). It protects against a box that is too small: T3 shows what happens then.
</details>

<details><summary>P8</summary>

113 652 × 5.4 µs ≈ 0.61 s. Measured: 643–651 ms, about 5.7 µs per evaluation. Upload: 113 652 × 4 = 455 kB. Download: 106 600 × 8 × 4 = 3.41 MB, about 7.5 times the upload. Sampling dominates: on the GPU path pass 1 took 2.1–2.8 ms (download 1.3–1.6 ms of it), against 368–371 ms for pass 1 in GDScript; faces took 254–257 ms.
</details>

<details><summary>P9</summary>

Samples grow by about 8 (three axes), triangles by about 4: the surface is two-dimensional, so the number of cells it passes through grows with the square of 1/h. Measured from 0.15 to 0.075 m: points 113 652 → 819 072 (× 7.2, less than 8 because the spare layer and the rounding up are a smaller share of a finer grid); triangles 8500 → 34 352 (× 4.04).
</details>

<details><summary>O1</summary>

The mesh's outline follows the white line closely; the largest |f| at any mesh vertex is 0.10 m at h = 0.15 (0.13 m at 0.3, 0.05 m at 0.1). Expect the largest gaps where the surface turns sharply within one cell: the creases where two stones meet, the rims of the cleft, the perched stone's contact. There the average of crossings lies off the surface (P2), and the grid cannot resolve the shape (P6).
</details>

<details><summary>O2</summary>

Measured headless with the stick held forward for 5 s from eight directions, starting 7 m from the point (1.5, 0, 0.3) of shape space: the highest feet position was 1.19 m above the Rocks node, reached from the −z side (directions 180° and 225°); from +x and −x the capsule rose no higher than the ground there, from the other directions 0.25–0.74 m. The capsule climbs where the rock is less steep than the floor angle (45° by default) and stops against steeper faces, as against the ramp tower of Lesson 02. Dropped onto the split boulder at shape point (3.6, 4.5, 0.8), it came to rest with its feet at y = 2.007 m, on the floor, f at the feet −0.022 m (the mesh lies up to 0.10 m off the zero set, O1). `test_08_mesher_scene.gd` repeats the drop and a walk off the stone.
</details>

<details><summary>O3</summary>

Measured in a windowed run of the scene at h = 0.15: with the GPU, total 919–920 ms (sampling 646–650, pass 1 2.8–4.3, faces 255–257, collision 10); with the CPU, total 1273–1291 ms (pass 1 367–372). Sampling, faces and collision do not depend on J. The mesh is identical: 4225 vertices, 8500 triangles. The freeze lasts about 0.9 s with the GPU and 1.3 s without; E4 removes it.
</details>

<details><summary>O4</summary>

Measured with `tools/mesher_compare.sh` (three runs each; ranges):

| h (m) | points | vertices | triangles | sampling (ms) | pass 1 CPU (ms) | pass 1 GPU (ms) | faces (ms) |
|---|---|---|---|---|---|---|---|
| 0.3 | 17 710 | 1 024 | 2 112 | 100–104 | 56–57 | 1.5–1.8 | 38–39 |
| 0.15 | 113 652 | 4 225 | 8 500 | 647–651 | 368–371 | 2.1–2.8 | 254–257 |
| 0.1 | 355 020 | 9 637 | 19 268 | 2027–2034 | 1160–1163 | 5.7–7.7 | 814–815 |
| 0.075 | 819 072 | 17 174 | 34 352 | 4680–4687 | 2680–2688 | 12.3–13.6 | 1894–1897 |

Sampling and both CPU passes scale with the number of grid points (pass 2 visits every point and edge, not only the surface). The GPU pass grows less than the point count at small sizes, where fixed costs dominate, and approaches it at 0.075 m, where the download of 25 MB takes 8–9 ms.
</details>

<details><summary>O5</summary>

On smooth parts the triangles are near-regular, about one cell across. Thin and folded triangles appear where the surface turns sharply within a cell: creases between stones, the cleft, contact points. Measured at h = 0.15 m: 22 triangles of the pile face against the sum of their own vertex normals (none on the sphere). One way this happens: a cell that holds two sheets of surface (both sides of a gap thinner than h) gets one vertex for both, and quads from the two sheets share it. The same mechanism produces the nonmanifold edges of P5.
</details>

<details><summary>O6</summary>

The cell tables agree on which cells have a vertex (0 differences at every h). Positions differ by at most 0.60–1.03 µm, normals by at most 1.4 × 10⁻⁶, except one cell at h = 0.15 where they differ by 7.7 × 10⁻⁵ (a cell with a small gradient, where normalizing magnifies rounding). The CPU computes t and the averages in 64-bit floats and stores 32-bit results; the GPU computes in 32-bit throughout and in a different order (Lesson 07, the Q/A on `gradient()` in `sdf_shape.gd`: 32-bit numbers near 10 m are spaced about 10⁻⁶ m apart). At h = 0.15 the GPU time splits into upload 0.2–0.3 ms, dispatch 0.6–1.1 ms, download 1.2–1.6 ms. The dispatch includes waiting for the GPU to finish.
</details>

<details><summary>T1</summary>

Look at the pile for steps that follow the grid. `test_08_surface_nets.gd` fails "vertex off the sphere": at h = 0.2 the largest error grows from 0.0144 m to 0.089 m, above the 0.03 m tolerance (table in P2).
</details>

<details><summary>T2</summary>

Yes: each triangle keeps the order v0 → v1 → v2 → v3 around the quad, so it keeps the quad's orientation. The difference lies in nonplanar quads, where the two diagonals give different folds: the wireframe's diagonals switch direction, and a fold can turn from a ridge into a valley. A common rule splits along the shorter diagonal.
</details>

<details><summary>T3</summary>

The grid no longer covers the whole solid. Measured: with `grow(-1.0)`, 36 edges of the mesh belong to one triangle only (an open mesh), and the triangle count falls from 8500 to 8288; with `grow(-1.25)`, 104 open edges and 7800 triangles. A smaller shrink (0.25, 0.5) changed nothing, because `bounds()` of the pile is larger than the solid by 0.53 to 1.36 m per side: the mesh at h = 0.1 spans (−2.12, −0.18, −1.50) to (5.10, 3.59, 2.06), `bounds()` spans (−2.97, −1.54, −2.54) to (6.35, 4.12, 3.26). A shrink of 1.0 m cuts into the top (margin 0.53 m) and the −x end (0.85 m). A test counts edges used by one triangle; `test_08_surface_nets.gd` does so for the sphere.
</details>

<details><summary>T4</summary>

Every triangle faces inward: from outside, the near side of the rock is culled and the inner faces of the far side show through, lit as if from inside. `test_08_surface_nets.gd` fails "876 triangles face inward" (all of the sphere's). The collision did not change in kind: measured headless with Jolt, the dropped capsule still landed on the split boulder, with its feet at y = 1.954 m instead of 2.007 m, and `test_08_mesher_scene.gd` passed. Do not rely on that; Godot documents trimesh collision as one-sided unless `backface_collision` is set, and the result may differ between physics engines. A test of the winding has to look at the triangles, not at the capsule.
</details>

<details><summary>T5</summary>

Six extra evaluations per vertex: an estimate of 4225 × 6 × 5.7 µs ≈ 0.14 s per rebuild at h = 0.15. Measured over the vertices at 0.15 m, the angle between the trilinear normal and the normalized `shape.gradient()` is 2.96° on average and up to 137.7° (1.76° and 138.2° at 0.1 m; 11.4° and 163.6° at 0.5 m). The large angles lie at creases between stones, where ∇f jumps from one stone's direction to the other's; the shading changes there and nearly nowhere else.
</details>

<details><summary>T6</summary>

No change beyond the spread between runs. At h = 0.15 the GPU pass took 2.1–8.4 ms with groups of 8 (the first run slowest) and 2.4–3.0 ms with groups of 1; at 0.075 m, 11.2–14.3 and 10.6–12.7 ms. At these sizes the time is in the transfer and the synchronization, not in the arithmetic. Group size matters when the arithmetic dominates, as it would if the shader evaluated f (Lesson 10).
</details>
