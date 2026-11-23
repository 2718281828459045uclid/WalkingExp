# 0008. Signed distance fields as trees of Resources, evaluated in GDScript

Status: accepted, 2026-11-22 (Lesson 07).

## Context

Phase 3 builds rock from signed distance functions (SDFs). Lesson 07 defines shapes and their combinations; Lesson 08 turns the zero set into meshes with collision; Lesson 09 needs gradients and Hessians; Lesson 10 evaluates SDFs on the GPU. Decision 0004 requires parameters in `.tres` files and no asset paths in code. Open questions: how a composed shape is stored, which language evaluates it, what interface later lessons call, and how a shape is inspected before a mesh exists.

## Decision

1. **A shape is a tree of Resources.** `SdfShape` (`game/src/sdf/sdf_shape.gd`) is the base class. Primitives (`SdfSphere`, `SdfBox`, `SdfEllipsoid`, `SdfCapsule`) are leaves; operators (`SdfUnion`, `SdfSmoothUnion`, `SdfIntersection`, `SdfSubtraction`, `SdfTransform`, `SdfRepeat`, `SdfDisplace`) hold child shapes in exported properties. A boulder is one `.tres` file in `game/data/rocks/`; child shapes are sub-resources or other `.tres` files.
2. **Interface.** `evaluate(p: Vector3) -> float` (negative inside), `lipschitz_bound() -> float`, `bounds() -> AABB`, `level_bounds(level) -> AABB` (a box containing every p with f(p) ≤ level; default `bounds().grow(level)`, valid for exact distances; `SdfEllipsoid` grows by level · max(radii)/min(radii) because its estimates underestimate distance; smooth union and displacement query their children at a raised level instead of growing the children's `bounds()`), `evaluate_bounded(p)` = `evaluate(p) / lipschitz_bound()`, `gradient(p, h)` by central differences. Points are given in shape space; the node that draws or meshes a shape places shape space in the world.
3. **Evaluation in GDScript on the CPU** for Lessons 07–09. Lesson 10 adds a GPU evaluator; the GDScript evaluator stays as the reference against which the GPU results are tested.
4. **Lipschitz bounds are tracked per node.** Exact primitives report 1; operators report the bound their formula guarantees (the largest child bound for min, max, smooth minimum, and rigid or uniform-scale transforms; child bound plus amplitude times noise slope for displacement). An estimate without a finite bound reports `INF` (the `GRADIENT` estimate of `SdfEllipsoid`).
5. **Inspection by slices.** `SdfSlice` (`game/src/sdf/sdf_slice.gd`, `@tool`) samples a shape on a grid in one plane, stores f and |∇f| in a two-channel float texture, and colors it with `shaders/sdf_slice.gdshader`. The shader evaluates nothing.
6. **Noise for displacement is a `FastNoiseLite` Resource** (`data/rocks/granite_noise.tres`). Its largest gradient per unit frequency is not documented; it was measured (Lesson 07, section 3.4) and stored in `SdfDisplace.noise_slope_per_frequency`.

## Consequences

- An evaluation of the three-boulder pile takes about 5.4 µs (measured, Lesson 07); a 96-column slice (19296 evaluations) takes about 115 ms. A mesh of a boulder on a fine grid in GDScript will take seconds; Lesson 08 measures it and decides about compute shaders.
- Shapes are edited in the Inspector, and an `SdfSlice` in the editor redraws on every change (`changed` propagates from child to parent through `SdfShape._watch()`).
- A shape exists twice once Lesson 10 adds GPU code; the tests of that lesson compare the two.
- The smooth union folds left to right; its result depends on the order of three or more children (Lesson 07, T4).
- `SdfIntersection` and `SdfSubtraction` use the inside of a child (a cutter's inside becomes outside); their bounds hold only when every child's bound holds inside as well as outside.
