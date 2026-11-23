// raymarch.gdshader
//
// Lesson 10. Draws a signed distance field by sphere tracing, without a mesh.
//
// How this file relates to the others:
//   shaders/sdf/sdf_library.gdshaderinc
//                                 GLSL mirror of the SDF primitives and
//                                 operators (included below)
//   src/sdf/sdf_glsl.gd           SdfGlsl writes sdf_map() for one resource
//                                 tree (for example boulder_pile.tres)
//   src/sdf/raymarch_volume.gd    RaymarchVolume copies this file's code,
//                                 replaces the stub between SDF_MAP_BEGIN and
//                                 SDF_MAP_END with the generated sdf_map(),
//                                 and draws a box (the proxy) with it
//   src/lessons/raymarching.gd    sets debug_view (P key) and max_steps (X key)
//
// This file compiles on its own (the stub is a unit sphere), so the editor
// can show it; it is never used without the replacement.
//
// ---------------------------------------------------------------------------
// The idea: a box that pretends to hold a rock
// ---------------------------------------------------------------------------
// Q: A fragment shader colors the pixels of a triangle. How can it draw a
//    surface that has no triangles?
// A: Draw a box (the proxy) around where the rock would be. Every pixel
//    the box covers runs this fragment shader once. The shader shoots the
//    ray from the camera through that pixel, walks along it until it meets
//    the zero set of f, and colors the pixel as that surface point. Pixels
//    whose ray misses the rock are discarded: the box itself is never seen.
//
// Q: How does it walk along the ray without overshooting the surface?
// A: Sphere tracing (Hart 1996). At the point p = ro + t rd the value f(p)
//    is the distance to the nearest surface point (or a lower bound of it).
//    So a ball of radius f(p) around p holds no surface, and the march may
//    advance by f(p) safely. Near the surface f(p) shrinks and the steps
//    shrink with it; the march stops when f(p) falls below a tolerance.
//
// Q: What if f is not a true distance?
// A: If |f(a) - f(b)| <= L |a - b| (Lipschitz bound L), then f(p) / L is a
//    safe step. Displacement noise raises L above 1 (Lesson 07); the CPU
//    library reports L through lipschitz_bound(), and RaymarchVolume passes
//    step_scale = 1 / L to this shader.
//
// Q: Why must the shader write DEPTH?
// A: The depth buffer decides which surface is in front, pixel by pixel.
//    Without DEPTH the GPU would store the depth of the proxy box face, and
//    the terrain, the player and the meshed rocks would be sorted against
//    the box, not against the rock. Writing the depth of the hit point lets
//    raymarched and rasterized geometry cut through each other correctly.
// ---------------------------------------------------------------------------

shader_type spatial;

// Q: Why cull_front?
// A: Only the back faces of the box are drawn. When the camera is outside,
//    every pixel of the box has a back face behind its front face, so the
//    coverage is the same. When the camera is inside the box (walking into a
//    large formation), the front faces lie behind the camera and would be
//    clipped; the back faces are still there.
render_mode cull_front;

#include "res://shaders/sdf/sdf_library.gdshaderinc"

// 0 = lit and weathered, 1 = step count, 2 = normal as color,
// 3 = mean curvature map (blue negative, white zero, red positive).
uniform int debug_view : hint_range(0, 3) = 0;
// The largest number of sphere-tracing steps per pixel.
uniform int max_steps : hint_range(1, 512) = 96;
// The hit tolerance, in pixels: the march stops when f(p) is smaller than
// the width of this many pixels at the distance of p.
uniform float epsilon_pixels = 0.5;
// 1 / L, the Lipschitz bound of the field (RaymarchVolume sets it).
uniform float step_scale = 1.0;
// The proxy box in the node's local frame (RaymarchVolume sets it).
uniform vec3 proxy_min = vec3(-1.0);
uniform vec3 proxy_max = vec3(1.0);
// Finite-difference steps, in local meters, for the normal and for the
// curvature estimate.
// Q: Why 5 cm, when Lesson 09 found 1 mm best for a gradient?
// A: The displacement noise is a trilinear grid with 0.1 m cells, whose
//    gradient jumps at every cell face. A step of half a cell or more
//    averages over the jumps; a 2 mm step shows the grid (README O3).
uniform float normal_step = 0.05;
uniform float curvature_step = 0.1;

// The weathering colors and thresholds of rock_weathering.gdshader (Lesson 09).
uniform vec3 base_color : source_color = vec3(0.64, 0.56, 0.47);
uniform vec3 worn_color : source_color = vec3(0.86, 0.80, 0.70);
uniform vec3 cavity_color : source_color = vec3(0.30, 0.27, 0.20);
uniform vec3 dust_color : source_color = vec3(0.74, 0.62, 0.46);
uniform float wear_start = 0.9;
uniform float wear_full = 2.0;
uniform float cavity_start = 0.2;
uniform float cavity_full = -1.0;
uniform float dust_facing = 0.75;
uniform float dust_amount = 0.35;
uniform float map_scale = 2.0;

// SDF_MAP_BEGIN
float sdf_map(vec3 p0) {
	return sdf_sphere(p0, vec3(0.0), 1.0);
}
// SDF_MAP_END

// The camera position and the box surface point, both in the node's local
// frame. The march runs in that frame, so a moved, turned or uniformly
// scaled node needs no change to sdf_map().
varying vec3 camera_local;
varying vec3 surface_local;

void vertex() {
	// Q: Why compute the camera position per vertex?
	// A: It is the same for every vertex, so the interpolated value equals
	//    it in every fragment; one inverse() per vertex is cheaper than one
	//    per fragment.
	camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	// In vertex(), VERTEX is still in model (local) space.
	surface_local = VERTEX;
}

// Ray-box intersection by slabs. Returns (t_enter, t_exit) along ro + t rd.
// Q: How does it work?
// A: Per axis the ray is inside the slab min <= x <= max for t between
//    (min - ro) / rd and (max - ro) / rd. The box is the intersection of the
//    three slabs, so t_enter is the largest entry and t_exit the smallest
//    exit. Division by a zero component gives +-infinity, which the min and
//    max handle.
vec2 box_interval(vec3 ro, vec3 rd) {
	vec3 t0 = (proxy_min - ro) / rd;
	vec3 t1 = (proxy_max - ro) / rd;
	vec3 t_small = min(t0, t1);
	vec3 t_large = max(t0, t1);
	float t_enter = max(max(t_small.x, t_small.y), t_small.z);
	float t_exit = min(min(t_large.x, t_large.y), t_large.z);
	return vec2(t_enter, t_exit);
}

// The tetrahedral samples of f at p + h k_i, with
//   k0 = ( 1, -1, -1), k1 = (-1, -1,  1), k2 = (-1,  1, -1), k3 = ( 1,  1,  1).
// Q: Why these four vectors?
// A: They are four corners of a cube that form a regular tetrahedron. Two
//    sums make them useful (README P4):
//      sum k_i = 0            the constant term of Taylor's expansion cancels
//                             from the gradient estimate
//      sum k_i k_i^T = 4 I    each direction is covered equally
//    From f(p + h k) = f + h k.g + (h^2 / 2) k^T Hf k + O(h^3):
//      sum k_i f_i = 4 h g + O(h^2)        so g = sum k_i f_i / (4 h) + O(h)
//      sum f_i = 4 f + 2 h^2 tr(Hf) + O(h^3)
//    Four evaluations instead of the six of a central difference. The
//    price: the error is first order in h, not second order as for the
//    central difference; the mixed second derivatives do not cancel
//    (README P4). On a unit sphere at h = 5 cm the normal is off by up
//    to 1.4 degrees.
vec4 tetra_samples(vec3 p, float h) {
	return vec4(
		sdf_map(p + h * vec3(1.0, -1.0, -1.0)),
		sdf_map(p + h * vec3(-1.0, -1.0, 1.0)),
		sdf_map(p + h * vec3(-1.0, 1.0, -1.0)),
		sdf_map(p + h * vec3(1.0, 1.0, 1.0)));
}

vec3 tetra_gradient(vec4 f, float h) {
	vec3 sum = vec3(1.0, -1.0, -1.0) * f.x + vec3(-1.0, -1.0, 1.0) * f.y
		+ vec3(-1.0, 1.0, -1.0) * f.z + vec3(1.0, 1.0, 1.0) * f.w;
	return sum / (4.0 * h);
}

vec3 diverging(float value, float s) {
	float t = clamp(value / s, -1.0, 1.0);
	vec3 white = vec3(0.9);
	return t < 0.0 ? mix(white, vec3(0.1, 0.25, 0.85), -t)
	               : mix(white, vec3(0.85, 0.15, 0.1), t);
}

// Blue (few steps) through green and yellow to red (max_steps).
vec3 heat(float x) {
	x = clamp(x, 0.0, 1.0);
	return clamp(vec3(1.5 * x, 1.5 - abs(2.0 * x - 1.0) * 1.5, 1.2 - 2.0 * x), 0.0, 1.0);
}

void fragment() {
	vec3 ro = camera_local;
	vec3 rd = normalize(surface_local - ro);

	// The march covers only the part of the ray inside the proxy box.
	// When the camera is inside the box, t_enter < 0, and the march starts
	// at the camera.
	vec2 span = box_interval(ro, rd);
	float t = max(span.x, 0.0);
	float t_end = span.y;

	// Q: How wide is one pixel at distance t?
	// A: PROJECTION_MATRIX[1][1] = 1 / tan(fov_y / 2). The screen spans
	//    2 tan(fov_y / 2) in height at distance 1, over VIEWPORT_SIZE.y
	//    pixels. So one pixel covers about t * 2 / (P11 * height) meters at
	//    distance t. The ratio is the same in the local frame, as long as
	//    the node's scale is uniform. abs() because the renderer may flip
	//    the y axis in the projection, which makes P11 negative.
	float pixel_angle = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);

	bool hit = false;
	int steps = 0;
	for (int i = 0; i < max_steps; i++) {
		vec3 p = ro + rd * t;
		float d = sdf_map(p) * step_scale;
		steps = i + 1;
		// Q: Why compare with a tolerance that grows with t?
		// A: A distant rock needs less precision: an error smaller than a
		//    pixel cannot be seen. A fixed tolerance would spend the
		//    steps on detail the screen cannot show.
		if (d < epsilon_pixels * pixel_angle * t) {
			hit = true;
			break;
		}
		t += d;
		if (t > t_end) {
			break;
		}
	}

	// Q: Why does the step-count view draw misses too?
	// A: A miss costs steps as well, often the most: rays that graze the
	//    rock take many small steps before they leave the box. The view
	//    shows the cost over the whole proxy, so a miss is placed at the
	//    box face where its march began.
	if (!hit && debug_view != 1) {
		discard;
	}
	if (!hit) {
		t = max(span.x, 0.0);
	}

	vec3 p_hit = ro + rd * t;

	// Normal from four samples; the gradient direction is all that counts.
	vec4 fn = tetra_samples(p_hit, normal_step);
	vec3 n_local = normalize(tetra_gradient(fn, normal_step));

	// Q: How does per-pixel curvature follow from the same tetrahedron?
	// A: sum f_i = 4 f + 2 h^2 tr(Hf), so tr(Hf) = (sum f_i - 4 f) / (2 h^2).
	//    Lesson 09: 2H = (tr Hf - n^T Hf n) / |g|. For a true distance
	//    |g| = 1 everywhere, and differentiating |g|^2 = 1 along n gives
	//    Hf n = 0, so 2H = tr Hf. For the library's estimates this holds
	//    only near the surface, and H here is an approximation (README 3.4).
	//    The step is larger than the normal's: a second difference sees the
	//    grid's slope jumps directly, and its rounding error grows like
	//    eps / h^2.
	vec4 fc = tetra_samples(p_hit, curvature_step);
	float f0 = sdf_map(p_hit);
	vec3 g_c = tetra_gradient(fc, curvature_step);
	float trace_h = (fc.x + fc.y + fc.z + fc.w - 4.0 * f0) / (2.0 * curvature_step * curvature_step);
	float h_mean = trace_h / (2.0 * max(length(g_c), 1e-6));

	// From the local frame to view space: the normal for lighting...
	vec3 n_world = normalize((MODEL_MATRIX * vec4(n_local, 0.0)).xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// ...and the hit point, for its depth and for lights and shadows.
	vec4 p_view = VIEW_MATRIX * MODEL_MATRIX * vec4(p_hit, 1.0);
	vec4 p_clip = PROJECTION_MATRIX * p_view;
	DEPTH = p_clip.z / p_clip.w;
	// Q: What is LIGHT_VERTEX?
	// A: The position Godot uses for light directions and shadow lookups.
	//    By default it is the rasterized position, here the proxy's back
	//    face. Setting it to the hit point makes shadows fall on the rock.
	LIGHT_VERTEX = p_view.xyz;

	vec3 color = base_color;
	if (debug_view == 1) {
		color = vec3(0.0);
		EMISSION = heat(float(steps) / float(max_steps));
	} else if (debug_view == 0) {
		float wear = smoothstep(wear_start, wear_full, h_mean);
		float shelter = smoothstep(-cavity_start, -cavity_full, -h_mean);
		float up = smoothstep(dust_facing, 1.0, n_world.y);
		color = mix(color, worn_color, wear);
		color = mix(color, cavity_color, shelter);
		color = mix(color, dust_color, up * dust_amount * (1.0 - wear));
	} else if (debug_view == 2) {
		color = n_world * 0.5 + 0.5;
	} else {
		color = diverging(h_mean, map_scale);
	}
	ALBEDO = color;
	ROUGHNESS = 0.92;
}
