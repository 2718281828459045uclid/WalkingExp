// terrain_painted.gdshader
//
// Lesson 03. Paints the terrain mesh built by src/terrain/terrain.gd with
// procedural texture, slope and height rules, and topographic contour lines.
//
// How this file relates to the others:
//   data/terrain/painted_terrain_material.tres  (ShaderMaterial)
//       -> uses this shader, holds every uniform value below
//       -> assigns data/terrain/ground_noise.tres (NoiseTexture2D) to
//          the ground_noise sampler
//   src/lessons/painting_the_ground.gd
//       -> sets paint_view and show_contours at runtime (V and C keys)
//   src/sandbox.gd (inherited by the lesson root)
//       -> sets debug_view (Tab), as it does for terrain.gdshader
//
// terrain.gdshader (Lesson 01) is not changed. This shader starts from the
// same structure: world-space varyings from vertex(), slope from the normal.
// Read the header of terrain.gdshader first if any of that is unfamiliar.
//
// ---------------------------------------------------------------------------
// Four ideas in this file
// ---------------------------------------------------------------------------
// 1. Triplanar mapping. A 2D texture needs 2D coordinates. The terrain has
//    no hand-made UVs worth using, so the shader invents coordinates from
//    the world position, three times: once looking down the x axis, once
//    down y, once down z. It blends the three samples by how much the
//    surface faces each axis.
//
// 2. Smooth rules. smoothstep() turns thresholds ("steeper than 22 degrees
//    is rock") into blends. Noise added to the input breaks up the
//    straight edges such a rule produces.
//
// 3. Contour lines. fract(height / interval) repeats every interval meters.
//    fwidth() measures how fast that value changes per screen pixel, which
//    lets the shader draw lines of a fixed width in pixels.
//
// 4. Color spaces. Uniforms marked source_color are typed in sRGB (the way
//    a color picker shows them) and arrive in the shader converted to
//    linear values, which is the space where lighting math is valid.
//    The noise texture is data, not a color, so it carries no such hint.
// ---------------------------------------------------------------------------

shader_type spatial;

// ---------------------------------------------------------------- views ----

// Same meaning as in terrain.gdshader, so the Tab key keeps working:
// 0 = painted material, 1 = normals as colors, 2 = slope heat map.
uniform int debug_view : hint_range(0, 2) = 0;

// Lesson 03 views, cycled with V by painting_the_ground.gd:
// 0 = painted material
// 1 = triplanar weights as colors (red = x, green = y, blue = z projection)
// 2 = noise alone, sampled triplanar, lit
// 3 = noise alone, sampled from above only (no triplanar), lit
uniform int paint_view : hint_range(0, 3) = 0;

// --------------------------------------------------------------- colors ----

// Q: What does source_color do?
// A: It tells Godot that the value is an sRGB color, as stored by a color
//    picker. Godot converts it to linear before the shader sees it.
//    Without the hint, the numbers would arrive unconverted and every
//    color would look lighter and more washed out than in the Inspector.
uniform vec3 grass_color : source_color = vec3(0.33, 0.40, 0.20);
uniform vec3 dirt_color : source_color = vec3(0.50, 0.40, 0.28);
uniform vec3 rock_color : source_color = vec3(0.52, 0.49, 0.46);

// ---------------------------------------------------------------- rules ----

uniform float rock_angle_start : hint_range(0.0, 90.0) = 22.0;
uniform float rock_angle_end : hint_range(0.0, 90.0) = 32.0;
uniform float dirt_height : hint_range(-20.0, 40.0) = 1.0;
uniform float dirt_blend_meters : hint_range(0.1, 20.0) = 3.0;

// How far the noise shifts the rules. Zero gives the clean bands of
// terrain.gdshader; larger values give irregular edges that follow the noise.
uniform float rock_breakup_degrees : hint_range(0.0, 30.0) = 8.0;
uniform float dirt_breakup_meters : hint_range(0.0, 10.0) = 1.5;

// ---------------------------------------------------------------- noise ----

// Q: Why no source_color here?
// A: The noise texture stores numbers (0 = low, 1 = high), not colors.
//    Converting data from sRGB to linear would bend it: 0.5 would become
//    about 0.21 and most of the noise would sit near zero.
//
// Q: What would the hint do to this texture?
// A: Nothing, on Godot 4.6. NoiseTexture2D writes a one-channel image
//    (format L8), and the renderer applies no sRGB decoding to that
//    format: with or without the hint, the samples are the same. Give the
//    NoiseTexture2D a color ramp and it writes RGBA8 instead; then the
//    hint decodes it and the noise darkens (Lesson 03 T1). The hint stays
//    off because the texture is data, whatever its format.
//
// Q: What are filter_linear_mipmap and repeat_enable?
// A: repeat_enable lets coordinates outside [0, 1] wrap around, so the
//    texture tiles across the whole terrain. filter_linear_mipmap blends
//    between texels and picks a smaller copy of the texture (a mipmap)
//    far from the camera, where one pixel covers many texels.
uniform sampler2D ground_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// Meters covered by one copy of the noise texture. The rock layer samples
// a second, finer scale to give it a different grain from the grass.
uniform float noise_scale_meters : hint_range(1.0, 200.0) = 24.0;
uniform float rock_noise_scale_meters : hint_range(0.5, 50.0) = 3.0;

// How much the noise darkens and lightens the base colors.
// 0.3 means albedo varies between 0.7x and 1.3x of the base color.
uniform float color_variation : hint_range(0.0, 1.0) = 0.3;

// Exponent applied to |n| before the triplanar weights are normalized.
// 1 gives wide, soft blends; large values give narrow seams.
uniform float triplanar_sharpness : hint_range(1.0, 32.0) = 4.0;

// ------------------------------------------------------------- contours ----

uniform bool show_contours = true;
uniform float contour_interval : hint_range(0.1, 20.0) = 1.0;
// Every Nth line is an "index contour", drawn wider, as on a printed map.
uniform int index_every : hint_range(1, 20) = 5;
uniform float contour_width_pixels : hint_range(0.1, 8.0) = 1.0;
uniform vec3 contour_color : source_color = vec3(0.20, 0.13, 0.08);
uniform float contour_opacity : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_normal;
varying vec3 world_position;


void vertex() {
	// Same conversion as terrain.gdshader: position with w = 1,
	// direction with w = 0. The terrain node is not scaled.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


// Same ramp as terrain.gdshader: blue -> green -> yellow -> red.
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


// ------------------------------------------------------------------------
// Triplanar weights
// ------------------------------------------------------------------------
// Picture the terrain inside a glass box, with a slide projector on three
// of the box's walls: one shining along x, one along y (from above), one
// along z. Each projector paints the texture onto every surface in its
// path, but a surface it hits edge-on receives a stretched smear.
//
// Q: How much should each projector count at a point with normal n?
// A: As much as the surface faces it. The x projector hits a surface
//    face-on when n points along x, so |n.x| measures its usefulness.
//    The same holds for |n.y| and |n.z|.
//
// Q: Why raise |n| to a power?
// A: With k = 1, two projectors share the work in equal parts on a
//    45-degree slope, and share it in comparable parts on most slopes
//    (side weight 0.37 at 30 degrees). Each projector shows the texture
//    at a different orientation, so their average mixes two unrelated
//    patterns: it has less contrast than either and can look doubled.
//    A power k > 1 shrinks the smaller components faster than the large
//    one, so one projector dominates almost everywhere and the mixed
//    region narrows to a band around 45 degrees (30 to 60 for k = 4).
//
// Q: Why divide by the sum?
// A: So the weights add to 1 for every normal. Without the division, the
//    sum of |n_i|^k changes with the normal. On flat ground it is 1 for
//    every k. On a 45-degree slope it is 1.41 for k = 1, 1 for k = 2, and
//    0.5 for the default k = 4. Slopes would come out brighter than flat
//    ground for k < 2 and darker for k > 2. With weights that sum to 1,
//    the blend keeps the texture's brightness on every slope.
vec3 triplanar_weights(vec3 n, float sharpness) {
	vec3 w = pow(abs(n), vec3(sharpness));
	return w / (w.x + w.y + w.z);
}


// Samples a texture three times, through the x, y, and z projectors, and
// blends with the weights above. scale_meters is the world size of one
// tile of the texture.
//
// Q: Which two world coordinates does each projector use?
// A: The two that change across its wall. Looking along x, a point moves
//    on the wall when z or y changes: (z, y). Looking along y (from
//    above): (x, z). Looking along z: (x, y).
float triplanar_sample(sampler2D tex, vec3 p, vec3 weights, float scale_meters) {
	vec3 q = p / scale_meters;
	float along_x = texture(tex, q.zy).r;
	float along_y = texture(tex, q.xz).r;
	float along_z = texture(tex, q.xy).r;
	return along_x * weights.x + along_y * weights.y + along_z * weights.z;
}


// ------------------------------------------------------------------------
// Contour lines
// ------------------------------------------------------------------------
// Returns line coverage in [0, 1]: 1 on a contour line, 0 between lines.
//
// Q: What is f = height / interval?
// A: The height measured in contour steps. A contour line sits wherever f
//    is a whole number.
//
// Q: How far is a point from the nearest whole number?
// A: fract(f) is the fractional part, in [0, 1). The distance to the
//    nearest integer is min(fract(f), 1 - fract(f)). The expression
//    abs(fract(f - 0.5) - 0.5) computes the same value without a branch:
//    it is 0 at integers and rises to 0.5 halfway between them.
//
// Q: That distance is in contour steps. How do we get pixels?
// A: fwidth(f) = |df/dx_screen| + |df/dy_screen|: how much f changes from
//    one pixel to its neighbor. The GPU computes it by comparing values
//    in a 2x2 block of neighboring pixels. Dividing the distance by
//    fwidth(f) converts "steps of f" into "pixels". A line of width w
//    pixels is then the set of points whose pixel distance is below w/2.
//
// Q: Why does that keep the line width constant on screen?
// A: Measured in f, the line is a band of width w * fwidth(f). Where the
//    ground is steep, or far from the camera (one pixel spans more
//    ground), f changes fast per pixel: fwidth is large, so a given
//    distance in f spans few pixels, and the w-pixel line covers a wide
//    band of f. Where f changes little per pixel (gentle ground, close
//    up), fwidth is small, and the same w pixels cover a narrow band of
//    f. In pixels the width stays w. Without fwidth, lines would be fat
//    on gentle ground and vanish on steep ground or far away.
//
// Q: Why smoothstep at the edge instead of a hard step?
// A: A hard edge decides "in or out" per pixel and produces staircase
//    edges (aliasing). A ramp one pixel wide approximates the fraction of
//    the pixel the line covers.
float contour_coverage(float height, float interval, float width_pixels) {
	float f = height / interval;
	float distance_in_steps = abs(fract(f - 0.5) - 0.5);
	float distance_in_pixels = distance_in_steps / max(fwidth(f), 1e-6);
	float half_width = 0.5 * width_pixels;
	return 1.0 - smoothstep(half_width - 0.5, half_width + 0.5, distance_in_pixels);
}


void fragment() {
	vec3 n = normalize(world_normal);
	float slope_degrees = degrees(acos(clamp(n.y, -1.0, 1.0)));

	vec3 weights = triplanar_weights(n, triplanar_sharpness);
	float noise_coarse = triplanar_sample(ground_noise, world_position, weights, noise_scale_meters);
	float noise_fine = triplanar_sample(ground_noise, world_position, weights, rock_noise_scale_meters);

	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = n * 0.5 + 0.5;
	} else if (debug_view == 2) {
		ALBEDO = vec3(0.0);
		EMISSION = heat_ramp(slope_degrees / 45.0);
	} else if (paint_view == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = weights;
	} else if (paint_view == 2) {
		ALBEDO = vec3(noise_coarse);
	} else if (paint_view == 3) {
		// Only the projector from above: the texture stretches on slopes,
		// because one texel of (x, z) covers a longer strip of surface
		// where the height changes fast.
		ALBEDO = vec3(texture(ground_noise, world_position.xz / noise_scale_meters).r);
	} else {
		// Noise in [0, 1] becomes an offset in [-0.5, 0.5] that shifts
		// each rule's input. The boundary then follows the noise's level
		// set instead of a straight slope or height threshold.
		float shift = noise_coarse - 0.5;
		float rockiness = smoothstep(rock_angle_start, rock_angle_end,
				slope_degrees + shift * 2.0 * rock_breakup_degrees);
		float dirtiness = 1.0 - smoothstep(dirt_height, dirt_height + dirt_blend_meters,
				world_position.y + shift * 2.0 * dirt_breakup_meters);

		// Q: Why multiply the color by (1 + variation * (2 noise - 1))?
		// A: The factor ranges over [1 - variation, 1 + variation] with
		//    mean 1, so the average color stays the base color from the
		//    material and the noise adds light and dark patches around it.
		vec3 ground = mix(grass_color, dirt_color, dirtiness);
		ground *= 1.0 + color_variation * (2.0 * noise_coarse - 1.0);
		vec3 rock = rock_color * (1.0 + color_variation * (2.0 * noise_fine - 1.0));

		ALBEDO = mix(ground, rock, rockiness);
		ROUGHNESS = 0.92;
		SPECULAR = 0.3;
	}

	if (show_contours) {
		float line = contour_coverage(world_position.y, contour_interval, contour_width_pixels);
		// Index contours: the same construction with a coarser interval
		// and twice the width, so every Nth line stands out.
		float index_interval = contour_interval * float(index_every);
		float index_line = contour_coverage(world_position.y, index_interval, 2.0 * contour_width_pixels);
		float coverage = max(line, index_line) * contour_opacity;
		ALBEDO = mix(ALBEDO, contour_color, coverage);
		EMISSION = mix(EMISSION, vec3(0.0), coverage);
	}
}
