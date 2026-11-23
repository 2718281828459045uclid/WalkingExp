// rock_weathering.gdshader
//
// Lesson 09. Colors the boulder mesh by its curvature.
//
// How this file relates to the others:
//   src/sdf/curvature_mesher.gd   computes, per vertex, the mean curvature H,
//                                 the Gaussian curvature K and the principal
//                                 curvatures k1 >= k2, and stores them in the
//                                 mesh's CUSTOM0 channel as (H, K, k1, k2)
//   data/rocks/weathered_rock_material.tres
//                                 the ShaderMaterial; holds the uniform values
//   src/lessons/implicit_curvature.gd
//                                 sets curvature_view at runtime (U key)
//
// ---------------------------------------------------------------------------
// The idea: weathering follows curvature
// ---------------------------------------------------------------------------
// Q: Why should curvature decide the color of a rock?
// A: Wind, rain and frost act on what sticks out. A convex edge (H > 0,
//    the surface bends away from the normal on all sides) is exposed from
//    many directions: it wears down and loses its dark coating, so it shows
//    pale, fresh stone. A concave pocket (H < 0) is sheltered: dust, water
//    and lichen collect there, so it is darker and tinted. Surfaces in
//    between keep the base color. This is the same rule game artists use as
//    a "curvature map" for edge wear and cavity dirt, computed here from the
//    field instead of baked by a texturing tool.
//
// Q: Why mean curvature and not Gaussian curvature?
// A: K = k1 k2 is the "and" of DDG 3.4: both directions bent. A cylinder
//    edge has K = 0 but is exposed all the same. H = (k1 + k2) / 2 is the
//    "or": it is large on a ridge (k1 large, k2 = 0) and on a knob. K is
//    shown as its own view (curvature_view = 2) to compare.
//
// Q: Why do the curvature values travel per vertex and not per pixel?
// A: The fragment shader does not know f; it only sees the mesh. The
//    mesher computed H at each vertex, and the rasterizer interpolates the
//    four numbers across each triangle, as it does with normals.
// ---------------------------------------------------------------------------

shader_type spatial;

// 0 = weathered rock, 1 = mean curvature map, 2 = Gaussian curvature map,
// 3 = the mesh normal as a color.
uniform int curvature_view : hint_range(0, 3) = 0;

uniform vec3 base_color : source_color = vec3(0.64, 0.56, 0.47);
uniform vec3 worn_color : source_color = vec3(0.86, 0.80, 0.70);
uniform vec3 cavity_color : source_color = vec3(0.30, 0.27, 0.20);
uniform vec3 dust_color : source_color = vec3(0.74, 0.62, 0.46);

// Q: Why do the thresholds have units?
// A: Curvature is 1 / radius, so it is measured in 1/m. An edge "counts as
//    worn" when its mean curvature exceeds wear_start (rounded to a radius
//    of 1 / wear_start meters or less). The boulders have a median H of
//    0.67 1/m (README O3); the defaults leave that in the plain band.
uniform float wear_start = 0.9;   // 1/m: H where wear begins
uniform float wear_full = 2.0;    // 1/m: H where wear is complete
uniform float cavity_start = 0.2;  // 1/m: H where shelter begins
uniform float cavity_full = -1.0; // 1/m: H where shelter is complete
// Up-facing surfaces collect dust: blend by normal.y above this value.
uniform float dust_facing = 0.75;
uniform float dust_amount = 0.35;
// Scale of the false-color maps: |value| at which the color saturates.
uniform float map_scale = 2.0;

varying vec4 curvature;
varying vec3 world_normal;

void vertex() {
	// CUSTOM0 holds (H, K, k1, k2) exactly as the mesher wrote them.
	curvature = CUSTOM0;
	// Q: Why convert the normal to world space here?
	// A: NORMAL in vertex() is in model space. "Up-facing" means world +y,
	//    and the Rocks node could be rotated in a later lesson.
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Blue for negative, white for zero, red for positive: a diverging map.
// The scale s is the value that reaches full color.
vec3 diverging(float value, float s) {
	float t = clamp(value / s, -1.0, 1.0);
	vec3 white = vec3(0.9);
	return t < 0.0 ? mix(white, vec3(0.1, 0.25, 0.85), -t)
	               : mix(white, vec3(0.85, 0.15, 0.1), t);
}

void fragment() {
	float h_mean = curvature.x;
	float k_gauss = curvature.y;
	vec3 color = base_color;

	if (curvature_view == 0) {
		// Q: How do the three rules combine?
		// A: Each rule yields a weight in [0, 1] from smoothstep. Wear and
		//    cavity cannot both be nonzero (H cannot be above 0.9 and below
		//    0.2), so they are applied one after the other with mix().
		//    Dust comes last and is reduced on worn edges (wind clears them).
		float wear = smoothstep(wear_start, wear_full, h_mean);
		float shelter = smoothstep(-cavity_start, -cavity_full, -h_mean);
		float up = smoothstep(dust_facing, 1.0, world_normal.y);
		color = mix(color, worn_color, wear);
		color = mix(color, cavity_color, shelter);
		color = mix(color, dust_color, up * dust_amount * (1.0 - wear));
	} else if (curvature_view == 1) {
		color = diverging(h_mean, map_scale);
	} else if (curvature_view == 2) {
		// Q: Why map sqrt(|K|) instead of K?
		// A: K has units 1/m^2. Its square root, with the sign kept, has
		//    units 1/m like H, so one map_scale serves both views.
		color = diverging(sign(k_gauss) * sqrt(abs(k_gauss)), map_scale);
	} else {
		color = world_normal * 0.5 + 0.5;
	}

	ALBEDO = color;
	ROUGHNESS = 0.92;
}
