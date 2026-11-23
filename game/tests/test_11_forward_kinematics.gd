extends SceneTree
## Lesson 11: checks ForwardKinematics, BodyProportions, WalkCycle and the
## skeleton that BodyRig builds.
##   1. ForwardKinematics.rotate() (v + 2w(u x v) + 2u x (u x v)) equals
##      Quaternion * Vector3, and the product of two quaternions equals the
##      product of their matrices.
##   2. The rig has one bone per spec, with the spec's parent and rest.
##   3. At rest the soles touch y = 0 and the head top is at standing_height().
##   4. For random joint rotations, global_transforms() by hand equals
##      Skeleton3D.get_bone_global_pose() for every bone.
##   5. WalkCycle: amount 0 gives identity rotations; the right side at
##      phase phi + 0.5 equals the left side at phi; the foot pitch cancels
##      the hip and knee pitch.
## Run: Godot --headless --path game -s res://tests/test_11_forward_kinematics.gd

var _failures := 0


func _initialize() -> void:
	_check_quaternions()
	await _check_rig()
	_check_walk_cycle()
	print("test_11_forward_kinematics: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_quaternions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial in 50:
		var q := _random_quaternion(rng)
		var r := _random_quaternion(rng)
		var v := Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		_expect(ForwardKinematics.rotate(q, v).distance_to(q * v) < 1e-5, "rotate() equals q * v")
		var product := Basis(q * r)
		var matrices := Basis(q) * Basis(r)
		for axis in 3:
			_expect(product[axis].distance_to(matrices[axis]) < 1e-5, "Basis(q r) = Basis(q) Basis(r)")


func _check_rig() -> void:
	var rig := BodyRig.new()
	rig.proportions = BodyProportions.new()
	rig.walk_cycle = WalkCycle.new()
	root.add_child(rig)
	await process_frame
	var skeleton := rig.skeleton()
	var specs := rig.proportions.bone_specs()

	# 2. Bones.
	_expect(skeleton.get_bone_count() == specs.size(), "%d bones, expected %d" % [skeleton.get_bone_count(), specs.size()])
	for i in specs.size():
		_expect(skeleton.get_bone_name(i) == String(specs[i].name), "bone %d name" % i)
		_expect(skeleton.get_bone_parent(i) == specs[i].parent, "bone %d parent" % i)
		_expect(skeleton.get_bone_rest(i).origin.is_equal_approx(specs[i].offset), "bone %d rest" % i)

	# 3. Rest heights. The lowest capsule point of a foot is its axis height
	#    minus the foot radius; the head capsule ends at head_length.
	skeleton.force_update_all_bone_transforms()
	var p := rig.proportions
	var foot := skeleton.find_bone("Foot.L")
	var head := skeleton.find_bone("Head")
	var foot_segment: Array = specs[foot].segments[0]
	var sole := skeleton.get_bone_global_pose(foot) * (foot_segment[0] as Vector3)
	_expect(absf(sole.y - p.foot_radius) < 1e-5, "sole at y = 0 (axis at %f)" % sole.y)
	var top := skeleton.get_bone_global_pose(head).origin.y + p.head_length
	_expect(absf(top - p.standing_height()) < 1e-5, "head top %f" % top)

	# 4. FK by hand against the skeleton.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var parents := PackedInt32Array()
	var locals: Array[Transform3D] = []
	for i in specs.size():
		parents.append(specs[i].parent)
		var q := _random_quaternion(rng)
		var offset := Vector3(0.0, 0.1, 0.0) if i == 0 else Vector3.ZERO
		var local := ForwardKinematics.local_transform(skeleton.get_bone_rest(i), q, offset)
		locals.append(local)
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, q)
	skeleton.force_update_all_bone_transforms()
	var globals := ForwardKinematics.global_transforms(parents, locals)
	var worst := 0.0
	for i in specs.size():
		worst = maxf(worst, globals[i].origin.distance_to(skeleton.get_bone_global_pose(i).origin))
	_expect(worst < 1e-5, "FK by hand equals Skeleton3D (largest difference %.9f m)" % worst)
	rig.queue_free()
	await process_frame


func _check_walk_cycle() -> void:
	var cycle := WalkCycle.new()
	var still := cycle.sample(0.3, 0.0)
	for bone in still.rotations:
		_expect((still.rotations[bone] as Quaternion).is_equal_approx(Quaternion.IDENTITY), "amount 0: %s at rest" % bone)
	for phi in [0.0, 0.13, 0.37, 0.71]:
		var a := cycle.sample(phi, 1.0)
		var b := cycle.sample(phi + 0.5, 1.0)
		for part in ["UpperLeg", "LowerLeg", "Foot", "UpperArm", "LowerArm"]:
			var left: Quaternion = a.rotations[StringName(part + ".L")]
			var right: Quaternion = b.rotations[StringName(part + ".R")]
			_expect(left.is_equal_approx(right), "%s.R at phi + 0.5 equals %s.L at phi" % [part, part])
		# The pitch angles of hip, knee and foot add to zero.
		var total := 0.0
		for part in ["UpperLeg.L", "LowerLeg.L", "Foot.L"]:
			var q: Quaternion = a.rotations[StringName(part)]
			total += q.get_angle() * signf(q.x)
		_expect(absf(total) < 1e-5, "foot level at phi %f (sum %f)" % [phi, total])


func _random_quaternion(rng: RandomNumberGenerator) -> Quaternion:
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	if axis.length() < 0.01:
		axis = Vector3.UP
	return Quaternion(axis.normalized(), rng.randf_range(-PI, PI))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
