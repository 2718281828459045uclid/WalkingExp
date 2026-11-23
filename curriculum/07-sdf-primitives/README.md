# Lesson 07. SDF primitives and composition

Lesson scene: `game/scenes/lessons/07_sdf_primitives.tscn`. Open it and press **F6** (Run Current Scene). **F5** runs the newest lesson's scene instead (`run/main_scene`). The scenes of Lessons 00–06 are unchanged; the Lesson 06 scene has no rocks.

## 1. Orientation

Phase 3 builds rock. The terrain of Lesson 01 is a graph, y = h(x, z): one height per column of the world. A boulder has an underside, a cleft, and a smaller boulder perched on top; no function of (x, z) can describe it. This lesson describes solids by a function of all three coordinates instead, f(x, y, z), whose zero set is the surface. It answers five questions:

1. What is a signed distance function (SDF), and what are the exact ones for a sphere, a box, a capsule? (distance functions)
2. Why has an ellipsoid no exact formula, and what can stand in for one? (bounds, estimates)
3. How do shapes combine: union, intersection, subtraction, and a union with a fillet? (min, max, smooth minimum)
4. How does one move, copy, and roughen a shape without touching its formula? (domain operators, repetition, displacement)
5. How fast can such a function change, and why does that number matter later? (the Lipschitz bound)

The result is a set of boulders after the monzogranite piles of Joshua Tree, stored as `.tres` files, and a tool that shows any SDF as a colored plane cut. Nothing is meshed yet; Lesson 08 turns the zero set into a walkable mesh through the `evaluate()` interface built here.

Goal served (`plan.md`): "get into procedural math based rendering and modeling, possibly using SDFs"; "crawling/climbing/scrambling, as if travelling up rocky formations in a place like Joshua Tree."

Files:

| File | Role |
|---|---|
| `game/src/sdf/sdf_shape.gd` | `SdfShape` Resource: the interface every shape shares (`evaluate`, `lipschitz_bound`, `bounds`, `gradient`). |
| `game/src/sdf/sdf_sphere.gd`, `sdf_box.gd`, `sdf_capsule.gd`, `sdf_ellipsoid.gd` | Primitives. |
| `game/src/sdf/sdf_union.gd`, `sdf_intersection.gd`, `sdf_subtraction.gd`, `sdf_smooth_union.gd` | Operators that combine children. |
| `game/src/sdf/sdf_transform.gd`, `sdf_repeat.gd`, `sdf_displace.gd` | Operators that move the point, copy the shape, or add noise. |
| `game/src/sdf/sdf_slice.gd` | `SdfSlice` (`@tool` Node3D): samples a shape in one plane and draws the result. |
| `game/shaders/sdf_slice.gdshader` | Colors a slice texture: distance bands, gradient length, sign. |
| `game/data/rocks/*.tres` | `granite_noise.tres` (FastNoiseLite), `tor_boulder.tres`, `split_boulder.tres`, `boulder_pile.tres`. |
| `game/data/debug/sdf_slice_material.tres` | The slice material. |
| `game/src/lessons/sdf_primitives.gd` | Scene root. Extends `spatial_audio.gd` (Lesson 06); places the rocks; G and H keys; HUD lines. |
| `game/scenes/lessons/07_sdf_primitives.tscn` | The Lesson 06 scene plus a `Rocks` node with two `SdfSlice` children. |
| `game/project.godot` | Input actions `cycle_slice_view` (G, gamepad A) and `step_slice` (H, right stick click); `run/main_scene`. |
| `game/tests/test_07_*.gd` | The shape library; the scene. |
| `docs/decisions/0008-sdf-resource-trees.md` | Why shapes are Resource trees evaluated in GDScript. |

Reading: Inigo Quilez, "distance functions" (the 3D primitives and the operators), "smooth minimum" (sections on the quadratic polynomial), and "ellipsoid SDF". John C. Hart, "Sphere tracing" (1996), sections 1–3, for distance bounds and Lipschitz constants. DDG §4.6.1 (the gradient as the direction of steepest ascent) and §4.6.3 (the directional derivative df(u) = u · ∇f); this lesson uses both to bound how fast f changes along a segment. DDG treats surfaces given by parameterizations and meshes, not by implicit functions; the other readings carry this lesson's geometry. Full entries: `docs/references.md`.

No earlier exercise is needed. The audio of Lessons 04–06 still runs; the rocks make no sound yet.

## 2. Predict

Work these on paper before reading the code. Notation: f(p) is the signed distance from a point p to a surface, negative inside, positive outside. "Exact" means |f(p)| equals the distance from p to the nearest surface point.

- **P1.** Write the SDF of a sphere of radius r centered at c. Evaluate it for r = 2, c = 0, at p = (3, 4, 0) and at p = (0, 0.5, 0). Compute its gradient ∇f. What is ‖∇f‖ wherever the gradient exists, and where does it not exist?
- **P2.** A box with half-extents (1, 1, 1) centered at the origin. Give the distance from (2, 0, 0), from (2, 2, 0), from (2, 2, 2), and from (0, 0.5, 0). Each answer is a distance to a different kind of feature: name the feature. Why can a formula first replace p by (|p.x|, |p.y|, |p.z|)?
- **P3.** Two unit spheres centered at (−0.5, 0, 0) and (0.5, 0, 0). Their union is the set of points inside either. Take f = min(f₁, f₂). At a point outside both, is f the exact distance to the union? At the origin, inside both, what does f report, and what is the true depth? (The surface of the union crosses the y axis at a height you can compute from either sphere.)
- **P4.** An ellipsoid with semi-axes (a, b, c) = (2, 0.5, 1). Let k₀ = ‖(x/a, y/b, z/c)‖. Then k₀ = 1 on the surface. Show that (k₀ − 1) · min(a, b, c) never exceeds the true distance outside. (Hint: the map (x, y, z) → (x/a, y/b, z/c) turns the ellipsoid into the unit sphere; by how much can it lengthen a segment?) Evaluate this estimate at (4, 0, 0) and at (0, 1, 0), and compare with the true distances.
- **P5.** The quadratic smooth minimum with width k: h = max(k − |a − b|, 0) / k, smin(a, b) = min(a, b) − h² k / 4. Show that smin ≤ min, that the two agree when |a − b| ≥ k, and that the largest difference, k/4, occurs at a = b. Show that ∂smin/∂a and ∂smin/∂b lie in [0, 1] and sum to 1. For the two spheres of P3 with k = 0.5, at what height does the smooth union cross the y axis?
- **P6.** A shape is moved by t and scaled by a factor s about the origin. Why is the new SDF s · f((p − t) / s), with the point moved backward and the result multiplied? A unit sphere scaled by (2, 1, 1) along the axes, evaluated as f(p / (2, 1, 1)): what does this give at (3, 0, 0) and at (0, 3, 0), and what are the true distances?
- **P7.** A function is L-Lipschitz if |f(p) − f(q)| ≤ L ‖p − q‖ for all p, q. Using DDG §4.6.3 (df(u) = u · ∇f) and the Cauchy–Schwarz inequality, show that sup ‖∇f‖ along the segment from q to p bounds the slope of f along it. Then show: if f is L-Lipschitz and zero on the surface, f(p) / L never exceeds the distance from p to the surface. A boulder adds noise to an exact SDF: f + a · n(p), with a = 0.12 m and ‖∇n‖ ≤ 6 · ν, where ν = 0.35 per meter is the noise frequency. What Lipschitz bound results?
- **P8.** Domain repetition replaces p.x by p.x − 4 · clamp(round(p.x / 4), −1, 1) before asking a child (and the same for z). The child is a sphere of radius 0.5 at the origin. Evaluate at (4, 0, −4), at (8, 0, 0), and at (2, 0, 0). Now move the child sphere to center (1.5, 0, 0) with radius 1.5. Evaluate just left and just right of x = −2. What has gone wrong?

## 3. Read

### 3.1 `sdf_shape.gd`

Read the header: it lists every file of `src/sdf/` and how they relate. An `SdfShape` is a Resource, as `HeightField` was in Lesson 01: its numbers live in `.tres` files, and changing them changes the world without changing code (decision 0004). Unlike `HeightField`, a shape can hold other shapes. A boulder is a tree: operators at the inner nodes, primitives at the leaves. Decision 0008 records why.

The interface has five functions:

| Function | Answers |
|---|---|
| `evaluate(p)` | the signed distance (or an estimate of it) at p |
| `lipschitz_bound()` | how fast `evaluate()` can change per meter (P7) |
| `bounds()` | a box that contains the solid; Lesson 08 samples inside it and nowhere else |
| `level_bounds(c)` | a box that contains every point with f ≤ c; smooth union and displacement use it |
| `evaluate_bounded(p)` | `evaluate(p) / lipschitz_bound()`: never more than the true distance |
| `gradient(p, h)` | ∇f by central differences |

Read the Q/A comment on the step `h` of `gradient()`. Lesson 01 O4 met the same trade-off for the height field: a step too large gives truncation error, a step too small gives rounding error, and `Vector3` holds 32-bit floats.

`_watch()` and `_watch_all()` connect a child's `changed` signal to the parent's `emit_changed`. Why does a slice drawing the whole pile need that, when the value you edit lives three levels down?

### 3.2 The primitives

`sdf_sphere.gd` is P1. `sdf_box.gd` is P2: read its two Q/A comments. The rounded box subtracts `rounding` at the end. Why does subtracting a constant from an SDF grow the shape by that constant, and why must the sharp box first shrink by the same amount? `sdf_capsule.gd` projects the point onto a segment and clamps the parameter; its Q/A comment says why the clamp.

`sdf_ellipsoid.gd` offers two estimates, selected by `estimate`:

- `SCALED_SPHERE`, the default: (k₀ − 1) · min(radii). This is P4.
- `GRADIENT`: k₀ (k₀ − 1) / k₁ with k₁ = ‖q / radii²‖. Read the Q/A comment: it divides the value of g = k₀ − 1 by the length of its gradient. Near a surface, a function falls to zero in about g / ‖∇g‖ meters. This is a first-order Taylor step, the same idea as one step of Newton's method.

Both estimates are zero on the surface and have the right sign everywhere; `test_07_sdf_shapes.gd` checks this on 40 random surface points of a turned ellipsoid. They differ in what P4 and P7 ask about: whether they can overestimate, and whether they have a Lipschitz bound. Read `lipschitz_bound()` and its Q/A comment: the `GRADIENT` estimate reports `INF`. O4 shows why.

The ellipsoid's rotation is stored in Euler angles (degrees) for the Inspector, and the inverse rotation is cached in the setter. Why the inverse? (Section 3.4.)

### 3.3 Combining shapes

`sdf_union.gd` takes the minimum of its children; read its header (P3). `sdf_intersection.gd` takes the maximum. `sdf_subtraction.gd` takes max(f_base, −f_cutter); its Q/A comment explains the minus sign. Each `lipschitz_bound()` returns the largest bound among the children. Why does min or max of L-Lipschitz functions stay L-Lipschitz? (Consider the two cases: the same child is smallest at p and q, or different children are.)

`sdf_smooth_union.gd` holds `smin()` (P5). Read its two Q/A comments. Then `evaluate()`: the children fold left to right, so three children give smin(smin(d₀, d₁), d₂). Is the fold the same for every order of the children? (T4.) `bounds()` calls `level_bounds(0)`. The smooth minimum lowers f by at most k/4 per fold, so a point where the blend is below zero has some child below folds · k/4; the union asks each child for `level_bounds(folds · k/4)`, the box where that child is below that value. Growing the children's boxes by k/4 would not suffice: a `SCALED_SPHERE` ellipsoid underestimates distance, so its field stays below k/4 up to (k/4) · max(radii)/min(radii) beyond its box. For two ellipsoids with radii (3, 1, 1) and k = 0.8, f = −0.033 at x = 3.5, past 3 + 0.2.

The unit of `blend` is meters. In the boulders, 0.8 m of blend joins ellipsoids whose radii are about 1 m: a broad fillet, as on a weathered stone.

### 3.4 Moving, copying, roughening

`sdf_transform.gd`: read the header. Every domain operator answers "how far is p from the moved shape?" by asking the unmoved shape about the moved-back point (P6). `scale` is uniform; P6 shows what a non-uniform scale does to distances, and E2 asks for an operator that handles it.

`sdf_repeat.gd` folds the point into the nearest cell (P8). Its header states the condition under which the result is exact. T5 breaks it.

`sdf_displace.gd` adds `amplitude · n(p)` to the child's value. The noise is a `FastNoiseLite` Resource; `get_noise_3dv()` returns values in about [−1, 1]. Read the Q/A comment on the Lipschitz bound. The bound needs the largest slope of the noise, S, which the FastNoiseLite documentation does not state. It was measured: 200 000 random points in a cube of side 40 m, central differences with step 10⁻³ m, frequency 1, seed 7:

| Noise (Simplex Smooth) | largest ‖∇n‖ found | largest \|n\| found |
|---|---|---|
| 1 octave, no fractal | 5.28 | 0.992 |
| fBm, 2 octaves | 5.84 | 0.902 |
| fBm, 3 octaves | 6.84 | 0.855 |

The slope scales with the frequency (n(νp) has gradient ν ∇n), so `noise_slope_per_frequency` stores S / ν. The rocks use 2 octaves and store 6.0, above the measured 5.84. A sample maximum is a measurement, not a proof; a larger slope may exist between the samples. With more octaves the slope grows while the range shrinks: why? (Each octave has half the amplitude and twice the frequency of the one before.)

### 3.5 The boulders: Joshua Tree monzogranite

The boulder piles of Joshua Tree are granite (much of it the White Tank monzogranite) that cooled underground and cracked along three sets of joints into rough blocks. Groundwater moving down the joints weathered each block from its faces inward. A corner is attacked from three faces, an edge from two, a face from one; so corners round first, and a block becomes an ellipsoid-like core stone. Erosion later removed the weathered material and left the core stones stacked where they lay, some split along a remaining joint.

The data files follow that history:

- `tor_boulder.tres`: three ellipsoids (one large, one on its shoulder, one low at its side) in an `SdfSmoothUnion` with blend 0.8 m, displaced by `granite_noise.tres` (frequency 0.35 per meter, 2 octaves) with amplitude 0.12 m. The displacement has a wavelength of about 3 m: it bends the large forms. Grain-scale roughness belongs to the normal maps of Lesson 20, not to the shape.
- `split_boulder.tres`: two ellipsoids, smooth union, displaced, then an `SdfSubtraction` whose cutter is a thin rounded box tilted 8°: a cleft along a joint.
- `boulder_pile.tres`: an `SdfUnion` of three `SdfTransform` nodes: the tor boulder, the split boulder turned 40° and scaled 0.85, and a second tor boulder scaled 0.5 and perched on the first. The pile uses a plain union, not a smooth one. Why? (Two stones resting on each other do not grow a fillet.)

Open `boulder_pile.tres` in the Inspector and unfold the tree. The two tor boulders are one file, used twice: editing it changes both.

The HUD shows the pile's Lipschitz bound, 1 + 0.12 · 6.0 · 0.35 = 1.252 ("L").

### 3.6 `sdf_slice.gd` and `sdf_slice.gdshader`

`SdfSlice` places a plane in its own local space, which is the shape's space. Read `plane_basis()`: its Q/A comment derives the three bases from the requirement u × v = n. Check the X case by hand.

`rebuild()` samples three layers: the plane, and one grid spacing to each side along the normal. Why three layers, when the picture shows one? (The gradient has a component across the plane.) Read the Q/A comment on the finite differences at the border. The values go into an `Image` with two 32-bit float channels (`FORMAT_RGF`): R holds f, G holds ‖∇f‖. Read the Q/A comment on duplicating the material.

The shader evaluates nothing; its header says why. It colors: orange inside, blue outside, dark near the surface; a line every `band_meters` (0.25 m) of distance; a white line on the zero set. Read the header's Q/A on the bands: bands at equal spacing, parallel to the surface, are what a true distance looks like. `line_coverage()` uses `fwidth`, as the contour lines of Lesson 03 did.

`_queue_rebuild()` defers the work to the end of the frame. A rebuild at the default resolution takes about 115 ms (O5).

### 3.7 `sdf_primitives.gd` and the scene

The root script places `Rocks` at the terrain height under it, so shape space has its floor on the ground. G cycles the view of both slices; H raises the horizontal cut by 0.5 m, from 0.25 m to 3.25 m, then wraps. The HUD shows f at the player's feet: the root converts the player's position into the Rocks node's space with `to_local()` and calls `evaluate()`. This is the call Lesson 08 makes for every grid point, and the call a later lesson can make for every foot.

## 4. Run and observe

Start the lesson scene. The two slices stand 10 m ahead and to the right of the spawn: one horizontal at 1.25 m above the ground, one vertical.

- **O1.** In the distance view, walk around the slices. Count the band lines between the white zero line and a point you choose. How far apart are the bands outside a single boulder? Where do bands of two boulders meet, what shape does the meeting line have?
- **O2.** Watch "f at feet" in the HUD as you walk toward the pile, and stop where it reads +1.00. Look at the horizontal slice from above: how far is your capsule from the white line? Press **H** several times and watch the horizontal cut climb through the pile. At which heights does the cut pass through the gap between the large tor boulder and the stone perched on it? What is the smallest value of f in the cut at each height?
- **O3.** Press **G** for the gradient view. Gray means ‖∇f‖ = 1, red larger, blue smaller. Where is the field gray, where blue, where red? Find the thin dark lines inside the boulders and between them; what lies on those lines? Compare the HUD's "|grad f|" range with "L".
- **O4.** Close the game. Open `data/rocks/tor_boulder.tres` in the Inspector, unfold `shape` → `shapes`, and set `estimate` of the first ellipsoid to `GRADIENT`. Run the scene and compare both views with O1 and O3. Then set it back. (The editor saves the change into the `.tres`; reverting restores the file.)
- **O5.** Read the HUD line with the sample count and the milliseconds. Set `resolution` of `SliceHorizontal` to 192 and run again. How does the build time scale with the resolution? Press H with each setting and feel the pause.
- **O6.** In the editor, open the lesson scene and select `Rocks/SliceVertical`. In the Inspector, open its `shape` and change the `blend` of the tor boulder's smooth union (`shapes[0]` → `shape` → `shape` → `blend`). Watch the slice redraw. Which signal chain carries the change from the smooth union to the slice?

## 5. Tweak

Make each change in the `.tres` file or the Inspector, run, observe, and revert.

- **T1.** In `tor_boulder.tres`, set the smooth union's `blend` to 0, then to 1.6. What appears at blend 0 where two ellipsoids meet? What happens to the small ellipsoids at 1.6?
- **T2.** Set the tor boulder's `amplitude` from 0.12 to 0.3. Predict the new Lipschitz bound, then read it on the HUD. In the gradient view, does any part of the slice turn red?
- **T3.** Set the frequency of `granite_noise.tres` from 0.35 to 1.5. Predict the new bound. What does the surface look like in the slices: still a boulder, or a sponge? Which physical scale does each frequency describe?
- **T4.** Build three spheres of radius 0.6 at (−0.8, 0, 0), (0.8, 0, 0), (0, 1, 0) in a smooth union with blend 1.0 (in a scratch `.tres`, assigned to `SliceVertical`). Then reverse the order of the children. Does the slice change? Where is the difference largest?
- **T5.** Make an `SdfRepeat` with period (4, 0, 4), count (2, 0, 2), and a child sphere of radius 1.5 at center (1.5, 0, 0). Draw it with `SliceHorizontal` at origin height 0. What do you see at x = −2, 2, 6? Explain with P8.
- **T6.** `SdfIntersection.bounds()` returns the merged box of its children. Replace it with the intersection of the children's boxes (`AABB.intersection()`). Why is the result still a valid bound? Which test would show that a bound is too small?

## 6. Exercises

- **E1 ★ More primitives.** Write `SdfTorus` (major radius R, minor radius r, in the xz plane) and `SdfCylinder` (capped, radius and half-height). Derive each formula on paper first. Add tests at chosen points with known distances, and a sampled check that ‖∇f‖ ≤ 1.
- **E2 ★ Non-uniform scale.** Write `SdfScale` with a `Vector3` factor. From P6, find the factor by which f(p / s) must be multiplied so that the result never overestimates the distance. What is its Lipschitz bound? Measure with the gradient view how far from 1 ‖∇f‖ falls for s = (2, 1, 1).
- **E3 ★★ Domain warping.** Write `SdfWarp`, which asks the child at p + a · w(p), where w is a vector of three noise values (three seeds or three offsets of one noise). Derive its Lipschitz bound from the chain rule: the Jacobian of p → p + a · w(p) has norm at most 1 + a · S · ν. Use a warp to bend the split boulder's cleft. Compare the look with displacement at the same amplitude: which one makes overhangs?
- **E4 ★★ A formation of your own.** Find a photograph of a Joshua Tree formation (Skull Rock, Arch Rock, a split boulder, a stack). Sketch it in Procreate from two directions, mark the ellipsoids and cuts on the sketch, and build it as a `.tres` tree in `data/rocks/`. Draw it with an `SdfSlice` in a scene of your own. Keep the sketch in your notes folder.
- **E5 ★★ The true ellipsoid distance.** The nearest point on an ellipsoid satisfies q − s = λ ∇g(s) for the surface point s. Reduce it to one equation in λ and solve it by Newton's method or bisection (Eberly's method). Measure the ratio estimate / true for both estimates over a shell of points, for radii (1.7, 1.05, 1.35) and (2, 0.5, 1), and compare with the figures in the O4 answer.
- **E6 ★★★ Order-free smooth union.** The fold of `SdfSmoothUnion` depends on the order of its children (T4). Design an n-ary smooth minimum that does not: for example, an exponential smooth minimum −k ln Σ exp(−dᵢ / k), or a symmetric pairwise scheme. Derive its largest difference from min, its Lipschitz bound, and its behavior far from all children. Measure the cost per evaluation against the fold.
- **E7 ★ Smooth subtraction and intersection.** Write `SdfSmoothSubtraction` and `SdfSmoothIntersection` from `smin()` and the identities max(a, b) = −min(−a, −b). Round the edges of the split boulder's cleft with it.

## 7. Reflect

- **R1.** Lesson 08 builds a mesh from the zero set by sampling f on a grid. Which properties of f does a mesher need: exact distances, a sign, values near zero, a bound? What does it need from `bounds()`? The `GRADIENT` ellipsoid has no Lipschitz bound; would it still mesh?
- **R2.** The height field of Lesson 01 answers "how high is the ground at (x, z)". The SDF answers "how far is the rock from p". The capsule's collision in Godot uses neither: it uses triangles. Where in a walking game would a distance query be cheaper or better than triangles? (Consider foot placement, Lesson 13, and the camera's spring arm.)
- **R3.** Lesson 09 takes the normal of an implicit surface as n = ∇f / ‖∇f‖. Why does a field with ‖∇f‖ = 1 near the surface make that division harmless, and what happens on the dark ridge lines of O3?
- **R4.** Lesson 10 evaluates SDFs on the GPU. The shapes will then exist twice, in GDScript and in shader code. Decision 0008 keeps the GDScript version as the reference. How would you test that the two agree?
- **R5.** Lesson 06 R5 asked how distance to rock could shape sound without ray tracing. The HUD now shows f at the feet. Which audio parameters could f drive (early reflections, a low-frequency boost near a wall, footstep reverb), and how often would it have to be sent?

## 8. Answers

<details><summary>P1</summary>

f(p) = ‖p − c‖ − r. At (3, 4, 0): 5 − 2 = 3. At (0, 0.5, 0): 0.5 − 2 = −1.5. ∇f = (p − c) / ‖p − c‖, a unit vector pointing away from the center: ‖∇f‖ = 1 everywhere except at the center, where the direction is undefined and f has a cone point. `test_07_sdf_shapes.gd` checks ‖∇f‖ = 1 within 10⁻³ at 50 random points with `gradient()`.
</details>

<details><summary>P2</summary>

(2, 0, 0): 1, to the face x = 1. (2, 2, 0): √2 = 1.414, to the edge x = y = 1. (2, 2, 2): √3 = 1.732, to the corner (1, 1, 1). (0, 0.5, 0): −0.5, to the nearest face y = 1 from inside. The box is symmetric under each reflection x → −x, y → −y, z → −z, and so is its distance function; folding into the positive octant changes neither. `test_07_sdf_shapes.gd` checks all four, and the rounded corner (rounding 0.25): √3 · 1.25 − 0.25 = 1.915.
</details>

<details><summary>P3</summary>

Outside both, yes: the nearest point of the union's surface is the nearest point of one sphere's surface (the other sphere's surface inside the first is not part of the union's surface, but it is also farther than the point that is). At the origin, min(−0.5, −0.5) = −0.5. The union's surface meets the y axis where 0.25 + y² = 1: y = √0.75 = 0.866. The nearest surface point is there, so the true depth is −0.866. The union underestimates depth inside an overlap. Measured with `SdfUnion` at the origin: −0.5.
</details>

<details><summary>P4</summary>

Write D = diag(1/a, 1/b, 1/c). Then ‖D v‖ ≤ ‖v‖ / min(a, b, c) for every v. Let s be the nearest surface point to an outside point p; D s lies on the unit sphere, so the distance from D p to the unit sphere, k₀ − 1, is at most ‖D p − D s‖ ≤ ‖p − s‖ / min(a, b, c). Multiply by min(a, b, c). At (4, 0, 0): k₀ = 2, estimate 0.5, true distance 2. At (0, 1, 0): k₀ = 2, estimate 0.5, true distance 0.5. The estimate is exact along the shortest axis and poor along the longest. The `GRADIENT` estimate gives 2 · 1 / 1 = 2 and 2 · 1 / 4 = 0.5: exact on both axes.
</details>

<details><summary>P5</summary>

h ∈ [0, 1] and k > 0, so the subtracted term is ≥ 0: smin ≤ min. For |a − b| ≥ k, h = 0 and smin = min. h is largest (1) at a = b, giving min − k/4. Take a < b and 0 < b − a < k: smin = a − (k − b + a)² / (4k). ∂/∂a = 1 − (k − b + a) / (2k) = 1 − h/2, and ∂/∂b = h/2; both lie in [0, 1] and sum to 1. The gradient of smin(f₁, f₂) is then (1 − h/2) ∇f₁ + (h/2) ∇f₂, a convex combination: its length is at most the larger of ‖∇f₁‖, ‖∇f₂‖. On the y axis both spheres give √(0.25 + y²) − 1, and smin subtracts 0.125: the surface is where √(0.25 + y²) = 1.125, y = √1.0156 = 1.0078, against 0.866 for the plain union. `test_07_sdf_shapes.gd` checks this height.
</details>

<details><summary>P6</summary>

A point p lies in the moved shape when (p − t) / s lies in the original, and not otherwise, so the inside test must use the moved-back point. Distances in the original's space are 1/s of distances in the world, so the value is multiplied by s. With (2, 1, 1): at (3, 0, 0), ‖(1.5, 0, 0)‖ − 1 = 0.5; the stretched sphere reaches x = 2, so the true distance is 1. At (0, 3, 0), ‖(0, 3, 0)‖ − 1 = 2, true distance 2. A non-uniform scale makes ‖∇f‖ differ from 1: here f underestimates along the stretched axis by a factor 2. A factor s < 1 on an axis would make f overestimate. E2.
</details>

<details><summary>P7</summary>

Parameterize the segment γ(t) = q + t (p − q), t ∈ [0, 1]. Then d/dt f(γ(t)) = df(p − q) = (p − q) · ∇f (DDG §4.6.3), and |(p − q) · ∇f| ≤ ‖p − q‖ ‖∇f‖ (Cauchy–Schwarz). Integrating over t: |f(p) − f(q)| ≤ sup ‖∇f‖ · ‖p − q‖. For the second part, let s be the nearest surface point; f(s) = 0, so |f(p)| = |f(p) − f(s)| ≤ L ‖p − s‖, and |f(p)| / L ≤ distance. For the boulder: the noise term changes by at most a · S · ν = 0.12 · 6 · 0.35 = 0.252 per meter, so L = 1 + 0.252 = 1.252, the HUD's value. Sampling 100 000 points around the pile found ‖∇f‖ up to 1.157 outside and 1.090 inside: below the bound, above 1.
</details>

<details><summary>P8</summary>

(4, 0, −4) folds into cell (1, −1) at local (0, 0, 0): −0.5. (8, 0, 0): the cell index round(2) = 2 is clamped to 1, the local point is (4, 0, 0): 3.5, the distance to the last copy. (2, 0, 0): round(0.5) = 1 in Godot (halves round away from zero), local (−2, 0, 0): 1.5, the same as from the copy at the origin. With the child at (1.5, 0, 0), radius 1.5: at x = −1.999 the point belongs to cell 0, whose copy is centered at 1.5: f = 3.499 − 1.5 = 1.999. At x = −2.001 it belongs to cell −1, whose copy at −2.5 contains it: f = −1.001. The field jumps by 3 m across the cell boundary. The copy of cell −1 reaches into cell 0, but points of cell 0 never ask it. Measured with `SdfRepeat`: 1.999 and −1.001.
</details>

<details><summary>O1</summary>

Outside a single boulder the bands are 0.25 m apart and parallel to the white line, as for a distance field with ‖∇f‖ near 1. Between two boulders the bands of each meet along a crease: the set of points equidistant from both, where min switches from one child to the other. In the plane cut it is a curve; in space a surface (part of the medial axis of the outside).
</details>

<details><summary>O2</summary>

The nearest rock surface need not lie in the horizontal cut: it may lie above or below the plane. With L = 1.252, f / L = 0.80, so the true distance is at least 0.80 m (P7). The `SCALED_SPHERE` ellipsoids underestimate, so the true distance can also exceed 1 m. The smallest f in each cut, measured headless:

| Cut height (m) | 0.25 | 0.75 | 1.25 | 1.75 | 2.25 | 2.75 | 3.25 |
|---|---|---|---|---|---|---|---|
| smallest f (m) | −0.41 | −0.82 | −0.81 | −0.73 | −0.25 | −0.44 | −0.34 |

At 2.25 m the cut passes near the top of the large tor boulder and below most of the perched stone: the smallest value is −0.25. The cut at 0.25 m catches the lower ellipsoids' bottoms, which the terrain buries in part. At the spawn, after landing, f at the feet read +6.44.
</details>

<details><summary>O3</summary>

Outside, near the surface, the field is near gray: the ellipsoids' `SCALED_SPHERE` estimate has ‖∇f‖ ≤ 1 and the displacement adds or subtracts up to 0.252. Away from the surface along the long axes the field turns blue: the estimate grows slower than distance (P4). Inside the boulders it is blue as well. The thin dark lines are ridges of the field, the medial axis: points with two nearest surface points (inside the boulders) or two nearest children (between them). There the finite differences straddle a crease, the two slopes cancel, and the measured ‖∇f‖ falls toward 0: the HUD's lower figure, 0.03 at the default cut. The upper figure was 1.00 at the default cut and at most 1.13 over all seven heights (2.75 m), below L = 1.25. The vertical cut measured 0.0008 to 1.063.
</details>

<details><summary>O4</summary>

With `GRADIENT`, the bands outside the first ellipsoid stay 0.25 m apart farther from the surface: the estimate is closer to the true distance. Inside, the gradient view turns red near the ellipsoid's center (0, 1, 0): the largest ‖∇f‖ in the horizontal cut rose from 1.00 to 1.66 at 1.25 m and to 1.60 at 0.75 m, both within 0.5 m of the center (measured headless). For the isolated ellipsoid, along x, 1 mm from the center, f = −1.699; along y, f = −1.049. The value jumps by the difference of the radii across a distance as small as one likes, so no Lipschitz bound exists. Measured over 300 points between 0.2 and 4 m from the center, ratio estimate / true distance:

| Radii | Estimate | Outside | Inside | Largest ‖∇f‖ sampled |
|---|---|---|---|---|
| 1.7, 1.05, 1.35 | `SCALED_SPHERE` | 0.627 – 0.997 | 0.641 – 1.000 | 1.000 |
| 1.7, 1.05, 1.35 | `GRADIENT` | 0.934 – 1.000 | 1.000 – 1.370 | 1.90 (4.27 near the center) |
| 2, 0.5, 1 | `SCALED_SPHERE` | 0.288 – 1.000 | 0.460 – 0.992 | 1.000 |
| 2, 0.5, 1 | `GRADIENT` | 0.638 – 1.000 | 1.004 – 1.901 | 10.1 |

`GRADIENT` never overestimated outside, but it overestimated depth inside by up to 90 %, and even outside its gradient reached 3.4 for the flat ellipsoid (near the long axis, beyond the tip): it underestimates distance without being 1-Lipschitz. A bound on the value and a bound on the slope are different properties. With all three ellipsoids of the tor boulder set to `GRADIENT`, sampled ‖∇f‖ inside it reached 17.4. The rock files keep `SCALED_SPHERE`.
</details>

<details><summary>O5</summary>

Resolution 96 gives a grid of 96 × 67 for the 10 × 7 m cut: 6432 texels, three evaluations each, 19 296 samples, about 114 ms (seven heights measured headless: 113–140 ms, the first build slowest). Resolution 192 took 455 ms: four times the texels, four times the time. One evaluation of the pile costs about 5.4 µs in GDScript. The vertical cut (96 × 48) has 13 824 samples and took 81 ms.
</details>

<details><summary>O6</summary>

The ellipsoid's or the union's setter calls `emit_changed()`. The parent operators connected their children's `changed` to their own `emit_changed` in `_watch()`, so the signal climbs: smooth union → `SdfDisplace` → `SdfTransform` → `SdfUnion` (the pile). `SdfSlice` connected the pile's `changed` to `_queue_rebuild()`, which runs `rebuild()` once at the end of the frame.
</details>

<details><summary>T1</summary>

At blend 0 the smooth union is a plain union: a crease (a sharp inward edge) runs where two ellipsoids meet, and the bands show a corner. At 1.6 the fillets widen past the small ellipsoids' size and swallow them into one rounded mass; the boulder also grows, since the field is lowered by up to k/4 = 0.4 m where children have equal values.
</details>

<details><summary>T2</summary>

L = 1 + 0.3 · 6 · 0.35 = 1.63, as the HUD shows. Sampling 20 000 points around the tor boulder found ‖∇f‖ up to 1.39 (against 1.13 at 0.12). In the gradient view, spots turn red where the noise slope adds to the field's slope.
</details>

<details><summary>T3</summary>

L = 1 + 0.12 · 6 · 1.5 = 2.08. The surface ripples at a wavelength under 1 m: the shape reads as a sponge or a cauliflower, not a weathered stone. At 0.35 per meter the noise bends the forms over about 3 m, the scale of a boulder's lumps; grain and pits belong to surface detail (normal maps, Lesson 20), not to the distance field the mesh and the collision use.
</details>

<details><summary>T4</summary>

Yes. Measured on a 81 × 81 grid in the z = 0 plane: the largest difference between the orders [left, right, top] and [top, left, right] was 0.034 m, at (−0.05, 0.64, 0), the region where all three spheres have similar distances and the two folds blend different pairs first.
</details>

<details><summary>T5</summary>

Copy n is centered at x = 4n + 1.5 and spans [4n, 4n + 3]; cell n spans [4n − 2, 4n + 2]. The part [4n + 2, 4n + 3] of each copy lies in the next cell, whose points ask their own copy and no other. The slice shows each circle cut by a straight line at x = −2, 2, 6, and the field jumps there by 3 m (P8: 1.999 and −1.001 at x = −2). The rightmost copy (n = 2) is not cut: beyond x = 10 the clamped index still names copy 2.
</details>

<details><summary>T6</summary>

The solid of an intersection lies inside every child's solid, so inside every child's box, so inside their intersection. A box that is too small would leave solid points outside it; `test_07_sdf_shapes.gd` samples points with f ≤ 0 and checks `bounds().has_point()`, which would catch it.
</details>
