extends SceneTree
## Lesson 07: checks the SDF library in src/sdf/ without a scene.
##   1. Sphere, box (sharp and rounded), capsule: exact distances at
##      chosen points; gradient() of a sphere has length 1.
##   2. Ellipsoid: zero on the surface, never more than the true distance
##      (brute force) for SCALED_SPHERE, sampled |grad f| <= 1;
##      GRADIENT reports an infinite Lipschitz bound.
##   3. smin(): equals min when |a - b| >= k, is k / 4 lower at a = b,
##      never above min; the smooth union of two spheres meets the y axis
##      at the height derived in the lesson.
##   4. Union, intersection, subtraction signs; transform (move, turn,
##      uniform scale); repetition with a count limit.
##   5. Displacement moves values by at most the amplitude; the boulder
##      Resources in data/rocks/ have sampled |grad f| below their bound
##      and contain their solid inside bounds().
## Run: Godot --headless --path game -s res://tests/test_07_sdf_shapes.gd

var _failures := 0


func _initialize() -> void:
	_check_primitives()
	_check_ellipsoid()
	_check_smooth_minimum()
	_check_operators()
	_check_rocks()
	print("test_07_sdf_shapes: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_primitives() -> void:
	var sphere := SdfSphere.new()
	sphere.center = Vector3(1, 2, 3)
	sphere.radius = 2.0
	_near(sphere.evaluate(Vector3(1, 2, 3)), -2.0, 1e-6, "sphere center")
	_near(sphere.evaluate(Vector3(1, 7, 3)), 3.0, 1e-6, "sphere above")
	_near(sphere.evaluate(Vector3(1, 2, 3) + Vector3(1, 1, 1).normalized() * 2.0), 0.0, 1e-6, "sphere surface")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 50:
		var p := Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		_near(sphere.gradient(p).length(), 1.0, 1e-3, "sphere |grad| at %s" % p)

	var box := SdfBox.new()
	_near(box.evaluate(Vector3(2, 0, 0)), 1.0, 1e-6, "box face")
	_near(box.evaluate(Vector3(2, 2, 0)), sqrt(2.0), 1e-6, "box edge")
	_near(box.evaluate(Vector3(2, 2, 2)), sqrt(3.0), 1e-6, "box corner")
	_near(box.evaluate(Vector3(0, 0.5, 0)), -0.5, 1e-6, "box inside")
	box.rounding = 0.25
	_near(box.evaluate(Vector3(2, 0, 0)), 1.0, 1e-6, "rounded box face")
	_near(box.evaluate(Vector3(2, 2, 2)), sqrt(3.0) * 1.25 - 0.25, 1e-6, "rounded box corner")

	var capsule := SdfCapsule.new()
	_near(capsule.evaluate(Vector3(2, 0.2, 0)), 1.5, 1e-6, "capsule side")
	_near(capsule.evaluate(Vector3(0, 3, 0)), 2.0, 1e-6, "capsule beyond end")


func _check_ellipsoid() -> void:
	var e := SdfEllipsoid.new()
	e.radii = Vector3(2, 0.5, 1)
	e.rotation_degrees = Vector3(10, 30, 0)
	e.center = Vector3(0.5, 1, 0)
	var to_world := Basis.from_euler(e.rotation_degrees * (PI / 180.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for estimate in [SdfEllipsoid.Estimate.SCALED_SPHERE, SdfEllipsoid.Estimate.GRADIENT]:
		e.estimate = estimate
		for i in 40:
			var theta := rng.randf_range(0.0, PI)
			var phi := rng.randf_range(0.0, TAU)
			var local := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * e.radii
			_near(e.evaluate(e.center + to_world * local), 0.0, 1e-5, "ellipsoid surface (estimate %d)" % estimate)
	_expect(e.lipschitz_bound() == INF, "GRADIENT estimate claims a finite bound")

	e.estimate = SdfEllipsoid.Estimate.SCALED_SPHERE
	_expect(e.lipschitz_bound() == 1.0, "SCALED_SPHERE bound is not 1")
	for i in 60:
		var p := e.center + Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		var truth := _ellipsoid_distance(e, to_world, p)
		var f := e.evaluate(p)
		_expect(signf(f) == signf(truth), "ellipsoid sign at %s" % p)
		_expect(absf(f) <= absf(truth) + 0.02, "ellipsoid estimate %f exceeds true %f" % [f, truth])
	for i in 2000:
		var p := e.center + Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		_expect(e.gradient(p).length() <= 1.0 + 1e-3, "ellipsoid |grad| > 1 at %s" % p)

	var round_one := SdfEllipsoid.new()
	round_one.radii = Vector3.ONE * 1.5
	_near(round_one.evaluate(Vector3(0, 4, 0)), 2.5, 1e-6, "ellipsoid with equal radii is a sphere")


## True signed distance to an ellipsoid by searching its surface on a
## grid of angles (accuracy about 0.01 m for these radii).
func _ellipsoid_distance(e: SdfEllipsoid, to_world: Basis, p: Vector3) -> float:
	var q := to_world.inverse() * (p - e.center)
	var best := INF
	for i in 120:
		var theta := PI * (i + 0.5) / 120.0
		for j in 240:
			var phi := TAU * j / 240.0
			var s := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * e.radii
			best = minf(best, (s - q).length())
	return best if (q / e.radii).length() >= 1.0 else -best


func _check_smooth_minimum() -> void:
	_near(SdfSmoothUnion.smin(1.0, 3.0, 0.5), 1.0, 0.0, "smin far apart")
	_near(SdfSmoothUnion.smin(2.0, 2.0, 0.5), 2.0 - 0.125, 1e-12, "smin at a = b")
	_near(SdfSmoothUnion.smin(2.0, 2.0, 0.0), 2.0, 0.0, "smin with k = 0")
	for i in 200:
		var a := -1.0 + i * 0.01
		_expect(SdfSmoothUnion.smin(a, 0.3, 0.5) <= minf(a, 0.3), "smin above min at a = %f" % a)

	var left := SdfSphere.new()
	left.center = Vector3(-0.5, 0, 0)
	var right := SdfSphere.new()
	right.center = Vector3(0.5, 0, 0)
	var blend := SdfSmoothUnion.new()
	blend.blend = 0.5
	blend.shapes = [left, right] as Array[SdfShape]
	# On the y axis both distances are sqrt(0.25 + y^2) - 1 and the
	# smooth union subtracts k / 4 = 0.125, so the surface is where
	# sqrt(0.25 + y^2) = 1.125.
	var y := sqrt(1.125 * 1.125 - 0.25)
	_near(blend.evaluate(Vector3(0, y, 0)), 0.0, 1e-6, "smooth union surface on the y axis")
	_near(blend.bounds().size.x, 3.25, 1e-6, "smooth union bounds grow by k / 4 on each side")

	# Two SCALED_SPHERE ellipsoids with radii (3, 1, 1): the estimate is
	# (k0 - 1) * 1 outside, a third of the true distance along x. At
	# x = 3.5 each child gives 0.1667 and the blend (k = 0.8) gives -0.033,
	# so bounds() must reach past x = 3.5, not stop at 3 + k / 4.
	var long_a := SdfEllipsoid.new()
	long_a.radii = Vector3(3, 1, 1)
	var long_b := SdfEllipsoid.new()
	long_b.radii = Vector3(3, 1, 1)
	var long_blend := SdfSmoothUnion.new()
	long_blend.blend = 0.8
	long_blend.shapes = [long_a, long_b] as Array[SdfShape]
	var tip := Vector3(3.5, 0, 0)
	_expect(long_blend.evaluate(tip) < 0.0, "blended ellipsoids reach x = 3.5")
	_expect(long_blend.bounds().has_point(tip), "smooth union bounds contain the blended ellipsoid tip")


func _check_operators() -> void:
	var a := SdfSphere.new()
	var b := SdfSphere.new()
	b.center = Vector3(1.5, 0, 0)
	var union := SdfUnion.new()
	union.shapes = [a, b] as Array[SdfShape]
	var meet := SdfIntersection.new()
	meet.shapes = [a, b] as Array[SdfShape]
	var cut := SdfSubtraction.new()
	cut.base = a
	cut.cutter = b
	var points := {
		"in a only": Vector3(-0.5, 0, 0),
		"in both": Vector3(0.75, 0, 0),
		"in b only": Vector3(2.0, 0, 0),
		"in neither": Vector3(0, 3, 0),
	}
	var expected_union := {"in a only": true, "in both": true, "in b only": true, "in neither": false}
	var expected_meet := {"in a only": false, "in both": true, "in b only": false, "in neither": false}
	var expected_cut := {"in a only": true, "in both": false, "in b only": false, "in neither": false}
	for key in points:
		var p: Vector3 = points[key]
		_expect((union.evaluate(p) < 0.0) == expected_union[key], "union, " + key)
		_expect((meet.evaluate(p) < 0.0) == expected_meet[key], "intersection, " + key)
		_expect((cut.evaluate(p) < 0.0) == expected_cut[key], "subtraction, " + key)

	var moved := SdfTransform.new()
	moved.shape = a
	moved.translation = Vector3(0, 5, 0)
	moved.scale = 2.0
	_near(moved.evaluate(Vector3(0, 5, 0)), -2.0, 1e-6, "scaled sphere center")
	_near(moved.evaluate(Vector3(3, 5, 0)), 1.0, 1e-6, "scaled sphere side")
	var long_box := SdfBox.new()
	long_box.half_extents = Vector3(2, 0.5, 0.5)
	var turned := SdfTransform.new()
	turned.shape = long_box
	turned.rotation_degrees = Vector3(0, 90, 0)
	# A turn of +90 degrees about y takes +x to -z.
	_near(turned.evaluate(Vector3(0, 0, -3)), 1.0, 1e-5, "turned box end")
	_near(turned.evaluate(Vector3(3, 0, 0)), 2.5, 1e-5, "turned box side")

	var repeat := SdfRepeat.new()
	var small := SdfSphere.new()
	small.radius = 0.5
	repeat.shape = small
	repeat.period = Vector3(4, 0, 4)
	repeat.count = Vector3i(1, 0, 1)
	_near(repeat.evaluate(Vector3(4, 0, -4)), -0.5, 1e-6, "copy at (4, 0, -4)")
	_near(repeat.evaluate(Vector3(8, 0, 0)), 3.5, 1e-6, "no copy beyond the count")
	_near(repeat.evaluate(Vector3(2, 0, 0)), 1.5, 1e-6, "halfway between copies")


func _check_rocks() -> void:
	var tor := load("res://data/rocks/tor_boulder.tres") as SdfDisplace
	_expect(tor != null, "tor_boulder.tres does not load as SdfDisplace")
	if tor == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 500:
		var p := Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 4), rng.randf_range(-3, 3))
		var change := absf(tor.evaluate(p) - tor.shape.evaluate(p))
		_expect(change <= tor.amplitude + 1e-9, "displacement %f > amplitude at %s" % [change, p])
	var expected_bound := 1.0 + tor.amplitude * tor.noise_slope_per_frequency * tor.noise.frequency
	_near(tor.lipschitz_bound(), expected_bound, 1e-9, "displaced bound")

	for path in ["res://data/rocks/tor_boulder.tres", "res://data/rocks/split_boulder.tres", "res://data/rocks/boulder_pile.tres"]:
		var shape := load(path) as SdfShape
		var box := shape.bounds()
		var bound := shape.lipschitz_bound()
		var largest := 0.0
		for i in 3000:
			var p := box.position - Vector3.ONE + Vector3(rng.randf(), rng.randf(), rng.randf()) * (box.size + Vector3.ONE * 2.0)
			largest = maxf(largest, shape.gradient(p).length())
			if shape.evaluate(p) <= 0.0:
				_expect(box.has_point(p), "%s: solid point %s outside bounds()" % [path, p])
		_expect(largest <= bound, "%s: sampled |grad| %f > bound %f" % [path, largest, bound])
		_expect(shape.evaluate(Vector3(-0.8, 1, 0)) < 0.0, "%s: (-0.8, 1, 0) is not inside" % path)
		_expect(shape.evaluate(Vector3(0, 20, 0)) > 10.0, "%s: (0, 20, 0) is not far outside" % path)


func _near(value: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(value - expected) <= tolerance, "%s: %f, expected %f" % [message, value, expected])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
