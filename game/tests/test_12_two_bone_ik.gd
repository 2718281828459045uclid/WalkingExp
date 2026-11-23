extends SceneTree
## Lesson 12: checks TwoBoneIk and the swing helpers of FootRig.
##   1. Reachable targets: the end lands on the target, both bones keep
##      their lengths, the middle joint lies on the pole's side, and the
##      angles satisfy the law of cosines.
##   2. Out of reach (too far, too close): reached is false and the chain
##      points at the target.
##   3. leg_bases() and foot_basis() give the identity at rest; the bases
##      are rotations whose -y axes run along the bones.
##   4. limit_tilt(), swing_progress(), swing_ease().
## Run: Godot --headless --path game -s res://tests/test_12_two_bone_ik.gd

const A := 0.44
const B := 0.42

var _failures := 0


func _initialize() -> void:
	_check_reachable()
	_check_out_of_reach()
	_check_bases()
	_check_helpers()
	print("test_12_two_bone_ik: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_reachable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var worst_end := 0.0
	var worst_length := 0.0
	var worst_cosine := 0.0
	var pole_side_ok := true
	for i in 500:
		var root := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var d := rng.randf_range(absf(A - B) + 0.01, A + B - 0.01)
		var target := root + d * direction
		var pole := root + Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		var s := TwoBoneIk.solve(root, target, pole, A, B)
		_expect(s.reached, "reachable target %d reported unreached" % i)
		worst_end = maxf(worst_end, s.end.distance_to(target))
		worst_length = maxf(worst_length, absf(s.middle.distance_to(root) - A))
		worst_length = maxf(worst_length, absf(s.middle.distance_to(s.end) - B))
		# Law of cosines at the middle joint.
		worst_cosine = maxf(worst_cosine, absf(d * d - (A * A + B * B - 2.0 * A * B * cos(s.middle_angle))))
		# The middle joint lies on the pole's side of the line root -> target.
		var u := direction
		var to_pole := (pole - root) - (pole - root).dot(u) * u
		var to_middle := (s.middle - root) - (s.middle - root).dot(u) * u
		if to_pole.length() > 1e-3 and to_middle.dot(to_pole) <= 0.0:
			pole_side_ok = false
	_expect(worst_end < 1e-5, "end on target, worst %s m" % worst_end)
	_expect(worst_length < 1e-5, "bone lengths kept, worst %s m" % worst_length)
	_expect(worst_cosine < 1e-5, "law of cosines, worst %s" % worst_cosine)
	_expect(pole_side_ok, "middle joint on the pole's side")


func _check_out_of_reach() -> void:
	var root := Vector3(0, 1, 0)
	var pole := Vector3(0, 0.5, -1)
	var far := TwoBoneIk.solve(root, Vector3(0, -1, 0), pole, A, B)
	_expect(not far.reached, "far target unreached")
	_expect(absf(far.end.distance_to(root) - (A + B)) < 1e-3, "far: chain stretched to a + b")
	_expect(far.end.x == 0.0 and far.end.y < root.y, "far: chain points at the target")
	var near := TwoBoneIk.solve(root, root + Vector3(0, -0.01, 0), pole, A, B)
	_expect(not near.reached, "near target unreached")
	_expect(absf(near.end.distance_to(root) - absf(A - B)) < 1e-3, "near: chain folded to |a - b|")


func _check_bases() -> void:
	var hip := Vector3(0.1, 0.94, 0.0)
	var pole := hip + Vector3(0, -A, -1)
	# A straight leg is clamped STRAIGHT_MARGIN short of a + b, so the knee
	# keeps a bend of a fraction of a degree.
	var rest := TwoBoneIk.solve(hip, hip + Vector3(0, -(A + B), 0), pole, A, B)
	var bases := TwoBoneIk.leg_bases(rest, pole)
	_expect(_basis_error(bases[0], Basis.IDENTITY) < 0.05, "rest upper basis is identity")
	_expect(_basis_error(bases[1], Basis.IDENTITY) < 0.05, "rest lower basis is identity")
	_expect(_basis_error(TwoBoneIk.foot_basis(Vector3.UP, Vector3.FORWARD), Basis.IDENTITY) < 1e-6, "flat foot basis is identity")

	var bent := TwoBoneIk.solve(hip, hip + Vector3(0.05, -0.6, -0.2), pole, A, B)
	bases = TwoBoneIk.leg_bases(bent, pole)
	for basis in bases:
		_expect(absf(basis.determinant() - 1.0) < 1e-5, "basis is a rotation")
	_expect((bases[0] * Vector3(0, -A, 0) + bent.root).distance_to(bent.middle) < 1e-5, "upper -y runs hip -> knee")
	_expect((bases[1] * Vector3(0, -B, 0) + bent.middle).distance_to(bent.end) < 1e-5, "lower -y runs knee -> ankle")
	# Both bones share the hinge axis: the knee is a hinge.
	_expect(bases[0].x.distance_to(bases[1].x) < 1e-5, "shared hinge axis")

	var slope := Vector3(0.3, 1.0, 0.2).normalized()
	var foot := TwoBoneIk.foot_basis(slope, Vector3.FORWARD)
	_expect(foot.y.distance_to(slope) < 1e-5, "foot +y is the normal")
	_expect(absf(foot.z.dot(slope)) < 1e-5, "toes in the ground plane")


func _check_helpers() -> void:
	var steep := TwoBoneIk.limit_tilt(Vector3(1, 1, 0), 30.0)
	_expect(absf(rad_to_deg(steep.angle_to(Vector3.UP)) - 30.0) < 1e-3, "limit_tilt clamps to 30 degrees")
	var gentle := Vector3(0.1, 1, 0).normalized()
	_expect(TwoBoneIk.limit_tilt(gentle, 30.0).is_equal_approx(gentle), "limit_tilt keeps small tilts")

	# WalkCycle: left swing on (-0.25, 0.25), right swing on (0.25, 0.75).
	_expect(is_equal_approx(FootRig.swing_progress(0, -0.25 + 1.0), 0.0), "left swing starts at -0.25")
	_expect(is_equal_approx(FootRig.swing_progress(0, 0.0), 0.5), "left mid-swing at 0")
	_expect(FootRig.swing_progress(0, 0.5) >= 1.0, "left stance at 0.5")
	_expect(is_equal_approx(FootRig.swing_progress(1, 0.5), 0.5), "right mid-swing at 0.5")
	_expect(FootRig.swing_progress(1, 0.0) >= 1.0, "right stance at 0")

	_expect(is_zero_approx(FootRig.swing_ease(0.0)) and is_equal_approx(FootRig.swing_ease(1.0), 1.0), "ease ends")
	var h := 1e-4
	var start_slope := (FootRig.swing_ease(h) - FootRig.swing_ease(0.0)) / h
	var end_slope := (FootRig.swing_ease(1.0) - FootRig.swing_ease(1.0 - h)) / h
	_expect(start_slope < 1e-3 and end_slope < 1e-3, "ease starts and ends at rest")


func _basis_error(a: Basis, b: Basis) -> float:
	return (a.x - b.x).length() + (a.y - b.y).length() + (a.z - b.z).length()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
