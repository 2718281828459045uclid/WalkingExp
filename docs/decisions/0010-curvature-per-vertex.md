# 0010. Field normals and curvature computed per mesh vertex on the CPU

Status: accepted, 2026-11-22 (Lesson 09).

## Context

Lesson 09 colors the boulder mesh by its curvature and offers normals from the field gradient instead of the trilinear interpolant of Lesson 08. Curvature needs second derivatives of f. The shapes are evaluated in GDScript only (decision 0009); the fragment shader has no access to f. The Lesson 08 text describes `SdfMesher` and must stay true.

## Decision

1. **Second derivatives by central differences** of `SdfShape.evaluate()` (`ImplicitCurvature.hessian()`), with a default step of 0.01 m. No shape implements an analytic Hessian; `SdfTorus.analytic_gradient()` exists only as a test reference.
2. **Mean curvature with the sign of DDG 3.4**: H = ½ div(∇f/|∇f|), positive on a sphere with f negative inside. Gaussian curvature by Goldman (2005), Eq. (4.1).
3. **Per vertex, on the CPU, after meshing**, in a subclass `CurvatureMesher` of `SdfMesher`. The values travel to the GPU in the mesh's `CUSTOM0` channel as four 32-bit floats (H, K, k1, k2). The shader reads them; it does not compute curvature.
4. **A second `ArrayMesh`** replaces the one `SdfMesher` built, because a surface's vertex format is fixed at creation. Collision is not touched.

## Consequences

- One rebuild of the boulder pile at 0.15 m costs about 620 ms more (4225 vertices × 26 evaluations).
- Curvature resolution is the mesh resolution. Features smaller than a cell are not colored.
- The normal source can be switched without resampling (`normal_source`).
- At creases of unions the numbers are unbounded; consumers must clamp or reject them.
- Lesson 10 (raymarching) evaluates f in a shader; there, normals and curvature can be computed per pixel, and the CPU path here becomes the reference to compare against.
