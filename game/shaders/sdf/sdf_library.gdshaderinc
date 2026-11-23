// sdf_library.gdshaderinc
//
// Lesson 10. The GLSL mirror of the SDF library of Lessons 07 and 09.
//
// How this file relates to the others:
//   src/sdf/*.gd                 the reference library: one GDScript Resource
//                                per primitive or operator, evaluated on the
//                                CPU (Lessons 07-09)
//   src/sdf/sdf_glsl.gd          SdfGlsl: walks a resource tree and writes a
//                                function sdf_map(p) that calls the functions
//                                below, one call per node of the tree
//   shaders/sdf/raymarch.gdshader
//                                the raymarching template; it includes this
//                                file, and RaymarchVolume replaces its stub
//                                sdf_map() with the generated one
//
// ---------------------------------------------------------------------------
// Two copies of one library, and how they stay in sync
// ---------------------------------------------------------------------------
// Q: Why a second copy of the library at all?
// A: GDScript runs on the CPU, once per call. A fragment shader runs on the
//    GPU, once per pixel, thousands of pixels in parallel. The GPU cannot
//    call GDScript, so every formula the shader needs has to exist in GLSL.
//
// Q: Which half is written by hand and which half is generated?
// A: The formulas (this file) are written by hand, one function per GDScript
//    class, with the same argument names and the same order of operations.
//    The composition (which primitives, which operators, which numbers) is
//    never written by hand: SdfGlsl reads it from the same .tres file that
//    the CPU code evaluates. A rock edited in the inspector therefore changes
//    in both places at once; only a change to a formula has to be made twice.
//
// Q: How is a hand-written mirror checked?
// A: Three ways, from cheap to thorough (README section 3.1):
//    1. Every function below names the GDScript method it mirrors. Read
//       them side by side.
//    2. tests/test_10_sdf_glsl.gd compiles the generated code (a headless
//       run reports shader compile errors) and checks that every node type
//       of the library is translated.
//    3. The windowed silhouette comparison (README O2): the raymarched pile
//       and the Lesson 08 mesh of the same pile are drawn in one place.
//
// Q: Why are there no INF values?
// A: GLSL has no portable infinity literal. 1e30 plays its role: any real
//    distance is smaller, and min(1e30, d) = d.
// ---------------------------------------------------------------------------

const float SDF_FAR = 1e30;

// SdfSphere.evaluate(): distance to the center minus the radius. Exact.
float sdf_sphere(vec3 p, vec3 center, float radius) {
	return length(p - center) - radius;
}

// SdfBox.evaluate(). q measures how far p lies beyond each face of the inner
// (unrounded) box; the outside part is the length of the positive
// components, the inside part the largest negative one. Exact.
float sdf_box(vec3 p, vec3 center, vec3 half_extents, float rounding) {
	vec3 q = abs(p - center) - (half_extents - vec3(rounding));
	float outside = length(max(q, vec3(0.0)));
	float inside = min(max(q.x, max(q.y, q.z)), 0.0);
	return outside + inside - rounding;
}

// SdfCapsule.evaluate(): distance to the segment ab minus the radius. The
// clamped parameter t picks the nearest point of the segment. Exact.
float sdf_capsule(vec3 p, vec3 a, vec3 b, float radius) {
	vec3 ap = p - a;
	vec3 ab = b - a;
	float t = clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0);
	return length(ap - ab * t) - radius;
}

// SdfEllipsoid.evaluate() with estimate = SCALED_SPHERE (Lipschitz bound 1).
// to_local is the inverse rotation, the same matrix as SdfEllipsoid._to_local.
float sdf_ellipsoid_scaled(vec3 p, vec3 center, vec3 radii, mat3 to_local) {
	vec3 q = to_local * (p - center);
	float k0 = length(q / radii);
	return (k0 - 1.0) * min(radii.x, min(radii.y, radii.z));
}

// SdfEllipsoid.evaluate() with estimate = GRADIENT (no finite Lipschitz
// bound; Lesson 07 O4).
float sdf_ellipsoid_gradient(vec3 p, vec3 center, vec3 radii, mat3 to_local) {
	vec3 q = to_local * (p - center);
	float k0 = length(q / radii);
	float k1 = length(q / (radii * radii));
	if (k1 < 1e-9) {
		return -min(radii.x, min(radii.y, radii.z));
	}
	return k0 * (k0 - 1.0) / k1;
}

// SdfTorus.evaluate() (Lesson 09): axis y, reduced to the distance from a
// point in the (rho, y) half-plane to a disk of radius minor_radius.
float sdf_torus(vec3 p, vec3 center, float major_radius, float minor_radius) {
	vec3 q = p - center;
	float rho = length(q.xz);
	return length(vec2(rho - major_radius, q.y)) - minor_radius;
}

// SdfSmoothUnion.smin(): quadratic polynomial smooth minimum.
float sdf_smin(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

// SdfDisplace: the noise term. FastNoiseLite does not exist in GLSL, so
// SdfGlsl samples the noise on a grid (cell meters apart) and stores it in a
// 3D texture; this function reads that texture with trilinear filtering.
//
// Q: Which texture coordinate belongs to point p?
// A: Texel i holds the noise at origin + i * cell. Its center lies at the
//    texture coordinate (i + 0.5) / dims. Solving for i gives the line below.
//    Outside the grid the sampler clamps to the edge texel.
//
// Q: Is the trilinear interpolant as smooth as the noise?
// A: Its values are continuous, its gradient is not: inside each cell it is
//    a different polynomial, and the slopes jump at the cell faces. A
//    normal measured with a step much smaller than the cell sees those
//    jumps as a grid of ridges on the rock (README O3). The raymarch
//    template therefore measures normals with a step of about half a cell.
float sdf_noise(sampler3D noise, vec3 p, vec3 origin, float cell, vec3 dims) {
	vec3 uvw = ((p - origin) / cell + 0.5) / dims;
	return texture(noise, uvw).r;
}
