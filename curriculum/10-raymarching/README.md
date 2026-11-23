# Lesson 10. Raymarching

Lesson scene: `game/scenes/lessons/10_raymarching.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–09 are unchanged.

Complete Lesson 09 exercise E3 before reading this lesson; it contains one solution. (The raymarching shader estimates normals with the tetrahedral stencil of that exercise, in GLSL.)

## 1. Orientation

Lessons 07–09 evaluated the boulder field f on the CPU: on two plane cuts, on a grid that became a mesh, at the mesh vertices for curvature. This lesson moves f to the GPU and draws the rocks without a mesh. It answers five questions:

1. How does a fragment shader draw a surface that has no triangles? (a proxy box, one ray per pixel, sphere tracing)
2. How far may the march step, and when does it stop? (Lipschitz bound, hit tolerance in pixels, step budget)
3. How does a raymarched rock sort against the terrain, the player and the meshed rocks? (writing `DEPTH`; `LIGHT_VERTEX` for shadows)
4. Where do the normal and the curvature come from, per pixel? (four or five evaluations on a tetrahedron)
5. How does the GLSL copy of the SDF library stay equal to the GDScript one, and what does a raymarched rock cost per frame? (generated code; windowed frame-time measurement)

The method: a box around each rock is drawn with a shader. For every pixel of the box, the shader shoots the camera ray through the pixel, steps along it by f / L until f falls below the width of half a pixel, writes the depth of that point, and shades it with a normal and a mean curvature taken from f. The function f in the shader is written by a GDScript class, `SdfGlsl`, from the same `.tres` file the CPU code reads. The result: three rock formations (a pile beside the meshed pile, a pile four times larger and a field of nine tors on the far side of the hill) drawn with no mesh, cut by the terrain where they sink into it.

Goal served (`plan.md`): "a natural environment with rocks"; "as much as possible I want to use (differential) geometry ... to create surfaces". Distant rocks cost no meshing time and no memory per vertex. Lesson 15 (climbing) will march rays through the same fields to find holds.

Files:

| File | Role |
|---|---|
| `game/shaders/sdf/sdf_library.gdshaderinc` | GLSL mirror of the SDF formulas: one function per GDScript primitive or operator. |
| `game/src/sdf/sdf_glsl.gd` | `SdfGlsl`: walks a resource tree and writes `sdf_map()`; bakes `FastNoiseLite` into a 3D texture. |
| `game/shaders/sdf/raymarch.gdshader` | The template: proxy box, sphere tracing, depth, normal, curvature, views. Its stub `sdf_map()` is replaced at load time. |
| `game/src/sdf/raymarch_volume.gd` | `RaymarchVolume` (`@tool` Node3D): builds the shader, the material and the proxy box for one shape. |
| `game/src/sdf/sphere_tracer.gd` | `SphereTracer`: the march loop in GDScript, for tests and measurements. |
| `game/data/rocks/distant_tors.tres` | `SdfRepeat` of the tor boulder: a 3 × 3 field. |
| `game/src/lessons/raymarching.gd` | Scene root. Extends `implicit_curvature.gd` (Lesson 09); P, X and Z keys; places the formations on the terrain; frame time in `HUD/RockLabel`. |
| `game/scenes/lessons/10_raymarching.tscn` | The Lesson 09 scene plus `Formations` with three `RaymarchVolume` nodes. |
| `game/project.godot` | Input actions `cycle_raymarch_view` (P), `cycle_march_budget` (X), `toggle_formations` (Z). `run/main_scene` pointed to this scene while it was the newest lesson scene. |
| `game/tests/test_10_*.gd` | Translation and compilation of every node type; the CPU march; the scene and its keys. |
| `tools/raymarch_perf.sh`, `tools/godot/raymarch_perf.gd` | Windowed frame-time measurement at fixed views and step budgets. |
| `docs/decisions/0011-generated-glsl-from-sdf-trees.md` | Why the formulas are copied by hand and the composition is generated. |

P, X and Z are keyboard keys only; no gamepad button is free.

Reading: John C. Hart, "Sphere tracing" (1996), sections 2–3: the unbounding sphere, the march, Lipschitz bounds of combined functions. Inigo Quilez, "raymarching SDFs" and "normals for an SDF" (the tetrahedral stencil). DDG §4.6.3 (p. 69): df(u) = u · ∇f, which Lesson 07 P7 used to show that f / L never exceeds the distance to the surface; that inequality is the whole safety argument of the march. DDG §3.4 (pp. 38–41) for the mean curvature H. Godot documentation, "Spatial shaders": `DEPTH`, `LIGHT_VERTEX`, `CAMERA_POSITION_WORLD`. Full entries: `docs/references.md`.

## 2. Predict

Notation: the ray is r(t) = o + t d with ‖d‖ = 1, starting at the camera o. f is negative inside the rock; L is a Lipschitz bound of f (Lesson 07 P7).

- **P1.** A unit sphere at the origin, f(p) = ‖p‖ − 1. The ray starts at o = (0, 0, 5) with d = (0, 0, −1). Step by tᵢ₊₁ = tᵢ + f(r(tᵢ)). How many evaluations until f = 0? Now shift the ray sideways to o = (0, 1.01, 5): it passes 1 cm above the sphere. Sketch the steps. Where do they become small, and why does a ray that grazes a surface cost more steps than one that hits it head-on?
- **P2.** Let g = 2f: same zero set, L = 2. Step by g instead of g / 2 on a sphere of radius 0.25, from o = (0, 0, 5). Where does the first step land? What does the march report? The boulder pile has L = 1.252 (Lesson 07). How many more steps per ray do you expect from stepping by f / 1.252 instead of by f, and what would stepping by 2f risk?
- **P3.** The march stops when f(r(t)) / L < ε t. The player camera has a vertical field of view of 65° and the window is 720 pixels high. Show that one pixel subtends about 2 tan(32.5°) / 720 radians. How wide is one pixel at 5 m and at 50 m? With `epsilon_pixels` = 0.5, what tolerance in meters does each distance get? Which way does a larger tolerance move the silhouette of a rock: outward or inward?
- **P4.** Four vectors k₀ = (1, −1, −1), k₁ = (−1, −1, 1), k₂ = (−1, 1, −1), k₃ = (1, 1, 1). Show Σ kᵢ = 0 and Σ kᵢ kᵢᵀ = 4I. Expand fᵢ = f(p + h kᵢ) to second order and derive: ∇f ≈ Σ kᵢ fᵢ / (4h) and tr(Hf) ≈ (Σ fᵢ − 4 f(p)) / (2h²). Carry the second-order term of the gradient estimate: does it cancel, as it does for a central difference? What is the order of the error in h? For a true distance function (‖∇f‖ = 1), why is 2H = tr(Hf)? (Differentiate ‖∇f‖² = 1 along n; then use Lesson 09 P2.) Count the evaluations per hit pixel for a normal and H. Compare with the 26 of Lesson 09.
- **P5.** The shader draws the back faces of a box. Without a `DEPTH` write, the depth buffer receives the depth of that back face. The near pile sits half a meter into a slope. Which pixels of the rock does the terrain hide, and which pixels of the terrain does the rock hide, with and without `DEPTH`? Write the depth of a hit point p_view (view space) given the projection matrix P.
- **P6.** The pile's displacement noise is baked into a grid of 0.1 m texels and interpolated trilinearly. In one dimension, linear interpolation of samples of a smooth function is continuous; what about its derivative at a sample point? What does a normal measured with a step h = 2 mm see on such a surface? With h = 50 mm?
- **P7.** The baked region for the pile is about 6.1 × 5.7 × 5.7 m. How many texels does it hold at 0.1 m, and how many bytes at 4 bytes per texel? How long would GDScript take to fill it at about 0.11 µs per `get_noise_3d()` call plus the loop?
- **P8.** Decision 0011 splits the library: formulas by hand in GLSL, composition generated from `.tres`. List what you would have to change, and in which files, for (a) moving the perched stone 20 cm up, (b) a new `blend` of a smooth union, (c) a new primitive `SdfCone`, (d) changing `SdfSmoothUnion.smin()` from the quadratic to a cubic polynomial.

## 3. Read

### 3.1 The two libraries: `sdf_library.gdshaderinc` and `sdf_glsl.gd`

Open `sdf_library.gdshaderinc` and, beside it, `sdf_box.gd` and `sdf_ellipsoid.gd` (Lesson 07). Each GLSL function names the GDScript method it mirrors; compare `sdf_box()` with `SdfBox.evaluate()` line by line. The header's three Q/A state the split: formulas by hand, composition generated. `SDF_FAR` (10³⁰) stands in for `INF`.

Then `sdf_glsl.gd`. Read the header's example output and `translate()`. `_emit_node()` has one branch per class. Each branch appends one line to `_lines` (through `_assign()` or `_new_point()`) and returns the name of the variable that holds its distance. Follow three cases:

- `SdfSmoothUnion`. The GDScript `evaluate()` starts at d = INF and folds `smin(d, e)` over the children. Since `smin(INF, e) = e`, the first fold is skipped and the code starts at the first child. The folding order is kept, so the generated code gives the same order-dependent fillets (Lesson 07 known limits).
- `SdfTransform`. The point is moved into the child's frame with the inverse matrix, `vec3 pN = mat3(...) * p + vec3(...)`, and the child's distance is multiplied by `scale`. Read the Q/A on why the transform is rebuilt from the exported values. `_m()` writes a `Basis` as `mat3(x, y, z)`: both store columns.
- `SdfDisplace`. `FastNoiseLite` has no GLSL version. `_noise_index()` gives each distinct noise resource one index, and grows its region by the bounds of the displaced child (in the displaced child's own frame, the frame in which `get_noise_3dv()` is called). The pile's three displaced boulders share `granite_noise.tres`, so they share one texture. `bake_noise_slices()` samples the noise at the grid points; `sdf_noise()` in the library reads the texture. Read its two Q/A.

Then run `SdfGlsl.new().translate(load("res://data/rocks/boulder_pile.tres"))` in a scratch script and print the result: 35 lines for the pile's 21 nodes. Find the three noise calls and the three transforms.

### 3.2 `raymarch.gdshader`: from pixel to ray

Read the header's four Q/A. Then:

- `render_mode cull_front`. Read the Q/A. Only the inside of the box is drawn.
- The uniforms. `step_scale` is 1 / L; `proxy_min` and `proxy_max` are the box in the node's frame; `epsilon_pixels` is the hit tolerance.
- `// SDF_MAP_BEGIN` … `// SDF_MAP_END`. The stub makes the template compile on its own. `SdfGlsl.splice()` replaces everything between the markers.
- `vertex()`. Two varyings: the camera position and the box vertex, both in the node's local frame. The fragment shader receives the interpolated box point, and the ray direction is the normalized difference. Why is the camera position, computed per vertex, still exact in every fragment?
- `box_interval()`. Read the slab Q/A and test it by hand on the ray of P1 against the box [−1, 1]³: (t_enter, t_exit) = (4, 6). `test_10_sphere_tracer.gd` checks the GDScript copy on this case.

### 3.3 `raymarch.gdshader`: the march

`fragment()`, the first half. The march starts at `max(t_enter, 0)`: from the box face if the camera is outside, from the camera if it is inside. `pixel_angle` is P3; read the Q/A and the note on `abs()`. The loop:

```
d = sdf_map(p) * step_scale       // f / L: a safe step (P2)
if (d < epsilon_pixels * pixel_angle * t)  hit
t += d
if (t > t_end)  miss              // left the box
```

and the loop ends after `max_steps` evaluations with neither: an exhausted ray, treated as a miss. Read the Q/A on the tolerance that grows with t.

Then the miss handling: pixels whose ray missed are discarded, except in the step view, which draws them at the box face (read the Q/A). `heat()` maps the step count to a color.

### 3.4 `raymarch.gdshader`: normal, curvature, depth, light

`tetra_samples()` and `tetra_gradient()`: P4, in code. The normal uses `normal_step` (5 cm), the curvature `curvature_step` (10 cm). Read the Q/A at the `normal_step` uniform: Lesson 09 found 1 mm best for a gradient of an exact function, but here f contains a trilinear grid (P6).

The curvature line `h_mean = trace_h / (2 |g|)` is P4's 2H = tr(Hf) with a division by ‖g‖ for fields that are not exact distances. For the scaled-sphere ellipsoids of the rocks it is an approximation: their ‖∇f‖ ranges over min(radii) / max(radii) on the surface, and Hf n ≠ 0. Exercise E4 computes the full Lesson 09 formula per pixel.

The transforms at the end: `MODEL_MATRIX` takes local to world, `VIEW_MATRIX` world to view, `PROJECTION_MATRIX` view to clip. `DEPTH = p_clip.z / p_clip.w` is the value the rasterizer would have stored for a triangle through that point. `NORMAL` must be in view space. `LIGHT_VERTEX`: read the Q/A. The weathering rule is the one of `rock_weathering.gdshader` (Lesson 09), fed with the per-pixel H instead of the per-vertex one. The thresholds are in 1/m of the node's local frame: the four-times-larger `PileFar` has a quarter of the curvature in world units, but the same coloring.

### 3.5 `raymarch_volume.gd`

`rebuild()` runs the pipeline of decision 0011: translate, bake, splice, compile, set uniforms. Read:

- the Q/A on an infinite Lipschitz bound (the `GRADIENT` ellipsoid of Lesson 07);
- the Q/A on `level_bounds` and the 0.05 m margin;
- `_box_mesh()` and its Q/A: why the box vertices are moved instead of the `MeshInstance3D`. This is the reason `MODEL_MATRIX` equals the node's transform and the shader needs no offset.

The setters of `max_steps`, `epsilon_pixels` and `debug_view` write the uniform directly; `shape`, `template` and `noise_cell` queue a rebuild. The proxy casts no shadow (Q/A in `_ready()`).

### 3.6 `sphere_tracer.gd`

The same loop as the shader, in GDScript, with a `Result` that reports the step count. Compare the stopping rule with the shader's; `floor_tolerance` keeps the rule meaningful at t = 0. Read `test_10_sphere_tracer.gd`: the head-on ray of P1, a miss, the doubled field of P2, the slab test.

### 3.7 The scene root and the scene

`raymarching.gd` places each child of `Formations` at terrain height plus its scene y (so the scene file holds an offset, as Lesson 07 did for `Rocks`). P, X and Z write into every volume. Read the Q/A on `_process()`: why the HUD shows the frame time and not the GPU time.

In the scene: `PileNear` at (−9, ground − 0.5, 31), 13 m left of the meshed pile; `PileFar` at (−30, ground − 1, −8), scale 4, turned 30°; `TorField` at (26, ground − 0.8, −14), scale 2.5. The two far formations stand behind the hill as seen from the spawn.

## 4. Run and observe

Start the lesson scene.

- **O1.** Turn left from the spawn toward `PileNear`. Walk around it and compare it with the meshed pile 13 m to its right. Where does the terrain cut the raymarched rock? Walk into it: the capsule passes through. Why? Press P to cycle the views (steps, normals, mean H). In the H view, compare with the Lesson 09 H view (U on the meshed pile): which features does the per-pixel H show that the per-vertex one does not?
- **O2.** The silhouette check of the sync between the two libraries. In a scratch SceneTree script (not in the repository), place an `SdfMesher` with an unshaded white material and a `RaymarchVolume` for `boulder_pile.tres` at the same transform, a black background, and a camera at (1.5, 2, 9) looking at (1.5, 1.2, 0). Render the mesh alone and the march alone, and count the pixels each covers and the pixels covered by one but not the other. Images saved under `res://` become part of the project: the editor imports each one and writes an `.import` file beside it. Count from the `Image` in memory, or save next to the script. Repeat with mesher cell sizes 0.15 and 0.05, and `epsilon_pixels` 0.5, 0.1, 2. What does the difference measure: the GLSL mirror, the mesher, or the march?
- **O3.** Press P for the step view at the spawn and at `PileNear`. Where are the steps highest? Press X to set the budget to 16. What disappears from the lit view, and where? Read the CPU numbers of O6 before you answer.
- **O4.** Walk into `PileNear` until the camera is inside a stone (the spring arm lets the camera follow the head; lower the camera with the arrow keys). What fills the screen, and why? What would happen with `cull_back` (T6)?
- **O5.** Run `tools/raymarch_perf.sh`. It prints the mean frame time with vsync off at two camera views (an overview of all three formations from 16 m up, and a close view where `PileNear` fills most of the window), with the formations hidden and at budgets 16 to 192. How much does a formation cost in the overview? In the close view? How much of the cost depends on the budget, and why does a fourfold budget (16 → 64) not cost four times as much?
- **O6.** In a scratch script, trace the 160 × 90 rays of a camera at (1.5, 2, 9) looking at (1.5, 1.2, 0) (vertical field of view 75°) against the pile with `SphereTracer.trace()` inside `box_interval()` of `bounds().grow(0.05)`. Count hits, mean steps for hits and misses, the largest step count, and rays that exhaust the budget. Vary L (1.252, 1.0, 0.5), `epsilon_pixels` (0.5, 0.1, 2) and the budget (96, 16). For each hit, evaluate f at the hit point: how many hits lie more than 1 cm inside the rock?

## 5. Tweak

Make each change, run, observe, and revert.

- **T1.** In `RaymarchVolume.rebuild()`, set `step_scale` to 1.0 (ignore L), then to 2.0. What changes on screen in each case? Relate to P2 and O6.
- **T2.** Set `epsilon_pixels` to 0.05 and to 4 on `PileNear` in the editor (the remote scene tree of the running game, or the scene). Watch the silhouette and the step view. Which setting costs more steps, and where?
- **T3.** In `raymarch.gdshader`, set the default of `normal_step` to 0.002 and of `curvature_step` to 0.03. Walk close to `PileNear`. What pattern appears, and what is its spacing? Then 0.02 and 0.05. Relate to P6.
- **T4.** Comment out the line `DEPTH = p_clip.z / p_clip.w;`. Look at `PileNear` from the spawn. Compare with P5.
- **T5.** Comment out `LIGHT_VERTEX = p_view.xyz;`. Stand beside `PileNear` with the sun behind you so that your shadow falls on the rock. Where does the shadow go?
- **T6.** Replace `render_mode cull_front;` by `render_mode cull_back;`. Look at the rock from outside, then walk into the box of `PileNear` (the box reaches about half a meter beyond the stones). What happens when the camera crosses the box face?

## 6. Exercises

- **E1 ★ Over-relaxed stepping.** Keinert et al., "Enhanced sphere tracing" (2014), step by ω f / L with ω ≈ 1.2–1.6 and fall back to ω = 1 when two consecutive unbounding spheres do not overlap (|step| > previous d + current d). Implement it in a copy of `SphereTracer.trace()` and measure the step counts of O6. Then move it into the shader and measure with `tools/raymarch_perf.sh`.
- **E2 ★★ A numerical check of the mirror.** The tests check that the generated code compiles, not that it computes the same f as GDScript. Write a compute shader (use `SurfaceNetsGpu` of Lesson 08 as the model for the `RenderingDevice` calls) that includes `sdf_library.gdshaderinc`, receives the generated `sdf_map()` and the noise texture, and evaluates f at 10 000 random points inside `bounds()`. Compare with `SdfShape.evaluate()`. Report the largest difference with and without the noise term, and explain both.
- **E3 ★★★ Shadows cast by the formations.** The proxy casts no shadow. Let it cast one: enable shadow casting and make the march run in the shadow pass (the shader then needs the light's camera, not the player's; find out which matrices Godot supplies in a shadow pass). Then compare with a cheaper approach: Quilez's soft shadows, marching from the hit point toward the sun inside `fragment()`, for self-shadowing only. Measure both with `tools/raymarch_perf.sh`.
- **E4 ★★ The full curvature per pixel.** Replace the trace estimate by Lesson 09's formula: build the Hessian from finite differences in the shader (how many evaluations?) and compute H and K. Compare the H view of both on `PileNear` and the frame time. Where does the trace estimate fail, and by how much? (Hint: the scaled-sphere ellipsoid, P4.)
- **E5 ★★ Level of detail.** Draw `PileNear` as the Lesson 09 mesh when the camera is within 20 m and as a raymarch beyond, with the same weathering colors. Make the switch invisible: what has to agree, and where does it not (silhouette, normals, curvature)? Use O2's comparison.
- **E6 ★★★ Noise in GLSL.** Remove the texture: write a 3D gradient noise in GLSL and use the same function in GDScript (a new `SdfNoise` resource, not `FastNoiseLite`), so that the two libraries agree to rounding. Derive its Lipschitz bound analytically and compare with the measured `noise_slope_per_frequency`. What does the shader gain (memory, the P6 grid) and lose (evaluations per step)?

## 7. Reflect

- **R1.** A raymarched rock has no triangles and no collision. Lesson 15 needs the player's hands to touch rock. Which queries can a physics engine ask of a triangle mesh that sphere tracing answers directly from f, and which can it not?
- **R2.** The weathering rule now runs per pixel. Decision 0010 computed curvature per vertex on the CPU. Which choice would you keep for a rock the player stands beside, and which for one 60 m away? What does each cost when the rock moves?
- **R3.** Sphere tracing is safe because f / L never exceeds the distance (Lesson 07 P7, DDG §4.6.3). Lesson 20 adds normal-mapped detail and Lesson 07's `SdfDisplace` already adds noise. Each displacement raises L, so the march slows everywhere, also far from the detail. How could the march use a small L far from the surface and the large one only near it?
- **R4.** The `.tres` tree is now the source of three consumers: the slices, the mesher and the shader. A fourth one, sound, could use f: an echo from a rock face, or wind noise that depends on the distance to the nearest rock. Which number would you send over OSC, at which rate, and which GDScript call would compute it?

## 8. Answers

<details><summary>P1</summary>

Head-on: t₀ = 0, f = 4, t₁ = 4, f = 0. Two evaluations; an exact distance function jumps to the surface in one step along a line through the center. `test_10_sphere_tracer.gd` measures 2. A ray that passes at height 1.01 has distance √(1.01² + z²) − 1 to the sphere at height 1.01 and depth z. Far away the steps are large; near z = 0 the distance falls to 0.01 while the ray is still tangent, and each step advances by about the current gap. The steps shrink to about a centimeter, then grow again as the ray leaves. A grazing ray pays for every point where it is close to the surface without crossing it; the step view shows this as a bright rim around every silhouette (O3).
</details>

<details><summary>P2</summary>

At o = (0, 0, 5), g = 2 (5 − 0.25) = 9.5. The first step lands at t = 9.5, at z = −4.5, beyond the sphere; g there is 8.5, positive, and the march goes on until it leaves the box: a miss. Stepping by g / 2 lands at t = 4.75 in two steps. `test_10_sphere_tracer.gd` checks both. For the pile, a step of f / 1.252 is 80 % of f, so each step covers less: O6 measured 6.0 mean steps for hits at L = 1.252 and 5.0 at L = 1.0, a ratio of 1.2. Stepping by 2f overshoots whenever the remaining distance is less than f: O6 measured 586 of 722 hits more than 1 cm inside the rock, the deepest at f = −0.589 m.
</details>

<details><summary>P3</summary>

The screen spans 2 tan(fov / 2) at distance 1 over 720 pixels: 2 tan(32.5°) / 720 = 0.00177 rad per pixel. At 5 m one pixel is 8.8 mm, at 50 m 8.8 cm; half a pixel gives a tolerance of 4.4 mm and 4.4 cm. A larger tolerance moves the silhouette outward: a ray that passes the rock within the tolerance stops and counts as a hit. O2 measured it.
</details>

<details><summary>P4</summary>

Σ kᵢ: each coordinate has two +1 and two −1. Σ kᵢ kᵢᵀ: each diagonal entry is 4 (four squares of ±1); each off-diagonal entry sums four products ±1, two of each sign. Taylor: fᵢ = f + h kᵢ·∇f + (h²/2) kᵢᵀ Hf kᵢ + O(h³). Then Σ kᵢ fᵢ = 0 + 4h ∇f + (h²/2) Σ kᵢ (kᵢᵀ Hf kᵢ) + O(h³). The last sum does not cancel: kᵢᵀ Hf kᵢ = tr Hf + 2 (Hxy kx ky + Hxz kx kz + Hyz ky kz), and with the four kᵢ the sum Σ kᵢ (kᵢᵀ Hf kᵢ) works out to 8 (Hyz, Hxz, Hxy). So ∇f ≈ Σ kᵢ fᵢ / (4h) − h (Hyz, Hxz, Hxy) + O(h²): the error is first order. A central difference cancels this term because its sample set contains −k with every k; the tetrahedron does not. Measured on a unit sphere at 1000 random points: largest normal error 0.058°, 0.29°, 1.43°, 2.82° for h = 2 mm, 1 cm, 5 cm, 10 cm, proportional to h. For the sum: Σ fᵢ = 4f + (h²/2) tr(Hf Σ kᵢ kᵢᵀ) + O(h³) = 4f + 2h² tr(Hf) + O(h³), so tr(Hf) has an error of order h as well (the third derivative fxyz survives). For a distance function, differentiate ‖∇f‖² = 1 along n: 2 nᵀ Hf ∇f = 0, so Hf n = 0 and nᵀ Hf n = 0. Lesson 09 P2: 2H = (tr Hf − nᵀ Hf n) / ‖∇f‖ = tr Hf. Evaluations per hit pixel: 4 (normal) + 4 + 1 (curvature) = 9, against Lesson 09's 26 for g, Hf, H, K, k₁, k₂.
</details>

<details><summary>P5</summary>

Without `DEPTH`, every pixel of the rock carries the depth of the box's back face, which lies behind the rock and, where the box reaches into the slope, behind the terrain. The terrain then hides all rock pixels whose back face lies below the ground: most of the rock. Rock pixels in front of the sky keep showing, and the rock hides terrain that lies between the rock and the back face. With `DEPTH`, each pixel carries the hit point's depth, and the terrain hides exactly the part of the rock below ground. Depth of p_view: p_clip = P p_view, depth = p_clip.z / p_clip.w (perspective division). T4 shows the case without.
</details>

<details><summary>P6</summary>

Linear interpolation between samples is continuous with a derivative that is constant inside each interval and jumps at the samples: the slopes of two neighboring segments differ. In 3D the gradient of the trilinear interpolant jumps on every cell face. A normal with h = 2 mm measures the slope inside one cell, and neighboring cells disagree: the shading shows a grid of lines 0.1 m apart (in the node's frame). With h = 50 mm the four samples straddle cell faces and average the jumps. T3 shows the grid; at 2 cm it is faint, at 5 cm not visible.
</details>

<details><summary>P7</summary>

⌈6.11 / 0.1⌉ + 1 = 63, ⌈5.71 / 0.1⌉ + 1 = 59, 59: 63 × 59 × 59 = 219 303 texels, 877 KB as 32-bit floats. At 0.11 µs per noise call the noise alone is 24 ms. Measured: `bake_milliseconds` 34.6–34.8 ms per volume headless; the rebuild including translation and compilation took 37–38 ms per volume. `TorField` bakes the same region (only the tor boulder is displaced, and its local bounds cover the region of both boulders of the pile).
</details>

<details><summary>P8</summary>

(a) and (b): only the `.tres` file; `SdfGlsl` writes the new numbers at the next rebuild, and the slices, the mesh and the raymarch follow. (c): a new `SdfCone` class in `src/sdf/`, a GLSL function `sdf_cone()` in `sdf_library.gdshaderinc`, and a branch in `SdfGlsl._emit_node()`; until the branch exists, `SdfGlsl.unsupported` names the class and it is drawn as empty space. (d): `SdfSmoothUnion.smin()` and `sdf_smin()`, both by hand; nothing checks that they agree except the silhouette comparison of O2 and exercise E2.
</details>

<details><summary>O1</summary>

The terrain cuts the bottom of the large tor and of the split boulder: `PileNear` stands 0.5 m below the ground height at its origin, on a slope, so the cut is not level. The capsule passes through because the formation has no collision shape; only `SdfMesher` builds one (Lesson 08). In the H view the perched stone and the ends of the large stones are red, the seams between stones blue, as in Lesson 09. The per-pixel H is the trace estimate of 3.4, measured over a 10 cm tetrahedron; the per-vertex H of Lesson 09 is measured over 1 cm and interpolated over 0.15 m triangles. Where they differ, decide which of the two approximations is at work before trusting either.
</details>

<details><summary>O2</summary>

Measured in a 1280 × 720 window, camera field of view 75°, camera at (1.5, 2, 9):

| mesher cell | `epsilon_pixels` | mesh pixels | march pixels | differing pixels | fraction of union |
|---|---|---|---|---|---|
| 0.15 | 0.5 | 43 330 | 44 369 | 1 095 | 2.5 % |
| 0.05 | 0.5 | 43 757 | 44 369 | 614 | 1.4 % |
| 0.05 | 0.1 | 43 757 | 43 565 | 202 | 0.46 % |
| 0.05 | 2.0 | 43 757 | 47 295 | 3 538 | 7.5 % |

A second view from (9, 6, 5) gave 2.6 %, 1.4 %, 0.45 % and 7.5 %. A distant view from (1.5, 30, 60), where the pile covers about 800 pixels, gave 8.1 %, 7.1 %, 4.2 % and 35 %: there every rim pixel is a large share. The difference shrinks when the mesh is refined (the mesher rounds and shrinks the shape by part of a cell) and when the tolerance shrinks (the march's rim). At `epsilon_pixels` 0.1 the march covers fewer pixels than the mesh: grazing rays near the silhouette now need more than the budget allows, or pass. What remains, a few hundred pixels on the rim, bounds any disagreement of the two libraries from above; the comparison cannot separate the three sources. Exercise E2 measures the mirror alone.
</details>

<details><summary>O3</summary>

The steps are highest on the rims of each silhouette (grazing rays, P1) and on misses that pass close to a stone; the inside of a silhouette is cheap, a few steps. O6 measured from 9 m: 6.0 mean steps for hits, 4.1 for misses, at most 26. At a budget of 16, rays near the rims run out (169 of 5694 rays in O6), and from 9 m all of them are misses; the hits are the same 801 rays. Farther away the budget bites: in a windowed overview from (0, 16, 45), the `TorField` lost parts of its tors at budget 16 (5465 pixels changed against budget 96). A ray over a field of nine tors passes close to several stones in turn and pays the grazing cost at each.
</details>

<details><summary>O4</summary>

The screen fills with one flat rock color. A camera inside a stone starts the march at t = 0 at a point with f < 0; the first test d < ε t succeeds, and every pixel reports a hit at the camera, with the same normal and the same light. The measured capture from inside the large tor of `PileNear` held a single color in all 921 600 pixels. With `cull_back` (T6) the box's front faces are drawn; once the camera is inside the box, they are behind it and nothing of the box is drawn, so the rock vanishes.
</details>

<details><summary>O5</summary>

Measured, 1280 × 720 window, Apple M1 Pro, Metal, 240 frames per row, two runs (the second in brackets where it differed by more than 0.01 ms):

| view | hidden | 16 | 32 | 64 | 96 | 192 |
|---|---|---|---|---|---|---|
| overview | 1.74 | 2.57 [2.58] | 2.78 | 2.87 | 2.86 | 2.87 |
| close | 1.69 | 5.03 | 5.58 | 5.94 | 6.07 | 6.16 [6.20] |

In the overview the three formations add about 1.1 ms per frame; in the close view one formation covering most of the window adds about 4.4 ms. The cost follows the covered pixels, not the formations. The budget matters little above 64 because almost every ray stops earlier (O6: at most 26 steps from 9 m); the budget only limits the rare long rays. From 16 to 64 the close view rises by 0.9 ms, a fifth of the cost: the work of a pixel is dominated by its first few steps and by the 9 evaluations for the normal and curvature after a hit. The GPU time per viewport reads 0 on this backend (`raymarching.gd`, Q/A at `_process()`); the frame time with vsync off is the measure.
</details>

<details><summary>O6</summary>

Measured (14 400 rays, 5 694 of them inside the box):

| L | `epsilon_pixels` | budget | hits | mean steps (hit) | mean steps (miss) | max steps | exhausted | hits > 1 cm inside |
|---|---|---|---|---|---|---|---|---|
| 1.252 | 0.5 | 96 | 801 | 6.0 | 4.1 | 26 | 0 | 0 |
| 1.0 | 0.5 | 96 | 779 | 5.0 | 3.4 | 23 | 0 | 0 |
| 0.5 | 0.5 | 96 | 722 | 2.2 | 2.0 | 15 | 0 | 586 |
| 1.252 | 0.1 | 96 | 699 | 8.9 | 4.7 | 53 | 0 | 0 |
| 1.252 | 2.0 | 96 | 1205 | 3.9 | 3.1 | 14 | 0 | 0 |
| 1.252 | 0.5 | 16 | 801 | 6.0 | 4.0 | 16 | 169 | 0 |

L = 1.0 makes no hit fall inside: the true largest ‖∇f‖ of the pile is below 1.252 (Lesson 07 P7 measured 1.157 outside), so L = 1.0 is unsafe in principle and safe at these rays. The hit count depends on L because the test compares f / L with the tolerance: a larger L is a larger tolerance in units of f. One evaluation of the pile took 6.4–7.6 µs in GDScript.
</details>

<details><summary>T1</summary>

`step_scale` 1.0: O6 found no hit inside the rock at L = 1.0, with a sixth fewer steps. The bound 1.252 is a guarantee; the field's actual slope is lower. `step_scale` 2.0 (stepping by 2f): rays overshoot into the rock and stop inside (O6: 586 of 722 hits more than 1 cm inside). In windowed captures the near pile kept its outline but changed its shading (23 423 pixels changed in a close-up), and the far tors showed notches where rays skipped thin parts (18 846 pixels changed in the overview).
</details>

<details><summary>T2</summary>

0.05: the silhouette shrinks and grazing rays need more steps: the rims in the step view brighten, and at budget 16 more of them run out. 4: the silhouette grows on every side (O2 at 2.0: 7.5 % of the union differs near, 35 % at a distance), and the steps fall (O6 at 2.0: 3.9 per hit, 14 at most).
</details>

<details><summary>T3</summary>

At 2 mm the stones show a grid of light and dark lines, about 0.1 m apart on `PileNear`, crossing like a quilt; the worn color (from H) lights up along the lines. The spacing is the noise texel (P6). At 2 cm the grid is faint, at 5 cm not visible in a close-up.
</details>

<details><summary>T4</summary>

From the spawn the terrain hides most of `PileNear`; parts of the perched stone and the stones' tops remain where their box's back face lies above the ground or against the sky, and those parts float in front of everything behind them. With `DEPTH` the rock sinks into the slope at the line where f = 0 meets the terrain.
</details>

<details><summary>T5</summary>

With `LIGHT_VERTEX` the player's shadow falls on the rock where the capsule blocks the sun. Without it, the shadow map is read at the box's back face, which lies behind the rock: the shadow on the rock is displaced and dark bands appear where the back face is in shadow of other objects. In a measured close-up, 66 405 pixels of the 921 600 changed by more than 8 of 255, all on the rocks.
</details>

<details><summary>T6</summary>

From outside the image does not change (P5's argument: every pixel of the box has a front and a back face); measured, 2 to 399 pixels differed in three views. Inside the box the front faces are behind the camera and are clipped, so the rock disappears when the camera crosses a box face, also outside the stones. A capture from inside the box of `PileNear`, 1 m from the large tor, showed the whole pile with `cull_front` and none of it with `cull_back`. `cull_front` keeps the back faces, which surround the camera.
</details>
