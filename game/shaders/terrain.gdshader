// terrain.gdshader
//
// Colors the terrain mesh built by src/terrain/terrain.gd.
// Material values (colors, angles) live in data/terrain/terrain_material.tres,
// so they can be tuned in the Inspector without editing this file.
//
// ---------------------------------------------------------------------------
// How a Godot spatial shader runs
// ---------------------------------------------------------------------------
// The GPU runs two small programs:
//
//   vertex()   once per mesh vertex. Its job here: compute values that the
//              fragment stage needs and hand them over through "varyings".
//
//   fragment() once per pixel the mesh covers. Its job: decide the surface
//              properties at that pixel (ALBEDO = base color, ROUGHNESS, ...).
//              Godot's built-in lighting then turns those properties into a
//              final color using the scene's lights.
//
// Q: What happens to a varying between the two stages?
// A: The rasterizer interpolates it across each triangle. A pixel in the
//    middle of a triangle receives a weighted average (barycentric blend)
//    of the three vertex values.
//
// Q: What coordinate space is NORMAL in?
// A: In vertex(), NORMAL is in model (object) space. In fragment(), NORMAL
//    is in view (camera) space. For rules like "steep ground is rock" we
//    want world space, where +y is up regardless of where the camera looks.
//    So we convert in vertex() and pass the result through a varying.
// ---------------------------------------------------------------------------

shader_type spatial;

// 0 = lit material, 1 = normals as colors, 2 = slope heat map.
// sandbox.gd cycles this value with the Tab key.
uniform int debug_view : hint_range(0, 2) = 0;

uniform vec3 grass_color : source_color = vec3(0.33, 0.40, 0.20);
uniform vec3 dirt_color : source_color = vec3(0.50, 0.40, 0.28);
uniform vec3 rock_color : source_color = vec3(0.52, 0.49, 0.46);

// Slope angles in degrees where grass begins to turn into rock, and where
// the transition ends.
uniform float rock_angle_start : hint_range(0.0, 90.0) = 22.0;
uniform float rock_angle_end : hint_range(0.0, 90.0) = 32.0;

// Below this world height the ground shifts toward dirt.
uniform float dirt_height : hint_range(-20.0, 40.0) = 1.0;
uniform float dirt_blend_meters : hint_range(0.1, 20.0) = 3.0;

varying vec3 world_normal;
varying vec3 world_position;


void vertex() {
	// MODEL_MATRIX maps model space to world space.
	// w = 1 for a position: translation applies.
	// w = 0 for a direction: translation does not apply (a direction has
	// no location, so moving the object must not change it).
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Q: Is multiplying a normal by MODEL_MATRIX always correct?
	// A: Only when the object has uniform scale. A non-uniform scale
	//    (stretching x but not y) tilts normals the wrong way; the correct
	//    matrix is the inverse transpose of the model matrix. The terrain
	//    node is not scaled, so the simple form works here.
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


// Maps t in [0, 1] to a blue -> green -> yellow -> red ramp.
vec3 heat_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 cold = vec3(0.10, 0.25, 0.90);
	vec3 mid = vec3(0.15, 0.80, 0.30);
	vec3 warm = vec3(0.95, 0.85, 0.15);
	vec3 hot = vec3(0.90, 0.10, 0.10);
	if (t < 0.33) {
		return mix(cold, mid, t / 0.33);
	}
	if (t < 0.66) {
		return mix(mid, warm, (t - 0.33) / 0.33);
	}
	return mix(warm, hot, (t - 0.66) / 0.34);
}


void fragment() {
	// Q: The vertex normals had length 1. Why normalize again?
	// A: Interpolating between unit vectors produces vectors shorter than 1
	//    (the average of two different unit vectors lies inside the sphere).
	vec3 n = normalize(world_normal);

	// The slope angle is the angle between the normal and straight up.
	// cos(angle) = dot(n, up) = n.y, because up = (0, 1, 0).
	// Q: acos() runs for every pixel. Could we avoid it?
	// A: Yes: compare n.y against cos(threshold) instead. Note that the
	//    inequality flips, since cosine decreases as the angle grows.
	//    The degree form is kept here because it reads more clearly.
	float slope_degrees = degrees(acos(clamp(n.y, -1.0, 1.0)));

	if (debug_view == 1) {
		// Normal visualization: map each component from [-1, 1] to [0, 1].
		// Flat ground (0, 1, 0) shows as (0.5, 1.0, 0.5), a light green.
		// Writing to EMISSION with black ALBEDO bypasses lighting, so the
		// color shows the normal itself, not the normal times the sunlight.
		ALBEDO = vec3(0.0);
		EMISSION = n * 0.5 + 0.5;
	} else if (debug_view == 2) {
		// 0 degrees = blue, 45 degrees (the player's walkable limit) = red.
		ALBEDO = vec3(0.0);
		EMISSION = heat_ramp(slope_degrees / 45.0);
	} else {
		// smoothstep(a, b, x) returns 0 below a, 1 above b, and a smooth
		// S-curve between. It turns a hard threshold into a soft blend.
		float rockiness = smoothstep(rock_angle_start, rock_angle_end, slope_degrees);
		float dirtiness = 1.0 - smoothstep(dirt_height, dirt_height + dirt_blend_meters, world_position.y);

		vec3 ground = mix(grass_color, dirt_color, dirtiness);
		ALBEDO = mix(ground, rock_color, rockiness);
		ROUGHNESS = 0.92;
		SPECULAR = 0.3;
	}
}
