extends SceneTree
## Lesson 12: checks FootRig on a floor box, driven by hand (no player).
##   1. Standing: the right foot planted under its hip (at phase 0 the left
##      foot is in mid-swing, WalkCycle); both ankles on the floor.
##   2. Walking at amount 1 over flat ground: a stance ankle does not move
##      in world space; plants come every half stride (0.70 m); the pelvis
##      stays between -max_pelvis_drop and 0; every ankle reaches its target.
##   3. Onto a 0.18 m step: plants after the edge lie on the step top.
##   4. TwoBoneIK3D (solver ENGINE) puts the knees where TwoBoneIk does.
## Run: Godot --headless --path game -s res://tests/test_12_foot_rig.gd

const STEP_HEIGHT := 0.18
const STEP_FRONT := -4.0
const DT := 1.0 / 60.0
const SPEED := 3.0

var _failures := 0


func _initialize() -> void:
	await process_frame
	await _check_walk()
	await _check_engine()
	print("test_12_foot_rig: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


## A 40 m floor with its top at y = 0 and a 0.18 m step from z = -4 on.
func _make_world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0)))
	world.add_child(_box(Vector3(4, 1, 10), Vector3(0, STEP_HEIGHT - 0.5, STEP_FRONT - 5.0)))
	return world


func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	return body


func _make_rig(world: Node3D) -> FootRig:
	var rig := FootRig.new()
	rig.proportions = load("res://data/body/default_proportions.tres")
	rig.walk_cycle = load("res://data/body/placeholder_walk.tres")
	world.add_child(rig)
	return rig


func _ankle(rig: FootRig, side: int) -> Vector3:
	var skeleton := rig.skeleton()
	skeleton.force_update_all_bone_transforms()
	var index := skeleton.find_bone("Foot." + FootRig.SIDE_NAMES[side])
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _check_walk() -> void:
	var world := _make_world()
	var rig := _make_rig(world)
	await physics_frame
	await physics_frame

	# 1. Standing.
	rig.advance(0.0, 0.0, DT)
	_expect(rig.feet[1].planted, "standing: right foot planted")
	var home := rig.home_point(1) + Vector3.UP * rig.proportions.ankle_height
	_expect(_ankle(rig, 1).distance_to(home) < 1e-3, "standing: right ankle above its home point")
	for side in 2:
		_expect(absf(_ankle(rig, side).y - rig.proportions.ankle_height) < 1e-3, "standing: ankle %d at ankle height" % side)

	# 2. Walking.
	var plants: Array = []
	rig.foot_planted.connect(func(side: int, point: Vector3, _n: Vector3, _f: float) -> void: plants.append([side, point]))
	var stance_drift := 0.0
	var worst_error := 0.0
	var lowest_pelvis := 0.0
	var highest_pelvis := -1.0
	var previous: Array = [null, null]
	for i in 160:
		var distance := SPEED * DT
		rig.position.z -= distance
		rig.advance(distance, 1.0, DT)
		lowest_pelvis = minf(lowest_pelvis, rig.pelvis_offset)
		highest_pelvis = maxf(highest_pelvis, rig.pelvis_offset)
		for side in 2:
			worst_error = maxf(worst_error, rig.ankle_errors[side])
			var stance := rig.feet[side].swing >= 1.0
			var ankle := _ankle(rig, side)
			if stance and previous[side] != null:
				stance_drift = maxf(stance_drift, ankle.distance_to(previous[side]))
			previous[side] = ankle if stance else null

	_expect(stance_drift < 1e-4, "stance ankle drift per tick %s m" % stance_drift)
	_expect(worst_error < 1e-4, "ankle error %s m" % worst_error)
	_expect(lowest_pelvis >= -rig.max_pelvis_drop - 1e-6 and highest_pelvis <= 1e-6, "pelvis in [%s, %s]" % [lowest_pelvis, highest_pelvis])
	_expect(plants.size() >= 10, "%d plants" % plants.size())
	var half_stride := 0.5 * rig.walk_cycle.stride_length
	for k in range(1, plants.size()):
		var gap := absf((plants[k][1] as Vector3).z - (plants[k - 1][1] as Vector3).z)
		_expect(absf(gap - half_stride) < 0.02, "plant gap %s m, expected %s" % [gap, half_stride])
		_expect(plants[k][0] != plants[k - 1][0], "plants alternate sides")

	# 3. The step.
	var on_step := 0
	for plant in plants:
		var point: Vector3 = plant[1]
		if point.z < STEP_FRONT - 0.05:
			on_step += 1
			_expect(absf(point.y - STEP_HEIGHT) < 1e-3, "plant at z %s on the step top (y %s)" % [point.z, point.y])
		elif point.z > STEP_FRONT + 0.05:
			_expect(absf(point.y) < 1e-3, "plant at z %s on the floor (y %s)" % [point.z, point.y])
	_expect(on_step >= 3, "%d plants on the step" % on_step)

	world.queue_free()
	await process_frame


func _check_engine() -> void:
	var knees: Array = []
	for solver in [FootRig.Solver.OWN, FootRig.Solver.ENGINE]:
		var world := _make_world()
		var rig := _make_rig(world)
		await physics_frame
		rig.solver = solver
		var skeleton := rig.skeleton()
		var record: Array = []
		var knee := [Vector3.ZERO]
		# TwoBoneIK3D's result is visible only while the skeleton reports
		# its final pose (FootRig._on_skeleton_updated()).
		skeleton.skeleton_updated.connect(func() -> void: knee[0] = skeleton.get_bone_global_pose(skeleton.find_bone("LowerLeg.L")).origin)
		for i in 60:
			rig.position.z -= SPEED * DT
			rig.advance(SPEED * DT, 1.0, DT)
			await process_frame
			record.append(knee[0])
		knees.append(record)
		world.queue_free()
		await process_frame
	var worst := 0.0
	for i in range(5, knees[0].size()):
		worst = maxf(worst, (knees[0][i] as Vector3).distance_to(knees[1][i]))
	_expect(worst < 1e-4, "TwoBoneIK3D knee vs TwoBoneIk knee: %s m" % worst)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
