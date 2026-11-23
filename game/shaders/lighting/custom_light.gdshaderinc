// custom_light.gdshaderinc
//
// Lesson 17. A light() function with four shading models, for appending
// to any spatial shader that has a fragment() and no light() of its own.
//
// How this file relates to the others:
//   shaders/lighting/brdf.gdshaderinc   the BRDF formulas (included below)
//   src/render/lit_shader.gd            LitShader.make() copies the code of
//                                       an existing shader (Lesson 03's
//                                       terrain_painted.gdshader, Lesson 09's
//                                       rock_weathering.gdshader) and appends
//                                       an #include of this file; the
//                                       result is a new Shader with the old
//                                       fragment() and this light()
//   src/render/shading_switch.gd        ShadingSwitch swaps the terrain's and
//                                       the rocks' materials between the
//                                       original (built-in light) and the
//                                       generated one, and sets light_model
//                                       and light_term (F5, F6)
//   src/render/shading_gallery.gd       ShadingGallery shows every model side
//                                       by side, one material per column
//
// ---------------------------------------------------------------------------
// What light() is
// ---------------------------------------------------------------------------
// Q: When does Godot call light()?
// A: After fragment() has decided what the surface is at a pixel (ALBEDO,
//    ROUGHNESS, METALLIC, NORMAL), Godot loops over the lights that reach
//    the pixel and calls light() once per light. Each call adds that
//    light's contribution to two sums, DIFFUSE_LIGHT and SPECULAR_LIGHT.
//    Without a light() function Godot runs its own code in the same place
//    (Lambert diffuse and GGX specular by default in Godot 4.6).
//
// Q: What does light() receive? (All vectors are unit vectors in view
//    space; README section 3.2 lists the measurements behind each claim.)
// A:   NORMAL                the surface normal written by fragment()
//      VIEW                  from the surface point toward the camera
//      LIGHT                 from the surface point toward the light
//      LIGHT_COLOR           light color * energy * PI
//      ATTENUATION           distance falloff and shadow, 0..1
//                            (1 for an unshadowed directional light)
//      LIGHT_IS_DIRECTIONAL  true for the sun
//      SPECULAR_AMOUNT       the light's light_specular property
//      ALBEDO, ROUGHNESS, METALLIC   what fragment() wrote
//    and may write:
//      DIFFUSE_LIGHT         (inout) running sum of diffuse light
//      SPECULAR_LIGHT        (inout) running sum of specular light
//
// Q: What happens to the two sums afterward?
// A: Godot multiplies DIFFUSE_LIGHT by ALBEDO and by (1 - METALLIC), then
//    adds SPECULAR_LIGHT unchanged, plus the ambient light, the
//    reflections of the sky and the emission. So light() must NOT multiply
//    the diffuse term by ALBEDO itself, or the color would be squared.
//
// Q: Why does LIGHT_COLOR carry a factor of PI?
// A: Every diffuse BRDF that conserves energy has a 1/PI (Lambert: rho / PI).
//    With PI folded into the light, a white Lambertian surface facing a
//    light of energy 1 shows 1: PI * (1 / PI) * cos(0) = 1. The
//    energy slider then means "brightness of a white wall facing the
//    light", which is what an artist expects.
//
// Q: What does light() not touch?
// A: Ambient light, sky reflections, global illumination (SDFGI, VoxelGI,
//    lightmaps) and emission are added outside light(). A shader with an
//    empty light() still shows them (README T1).
// ---------------------------------------------------------------------------

#include "res://shaders/lighting/brdf.gdshaderinc"

// 0 = Lambert, 1 = wrap, 2 = Oren-Nayar, 3 = GGX (Lambert + GGX specular).
// The numbers match the enum Brdf.Model in src/render/brdf.gd.
uniform int light_model : hint_range(0, 3) = 0;
// 0 = diffuse and specular, 1 = diffuse only, 2 = specular only.
uniform int light_term : hint_range(0, 2) = 0;
// Wrap lighting: the dark side begins at cos(theta_l) = -light_wrap.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.5;
// Oren-Nayar: standard deviation of the facet slopes, in degrees.
uniform float light_sigma_degrees : hint_range(0.0, 90.0) = 30.0;
// GGX: reflectance of a facet at normal incidence (non-metals about 0.04).
// Q: Why a uniform and not the material's SPECULAR?
// A: SPECULAR is written in fragment() but is not passed to light().
//    Godot's built-in code turns it into f0 = 0.16 * SPECULAR^2, so the
//    default SPECULAR 0.5 gives 0.04; the terrain writes SPECULAR 0.3,
//    which gives 0.0144 (README O5).
uniform float light_f0 : hint_range(0.0, 1.0) = 0.04;


void light() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(LIGHT);
	vec3 v = normalize(VIEW);
	float n_dot_l = dot(n, l);

	// Q: What does each branch compute?
	// A: f * cos(theta_l) without albedo, per unit of light: the factor
	//    that turns "light arriving" into "light leaving toward the eye".
	float diffuse;
	if (light_model == 1) {
		diffuse = wrap_cosine(n_dot_l, light_wrap);
	} else if (light_model == 2) {
		diffuse = oren_nayar_cosine(n, l, v, radians(light_sigma_degrees));
	} else {
		diffuse = lambert_cosine(n_dot_l);
	}

	vec3 specular = vec3(0.0);
	if (light_model == 3) {
		// Q: Why mix f0 toward ALBEDO by METALLIC?
		// A: A metal has no diffuse light (Godot multiplies the diffuse sum
		//    by 1 - METALLIC); its color lives in the reflection itself. The
		//    same mix is in Godot's built-in code.
		vec3 f0 = mix(vec3(light_f0), ALBEDO, METALLIC);
		specular = ggx_specular_cosine(n, l, v, ROUGHNESS, f0) * SPECULAR_AMOUNT;
	}

	// The F6 key: show one term alone.
	if (light_term == 1) {
		specular = vec3(0.0);
	} else if (light_term == 2) {
		diffuse = 0.0;
	}

	// Q: Why "+=" and not "="?
	// A: light() runs once per light. The sums start at zero for each
	//    pixel, and every light adds its share. Writing "=" would keep only
	//    the last light that Godot happened to process.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diffuse;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * specular;
}
