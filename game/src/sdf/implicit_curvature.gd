class_name ImplicitCurvature
extends RefCounted
## Normal, Hessian, and curvature of the level set of an SdfShape through
## a point (Lesson 09). Static functions only.
##
## How the files relate:
##   sdf_shape.gd          evaluate(p); gradient(p, h) of Lesson 07
##   this file             second derivatives and the curvature formulas
##   curvature_mesher.gd   calls sample() once per mesh vertex
##
## Notation (README, section 2):
##   g = grad f                  (Vector3)
##   Hf = Hessian of f           (Basis; symmetric, so rows = columns)
##   n = g / |g|                 the unit normal, pointing outward
##   H = 1/2 div n               the mean curvature
##       = (|g|^2 tr Hf - g . Hf g) / (2 |g|^3)
##   K = g . adj(Hf) g / |g|^4   the Gaussian curvature
## With n outward, H = +1/r on a sphere of radius r (the convention of
## DDG 3.4, where normal curvature is df(X) . dN(X)). Goldman (2005),
## Eq. (4.2), uses the opposite sign: K_M = -H.

## Default step in meters for the differences of sample().
##
## Q: Why 0.01 m here, when SdfShape.gradient() uses 0.001?
## A: A second difference divides by h^2. evaluate() at a point near 5 m
##    is off by about 5e-7 m (32-bit Vector3 rounding of p + h); divided
##    by h^2 = 1e-6 that is an error near 0.5 per meter, as large as the
##    curvature being measured. With h = 0.01 it is near 0.005. The
##    truncation error grows as h^2 instead; README P4 and O5 measure
##    where the two balance.
const DEFAULT_STEP := 0.01


## Everything sample() measures at one point.
class Sample:
	var value := 0.0
	var gradient := Vector3.ZERO
	var hessian := Basis()
	var normal := Vector3.ZERO
	var mean := 0.0
	var gaussian := 0.0
	## Principal curvatures, k1 >= k2.
	var k1 := 0.0
	var k2 := 0.0


## Second derivatives by central differences.
##
## Q: Where does the diagonal formula come from?
## A: Taylor: f(p + h e) = f + h f' + h^2/2 f'' + h^3/6 f''' + ...
##    Add the expansion at -h: the odd terms cancel, so
##    f(p + h e) - 2 f(p) + f(p - h e) = h^2 f'' + O(h^4).
## Q: And the mixed derivative d2f/dx dy?
## A: Take the central difference in y of the central difference in x.
##    That uses the four corners (+-h, +-h) and divides by (2h)^2.
static func hessian(shape: SdfShape, p: Vector3, h: float = DEFAULT_STEP) -> Basis:
	var axes: Array[Vector3] = [Vector3(h, 0, 0), Vector3(0, h, 0), Vector3(0, 0, h)]
	var f0 := shape.evaluate(p)
	var m := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		var a := axes[i]
		m[i][i] = (shape.evaluate(p + a) - 2.0 * f0 + shape.evaluate(p - a)) / (h * h)
		for j in range(i + 1, 3):
			var b := axes[j]
			var mixed := shape.evaluate(p + a + b) - shape.evaluate(p + a - b) \
				- shape.evaluate(p - a + b) + shape.evaluate(p - a - b)
			m[i][j] = mixed / (4.0 * h * h)
			m[j][i] = m[i][j]
	return Basis(
		Vector3(m[0][0], m[1][0], m[2][0]),
		Vector3(m[0][1], m[1][1], m[2][1]),
		Vector3(m[0][2], m[1][2], m[2][2]))


## H = 1/2 div n for n = g / |g|.
##
## Q: Why is this half the divergence of n?
## A: div (g / |g|) = (div g) / |g| + g . grad(1 / |g|)
##                  = tr Hf / |g| - (g . Hf g) / |g|^3.
##    The first term counts the bending in all three directions; the
##    second removes the direction along n, in which the surface does
##    not bend. README section 3.2 derives it step by step.
static func mean_curvature(g: Vector3, hess: Basis) -> float:
	var len2 := float(g.length_squared())
	if len2 == 0.0:
		return 0.0
	var trace := float(hess.x.x + hess.y.y + hess.z.z)
	var along := float(g.dot(hess * g))
	return (len2 * trace - along) / (2.0 * pow(len2, 1.5))


## K = g . adj(Hf) g / |g|^4 (Goldman 2005, Eq. 4.1).
##
## Q: What is adj(Hf)?
## A: The adjugate: the transpose of the matrix of cofactors, so that
##    Hf adj(Hf) = det(Hf) I. For a symmetric matrix
##        | a d e |
##        | d b f |
##        | e f c |
##    the cofactors give the six terms below. Only the 2x2 minors appear:
##    K measures the bending in the plane perpendicular to g.
static func gaussian_curvature(g: Vector3, hess: Basis) -> float:
	var len2 := float(g.length_squared())
	if len2 == 0.0:
		return 0.0
	var a := float(hess.x.x)
	var b := float(hess.y.y)
	var c := float(hess.z.z)
	var d := float(hess.y.x)
	var e := float(hess.z.x)
	var f := float(hess.z.y)
	var gx := float(g.x)
	var gy := float(g.y)
	var gz := float(g.z)
	var quadratic := gx * gx * (b * c - f * f) + gy * gy * (a * c - e * e) \
		+ gz * gz * (a * b - d * d) + 2.0 * gx * gy * (e * f - c * d) \
		+ 2.0 * gx * gz * (d * f - b * e) + 2.0 * gy * gz * (d * e - a * f)
	return quadratic / (len2 * len2)


## Principal curvatures from H and K: the roots of k^2 - 2 H k + K = 0.
##
## Q: Why clamp the square root at zero?
## A: H^2 - K = ((k1 - k2) / 2)^2 is never negative in exact arithmetic.
##    At an umbilic (sphere) it is zero, and rounding can make it -1e-12.
static func principal_curvatures(mean: float, gaussian: float) -> Vector2:
	var spread := sqrt(maxf(mean * mean - gaussian, 0.0))
	return Vector2(mean + spread, mean - spread)


## Value, gradient, Hessian, normal and curvatures at p with one step h.
## Cost: 1 (value) + 6 (gradient) + 19 (Hessian) = 26 evaluations.
# EXERCISE (lesson 09): E2 — the gradient's six samples are the same
# points as the Hessian diagonal's; share them and count the evaluations.
static func sample(shape: SdfShape, p: Vector3, h: float = DEFAULT_STEP) -> Sample:
	var result := Sample.new()
	result.value = shape.evaluate(p)
	result.gradient = shape.gradient(p, h)
	result.hessian = hessian(shape, p, h)
	result.normal = result.gradient.normalized()
	result.mean = mean_curvature(result.gradient, result.hessian)
	result.gaussian = gaussian_curvature(result.gradient, result.hessian)
	var k := principal_curvatures(result.mean, result.gaussian)
	result.k1 = k.x
	result.k2 = k.y
	return result


## Closed-form H and K of a torus (R, r) at the tube angle theta, where
## theta = 0 is the outer equator. Used by the tests and README P3.
##   K = cos(theta) / (r (R + r cos(theta)))
##   H = (R + 2 r cos(theta)) / (2 r (R + r cos(theta)))
static func torus_curvatures(major: float, minor: float, theta: float) -> Vector2:
	var c := cos(theta)
	var ring := major + minor * c
	return Vector2((major + 2.0 * minor * c) / (2.0 * minor * ring), c / (minor * ring))
