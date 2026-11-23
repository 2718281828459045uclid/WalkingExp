// sdf_slice.gdshader
//
// Lesson 07. Draws one plane cut through a signed distance field.
//
// How the files relate:
//   src/sdf/sdf_slice.gd    samples an SdfShape on a grid of points in a
//                           plane, writes the values into a float texture,
//                           and puts that texture into the `field` uniform
//                           of its own copy of this material
//   data/debug/sdf_slice_material.tres
//                           the ShaderMaterial with this shader and the
//                           default colors; every SdfSlice duplicates it
//   this file               turns the stored numbers into colors
//
// ---------------------------------------------------------------------------
// What is in the texture?
// ---------------------------------------------------------------------------
// One texel per grid point, two 32-bit float channels (Image.FORMAT_RGF):
//   R = f(p)        the signed distance at the grid point, in meters
//   G = |grad f(p)| the length of the gradient, from finite differences
// The CPU computed both. The shader does no SDF math; it only colors.
//
// Q: Why not evaluate the SDF here, on the GPU, for every pixel?
// A: The SDF lives in GDScript Resources (src/sdf/). To evaluate it here,
//    every shape would need a second copy in shader code, and the two
//    copies could disagree. A texture of CPU samples shows the values
//    Lesson 08 will mesh. Lesson 10 moves SDF evaluation to the GPU.
//
// ---------------------------------------------------------------------------
// The three views (uniform `view`)
// ---------------------------------------------------------------------------
//   0  distance   orange inside, blue outside; brightness falls toward the
//                 surface; a thin dark line every `band_meters` of distance;
//                 a white line on the zero set (the surface itself)
//   1  gradient   gray where |grad f| = 1 (a true distance field), red
//                 where it is larger (the field overestimates distance
//                 somewhere), blue where smaller (the field underestimates)
//   2  sign       flat orange inside, flat blue outside
//
// Q: Why are bands at equal spacing a test of the distance property?
// A: If f is a true distance, moving 0.25 m straight away from the surface
//    raises f by 0.25, so the band lines are 0.25 m apart in space
//    and parallel to the surface. Where the bands crowd together, f grows
//    faster than distance (|grad f| > 1); where they spread, slower.
// ---------------------------------------------------------------------------

shader_type spatial;
// unshaded: the colors are data, so the sun should not change them.
// cull_disabled: the slice is a single quad, visible from both sides.
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D field : filter_linear, repeat_disable;
uniform int view : hint_range(0, 2) = 0;
uniform float band_meters = 0.25;
uniform vec3 outside_color : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 inside_color : source_color = vec3(0.9, 0.55, 0.25);
uniform vec3 zero_line_color : source_color = vec3(1.0);
// Width of the zero line and the band lines on screen, in pixels.
uniform float line_pixels = 1.5;

// Coverage (0..1) of a line drawn where `value` crosses a whole number.
//
// Q: Why divide by fwidth?
// A: fwidth(value) is how much `value` changes from one pixel to the next
//    (Lesson 03, contour lines). Dividing the distance to the nearest whole
//    number by it converts "distance in value units" into "distance in
//    pixels", so the line has the same width on screen near and far.
float line_coverage(float value, float width_px) {
	float to_line = abs(value - round(value));
	float per_pixel = max(fwidth(value), 1e-6);
	return 1.0 - smoothstep(0.0, width_px, to_line / per_pixel);
}

void fragment() {
	vec2 sample_value = texture(field, UV).rg;
	float d = sample_value.r;
	float grad_length = sample_value.g;
	vec3 color;

	if (view == 1) {
		// Q: How is the gradient length turned into a color?
		// A: Start from gray and move toward red by the excess over 1,
		//    toward blue by the shortfall under 1. A factor 4 makes a 25 %
		//    error the full color, so small errors are visible.
		float excess = clamp((grad_length - 1.0) * 4.0, 0.0, 1.0);
		float shortfall = clamp((1.0 - grad_length) * 4.0, 0.0, 1.0);
		color = vec3(0.5);
		color = mix(color, vec3(0.9, 0.15, 0.1), excess);
		color = mix(color, vec3(0.15, 0.3, 0.9), shortfall);
	} else if (view == 2) {
		color = d > 0.0 ? outside_color : inside_color;
	} else {
		color = d > 0.0 ? outside_color : inside_color;
		// Q: Why exp(-|d|) and not a straight line?
		// A: It leaves the colors near the surface dark and saturates far
		//    away, so the eye finds the zero set at once at any scale.
		color *= 0.35 + 0.65 * (1.0 - exp(-1.5 * abs(d)));
		// Band lines: d / band_meters crosses a whole number every band.
		color *= 1.0 - 0.6 * line_coverage(d / band_meters, line_pixels * 0.6);
	}

	// The zero set is drawn in every view: it is the surface Lesson 08 meshes.
	// line_coverage(d) is 1 where d crosses 0 (and every other whole meter,
	// so restrict it to |d| < 0.5).
	float zero_line = abs(d) < 0.5 ? line_coverage(d, line_pixels) : 0.0;
	color = mix(color, zero_line_color, zero_line);

	ALBEDO = color;
}
