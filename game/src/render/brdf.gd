class_name Brdf
extends RefCounted
## CPU reference of the shading models in shaders/lighting/brdf.gdshaderinc
## (Lesson 17), and numerical integrals over the hemisphere that check them.
##
## How this file relates to the others:
##   shaders/lighting/brdf.gdshaderinc     the same formulas in GLSL, used by
##                                          shaders/lighting/custom_light.gdshaderinc
##   tests/test_17_brdf.gd                 white-furnace and normalization
##                                          checks of the functions below
##   tests/test_17_light_pixels.gd         (windowed) compares rendered pixels
##                                          with reflected() below
##
## Q: Why repeat shader math in GDScript?
## A: A shader returns pixels; the questions of this lesson are about
##    integrals ("how much light does the surface reflect in total?").
##    GDScript runs headless, in 64-bit floats, and can sum a function over
##    thousands of directions. If you change a formula in brdf.gdshaderinc,
##    change its copy here (Lesson 03's PaintMath follows the same rule).
##
## Conventions:
##   n, l, v   unit vectors: surface normal, direction TO the light,
##             direction TO the viewer. h = normalize(l + v).
##   A BRDF f(l, v) has units 1/sr. The light a surface sends toward v from
##   a directional light of irradiance E (measured on a plane facing the
##   light) is  f(l, v) * E * cos(theta_l).  The functions named
##   *_cosine() return f * cos(theta_l), the quantity the shader adds.
##   albedo (rho) is the diffuse reflectance in [0, 1].

## The shading models, numbered as the shader's light_model uniform.
enum Model {
	LAMBERT,     ## rho / pi
	WRAP,        ## Lambert with the terminator moved past 90 degrees
	OREN_NAYAR,  ## rough diffuse, qualitative model of Oren and Nayar (1994)
	GGX,         ## Lambert diffuse plus a GGX microfacet specular lobe
}

const MODEL_NAMES: Array[String] = ["Lambert", "wrap", "Oren-Nayar", "GGX"]


## Parameters shared by the models. Defaults match the uniforms of
## custom_light.gdshaderinc.
class Params:
	var albedo := 1.0
	var wrap := 0.5               ## w in (cos + w) / (1 + w)
	var sigma := deg_to_rad(30.0) ## Oren-Nayar facet slope deviation, radians
	var roughness := 0.92         ## perceptual roughness; alpha = roughness^2
	var f0 := 0.04                ## Fresnel reflectance at normal incidence


# ------------------------------------------------------------------ diffuse --

## Lambert: f = rho / pi, the same for every pair of directions.
static func lambert(albedo: float) -> float:
	return albedo / PI


## Q: What does wrap lighting change?
## A: It replaces cos(theta_l) by (cos(theta_l) + w) / (1 + w), clamped at 0.
##    The response is 1 facing the light, as Lambert's, and reaches 0 at
##    cos(theta_l) = -w instead of 0: the dark side starts past 90 degrees.
##    It is a response to the light direction, not a BRDF; this function
##    returns rho / pi times that response.
static func wrap_cosine(n_dot_l: float, albedo: float, w: float) -> float:
	return albedo / PI * maxf(0.0, (n_dot_l + w) / (1.0 + w))


## Oren-Nayar, qualitative model (Oren and Nayar 1994):
##   f = rho / pi * (A + B * max(0, cos(phi_v - phi_l)) * sin(alpha) * tan(beta))
##   A = 1 - 0.5 s^2 / (s^2 + 0.33),  B = 0.45 s^2 / (s^2 + 0.09)
## with s = sigma, alpha = max(theta_l, theta_v), beta = min(theta_l, theta_v).
## Returns f (not times cos). Zero below either horizon.
static func oren_nayar(n: Vector3, l: Vector3, v: Vector3, albedo: float, sigma: float) -> float:
	var n_dot_l := n.dot(l)
	var n_dot_v := n.dot(v)
	if n_dot_l <= 0.0 or n_dot_v <= 0.0:
		return 0.0
	var s2 := sigma * sigma
	var a := 1.0 - 0.5 * s2 / (s2 + 0.33)
	var b := 0.45 * s2 / (s2 + 0.09)
	return albedo / PI * (a + b * oren_nayar_angular(n, l, v))


## The angular factor max(0, cos(phi_v - phi_l)) * sin(alpha) * tan(beta).
##
## Q: How is cos(phi_v - phi_l) found without angles?
## A: Project l and v into the tangent plane (remove their n parts) and take
##    the cosine between the projections. If either lies along n, its
##    azimuth is undefined and sin(theta) = 0 kills the term anyway.
##
## Q: How are sin(alpha) and tan(beta) found without acos?
## A: alpha is the larger angle, so cos(alpha) is the smaller cosine; beta
##    is the smaller angle, so cos(beta) is the larger cosine. Then
##    sin = sqrt(1 - cos^2) and tan = sin / cos.
static func oren_nayar_angular(n: Vector3, l: Vector3, v: Vector3) -> float:
	var n_dot_l := n.dot(l)
	var n_dot_v := n.dot(v)
	var l_flat := l - n * n_dot_l
	var v_flat := v - n * n_dot_v
	var lengths := l_flat.length() * v_flat.length()
	if lengths < 1e-12:
		return 0.0
	var cos_phi := maxf(0.0, l_flat.dot(v_flat) / lengths)
	var cos_alpha := minf(n_dot_l, n_dot_v)
	var cos_beta := maxf(n_dot_l, n_dot_v)
	var sin_alpha := sqrt(maxf(0.0, 1.0 - cos_alpha * cos_alpha))
	var tan_beta := sqrt(maxf(0.0, 1.0 - cos_beta * cos_beta)) / cos_beta
	return cos_phi * sin_alpha * tan_beta


# ----------------------------------------------------------------- specular --

## GGX (Trowbridge-Reitz) distribution of microfacet normals:
##   D(h) = alpha^2 / (pi * ((n.h)^2 (alpha^2 - 1) + 1)^2)
## Normalized so that the integral of D(h) (n.h) over the hemisphere is 1.
static func ggx_distribution(n_dot_h: float, alpha: float) -> float:
	if n_dot_h <= 0.0:
		return 0.0
	var a2 := alpha * alpha
	var d := n_dot_h * n_dot_h * (a2 - 1.0) + 1.0
	return a2 / (PI * d * d)


## Smith's Lambda for GGX, for a direction s at cos(theta) = n_dot_s:
##   Lambda = (sqrt(1 + alpha^2 tan^2(theta)) - 1) / 2
static func smith_lambda(n_dot_s: float, alpha: float) -> float:
	var c2 := n_dot_s * n_dot_s
	var tan2 := maxf(0.0, 1.0 - c2) / maxf(c2, 1e-12)
	return 0.5 * (sqrt(1.0 + alpha * alpha * tan2) - 1.0)


## Masking G1(s) = 1 / (1 + Lambda(s)): the fraction of facets of normal h
## (h.s > 0) that the direction s sees.
static func smith_masking(n_dot_s: float, alpha: float) -> float:
	return 1.0 / (1.0 + smith_lambda(n_dot_s, alpha))


## Height-correlated masking-shadowing (Heitz 2014):
##   G2(l, v) = 1 / (1 + Lambda(l) + Lambda(v))
## A facet high on the surface is seen by both directions more often than
## two independent G1 factors predict; this form counts that once.
static func smith_height_correlated(n_dot_l: float, n_dot_v: float, alpha: float) -> float:
	return 1.0 / (1.0 + smith_lambda(n_dot_l, alpha) + smith_lambda(n_dot_v, alpha))


## Schlick's approximation of Fresnel reflectance:
##   F = f0 + (1 - f0) (1 - cos)^5,  cos = l.h = v.h
static func schlick_fresnel(f0: float, cos_theta: float) -> float:
	var m := clampf(1.0 - cos_theta, 0.0, 1.0)
	return f0 + (1.0 - f0) * m * m * m * m * m


## GGX specular BRDF: D(h) G2(l, v) F(v.h) / (4 (n.l) (n.v)). Not times cos.
static func ggx_specular(n: Vector3, l: Vector3, v: Vector3, roughness: float, f0: float) -> float:
	var n_dot_l := n.dot(l)
	var n_dot_v := n.dot(v)
	if n_dot_l <= 0.0 or n_dot_v <= 0.0:
		return 0.0
	var h := (l + v).normalized()
	var alpha := roughness * roughness
	var d := ggx_distribution(n.dot(h), alpha)
	var g := smith_height_correlated(n_dot_l, n_dot_v, alpha)
	var f := schlick_fresnel(f0, v.dot(h))
	return d * g * f / (4.0 * n_dot_l * n_dot_v)


# ------------------------------------------------------------ whole models --

## f * cos(theta_l) of the diffuse part of a model, per unit irradiance.
## This is what the shader adds to DIFFUSE_LIGHT, times albedo (which the
## engine applies after light(); README section 3.2).
static func diffuse_cosine(model: Model, n: Vector3, l: Vector3, v: Vector3, p: Params) -> float:
	var n_dot_l := n.dot(l)
	match model:
		Model.WRAP:
			return wrap_cosine(n_dot_l, p.albedo, p.wrap)
		Model.OREN_NAYAR:
			return oren_nayar(n, l, v, p.albedo, p.sigma) * maxf(n_dot_l, 0.0)
		_:
			return lambert(p.albedo) * maxf(n_dot_l, 0.0)


## f * cos(theta_l) of the specular part (GGX model only, else 0).
static func specular_cosine(model: Model, n: Vector3, l: Vector3, v: Vector3, p: Params) -> float:
	if model != Model.GGX:
		return 0.0
	return ggx_specular(n, l, v, p.roughness, p.f0) * maxf(n.dot(l), 0.0)


## The value a pixel takes under one directional light of energy E, with no
## ambient light, Linear tonemapping and exposure 1 (README section 3.2):
##   pixel = pi * E * (diffuse_cosine + specular_cosine)
## Godot's LIGHT_COLOR already holds the factor pi (measured).
static func reflected(model: Model, n: Vector3, l: Vector3, v: Vector3, p: Params, energy: float = 1.0) -> float:
	return PI * energy * (diffuse_cosine(model, n, l, v, p) + specular_cosine(model, n, l, v, p))


# ---------------------------------------------------------------- integrals --

## Directional albedo of a model: the fraction of light, arriving with
## equal radiance from every direction above the surface, that leaves
## toward v.
##   E(v) = integral over the hemisphere of f(l, v) cos(theta_l) d omega_l
## A "white furnace": a surface inside a sphere of constant radiance reflects at
## most what it receives, so E(v) <= 1 for albedo 1 if the model conserves
## energy.
##
## Q: How is the hemisphere cut into pieces?
## A: With mu = cos(theta), the solid angle is d omega = d mu d phi (the
##    sin(theta) d theta of spherical coordinates is -d mu). A grid of
##    equal steps in mu in [mu_min, 1] and phi in [0, 2 pi) has cells of
##    equal solid angle; the midpoint of each cell stands for the cell.
##    mu_min = 0 is the hemisphere; mu_min = -1 the whole sphere (wrap
##    lighting also answers light from below the horizon).
static func directional_albedo(model: Model, v: Vector3, p: Params, mu_steps: int = 256, phi_steps: int = 256, mu_min: float = 0.0) -> float:
	var n := Vector3.UP
	var d_mu := (1.0 - mu_min) / mu_steps
	var d_phi := TAU / phi_steps
	var total := 0.0
	for i in mu_steps:
		var mu := mu_min + (i + 0.5) * d_mu
		var s := sqrt(maxf(0.0, 1.0 - mu * mu))
		for j in phi_steps:
			var phi := (j + 0.5) * d_phi
			var l := Vector3(s * cos(phi), mu, s * sin(phi))
			total += diffuse_cosine(model, n, l, v, p) + specular_cosine(model, n, l, v, p)
	return total * d_mu * d_phi


## Integral of D(h) (n.h) over the hemisphere of h; equals 1 for a
## normalized distribution. D depends on theta_h alone, so the phi integral
## is 2 pi and one loop over theta remains:
##   2 pi * integral_0^(pi/2) D(cos t) cos t sin t dt
## Steps in theta (not in mu) follow the narrow peak of a smooth surface,
## whose width is about alpha radians.
static func ggx_normalization(alpha: float, steps: int = 4096) -> float:
	var dt := 0.5 * PI / steps
	var total := 0.0
	for i in steps:
		var t := (i + 0.5) * dt
		total += ggx_distribution(cos(t), alpha) * cos(t) * sin(t)
	return TAU * total * dt


## Integral of max(0, v.h) D(h) over the hemisphere of h, divided by
## cos(theta_v). Smith's Lambda is defined by
##   integral max(0, v.h) D(h) d omega_h = (1 + Lambda(v)) cos(theta_v)
## (the facets seen from v cover the projected area cos(theta_v), plus the
## back-facing area Lambda hides). The function returns the integral's
## left side divided by cos(theta_v), to compare with 1 + Lambda(v).
static func projected_facet_area(v: Vector3, alpha: float, theta_steps: int = 1024, phi_steps: int = 256) -> float:
	var dt := 0.5 * PI / theta_steps
	var d_phi := TAU / phi_steps
	var total := 0.0
	for i in theta_steps:
		var t := (i + 0.5) * dt
		var d := ggx_distribution(cos(t), alpha) * sin(t)
		for j in phi_steps:
			var phi := (j + 0.5) * d_phi
			var h := Vector3(sin(t) * cos(phi), cos(t), sin(t) * sin(phi))
			total += maxf(0.0, v.dot(h)) * d
	return total * dt * d_phi / v.y


## Directional albedo of the GGX specular lobe alone (diffuse left out),
## with f0 = 1 (every facet a perfect mirror) unless given.
##
## Q: Why not the mu-phi grid of directional_albedo()?
## A: A smooth surface reflects into a lobe a few degrees wide; an even grid
##    would put few cells inside it. Instead the grid is laid over the
##    facet normals h in proportion to D(h)(n.h) (the inverse of its
##    cumulative distribution: tan^2(theta_h) = alpha^2 u / (1 - u)), each
##    h is turned into the mirror direction l = 2 (v.h) h - v, and each
##    cell's value is divided by the probability of picking it. For GGX the
##    quotient simplifies to F G2 (v.h) / ((n.v)(n.h)).
static func ggx_specular_albedo(v: Vector3, roughness: float, f0: float = 1.0, u_steps: int = 256, phi_steps: int = 128) -> float:
	var n := Vector3.UP
	var alpha := roughness * roughness
	var total := 0.0
	for i in u_steps:
		var u := (i + 0.5) / u_steps
		var theta := atan(alpha * sqrt(u / (1.0 - u)))
		for j in phi_steps:
			var phi := TAU * (j + 0.5) / phi_steps
			var h := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			var v_dot_h := v.dot(h)
			if v_dot_h <= 0.0:
				continue
			var l := 2.0 * v_dot_h * h - v
			if l.y <= 0.0:
				continue
			var g := smith_height_correlated(l.y, v.y, alpha)
			total += schlick_fresnel(f0, v_dot_h) * g * v_dot_h / (v.y * h.y)
	return total / (u_steps * phi_steps)


## Unit vector at angle theta from the normal (+y), in the x-y plane.
static func direction(theta: float, phi: float = 0.0) -> Vector3:
	return Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
