# Lesson 09. Normals and curvature of implicit surfaces

Lesson scene: `game/scenes/lessons/09_implicit_curvature.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–08 are unchanged; the Lesson 08 scene keeps its one-color rock.

## 1. Orientation

Lesson 08 turned the boulder field f into triangles. Its normals came from the trilinear interpolant of the grid, and its color was one number. This lesson returns to the field itself and asks what f says about the shape of its zero set at a point. It answers four questions:

1. What is the normal of a level set, and how do an analytic gradient and a central difference compare? (n = ∇f / ‖∇f‖, truncation and rounding error)
2. How does the normal change as one moves along the surface? (the Hessian, the shape operator)
3. How are mean and Gaussian curvature read off ∇f and the Hessian, and how are the formulas checked? (H = ½ div n; Goldman's adjugate formula; sphere and torus)
4. How does a number per vertex reach a fragment shader and become color? (a custom vertex channel; a weathering rule)

The method: at every mesh vertex, 26 evaluations of f give the gradient and the Hessian by central differences; from them come the unit normal, the mean curvature H, the Gaussian curvature K and the principal curvatures k₁ ≥ k₂. The mesh carries the normal and the four curvature numbers; a new rock shader lightens convex edges, darkens sheltered hollows and adds dust on top faces. The result: the boulder pile with curvature-driven weathering color, and three diagnostic views (H, K, normals).

Goal served (`plan.md`): "a natural environment with rocks ... all geometrically normal mapped"; "as much as possible I want to use (differential) geometry ... to create surfaces". Lesson 15 (climbing) will query normals and curvature of the field to find holds.

Files:

| File | Role |
|---|---|
| `game/src/sdf/implicit_curvature.gd` | `ImplicitCurvature` (static): Hessian by central differences, mean and Gaussian curvature, principal curvatures, `sample()` at one point, closed-form torus curvature. |
| `game/src/sdf/sdf_torus.gd` | `SdfTorus`: a test surface whose curvature changes sign; `analytic_gradient()` by the chain rule. |
| `game/src/sdf/curvature_mesher.gd` | `CurvatureMesher` (`@tool`, extends `SdfMesher`): after the Lesson 08 rebuild, samples curvature at each vertex and re-assembles the mesh with gradient normals and a `CUSTOM0` channel. |
| `game/shaders/rock_weathering.gdshader` | Rock shader: color from H; views for H, K, normals. |
| `game/data/rocks/weathered_rock_material.tres` | `ShaderMaterial` with that shader. |
| `game/src/lessons/implicit_curvature.gd` | Scene root. Extends `field_to_mesh.gd` (Lesson 08); U and I keys; two lines in `HUD/RockLabel`. |
| `game/scenes/lessons/09_implicit_curvature.tscn` | The Lesson 08 scene with `Rocks/Boulders` as a `CurvatureMesher` and the new material. |
| `game/project.godot` | Input actions `cycle_curvature_view` (U) and `toggle_normal_source` (I); `run/main_scene`. |
| `game/tests/test_09_*.gd` | Formulas on sphere and torus; the scene, the mesh channel, the keys. |
| `docs/decisions/0010-curvature-per-vertex.md` | Why curvature is computed per vertex on the CPU and carried in `CUSTOM0`. |

U and I are keyboard keys only; no gamepad button is free.

Reading: DDG §3.4 (pp. 38–41): normal curvature κₙ(X) = df(X) · dN(X) / |df(X)|², the shape operator, principal curvatures as its eigenvalues, H = (κ₁ + κ₂)/2, K = κ₁κ₂, and κₙ(Y) = κ₁cos²θ + κ₂sin²θ. DDG writes f for the immersion of a parametric surface; here f is the distance field, and the surface is its zero set. Ron Goldman, "Curvature formulas for implicit curves and surfaces" (*CAGD* 22, 2005), Section 4: Eqs. (4.1)–(4.3), Corollary 4.5, Example 4.1. Inigo Quilez, "normals for an SDF". Full entries: `docs/references.md`.

No earlier exercise is needed.

## 2. Predict

Notation: g = ∇f (a column vector), Hf = the Hessian, the 3 × 3 matrix of second derivatives ∂²f/∂xᵢ∂xⱼ; n = g / ‖g‖. f is negative inside the rock, so n points outward.

- **P1.** For the sphere f(p) = ‖p‖ − r, compute g and Hf by hand. (Write ‖p‖ = (p · p)^½ and differentiate twice.) What is ‖g‖? Which vector is in the kernel of Hf, and what are its other two eigenvalues? What do the eigenvalues say about how n turns as p moves along the surface?
- **P2.** Show that div n = tr(Hf)/‖g‖ − gᵀHf g / ‖g‖³. (Use the product rule on gᵢ · ‖g‖⁻¹ and ∂ⱼ‖g‖ = (Hf g)ⱼ / ‖g‖.) Evaluate it on the sphere. Why is the mean curvature *half* of it?
- **P3.** A torus around the y axis has tube radius r and center-circle radius R. At the outer equator (farthest from the axis), what are the two principal curvatures? At the inner equator? At the top of the tube? Use DDG's picture of normal curvature: a circle of radius ρ that bends toward the inside of the solid has curvature 1/ρ; one that bends the other way counts negative. Compute H and K at the three points for R = 1, r = 0.25.
- **P4.** A central difference [f(x + h) − f(x − h)] / 2h has truncation error (h²/6) f‴. The second difference [f(x + h) − 2f(x) + f(x − h)] / h² has truncation error (h²/12) f⁗. Each f value carries a rounding error ε (Lesson 07: about 10⁻⁷ m for points near 1 m stored in 32-bit `Vector3`). How does the rounding error of each formula scale with h? Estimate the step that balances the two for the second difference on a sphere of radius 1. Is it larger or smaller than the best step for the gradient?
- **P5.** f of a union is min(f₁, f₂). Where the two stones meet, f has a crease. What does a central difference of width 2h return for the gradient at a point on the crease where the two stone normals are opposite (two stones pressed against each other)? What happens to n, to H, to K there?
- **P6.** A sphere scaled to f = c(‖p‖ − r) has the same zero set. Which of g, Hf, n, H, K change with c > 0? Which change sign with c = −1?
- **P7.** The weathering rule lightens vertices with H above 0.9 /m and darkens those below 0.2 /m. A boulder that is roughly an ellipsoid with semi-axes 1.5, 1.0, 0.8 m: which parts are worn, which are plain, which are sheltered? Where would a cylinder-shaped ridge with radius 0.4 m fall?
- **P8.** One curvature sample costs 26 evaluations of f. The pile mesh has 4225 vertices; one evaluation costs about 5.7 µs (Lesson 08). Estimate the time. Compare it with the 650 ms of sampling in Lesson 08.

## 3. Read

### 3.1 `sdf_torus.gd`

Read `evaluate()`. The torus reduces to a 2D problem in the half-plane that contains the y axis and p: distance to a disk. Then read `analytic_gradient()`: the chain rule through ρ = √(x² + z²) and d = √((ρ − R)² + y²). Derive each component yourself before checking the comment. Where is the gradient undefined, and why does that not matter for points on the surface? (On the surface d = r > 0, and ρ ≥ R − r > 0 when R > r.)

### 3.2 `implicit_curvature.gd`

Read the header: the notation and the sign convention. Then:

- `DEFAULT_STEP`. Read the Q/A against your answer to P4.
- `hessian()`. Read both Q/A comments. The diagonal uses three points per axis, the off-diagonal four corners per pair: 1 + 6 + 12 = 19 evaluations. The result is returned as a `Basis`, whose three columns are `x`, `y`, `z`; for a symmetric matrix rows and columns agree, so `hess.y.x` is ∂²f/∂x∂y.
- `mean_curvature()`. Check the formula against P2: (‖g‖² tr Hf − gᵀHf g) / (2‖g‖³). `hess * g` is the matrix–vector product.
- `gaussian_curvature()`. The adjugate adj(A) satisfies A adj(A) = det(A) I. For K only the quadratic form gᵀ adj(Hf) g is needed. Expand it for a symmetric matrix and compare with the six terms in the code. Goldman writes it as −det of the 4 × 4 matrix [[Hf, g], [gᵀ, 0]] divided by ‖g‖⁴ (Eq. 4.1); expanding that determinant along the last row and column gives the same six terms.
- `principal_curvatures()`. k₁ and k₂ are the roots of k² − 2Hk + K = 0 (Goldman Eq. 4.3).
- `sample()`. It calls `SdfShape.gradient()` (Lesson 07) and `hessian()` with the same h. The `# EXERCISE` marks E2: the six gradient samples repeat points the Hessian already evaluated.

A sign note. Goldman's Eq. (4.2) reads (gᵀHf g − ‖g‖² tr Hf) / (2‖g‖³), and his Example 4.1 gives −1/R for a sphere with F = x² + y² + z² − R², whose gradient points outward. This lesson follows DDG §3.4, where the normal curvature of a sphere with outward normal is positive, and uses the negative of Goldman's expression. Goldman's Corollary 4.5 states K_M = −∇ · N; expanding the divergence (P2) gives −2 K_M, so the corollary as printed lacks the factor ½. The tests check this lesson's convention on the sphere (H = +1/r) and that H changes sign under f → −f while K does not.

### 3.3 Why the Hessian gives curvature

Take a unit tangent vector t at a surface point (t · g = 0). Move along the surface in direction t; n changes at the rate dn(t) = P Hf t / ‖g‖, where P = I − n nᵀ removes the part along n (differentiate g/‖g‖; the derivative of ‖g‖ only scales along n). DDG's normal curvature is κₙ(t) = t · dn(t) = tᵀHf t / ‖g‖. So the restriction of Hf / ‖g‖ to the tangent plane is the shape operator, its eigenvalues are k₁ and k₂, its trace is 2H and its determinant is K. tr(Hf) counts all three directions; subtracting nᵀHf n leaves the two tangent ones: 2H = (tr Hf − nᵀHf n) / ‖g‖, which is P2. The determinant of a 2 × 2 restriction is the corresponding cofactor, which is why adj(Hf) appears in K.

### 3.4 `curvature_mesher.gd`

`CurvatureMesher` extends `SdfMesher` and overrides `rebuild()`: it calls `super()` (Lesson 08, unchanged: grid, cell table, faces, collision), then samples each vertex and calls `_assemble_mesh()`. Read the two Q/A comments:

- Why a second `ArrayMesh`. A surface's vertex format is fixed when it is created.
- The format flag. `CUSTOM0` can hold 8-bit bytes, half floats or floats; the flag `ARRAY_CUSTOM_RGBA_FLOAT << ARRAY_FORMAT_CUSTOM0_SHIFT` selects four 32-bit floats. Curvature at creases reaches millions per meter (O4); half floats stop at 65504.

`normal_source` switches between the trilinear normals stored by `SurfaceNets` and the gradient normals; the setter calls `_assemble_mesh()` directly, without resampling. The comment on `_mesh_instance` explains why the subclass touches a member of its parent. `normal_angle_stats()` compares the two normals per vertex.

### 3.5 `rock_weathering.gdshader`

Read the header's three Q/A. Then `vertex()`: `CUSTOM0` is copied into a `varying`, and the rasterizer interpolates it across each triangle, as it does with `NORMAL`. The normal goes to world space for the dust rule.

`fragment()`, view 0. Three weights from `smoothstep`: wear from H between `wear_start` and `wear_full`, shelter from −H between −`cavity_start` and −`cavity_full`, dust from the world normal's y. Note the argument order in the shelter line: `smoothstep(e0, e1, x)` needs e0 < e1, so the rule is written on −H. Views 1 and 2 use a diverging map (blue negative, white zero, red positive); K is shown as sign(K)√|K| so that it has the units of H. Lesson 03 introduced `source_color`; the four color uniforms are typed in sRGB.

### 3.6 `implicit_curvature.gd` (the scene root) and the scene

U writes `curvature_view` into the material. The material is a shared resource: the Lesson 09 scene is its only user, so no copy is made (compare `SdfSlice`, which duplicates its material because two slices share one file). I flips `normal_source`. The HUD appends the view, the normal source, the curvature time, and the mean and largest angle between the two normals.

## 4. Run and observe

Start the lesson scene. The boulders stand ahead and to the right of the spawn.

- **O1.** Walk to the pile. Where is the stone pale, where dark, where dusty? Compare with your answer to P7. Press U to show the H map. Which stone has the most red, and why? Press U again for the K map. Where is K negative (blue)?
- **O2.** Press I several times while looking at the pile from a few meters, with the low sun behind you. Where does the shading change? Read the angle line in the HUD. Compare its maximum with Lesson 08 T5.
- **O3.** Read the curvature time in `HUD/RockLabel` and compare with P8. What fraction of the rebuild is it now?
- **O4.** In the H view, look where the perched stone rests on the large one and into the cleft of the split boulder. Then close the game, select `Rocks/Boulders` in the editor, and set `curvature_step` to 0.005, 0.02, 0.04 in turn. Where does the color change, and where does it stay? (The editor rebuilds; the HUD of a running game shows the timings.)
- **O5.** Run `test_09_implicit_curvature.gd`. Then, in a scratch SceneTree script (not in the repository), call `ImplicitCurvature.sample()` on a unit sphere at 200 random surface points for h = 10⁻⁴, 10⁻³, 3 × 10⁻³, 10⁻², 3 × 10⁻², 10⁻¹, and record the largest |H − 1|. Repeat with the sphere centered at (5, 5, 5). Plot the error against h on log–log axes. Compare with P4.
- **O6.** In the same script, compare `SdfTorus.gradient(p, h)` with `analytic_gradient(p)` for h from 10⁻⁵ to 10⁻¹. Where is the smallest error, and why does it lie at a smaller h than in O5?

## 5. Tweak

Make each change, run, observe, and revert.

- **T1.** In `rock_weathering.gdshader`, set `wear_start` to 0.5 and `cavity_start` to 0.6. What happens to the stones? Why can wear and shelter now act on the same vertex, and what does the order of the two `mix()` calls decide?
- **T2.** In `mean_curvature()`, drop the term `- along`. Run `test_09_implicit_curvature.gd`. Which checks fail? What does the sphere give, and why (P1)?
- **T3.** In `hessian()`, divide the mixed difference by `2.0 * h * h` instead of `4.0 * h * h`. Which test catches it, and which do not? Why does the sphere at a point on a coordinate axis not notice?
- **T4.** In `_assemble_mesh()`, remove the `format` argument from `add_surface_from_arrays()`. What does Godot report, and why does it need to be told the layout of `CUSTOM0`?
- **T5.** In the shader, replace `curvature = CUSTOM0;` by `curvature = vec4(CUSTOM0.x * 0.0 + 1.0, 0.0, 0.0, 0.0);`. Every vertex now claims H = 1 /m. Which view shows what?
- **T6.** Set `curvature_step` to 0.001 in the editor. Look at the H view. Relate the speckle to O5.

## 6. Exercises

- **E1 ★ Analytic Hessian of the torus.** Add `analytic_hessian(p)` to a copy of the torus (your own class, or a scratch script). Differentiate `analytic_gradient()` once more by the chain rule. Compare with `ImplicitCurvature.hessian()` at 100 points for h = 10⁻³, 10⁻², 3 × 10⁻², and with the closed-form H and K from `torus_curvatures()`. Which error dominates at each h?
- **E2 ★ Fewer evaluations.** Complete the `# EXERCISE` in `ImplicitCurvature.sample()`: compute the gradient from the six axis samples the Hessian diagonal already takes, and f(p) once. Count the evaluations (a counting wrapper `SdfShape` subclass does this) and measure the curvature time of the pile. Check that the tests still pass.
- **E3 ★★ Tetrahedral normals.** Quilez's "normals for an SDF" estimates the gradient from four samples at the vertices of a tetrahedron, k₀ = (1, −1, −1), k₁ = (−1, −1, 1), k₂ = (−1, 1, −1), k₃ = (1, 1, 1): g ≈ Σ kᵢ f(p + h kᵢ). Show by Taylor expansion that g = 4h ∇f + O(h²), so the estimated direction g / ‖g‖ has error O(h). (Lesson 10 P4 carries the second-order term.) Compare its normals with the six-sample normals on the torus and the pile (angles), and its cost.
- **E4 ★★ Principal directions.** Extend `sample()` to return the principal directions: the eigenvectors of P Hf P / ‖g‖ in the tangent plane. (Build an orthonormal tangent basis t₁, t₂, form the symmetric 2 × 2 matrix tᵢᵀHf tⱼ / ‖g‖, and diagonalize it.) Draw short line segments along the direction of k₁ at a subset of vertices with an `ImmediateMesh`. Check on the torus: k₁ runs around the tube. Where on the pile are the directions undefined, and how would you detect that?
- **E5 ★★ Ambient occlusion from the field.** Cavities are dark for a second reason: less sky reaches them. Estimate occlusion at a vertex from f alone: sample f at p + n·dᵢ for d = 0.1, 0.2, 0.4, 0.8 m; on a flat surface f(p + n d) = d, in a hollow it is less. Sum the shortfall with weights, store it in a second custom channel (`CUSTOM1`), and blend it into the shader. Compare with the H-based darkening: where do the two agree, where not?
- **E6 ★★★ Curvature at the crease.** Vertices on the crease where stones meet carry absurd H and K (O4). Detect them from the samples you already have (small ‖g‖, a large difference between the trilinear and gradient normal, or |f| at the vertex), and replace their values by a robust estimate: the median of the neighbors' values over the mesh's edges. Show the count of replaced vertices in the HUD. What does Lesson 21's halfedge structure make easier here?

## 7. Reflect

- **R1.** Curvature is a property of the surface, not of f. A smooth union changes f near the seam and so changes the surface. A hard union leaves each stone's surface intact but adds a crease. Which union would you choose for a climbing route, given that Lesson 15 looks for holds by curvature?
- **R2.** Lesson 10 evaluates f per pixel on the GPU. The weathering rule would then run per pixel, with no mesh. How many evaluations does one pixel need for H, and what would replace the 26-sample stencil? What becomes possible that a per-vertex value cannot show?
- **R3.** DDG chapter 5 defines curvature on a triangle mesh directly (angle defect, cotangent Laplacian). Lesson 22 does so. Which estimate would you expect to agree better with the field values of this lesson on the smooth parts, and which would behave better at the crease?
- **R4.** The rock color now depends on curvature; footsteps on the rock (Lesson 05) still report the terrain under it. A footstep on a convex edge and one in a hollow could sound different. Which of H, K, k₁ would you send over OSC, and how would you append it to `/foot/step` without breaking the SuperCollider side?
- **R5.** P6 found that K is invariant under f → cf and H changes sign under f → −f. In Lesson 15 a hand may grip the underside of a ledge. Which sign tells concave from convex there, and does the answer depend on the hand's direction?

## 8. Answers

<details><summary>P1</summary>

g = p / ‖p‖, so ‖g‖ = 1 everywhere except the center (an exact distance function, Lesson 07). Hf = (I − n nᵀ) / ‖p‖ with n = p / ‖p‖. n is in the kernel (Hf n = 0); every vector perpendicular to n is an eigenvector with eigenvalue 1/‖p‖, which on the surface is 1/r. Moving a distance s along the surface turns n by the angle s/r in every tangent direction: k₁ = k₂ = 1/r, an umbilic (DDG §3.4.1).
</details>

<details><summary>P2</summary>

∂ⱼ(gᵢ / ‖g‖) = (Hf)ᵢⱼ / ‖g‖ − gᵢ (Hf g)ⱼ / ‖g‖³. Summing i = j gives div n = tr Hf / ‖g‖ − gᵀHf g / ‖g‖³. On the sphere: tr Hf = 2/r, gᵀHf g = 0, ‖g‖ = 1, so div n = 2/r. The divergence is the sum of the two principal curvatures (section 3.3: the trace of the shape operator); their mean is half of it, H = 1/r.
</details>

<details><summary>P3</summary>

At the outer equator the tube circle has curvature 1/r and the big circle around the axis has curvature 1/(R + r), both bending toward the inside: k₁ = 4, k₂ = 0.8, H = 2.4, K = 3.2 (per meter). At the inner equator the tube circle still gives 1/r = 4; the circle around the axis has radius R − r = 0.75 and bends away from the solid: −1/0.75 = −1.333. H = 1.333, K = −5.333: a saddle. At the top of the tube the normal is vertical, and the circle of radius R around the axis lies in the tangent plane: the plane spanned by its tangent and the normal cuts the surface in a curve with no bend at that point, normal curvature 0. k₁ = 4, k₂ = 0, H = 2, K = 0. In general K = cos θ / (r (R + r cos θ)) and H = (R + 2r cos θ) / (2r (R + r cos θ)), θ = 0 at the outer equator; `torus_curvatures()` returns these, and the test compares the numerical values with them.
</details>

<details><summary>P4</summary>

Rounding: the first difference divides an error near ε by 2h, so it scales as ε / h; the second difference divides by h², so it scales as ε / h². Balancing h² f⁗/12 against 4ε/h² gives h ≈ (48 ε / f⁗)^¼. For a sphere of radius 1, f⁗ is of order 1 near the surface, and ε ≈ 10⁻⁷ m gives h of order 0.05 m. The gradient balances h² against ε/h, balancing h² f‴/6 against ε/h gives h ≈ (6 ε / f‴)^⅓ ≈ 0.008 m for f‴ of order 1, a smaller step. Measured (O5): the H error is smallest near h = 0.03 m for the unit sphere. The default 0.01 m is a compromise for smaller features: the torus tube of radius 0.25 m has its smallest H error at h = 0.01 m (O5 answer).
</details>

<details><summary>P5</summary>

With opposite stone normals n₁ and −n₁, the difference across the crease averages them: f(p + h e) and f(p − h e) are taken on different stones, and the central difference returns roughly the average of the two gradients, which is close to zero. ‖g‖ is small, n is the normalization of a small, noisy vector, and H and K, which divide by ‖g‖³ and ‖g‖⁴, become huge. Measured on the pile at h = 0.01: smallest ‖g‖ 1.2 × 10⁻⁵, smallest H −9.2 × 10⁶ /m, largest K 5.6 × 10¹³ /m²; 21 of 4225 vertices have ‖g‖ < 0.5. The true surface has a crease there; its curvature is infinite along the crease (a concave kink), and the numbers measure the stencil, not the rock (O4).
</details>

<details><summary>P6</summary>

g and Hf scale by c; n, H and K do not change for c > 0 (Goldman 2005, the paragraph after Corollary 4.5: a factor c³ in numerator and denominator of H, c⁴ for K). For c = −1, g, Hf and n change sign, H changes sign, K does not. `test_09_implicit_curvature.gd` checks all four. A consequence: the weathering rule depends on the convention "negative inside" (decision 0008).
</details>

<details><summary>P7</summary>

On an ellipsoid with semi-axes a ≥ b ≥ c, H is smallest at the ends of the short axis (the broad faces) and largest at the ends of the long axis. For (1.5, 1.0, 0.8): at the end of the 0.8 axis, the curvatures are 0.8/1.5² = 0.36 and 0.8/1.0² = 0.8, H = 0.58; at the end of the 1.5 axis, 1.5/1.0² = 1.5 and 1.5/0.8² = 2.34, H = 1.92. So the broad faces stay plain, the long ends are worn, nothing on a convex ellipsoid is sheltered (H > 0 everywhere). A cylinder of radius 0.4 m has k₁ = 2.5, k₂ = 0, H = 1.25: worn, at about a quarter of the full wear weight (smoothstep of t = 0.32 is 0.24). Shelter comes only from concave places: seams between ellipsoids of a smooth union, the cleft, the noise displacement's hollows. Measured over the pile's vertices at h = 0.01: median H 0.67 /m; 1140 of 4225 above 0.9, 72 above 2.0; 629 below 0.2, 33 below −1.0.
</details>

<details><summary>P8</summary>

4225 × 26 × 5.7 µs ≈ 0.63 s, about the same as the 650 ms of sampling the whole grid. Measured: one `sample()` of the pile takes 147 µs; the curvature pass took 620 ms headless and 627 ms in a windowed run. `total_milliseconds` of `SdfMesher` does not include it: 1274 ms headless (CPU pass 1) plus 620 ms. The two counts of evaluations are close: 113 652 for the grid, 4225 × 26 = 109 850 for the curvature. A vertex is cheap to find and expensive to measure.
</details>

<details><summary>O1</summary>

Worn (pale): the small perched stone, which has the smallest radii (it is a tor boulder at scale 0.5, so its curvatures are twice those of the large tor), and the rims of the split boulder's cleft. Dark: the seam where the perched stone sits on the large one, the cleft's inner faces, and small hollows of the noise. Dusty: the tops of the large stones. In the K view, blue (K < 0) marks saddles. Expect them along the seams of the smooth unions inside each boulder, where two ellipsoids blend: the surface bends outward around the seam and inward across it. Measured: 587 of 4225 vertices have K < 0.
</details>

<details><summary>O2</summary>

The shading changes at creases: where the perched stone meets the large one and along the cleft. Elsewhere the two normals agree to a few degrees. Measured: mean angle 2.93° headless (CPU pass 1) and 2.96° windowed (GPU pass 1); largest 137.7° headless and 161.2° windowed. Lesson 08 T5 measured 2.96° and 137.7° with the CPU path. The maximum depends on the backend because both normals are unreliable at the same few crease vertices: the trilinear normal of a cell that holds two sheets, and the gradient normal of a near-zero gradient (P5); a difference of 10⁻⁶ in a cell value can flip either.
</details>

<details><summary>O3</summary>

Measured windowed: curvature 627 ms against sampling 678 ms, vertices (GPU) 3.0 ms, faces 257 ms, collision 10 ms. Curvature is about 40 % of the new rebuild. E2 removes 6 of the 26 evaluations per vertex (about 23 %).
</details>

<details><summary>O4</summary>

The smooth parts keep their color: the median H is 0.664, 0.665, 0.668, 0.666 /m at h = 0.005, 0.01, 0.02, 0.04. The crease values follow the stencil, not the rock: at the 1 % quantile H is −0.04, −0.12, −1.37, −6.09 /m, and the count below −1.0 /m is 35, 33, 45, 75. The 99 % quantile rises from 2.29 to 8.69 /m: a wider stencil reaches across more creases and rims. A curvature that grows as the step grows is the signature of a kink: across a crease of angle α the second difference is about α/h at the center and 0 further out, so its value at a vertex depends on how close the stencil comes.
</details>

<details><summary>O5</summary>

Largest |H − 1| on the unit sphere, 200 points (|K − 1| about twice as large):

| h (m) | 10⁻⁴ | 10⁻³ | 3 × 10⁻³ | 10⁻² | 3 × 10⁻² | 10⁻¹ |
|---|---|---|---|---|---|---|
| centered at 0 | 13.3 | 0.148 | 0.0204 | 0.00157 | 0.00023 | 0.0025 |
| centered at (5, 5, 5) | 16.7 | 0.165 | 0.0215 | 0.00203 | 0.00026 | 0.0025 |

Left of the minimum the error falls by about 100 per factor 10 in h (rounding, ε/h²); right of it, it rises by about 10 per factor 3 (truncation, h²). Moving the sphere to (5, 5, 5) raised the rounding error by 10–30 %, less than the factor 9.7 in ‖p‖ would suggest; the rounding of the evaluations near the origin is not the only source of error at small h. The torus (r = 0.25) at 360 points: H error 0.113, 0.0016, 0.0071 /m and K error 0.78, 0.012, 0.047 /m² for h = 10⁻³, 10⁻², 3 × 10⁻²; its fourth derivative is larger (smaller radius), so its best step is smaller.
</details>

<details><summary>O6</summary>

Largest ‖`gradient(p, h)` − `analytic_gradient(p)`‖ over 100 points of the torus tube: 1.5 × 10⁻³ (h = 10⁻⁵), 2.5 × 10⁻⁴ (10⁻⁴), 5.2 × 10⁻⁵ (10⁻³), 4.0 × 10⁻⁴ (10⁻²), 4.0 × 10⁻² (10⁻¹). The minimum lies near 10⁻³, the default of `SdfShape.gradient()` (Lesson 07), smaller than the best Hessian step because rounding enters as ε/h instead of ε/h² (P4). The normals from `sample()` at h = 10⁻² differ from the analytic ones by at most 0.013° on the torus.
</details>

<details><summary>T1</summary>

Half of the vertices have H between 0.43 and 0.92 /m (quartiles, P7 answer). With the new thresholds every vertex below 0.6 /m gets some shelter, and every vertex above 0.5 /m some wear; between 0.5 and 0.6 both act. The second `mix()` (cavity) is applied last and wins where both act, so the rock darkens over a large part of its surface. The order of the `mix()` calls is a priority rule; the default thresholds avoid needing one.
</details>

<details><summary>T2</summary>

Measured: one check fails, "squared sphere H error 0.335". For an exact distance ‖g‖ = 1 everywhere, so its derivative along n vanishes, Hf g = 0 (P1: g is in the kernel), and the dropped term is zero: the sphere, torus and formula checks all pass. The field f = ‖p‖² − r² is not a distance: g = 2p, Hf = 2I, gᵀHf g = 8r². Without the term, H = 4r² · 6 / (2 · 8r³) = 1.5/r = 1.0 for r = 1.5 instead of 0.667. The term matters for fields that are not distances; the smooth union inside the tor boulders is one (Lesson 07).
</details>

<details><summary>T3</summary>

The mixed derivatives double. Measured: 8 checks fail. The Quadratic gives ∂²f/∂y∂z = 4.0 instead of 2; the sphere's H error is 0.223 /m and its K error 0.347 /m² at both centers; the torus H error is 1.0 /m and its K error 12.9 /m². The exact-derivative checks of `_check_formulas()` do not call `hessian()` and pass; the squared sphere has the diagonal Hessian 2I and passes too. At a sphere point on a coordinate axis, Hf = (I − n nᵀ)/r is diagonal, so the mixed terms are zero and doubling them changes nothing; the random directions of the test avoid that case.
</details>

<details><summary>T4</summary>

Measured: Godot reports `Condition "p_arrays[ai].get_type() != Variant::PACKED_BYTE_ARRAY" is true` and "Invalid array format for surface", and the mesh gets no surface: the rock disappears. Without the flag, `CUSTOM0` defaults to four 8-bit values per vertex, passed as a `PackedByteArray`. The vertex buffer is a block of bytes; the format bits tell Godot and the shader how many bytes each vertex holds in each channel and how to read them.
</details>

<details><summary>T5</summary>

H = 1 /m lies just above `wear_start`: smoothstep(0.9, 2.0, 1.0) = 0.023, so the weathered view shows nearly plain rock everywhere, with dust on top faces (the normal still varies). The H map shows uniform pink (t = 1/2 of `map_scale` = 2). The K map is white (K = 0). The normal view does not change: it does not read `CUSTOM0`.
</details>

<details><summary>T6</summary>

At h = 10⁻³ the rounding error of the second difference is of order ε/h² ≈ 0.1–1 /m on a pile placed a few meters from shape origin (O5: 0.15–0.16 on a unit sphere). That is the size of the curvature itself, so neighboring vertices get random-looking H: speckle in the H view and spotty wear in the weathered view.
</details>
