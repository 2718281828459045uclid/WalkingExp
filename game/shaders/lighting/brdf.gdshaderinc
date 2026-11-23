// brdf.gdshaderinc
//
// Lesson 17. The shading models as GLSL functions: Lambert, wrap lighting,
// Oren-Nayar, and the GGX microfacet specular lobe (distribution D,
// masking-shadowing G, Fresnel F).
//
// How this file relates to the others:
//   shaders/lighting/custom_light.gdshaderinc
//                       includes this file and calls these functions from
//                       light(), once per pixel and per light
//   src/render/brdf.gd  the same formulas in GDScript (class Brdf), where
//                       tests integrate them over the hemisphere; change
//                       both files together
//
// Nothing in this file reads a Godot built-in. Every function takes plain
// numbers and vectors, so the same lines could run in any GLSL program.
//
// ---------------------------------------------------------------------------
// The words of this file
// ---------------------------------------------------------------------------
// Q: What is a BRDF?
// A: The Bidirectional Reflectance Distribution Function f(l, v) answers
//    one question about a surface point: light arrives from direction l;
//    how much of it leaves toward direction v? Its unit is 1/steradian.
//    A sun of irradiance E (light per square meter, measured on a plane
//    facing the sun) shining at angle theta_l from the normal delivers
//    E cos(theta_l) per square meter of surface (the same beam spreads
//    over a larger patch when it arrives slanted). The light sent toward
//    the eye is
//        L_out = f(l, v) * E * cos(theta_l).
//    The functions below return f * cos(theta_l) (named ..._cosine) or a
//    factor of f; custom_light.gdshaderinc multiplies by the light.
//
// Q: Why is there a 1/pi in Lambert?
// A: Energy. A Lambertian surface sends the same radiance in every
//    direction. The total that leaves is that radiance times the integral
//    of cos(theta) over the hemisphere, which is pi (README section 2, P1).
//    For a surface that reflects a fraction rho of what it receives, the
//    radiance must therefore be rho * E / pi, and f = rho / pi.
//
// Q: Where do these vectors live?
// A: In light(), Godot gives NORMAL, VIEW and LIGHT in view space (camera
//    space). Only dot products between them are used here, and a rotation
//    does not change a dot product, so the frame does not matter.
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------- diffuse ----

// Lambert: f = rho / pi. Returned without rho: Godot multiplies the
// diffuse light by ALBEDO after light() has run (measured, README 3.2).
float lambert_cosine(float n_dot_l) {
	return max(n_dot_l, 0.0) / PI;
}


// Wrap lighting.
//
// Q: What does it do?
// A: Lambert's cos(theta_l) falls to 0 at 90 degrees, so a sphere lit from
//    the side is black on half its surface, with a sharp edge between lit
//    and dark (the terminator). Wrap lighting replaces cos(theta_l) by
//        (cos(theta_l) + w) / (1 + w),   clamped at 0.
//    Facing the light it still gives 1; it reaches 0 at cos(theta_l) = -w,
//    so the light "wraps" past the terminator by an angle of asin(w). Skin,
//    moss and dusty rock let light creep past the geometric edge (light
//    scatters inside them); wrap lighting imitates that look.
//
// Q: Is it a BRDF?
// A: No. It is a rule for the response to one light direction. It also
//    answers light from below the surface's horizon (cos < 0), which a
//    BRDF never sees. README P2 computes how much more light it returns
//    than it receives.
float wrap_cosine(float n_dot_l, float w) {
	return max(0.0, (n_dot_l + w) / (1.0 + w)) / PI;
}


// Oren-Nayar, qualitative model (Oren and Nayar 1994).
//
// Q: Where does Lambert fail?
// A: For rough surfaces such as sand, plaster, the moon or weathered rock.
//    Such a surface is made of small facets tilted every way. Seen from
//    the side of the light, the eye sees the facets that face the light
//    (bright); seen from the other side, it sees their shadowed backs.
//    A full moon looks like a flat disc, not like a Lambertian ball that
//    darkens toward the rim: the rim facets that face us also face the
//    sun, which is behind us.
//
// Q: What is sigma?
// A: The standard deviation of the facets' slope angle, in radians.
//    sigma = 0 is a smooth Lambertian surface (A = 1, B = 0); the default
//    of custom_light.gdshaderinc is 30 degrees.
//
// The model:
//   f = rho / pi * (A + B * max(0, cos(phi_v - phi_l)) * sin(alpha) * tan(beta))
//   A = 1 - 0.5 s^2 / (s^2 + 0.33)
//   B = 0.45 s^2 / (s^2 + 0.09)
//   alpha = max(theta_l, theta_v),  beta = min(theta_l, theta_v)
// A lowers the plain Lambert part; B adds light when eye and light are on
// the same side (cos(phi_v - phi_l) > 0) and both are far from the normal.
//
// Returned: f * cos(theta_l) without rho.
float oren_nayar_cosine(vec3 n, vec3 l, vec3 v, float sigma) {
	float n_dot_l = dot(n, l);
	float n_dot_v = dot(n, v);
	if (n_dot_l <= 0.0 || n_dot_v <= 0.0) {
		return 0.0;
	}
	float s2 = sigma * sigma;
	float a = 1.0 - 0.5 * s2 / (s2 + 0.33);
	float b = 0.45 * s2 / (s2 + 0.09);

	// Q: How do we get cos(phi_v - phi_l), the angle between the two
	//    directions measured around the normal?
	// A: Flatten both into the tangent plane by removing their normal
	//    parts, then take the cosine between the flattened vectors. If one
	//    of them points along n its azimuth is undefined; sin(theta) is 0
	//    there and the B term vanishes anyway, so 0 is a safe answer.
	vec3 l_flat = l - n * n_dot_l;
	vec3 v_flat = v - n * n_dot_v;
	float lengths = length(l_flat) * length(v_flat);
	float cos_phi = lengths > 1e-6 ? max(0.0, dot(l_flat, v_flat) / lengths) : 0.0;

	// Q: How do we get sin(alpha) and tan(beta) without acos()?
	// A: alpha is the larger of the two angles, so its cosine is the
	//    smaller of the two cosines; beta is the smaller angle, so its
	//    cosine is the larger one. Then sin = sqrt(1 - cos^2) and
	//    tan = sin / cos. cos_beta > 0 here because both dots are > 0.
	float cos_alpha = min(n_dot_l, n_dot_v);
	float cos_beta = max(n_dot_l, n_dot_v);
	float sin_alpha = sqrt(max(0.0, 1.0 - cos_alpha * cos_alpha));
	float tan_beta = sqrt(max(0.0, 1.0 - cos_beta * cos_beta)) / cos_beta;

	return (a + b * cos_phi * sin_alpha * tan_beta) * n_dot_l / PI;
}


// --------------------------------------------------------------- specular ----
//
// Q: What is a microfacet model?
// A: Picture the surface under a microscope as a field of tiny mirrors
//    (microfacets), each tilted a little. A mirror sends light from l to v
//    only if its normal is the half vector h = normalize(l + v),
//    the direction halfway between them. So the brightness of a highlight
//    depends on three questions:
//      D(h)   How many facets point along h?          (distribution)
//      G(l,v) How many of them are neither in shadow   (masking-shadowing)
//             (hidden from l) nor masked (hidden from v)
//             by their neighbors?
//      F      How much does one facet reflect at the   (Fresnel)
//             angle between v and h?
//    Cook and Torrance put them together as
//        f_spec = D(h) G(l, v) F(v.h) / (4 (n.l)(n.v)).
//    The 4 (n.l)(n.v) converts "facets per unit solid angle of h" into
//    "light per unit solid angle of v" (README P5 counts the factor).


// GGX / Trowbridge-Reitz distribution of facet normals.
//
// Q: What shape does it have?
// A: D(h) = alpha^2 / (pi ((n.h)^2 (alpha^2 - 1) + 1)^2).
//    At n.h = 1 (facets aligned with the macro normal) it is
//    1 / (pi alpha^2): tall and narrow for a smooth surface (small alpha),
//    low and wide for a rough one. Away from the peak it falls off as
//    a power of tan(theta_h) (about alpha^2 / (pi tan^4) once tan is a
//    few times alpha and the angle still small),
//    not exponentially, so a GGX highlight has a bright core and a soft
//    halo around it.
//
// Q: Why is alpha = roughness^2?
// A: ROUGHNESS is "perceptual": artists found that squaring it spreads the
//    visible change in equal steps over the slider (Burley 2012, Karis 2013).
//    Godot's built-in GGX uses alpha = roughness^2 as well. Rock here has
//    ROUGHNESS 0.92, alpha 0.85.
//
// Q: How do we know the formula is normalized?
// A: The projected area of all facets must equal the area of the macro
//    surface: the integral of D(h) (n.h) over the hemisphere is 1.
//    tests/test_17_brdf.gd checks it by numerical integration (README P4).
float ggx_distribution(float n_dot_h, float alpha) {
	float a2 = alpha * alpha;
	float d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d);
}


// Smith's Lambda for GGX: Lambda(s) = (sqrt(1 + alpha^2 tan^2 theta_s) - 1) / 2.
//
// Q: What does Lambda measure?
// A: Seen from direction s, the facets that turn their backs to s hide
//    part of the front-facing ones. Lambda is the ratio of that hidden
//    area to the visible projected area. It is 0 looking straight down
//    and grows toward grazing angles (tan theta -> infinity). The masking
//    of one direction is G1(s) = 1 / (1 + Lambda(s)).
float smith_lambda(float n_dot_s, float alpha) {
	float c2 = n_dot_s * n_dot_s;
	float tan2 = max(0.0, 1.0 - c2) / max(c2, 1e-6);
	return 0.5 * (sqrt(1.0 + alpha * alpha * tan2) - 1.0);
}


// Height-correlated Smith masking-shadowing (Heitz 2014).
//
// Q: Why not G1(l) * G1(v)?
// A: That product treats "hidden from the light" and "hidden from the eye"
//    as independent events. They are not: a facet that sits high above its
//    neighbors tends to be visible from both, one deep in a pit from
//    neither. Counting the height once gives
//        G2 = 1 / (1 + Lambda(l) + Lambda(v)),
//    which is never smaller than the product (README P5). Godot's built-in
//    GGX uses an approximation of this same G2 (Hammon 2017); README O5
//    compares the two.
float smith_g2(float n_dot_l, float n_dot_v, float alpha) {
	return 1.0 / (1.0 + smith_lambda(n_dot_l, alpha) + smith_lambda(n_dot_v, alpha));
}


// Schlick's Fresnel approximation: F = f0 + (1 - f0) (1 - cos)^5.
//
// Q: What is f0?
// A: The fraction of light a facet reflects when looked at head-on. For
//    stone, soil and most non-metals it is about 0.04: 4 percent is
//    reflected, the rest enters the material and comes back out (if at
//    all) as diffuse light. Toward grazing angles every surface becomes a
//    mirror, F -> 1: a lake at sunset, or a dusty road seen far ahead.
//    The fifth power is Schlick's fit to the exact Fresnel equations.
vec3 schlick_fresnel(vec3 f0, float cos_theta) {
	float m = clamp(1.0 - cos_theta, 0.0, 1.0);
	float m5 = m * m * m * m * m;
	return f0 + (vec3(1.0) - f0) * m5;
}


// The GGX specular lobe, times cos(theta_l):
//   D(h) G2(l, v) F(v.h) / (4 (n.l)(n.v)) * (n.l) = D G2 F / (4 (n.v))
vec3 ggx_specular_cosine(vec3 n, vec3 l, vec3 v, float roughness, vec3 f0) {
	float n_dot_l = dot(n, l);
	float n_dot_v = dot(n, v);
	if (n_dot_l <= 0.0 || n_dot_v <= 0.0) {
		return vec3(0.0);
	}
	vec3 h = normalize(l + v);
	float alpha = roughness * roughness;
	float d = ggx_distribution(max(dot(n, h), 0.0), alpha);
	float g = smith_g2(n_dot_l, n_dot_v, alpha);
	vec3 f = schlick_fresnel(f0, max(dot(v, h), 0.0));
	return d * g * f / (4.0 * n_dot_v);
}
