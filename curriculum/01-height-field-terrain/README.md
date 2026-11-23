# Lesson 01. Height-field terrain and normals

## 1. Orientation

The ground in the sandbox is the graph of a function h : ℝ² → ℝ. Building it requires answers to three questions:

1. Where are the points? (positions)
2. How are the points connected? (triangles)
3. Which way does the surface face at each point? (normals)

Normals control lighting, the slope coloring, and the player's sense of the ground. Later phases read them again: footstep synthesis (Lesson 05), normal maps (Lesson 20), climbing holds (Lesson 15).

Goal served (`plan.md`): "use (differential) geometry to create surfaces and effects"; "geometrically normal mapped to interact with the player."

Files:

| File | Role |
|---|---|
| `game/src/terrain/height_field.gd` | The function h, its gradient, its normal. Math only. |
| `game/src/terrain/terrain.gd` | Samples h on a grid, builds triangles, chooses a normal method. |
| `game/shaders/terrain.gdshader` | Colors the mesh by slope and height; debug views. |
| `game/data/terrain/sandbox_height_field.tres` | Parameter values for h. |

Reading: DDG §3.1–3.2 (surfaces, tangent vectors); §5.4 (definitions of vertex normals).

## 2. Predict

Work these on paper before reading the code.

- **P1.** Write the terrain as a map f(x, z) = (x, h(x, z), z). Compute ∂f/∂x and ∂f/∂z.
- **P2.** Godot uses a right-handed coordinate system with +y up. Which of the two cross products, ∂f/∂x × ∂f/∂z or ∂f/∂z × ∂f/∂x, points upward?
- **P3.** Show that the upward normal, before normalization, is (−h_x, 1, −h_z). Why does its y component not depend on h?
- **P4.** Let θ be the angle between the unit normal and straight up. Express cos θ and tan θ in terms of ‖∇h‖.
- **P5.** A mesh is made of flat triangles, and a flat triangle has one normal. The renderer asks for a normal at each *vertex*. Propose at least two definitions of a vertex normal.
- **P6.** For the Gaussian hill g(x, z) = A · exp(−(x² + z²) / (2σ²)), at what distance from the center is the slope steepest? What is the maximum slope angle for A = 12 m, σ = 22 m?

## 3. Read

### 3.1 `height_field.gd`

Three terms are summed: a tilted plane, a Gaussian mound, and a product of sinusoids. `height()` evaluates them; `gradient()` returns their partial derivatives, derived by hand; `normal()` converts the gradient into a unit normal.

Check each line of `gradient()` against your own derivative. Note the convention stated at the top of the file: a `Vector2 p` carries world x in `p.x` and world z in `p.y`.

Each exported property has a setter that calls `emit_changed()`. Find where `terrain.gd` connects to that signal.

### 3.2 `terrain.gd`

- `_build_arrays()` fills three arrays with one entry per vertex (position, normal, UV) and one index array with three entries per triangle. Study the ASCII diagram above the index loop.
- `_normal_at()` and `rebuild()` implement the three normal methods. `FACE_AVERAGED` discards the computed normals and asks Godot's `SurfaceTool` to derive them from the triangles.
- `_queue_rebuild()` collapses several property changes in one frame into one rebuild. Why does it check `is_node_ready()`?

### 3.3 `terrain.gdshader`

Read the header comment, then follow `world_normal` from `vertex()` to `fragment()`. Find the line that converts the normal into a slope angle and compare it with your answer to P4.

## 4. Run and observe

Open `scenes/sandbox.tscn` and run it (F6). Tab cycles views (lit, normals, slope). N cycles normal methods (analytic, finite difference, face averaged). Some experiments require changing **Terrain** properties in the Inspector; the terrain rebuilds in the editor viewport without running the game.

- **O1.** Slope view. Find the steepest ring on the central hill. Compare its distance from the center with your answer to P6. (The ripples and the tilt shift it.)
- **O2.** Set **Vertices Per Side** to 17 (8 m spacing). In the lit view, cycle the three normal methods. Which looks smoothest? Which shows the triangles?
- **O3.** Keep 17 vertices and analytic normals. Run the game and walk across a ridge. The shading suggests a smooth surface; the capsule follows flat triangles. What does this mismatch tell you about what a normal *is* to a renderer?
- **O4.** Choose `FINITE_DIFFERENCE`. Set **Finite Difference Step** to 4.0, then to 0.05, then to 0.00001. Describe each result in the lit and normals views.
- **O5.** In the normals view the colors look pale. The shader writes `n * 0.5 + 0.5`; flat ground should be (0.5, 1.0, 0.5). Why is the color on screen different?

Reference measurements, taken at 129 vertices per side: face-averaged normals deviate from the analytic normals by 0.66° on average and by 3.8° at the worst vertex. Predict how both numbers change at 17 and at 257 vertices per side. Exercise E6 asks you to measure them.

## 5. Tweak

Restore each change after the observation.

- **T1.** Set **Tilt** to (0.2, 0). In which direction does the ground rise? Confirm with the slope view and P4: what angle does a gradient of 0.2 give?
- **T2.** Set **Ripple Wavelength** to (1.5, 1.5) at 129 vertices per side (1 m spacing). The mesh shows a pattern, but its wavelength is not 1.5 m. Measure it in the viewport and explain the result with the sampling theorem. The grid spacing plays the role of the sample period.
- **T3.** In `_build_arrays()`, swap `indices[k + 1]` and `indices[k + 2]`. Predict the result, then run. Fly the editor camera below the terrain.

## 6. Exercises

- **E1 ★ Gradient check.** Write a function that compares `gradient(p)` with a central-difference estimate at many random points and returns the largest discrepancy. Run it for step sizes 10⁻¹ through 10⁻⁶ and tabulate the error. The curve has a minimum. Name the two sources of error on either side of it. Then consider: `Vector2` stores 32-bit floats while `float` is 64-bit. Which one limits the result here, and how would you change the test to move the minimum?
- **E2 ★ A ridge.** Add a fourth term: a Gaussian ridge of height R and width w along a line through point c with direction u = (cos φ, sin φ). Let d be the signed perpendicular distance from p to the line. Write h_ridge in terms of d, derive its gradient, and implement both with exported, signal-emitting properties. Verify with E1.
- **E3 ★ Slope readout.** Show the slope angle under the player on the HUD, computed two ways: from `HeightField.normal()` at the player's (x, z), and from `CharacterBody3D.get_floor_normal()`. When do the two disagree, and by how much? Try 17 and 129 vertices per side.
- **E4 ★★ Uphill effort.** In `player.gd`, scale walking speed by a function of the directional derivative D_v h = ∇h · v, where v is the unit direction of travel. Uphill should slow the player; steep downhill should also slow the player. Sketch the function before coding it. You will need ∇h from the floor normal alone: given a unit normal n, recover ∇h. (Start from your answer to P3.)
- **E5 ★★ Your own vertex normals.** Replace `SurfaceTool.generate_normals()` with your own code for three definitions from DDG §5.4: equal weights, area weights, and angle weights. Hint for area weights: the length of a triangle's edge cross product is twice its area. Which definition does Godot use? Decide by experiment, or read `scene/resources/surface_tool.cpp` in the Godot source.
- **E6 ★★ Convergence.** Write a function that reports the mean and worst angle between the mesh normals and the analytic normals. Measure `FACE_AVERAGED` at 17, 33, 65, 129, and 257 vertices per side. Plot error against grid spacing on log-log axes. What slopes do you find for the mean and for the worst case? Where on the terrain does the worst vertex sit? (DDG §5.6 discusses numerical convergence tests.)
- **E7 ★★★ Curvature view.** Add `hessian(p)` to `HeightField`, returning (h_xx, h_xz, h_zz). For a graph surface,

  K = (h_xx h_zz − h_xz²) / (1 + h_x² + h_z²)²

  H = ((1 + h_z²) h_xx − 2 h_x h_z h_xz + (1 + h_x²) h_zz) / (2 (1 + h_x² + h_z²)^(3/2))

  With this sign convention a bowl has H > 0. Pass K or H to the shader per vertex (vertex color or `Mesh.ARRAY_CUSTOM0`) and add `debug_view = 3`. Where on the terrain is K positive, negative, zero? Relate the regions to DDG §3.4. Phase 3 uses curvature to weather rock.
- **E8 ★★★ Diagonal choice.** Every grid square is split along the i00–i11 diagonal. Construct a height function that exposes the resulting artifact. Then choose the diagonal per square, for example by comparing each diagonal's midpoint height with h at the square's center. Compare with the Delaunay criterion for triangulations.

## 7. Reflect

- **R1.** A Joshua Tree boulder overhangs: a vertical line can cross its surface more than once. Why can a height field not represent it? What representation can? (Phase 3.)
- **R2.** At low resolution, analytic normals made the surface look smoother than its geometry. When is this deception useful, and where does it fail? Consider silhouettes, shadows, and collisions. (Lesson 20.)
- **R3.** Lesson 05 synthesizes footsteps from contact data. Which quantities computed in this lesson would you send to SuperCollider with each step?

## 8. Answers

<details><summary>P1</summary>

∂f/∂x = (1, h_x, 0) and ∂f/∂z = (0, h_z, 1), where h_x = ∂h/∂x and h_z = ∂h/∂z.
</details>

<details><summary>P2</summary>

∂f/∂z × ∂f/∂x. With a = (0, h_z, 1) and b = (1, h_x, 0):

a × b = (a_y b_z − a_z b_y, a_z b_x − a_x b_z, a_x b_y − a_y b_x) = (−h_x, 1, −h_z).

The y component is 1 > 0, so it points up. The other order gives the negation, pointing down.
</details>

<details><summary>P3</summary>

The computation is in P2. The y component of a × b is a_z b_x − a_x b_z, which involves only the x and z components of the tangents: (0, 1) and (1, 0) in the xz-plane. Those components come from the parameterization (x and z map to themselves), not from h. Geometrically, the y component equals the area of the parallelogram spanned by the tangents' projections onto the ground plane, which is 1 for this parameterization.
</details>

<details><summary>P4</summary>

n = (−h_x, 1, −h_z) / √(1 + ‖∇h‖²). With up = (0, 1, 0):

cos θ = n · up = 1 / √(1 + ‖∇h‖²), sin θ = ‖∇h‖ / √(1 + ‖∇h‖²), so tan θ = ‖∇h‖.

The slope angle is the arctangent of the gradient's length, which matches the everyday definition "rise over run."
</details>

<details><summary>P5</summary>

Candidates include: the average of adjacent face normals with equal weights; the same average weighted by triangle area; weighted by the triangle's angle at the vertex; and, when the smooth surface is known (as here), the normal of that surface at the vertex. DDG §5.4 derives further definitions (mean curvature normal, sphere-inscribed normal) and shows each is the answer to a different question.
</details>

<details><summary>P6</summary>

In polar form g(r) = A exp(−r² / 2σ²), so g′(r) = −(A r / σ²) exp(−r² / 2σ²). The steepness |g′| is greatest where d/dr [r exp(−r²/2σ²)] = exp(−r²/2σ²)(1 − r²/σ²) = 0, that is at r = σ.

Maximum slope: (A / σ) e^(−1/2) = (12 / 22)(0.607) ≈ 0.33, so θ = arctan(0.33) ≈ 18°.
</details>

<details><summary>O2</summary>

Analytic and finite-difference (small step) normals look smooth. Face-averaged normals show facets and creases along triangle edges, because they know only the coarse triangles, not the function underneath.
</details>

<details><summary>O3</summary>

To the renderer a normal is an input, not a property derived from the geometry. Lighting uses whatever vector it is given. That is the principle behind normal mapping (Lesson 20): store fine-scale normals in a texture and light a coarse mesh as if it carried the fine detail. The deception holds for shading; it fails at silhouettes and in physics, which use the actual triangles.
</details>

<details><summary>O4</summary>

Measured at 129 vertices per side:

| Step | Mean error | Worst error | Appearance |
|---|---|---|---|
| 4.0 m | 4.4° | 9.3° | Smoothed. Each secant spans 8 m and averages away the ripples. |
| 0.05 m | 0.006° | 0.04° | Matches analytic. (The residual comes from Godot compressing stored normals.) |
| 0.00001 m | 1.6° | 4.4° | Noisy. |

Large steps give truncation error, which grows with the step squared for central differences. Tiny steps give rounding error: `p + Vector2(e, 0)` is computed in 32-bit floats, and near |x| = 50 m adjacent 32-bit values are about 4 × 10⁻⁶ m apart. A step of 10⁻⁵ m is only two or three of those increments, so the step the code divides by is not the step that was taken. E1 examines this.
</details>

<details><summary>O5</summary>

`EMISSION` passes through the rest of the pipeline after the fragment shader. Fog blends each pixel toward the fog color with distance, and the tonemapper (AgX, set in the `Environment`) compresses and desaturates bright values. To inspect raw normals: set the environment's tonemap mode to Linear and disable fog, or write a debug shader with `render_mode unshaded, fog_disabled;`. Lesson 03 treats color spaces and tonemapping, and its O6 adds a third step: the display shows the sRGB encoding of the linear value, so 0.5 appears as 188 of 255.
</details>

<details><summary>Reference measurements (face-averaged error versus resolution)</summary>

Measured, not to be read before E6:

| Vertices per side | Spacing | Mean | Worst |
|---|---|---|---|
| 17 | 8.0 m | 15.9° | 26.1° |
| 33 | 4.0 m | 7.9° | 14.3° |
| 65 | 2.0 m | 2.5° | 7.5° |
| 129 | 1.0 m | 0.66° | 3.8° |
| 257 | 0.5 m | 0.17° | 1.9° |

At fine spacing the mean error falls by about 4 per halving (second order). The worst error falls by about 2 per halving (first order) and sits on the boundary of the grid, where each vertex has neighbors on one side alone.
</details>

<details><summary>T1</summary>

The height increases by 0.2 m per meter of +x, so the ground rises toward +x. θ = arctan(0.2) ≈ 11.3°. The slope view shifts toward green on the whole terrain.
</details>

<details><summary>T2</summary>

Sampling at 1 sample per meter, the highest representable frequency (Nyquist) is 0.5 cycles per meter: wavelength 2 m. A ripple of 1 / 1.5 ≈ 0.667 cycles per meter folds back to |0.667 − 1| ≈ 0.333 cycles per meter, a wavelength of 3 m. This is the same aliasing heard when a sine above half the sample rate is digitized.
</details>

<details><summary>T3</summary>

The first triangle of each square (i00, i10, i11) now runs counterclockwise as seen from above, so Godot treats its back side as facing up and culls it. Seen from above, every square loses that triangle; seen from below, those triangles are the only ones visible. The vertex normals are unchanged, so the remaining triangles light the same as before. Winding decides visibility; normals decide shading.
</details>
