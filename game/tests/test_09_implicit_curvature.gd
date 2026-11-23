extends SceneTree
## Lesson 09: checks ImplicitCurvature (src/sdf/implicit_curvature.gd)
## and SdfTorus (src/sdf/sdf_torus.gd) against closed-form answers.
##   1. Formulas alone, with an exact gradient and Hessian: the sphere
##      f = |p| - r gives H = 1/r, K = 1/r^2 at any point of the surface.
##   2. Sphere of radius 1.5, numerical sample() at 100 directions, at
##      the origin and moved to (5, 5, 5): |H - 1/r| and |K - 1/r^2|
##      below 0.01 with the default step.
##   3. Torus R = 1, r = 0.25 around the tube: H and K against
##      torus_curvatures(); K changes sign; normals against the analytic
##      gradient within 0.1 degree.
##   4. The Hessian of a linear field is zero; that of the quadratic
##      x^2 + 2 y z is returned exactly (up to rounding).
##   5. principal_curvatures() inverts (H, K), and clamps at umbilics.
##   6. A field that is not a distance, f = |p|^2 - r^2 (Goldman's
##      Example 4.1), gives the same H and K as the distance field.
## Run: Godot --headless --path game -s res://tests/test_09_implicit_curvature.gd

var _failures := 0


func _initialize() -> void:
	_check_formulas()
	_check_sphere()
	_check_torus()
	_check_hessian()
	_check_principal()
	_check_squared_sphere()
	print("test_09_implicit_curvature: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_formulas() -> void:
	# For f = |p| - r: grad f = p / |p|, Hessian = (I - n n^T) / |p|.
	var r := 2.0
	var p := Vector3(1.2, -0.8, 1.4).normalized() * r
	var n := p.normalized()
	var outer := Basis(n * n.x, n * n.y, n * n.z)
	var hess := Basis()
	for i in 3:
		hess[i] = (Basis.IDENTITY[i] - outer[i]) / r
	_near(ImplicitCurvature.mean_curvature(n, hess), 1.0 / r, 1e-6, "exact sphere H")
	_near(ImplicitCurvature.gaussian_curvature(n, hess), 1.0 / (r * r), 1e-6, "exact sphere K")
	# Scaling f by c > 0 changes neither (Goldman 2005, after Eq. 4.5).
	_near(ImplicitCurvature.mean_curvature(n * 3.0, hess * 3.0), 1.0 / r, 1e-6, "H of 3 f")
	_near(ImplicitCurvature.gaussian_curvature(n * 3.0, hess * 3.0), 1.0 / (r * r), 1e-6, "K of 3 f")
	# -f flips the normal and the sign of H, not K.
	_near(ImplicitCurvature.mean_curvature(-n, hess * -1.0), -1.0 / r, 1e-6, "H of -f")
	_near(ImplicitCurvature.gaussian_curvature(-n, hess * -1.0), 1.0 / (r * r), 1e-6, "K of -f")


func _check_sphere() -> void:
	var sphere := SdfSphere.new()
	sphere.radius = 1.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for center in [Vector3.ZERO, Vector3(5, 5, 5)]:
		sphere.center = center
		var worst_h := 0.0
		var worst_k := 0.0
		for i in 100:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var s := ImplicitCurvature.sample(sphere, center + d * 1.5)
			worst_h = maxf(worst_h, absf(s.mean - 1.0 / 1.5))
			worst_k = maxf(worst_k, absf(s.gaussian - 1.0 / 2.25))
		_expect(worst_h < 0.01, "sphere at %s: H error %f" % [center, worst_h])
		_expect(worst_k < 0.01, "sphere at %s: K error %f" % [center, worst_k])


func _check_torus() -> void:
	var torus := SdfTorus.new()
	torus.major_radius = 1.0
	torus.minor_radius = 0.25
	var worst_h := 0.0
	var worst_k := 0.0
	var worst_angle := 0.0
	var smallest_k := INF
	var largest_k := -INF
	for i in 72:
		var theta := TAU * i / 72.0
		var phi := 0.7 * i
		var rho := 1.0 + 0.25 * cos(theta)
		var p := Vector3(rho * cos(phi), 0.25 * sin(theta), rho * sin(phi))
		var s := ImplicitCurvature.sample(torus, p)
		var exact := ImplicitCurvature.torus_curvatures(1.0, 0.25, theta)
		worst_h = maxf(worst_h, absf(s.mean - exact.x))
		worst_k = maxf(worst_k, absf(s.gaussian - exact.y))
		worst_angle = maxf(worst_angle, rad_to_deg(s.normal.angle_to(torus.analytic_gradient(p))))
		smallest_k = minf(smallest_k, s.gaussian)
		largest_k = maxf(largest_k, s.gaussian)
	_expect(worst_h < 0.01, "torus H error %f" % worst_h)
	_expect(worst_k < 0.05, "torus K error %f" % worst_k)
	_expect(worst_angle < 0.1, "torus normal angle %f deg" % worst_angle)
	_expect(smallest_k < -5.0 and largest_k > 3.0, "torus K range %f..%f" % [smallest_k, largest_k])
	# The analytic gradient is a unit vector (exact distance).
	_near(torus.analytic_gradient(Vector3(1.3, 0.1, 0.2)).length(), 1.0, 1e-6, "|analytic gradient|")


func _check_hessian() -> void:
	var plane := SdfBox.new()
	plane.half_extents = Vector3(10, 10, 10)
	# Inside the box near one face the field is linear: f = x - 10.
	var linear := ImplicitCurvature.hessian(plane, Vector3(9.5, 0.3, -0.2))
	for i in 3:
		_expect(linear[i].length() < 1e-3, "linear field Hessian column %d: %s" % [i, linear[i]])
	var quadratic := Quadratic.new()
	var q := ImplicitCurvature.hessian(quadratic, Vector3(0.3, -0.4, 0.5))
	_near(q.x.x, 2.0, 1e-3, "d2/dx2 of x^2 + 2yz")
	_near(q.z.y, 2.0, 1e-3, "d2/dydz of x^2 + 2yz")
	_near(q.y.z, 2.0, 1e-3, "d2/dzdy of x^2 + 2yz")
	_near(q.y.y + q.z.z + q.y.x + q.z.x, 0.0, 1e-3, "zero entries of x^2 + 2yz")


## The result is a Vector2, so 32-bit: 0.8 comes back as 0.800000011920929.
func _check_principal() -> void:
	var k := ImplicitCurvature.principal_curvatures(2.4, 3.2)
	_near(k.x, 4.0, 1e-6, "k1 of torus outer equator")
	_near(k.y, 0.8, 1e-6, "k2 of torus outer equator")
	var umbilic := ImplicitCurvature.principal_curvatures(1.0, 1.0 + 1e-12)
	_near(umbilic.x, 1.0, 1e-6, "umbilic k1")


## Q: Why test a field that is not a distance?
## A: For an exact distance |grad f| = 1 everywhere, so Hf g = 0 and the
##    term g . Hf g of the mean curvature vanishes. Only a field whose
##    gradient length varies along n tests that term.
func _check_squared_sphere() -> void:
	var squared := SquaredSphere.new()
	var worst_h := 0.0
	var worst_k := 0.0
	for i in 20:
		var d := Vector3(cos(i * 0.9), sin(i * 1.3), cos(i * 2.1)).normalized()
		var s := ImplicitCurvature.sample(squared, d * 1.5)
		worst_h = maxf(worst_h, absf(s.mean - 1.0 / 1.5))
		worst_k = maxf(worst_k, absf(s.gaussian - 1.0 / 2.25))
	_expect(worst_h < 0.01, "squared sphere H error %f" % worst_h)
	_expect(worst_k < 0.01, "squared sphere K error %f" % worst_k)


## f = |p|^2 - 1.5^2: the sphere of radius 1.5 as a field that grows
## quadratically; |grad f| = 2 |p|.
class SquaredSphere:
	extends SdfShape

	func evaluate(p: Vector3) -> float:
		return p.length_squared() - 2.25


## f = x^2 + 2 y z: a field with a known, constant Hessian.
class Quadratic:
	extends SdfShape

	func evaluate(p: Vector3) -> float:
		return p.x * p.x + 2.0 * p.y * p.z


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _near(a: float, b: float, tolerance: float, message: String) -> void:
	_expect(absf(a - b) <= tolerance, "%s: %f vs %f" % [message, a, b])
