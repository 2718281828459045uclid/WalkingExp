extends SceneTree
## Lesson 15: checks the static parts of climbing.
##   1. ReachSolver: projections onto a ball and a half-space; two
##      overlapping balls give a common point; two separate balls leave
##      the gap as the residual; random feasible sets of three balls and
##      a half-space are solved.
##   2. Fabrik: bone lengths kept; the elbow stays in the plane of the
##      root, the target and the starting elbow; the converged elbow
##      equals TwoBoneIk's with the starting elbow as pole; a target
##      beyond reach gives the straight chain; a four-joint chain.
##   3. HoldFinder: the vertex tests; the score; knob and edge from the
##      principal curvatures; suppression keeps the best of each
##      neighborhood; refine() moves a point onto a sphere and measures
##      H = 1/r; refine() rejects a crease by its gradient; find() runs
##      the three stages on vertex data; in_reach() filters, excludes and
##      sorts.
##   4. ClimbBalanceMonitor.pull_ratio(): F/W = d/h, INF without feet,
##      NAN without hands or with the hands at the feet's height.
## Run: Godot --headless --path game -s res://tests/test_15_climb_math.gd

var _failures := 0


func _initialize() -> void:
	_check_reach_solver()
	_check_fabrik()
	_check_hold_finder()
	_check_pull_ratio()
	print("test_15_climb_math: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_reach_solver() -> void:
	var inside := ReachSolver.project_to_ball(Vector3(0.1, 0, 0), Vector3.ZERO, 1.0)
	_expect(inside == Vector3(0.1, 0, 0), "a point inside the ball stays")
	var outside := ReachSolver.project_to_ball(Vector3(3, 4, 0), Vector3.ZERO, 1.0)
	_expect(outside.is_equal_approx(Vector3(0.6, 0.8, 0)), "projection onto the ball: %s" % outside)
	var below := ReachSolver.project_to_half_space(Vector3(1, -2, 3), Vector3.ZERO, Vector3.UP)
	_expect(below.is_equal_approx(Vector3(1, 0, 3)), "projection onto the half-space: %s" % below)
	var above := ReachSolver.project_to_half_space(Vector3(1, 2, 3), Vector3.ZERO, Vector3.UP)
	_expect(above == Vector3(1, 2, 3), "a point in the half-space stays")

	var far_plane := Vector3(0, 0, -10)
	var centers := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	var overlap := ReachSolver.solve(Vector3(0.5, 1, 0), centers, PackedFloat32Array([0.6, 0.6]), far_plane, Vector3.BACK, 100, 1e-6)
	_expect(overlap.residual < 1e-4, "overlapping balls: residual %f" % overlap.residual)
	_expect(overlap.position.length() <= 0.6 + 1e-4 and overlap.position.distance_to(centers[1]) <= 0.6 + 1e-4, "point in both balls")
	var apart := ReachSolver.solve(Vector3(0.5, 1, 0), centers, PackedFloat32Array([0.4, 0.4]), far_plane, Vector3.BACK, 200, 1e-6)
	_expect(absf(apart.residual - 0.2) < 1e-3, "separate balls: residual %f is the gap 0.2" % apart.residual)

	# Random feasible problems: a point q, three balls that contain it, a
	# half-space that contains it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1501
	var worst := 0.0
	for trial in 300:
		var q := _random_vector(rng) * 2.0
		var c := PackedVector3Array()
		var r := PackedFloat32Array()
		for k in 3:
			var center := q + _random_vector(rng) * 0.8
			c.append(center)
			r.append(center.distance_to(q) + rng.randf_range(0.01, 0.3))
		var normal := _random_vector(rng).normalized()
		var plane := q - normal * rng.randf_range(0.0, 0.2)
		var result := ReachSolver.solve(q + _random_vector(rng) * 3.0, c, r, plane, normal, 200, 1e-7)
		worst = maxf(worst, result.residual)
	_expect(worst < 1e-3, "300 feasible sets: largest residual %f" % worst)


func _check_fabrik() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1502
	var lengths := PackedFloat32Array([0.29, 0.27])
	var worst_length := 0.0
	var worst_plane := 0.0
	var worst_elbow := 0.0
	var converged := 0
	for trial in 500:
		var root := Vector3.ZERO
		var elbow := _random_vector(rng).normalized() * 0.29
		var hand := elbow + _random_vector(rng).normalized() * 0.27
		var target := _random_vector(rng).normalized() * rng.randf_range(0.15, 0.53)
		var result := Fabrik.solve(PackedVector3Array([root, elbow, hand]), lengths, target, 1e-5, 200)
		var j := result.joints
		worst_length = maxf(worst_length, maxf(absf(j[0].distance_to(j[1]) - 0.29), absf(j[1].distance_to(j[2]) - 0.27)))
		var normal := target.cross(elbow).normalized()
		worst_plane = maxf(worst_plane, absf(j[1].dot(normal)))
		if result.error <= 1e-5:
			converged += 1
			var two := TwoBoneIk.solve(root, target, elbow, 0.29, 0.27)
			worst_elbow = maxf(worst_elbow, two.middle.distance_to(j[1]))
		_expect(j[0] == root, "root stays")
	_expect(worst_length < 1e-5, "bone lengths kept: %f" % worst_length)
	_expect(worst_plane < 1e-5, "elbow in the plane of root, target, start elbow: %f" % worst_plane)
	_expect(converged >= 490, "converged within 200 iterations: %d of 500" % converged)
	_expect(worst_elbow < 1e-3, "converged elbow equals TwoBoneIk with the start elbow as pole: %f" % worst_elbow)

	var far := Fabrik.solve(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.29, 0), Vector3(0, -0.56, 0)]), lengths, Vector3(1, 0, 0))
	_expect(not far.reachable, "a target 1 m away is out of reach")
	_expect(far.joints[2].is_equal_approx(Vector3(0.56, 0, 0)), "straight chain toward the target: %s" % far.joints[2])
	_expect(absf(far.error - 0.44) < 1e-5, "error is the shortfall: %f" % far.error)

	var chain := PackedVector3Array([Vector3.ZERO, Vector3(0, -0.3, 0), Vector3(0, -0.6, 0), Vector3(0, -0.9, 0)])
	var long := Fabrik.solve(chain, Fabrik.lengths(chain), Vector3(0.4, -0.4, 0.2), 1e-5, 50)
	_expect(long.error <= 1e-5, "four-joint chain reaches: error %f after %d iterations" % [long.error, long.iterations])
	var long_lengths := Fabrik.lengths(long.joints)
	_expect(absf(long_lengths[0] - 0.3) < 1e-5 and absf(long_lengths[2] - 0.3) < 1e-5, "four-joint chain keeps lengths")


func _check_hold_finder() -> void:
	var c := HoldFinder.Criteria.new()
	c.face = Vector3.BACK
	c.min_facing = 0.2
	var up_and_out := Vector3(0, 0.7, 0.7).normalized()
	_expect(HoldFinder.passes(10.0, up_and_out, c), "a bump facing up and out passes")
	_expect(not HoldFinder.passes(1.0, up_and_out, c), "a flat face fails (H below min)")
	_expect(not HoldFinder.passes(-50.0, up_and_out, c), "a hollow fails")
	_expect(not HoldFinder.passes(100.0, up_and_out, c), "a crease fails (H above max)")
	_expect(not HoldFinder.passes(10.0, Vector3(0, 0.2, 0.98).normalized(), c), "a normal 11.5 deg above horizontal fails")
	_expect(not HoldFinder.passes(10.0, Vector3(0, 0.99, 0.1).normalized(), c), "a normal facing up but not out fails")
	_expect(not HoldFinder.passes(10.0, Vector3(0, 0.7, -0.7).normalized(), c), "the back of the rock fails")
	_expect(is_equal_approx(HoldFinder.score(10.0, Vector3(0, 0.6, 0.8)), 6.0), "score H n.y")
	_expect(HoldFinder.score(10.0, Vector3(0, -0.6, 0.8)) == 0.0, "score 0 facing down")
	_expect(HoldFinder.classify(5.0, 5.0, 0.25) == HoldFinder.Kind.KNOB, "sphere: knob")
	_expect(HoldFinder.classify(8.3, 0.0, 0.25) == HoldFinder.Kind.EDGE, "cylinder: edge")
	_expect(HoldFinder.classify(8.0, -1.0, 0.25) == HoldFinder.Kind.EDGE, "saddle: edge")

	# Suppression: a line of candidates 0.05 m apart, scores falling.
	var line: Array[HoldFinder.Hold] = []
	for k in 10:
		var hold := HoldFinder.Hold.new()
		hold.position = Vector3(0.05 * k, 0, 0)
		hold.score = 10.0 - k
		line.append(hold)
	var kept := HoldFinder.suppress(line, 0.2)
	_expect(kept.size() == 3 and kept[0] == line[0] and kept[1] == line[4] and kept[2] == line[8], "suppression keeps 0, 4, 8 of 10")

	# Refinement on a sphere of radius 0.3: start 0.04 m outside.
	var sphere := SdfSphere.new()
	sphere.center = Vector3(1, 2, 3)
	sphere.radius = 0.3
	var on_sphere := HoldFinder.Hold.new()
	var direction := Vector3(0, 0.8, 0.6)
	on_sphere.position = sphere.center + direction * 0.34
	var sc := HoldFinder.Criteria.new()
	var accepted := HoldFinder.refine(sphere, on_sphere, sc)
	_expect(accepted, "sphere point accepted")
	_expect(absf(sphere.evaluate(on_sphere.position)) < 1e-5, "refined onto the surface: f = %f" % sphere.evaluate(on_sphere.position))
	_expect(absf(on_sphere.mean - 1.0 / 0.3) < 0.05, "H = 1/r: %f" % on_sphere.mean)
	_expect(on_sphere.normal.distance_to(direction) < 1e-3, "normal along the radius")
	_expect(on_sphere.kind == HoldFinder.Kind.KNOB, "a sphere is a knob")

	# Refinement at a crease: union of two unit spheres whose normals meet
	# at 143.6 degrees. Central differences give |g| = cos(71.8 deg) = 0.31.
	var a := SdfSphere.new()
	a.center = Vector3(-0.95, 0, 0)
	var b := SdfSphere.new()
	b.center = Vector3(0.95, 0, 0)
	var union := SdfUnion.new()
	union.shapes = [a, b]
	var lenient := HoldFinder.Criteria.new()
	lenient.min_mean = -INF
	lenient.max_mean = INF
	lenient.min_up = -1.0
	var crease := HoldFinder.Hold.new()
	crease.position = Vector3(0, sqrt(1.0 - 0.95 * 0.95), 0)
	_expect(not HoldFinder.refine(union, crease, lenient), "crease rejected by the gradient test")
	_expect(absf(crease.gradient_length - 0.3122) < 0.01, "crease |g| = %f" % crease.gradient_length)
	lenient.min_gradient = 0.0
	crease.position = Vector3(0, sqrt(1.0 - 0.95 * 0.95), 0)
	_expect(HoldFinder.refine(union, crease, lenient), "without the gradient test the crease passes")

	# find() on vertex data of the sphere: two vertices on its upper front
	# 0.05 m apart (one hold after suppression), one on its underside
	# (fails the up test). The vertices lie 0.01 m outside the surface.
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var means := PackedFloat32Array()
	for n in [Vector3(0, 0.8, 0.6), Vector3(0.1, 0.8, 0.6).normalized(), Vector3(0, -0.8, 0.6)]:
		positions.append(sphere.center + n * 0.31)
		normals.append(n)
		means.append(1.0 / 0.31)
	var face_criteria := HoldFinder.Criteria.new()
	face_criteria.face = Vector3.BACK
	face_criteria.min_facing = 0.2
	var found_on_sphere := HoldFinder.find(sphere, positions, normals, means, face_criteria)
	_expect(found_on_sphere.size() == 1, "find(): one hold from three vertices: %d" % found_on_sphere.size())
	if found_on_sphere.size() == 1:
		var hold := found_on_sphere[0]
		_expect(absf(sphere.evaluate(hold.position)) < 1e-5 and absf(hold.mean - 1.0 / 0.3) < 0.05, "find(): refined onto the sphere, H = %f" % hold.mean)
		_expect(hold.normal.distance_to(Vector3(0, 0.8, 0.6)) < 1e-3, "find(): the best-scored vertex survives")

	# Reach queries.
	var holds: Array[HoldFinder.Hold] = []
	for k in 5:
		var hold := HoldFinder.Hold.new()
		hold.position = Vector3(0.2 * k, 0, 0)
		holds.append(hold)
	var found := HoldFinder.in_reach(holds, Vector3.ZERO, 0.65, Vector3(0.6, 0, 0), [holds[3]])
	_expect(found.size() == 3, "three holds in reach, one excluded: %d" % found.size())
	_expect(found.size() == 3 and found[0] == holds[2] and found[2] == holds[0], "sorted by distance to the aim")


func _check_pull_ratio() -> void:
	var hands := PackedVector3Array([Vector3(-0.2, 2.0, 0.0), Vector3(0.2, 2.0, 0.0)])
	var feet := PackedVector3Array([Vector3(-0.2, 1.0, 0.0), Vector3(0.2, 1.0, 0.0)])
	var com := Vector3(0.0, 1.5, 0.25)
	var ratio := ClimbBalanceMonitor.pull_ratio(com, hands, feet, Vector3.BACK)
	_expect(is_equal_approx(ratio, 0.25), "F/W = d/h = 0.25 / 1.0: %f" % ratio)
	_expect(is_inf(ClimbBalanceMonitor.pull_ratio(com, hands, PackedVector3Array(), Vector3.BACK)), "no feet: INF")
	_expect(is_nan(ClimbBalanceMonitor.pull_ratio(com, PackedVector3Array(), feet, Vector3.BACK)), "no hands: NAN")
	_expect(is_nan(ClimbBalanceMonitor.pull_ratio(com, feet, feet, Vector3.BACK)), "hands at the feet's height: NAN")
	_expect(ClimbBalanceMonitor.pull_ratio(Vector3(0, 1.5, -0.1), hands, feet, Vector3.BACK) == 0.0, "center of mass behind the feet: 0")


func _random_vector(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
