// color_ramp.gdshader
//
// Lesson 03. A test strip for color spaces and tonemapping. It is drawn on a
// flat QuadMesh (the ColorStrip node in scenes/lessons/03_painting_the_ground.tscn)
// through data/debug/color_ramp_material.tres.
//
// The strip has three bands, top to bottom. Across each band, UV.x runs
// from 0 at the left edge to 1 at the right edge; call it t.
//
//   top     ALBEDO = t                 linear values 0 ... 1
//   middle  ALBEDO = srgb_to_linear(t) what a source_color uniform holding
//                                      the sRGB value t delivers
//   bottom  ALBEDO = t * hdr_max       linear values 0 ... hdr_max, beyond
//                                      what a display can show
//
// A black tick marks the position of each whole number from 1 upward in
// the lower half of the bottom band.
//
// ---------------------------------------------------------------------------
// Why "unshaded"?
// ---------------------------------------------------------------------------
// render_mode unshaded skips lighting: ALBEDO goes to the screen without
// being multiplied by the sun or the sky. The value written is the value
// that enters the end of the pipeline.
//
// Q: Does an unshaded surface skip the tonemapper too?
// A: No. Tonemapping happens after every object has been drawn, on the
//    whole image at once. That is why this strip is useful: it shows the
//    tonemapper's curve itself, as a row of known input values.
//
// fog_disabled keeps the strip out of the fog, so distance does not mix
// the fog color into the values.
// ---------------------------------------------------------------------------

shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Largest linear value in the bottom band.
uniform float hdr_max : hint_range(1.0, 32.0) = 8.0;


// The sRGB decoding curve (IEC 61966-2-1). It maps a stored sRGB value
// to the linear amount of light it stands for.
//
// Q: Why two pieces?
// A: A pure power curve x^2.4 has zero slope at 0, which would crush the
//    darkest values together. The standard replaces the bottom of the
//    curve with a straight line of slope 1/12.92 and joins the two pieces
//    at x = 0.04045, where they meet with almost equal value and slope.
vec3 srgb_to_linear(vec3 c) {
	vec3 low = c / 12.92;
	vec3 high = pow((c + 0.055) / 1.055, vec3(2.4));
	return mix(low, high, step(vec3(0.04045), c));
}


void fragment() {
	float t = UV.x;
	float value = t * hdr_max;
	// Q: Why compute fwidth here, before the branches?
	// A: fwidth compares values across a 2x2 block of pixels. If some of
	//    those pixels took a different branch, the comparison is undefined.
	//    Computing it where every pixel runs the same code avoids that.
	float value_per_pixel = max(fwidth(value), 1e-6);
	// UV.y runs from 0 at the top edge of the quad to 1 at the bottom.
	if (UV.y < 1.0 / 3.0) {
		ALBEDO = vec3(t);
	} else if (UV.y < 2.0 / 3.0) {
		ALBEDO = srgb_to_linear(vec3(t));
	} else {
		ALBEDO = vec3(value);

		// Q: How is a tick at every whole number drawn?
		// A: The same fract + fwidth construction as the contour lines in
		//    terrain_painted.gdshader, applied to value instead of height.
		//    Ticks fill the lower half of the band; the tick at 0 is left
		//    out, since black on black would not show.
		float distance_in_pixels = abs(fract(value - 0.5) - 0.5) / value_per_pixel;
		float tick = 1.0 - smoothstep(0.5, 1.5, distance_in_pixels);
		if (UV.y > 5.0 / 6.0 && value > 0.5) {
			ALBEDO = mix(ALBEDO, vec3(0.0), tick);
		}
	}
}
