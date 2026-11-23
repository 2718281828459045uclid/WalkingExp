extends SceneTree
## Lesson 13: checks the mass table, the center of mass, the pendulum and
## the state machine, with a FootRig on a floor box driven by hand.
##   1. SegmentMasses: the fractions sum to 1; 12 segments.
##   2. CenterOfMass: two unit-weight segments give their midpoint; on the
##      standing rig c lies between the hips, 0.9-1.0 m above the floor,
##      inside the support polygon of both feet.
##   3. Walking at 3 m/s: most ticks have one foot in contact and c
##      outside its polygon (walking is not statically balanced).
##   4. SwayPendulum: a push decays below 1 mm within 3 s; with kp below
##      g / L the offset grows to its limit within 5 s; natural frequency and damping ratio.
##   5. next_state(): thresholds and hysteresis.
## Run: Godot --headless --path game -s res://tests/test_13_balance.gd

const DT := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	await process_frame
	_check_table()
	await _check_rig()
	_check_pendulum()
	_check_states()
	print("test_13_balance: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_table() -> void:
	var masses := load("res://data/body/winter_segment_masses.tres") as SegmentMasses
	_expect(absf(masses.total_fraction() - 1.0) < 1e-9, "fractions sum to 1, got %s" % masses.total_fraction())
	var segments := masses.segments(load("res://data/body/default_proportions.tres"))
	_expect(segments.size() == 12, "12 segments, got %d" % segments.size())
	var sum := 0.0
	for segment in segments:
		sum += segment.fraction
	_expect(absf(sum - 1.0) < 1e-9, "segment list sums to 1")


func _box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	return body


func _check_rig() -> void:
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0)))
	var rig := FootRig.new()
	rig.proportions = load("res://data/body/default_proportions.tres")
	rig.walk_cycle = load("res://data/body/placeholder_walk.tres")
	world.add_child(rig)
	var monitor := BalanceMonitor.new()
	monitor.rig = rig
	monitor.masses = load("res://data/body/winter_segment_masses.tres")
	world.add_child(monitor)
	# The test calls measure() itself; no pendulum, no OSC.
	monitor.set_physics_process(false)
	await physics_frame
	await physics_frame

	# 2. Two segments of equal weight: the midpoint of their centers.
	var skeleton := rig.skeleton()
	var pair: Array[Dictionary] = [
		{"proximal_bone": &"Hips", "proximal_point": Vector3.ZERO, "distal_bone": &"Hips", "distal_point": Vector3(0, 1, 0), "fraction": 0.5, "ratio": 0.5},
		{"proximal_bone": &"Hips", "proximal_point": Vector3(1, 0, 0), "distal_bone": &"Hips", "distal_point": Vector3(1, 0, 0), "fraction": 0.5, "ratio": 0.0},
	]
	rig.apply_pose(null)
	skeleton.force_update_all_bone_transforms()
	var hips := rig.proportions.hip_height()
	_expect(CenterOfMass.compute(skeleton, pair).is_equal_approx(Vector3(0.5, hips + 0.25, 0)), "two segments: weighted mean")

	rig.advance(0.0, 0.0, DT)
	skeleton.force_update_all_bone_transforms()
	monitor.measure()
	var c := monitor.center_of_mass
	_expect(absf(c.x) < 1e-4, "standing: c on the midline, x = %s" % c.x)
	_expect(c.y > 0.9 and c.y < 1.0, "standing: c height %s" % c.y)
	_expect(monitor.foot_in_contact(0) and monitor.foot_in_contact(1), "standing: both feet in contact")
	_expect(monitor.polygon.size() >= 4, "standing: polygon of %d corners" % monitor.polygon.size())
	_expect(monitor.margin > 0.0, "standing: margin %s > 0" % monitor.margin)

	# 3. Walking.
	var single := 0
	var outside := 0
	var ticks := 0
	for i in 360:
		rig.position.z -= 3.0 * DT
		rig.advance(3.0 * DT, 1.0, DT)
		skeleton.force_update_all_bone_transforms()
		monitor.measure()
		await physics_frame
		if i < 60:
			continue
		ticks += 1
		if int(monitor.foot_in_contact(0)) + int(monitor.foot_in_contact(1)) == 1:
			single += 1
		if monitor.state == BalanceMonitor.State.OUTSIDE:
			outside += 1
	_expect(single > ticks / 2, "walking: one foot in contact on %d of %d ticks" % [single, ticks])
	_expect(outside > ticks / 2, "walking: c outside on %d of %d ticks" % [outside, ticks])
	world.queue_free()
	await process_frame


func _check_pendulum() -> void:
	var p := SwayPendulum.new()
	p.height = 0.96
	p.push(Vector2(0.4, 0.0))
	var peak := 0.0
	for i in 180:
		p.step(DT)
		peak = maxf(peak, p.offset.length())
	_expect(peak > 0.03 and peak < 0.1, "push 0.4 m/s: peak %s m" % peak)
	_expect(p.offset.length() < 1e-3, "push decays below 1 mm in 3 s: %s" % p.offset.length())
	_expect(is_equal_approx(p.natural_frequency(), sqrt(20.0 - 9.81 / 0.96)), "natural frequency")
	_expect(is_equal_approx(p.damping_ratio(), 4.0 / (2.0 * p.natural_frequency())), "damping ratio")

	var weak := SwayPendulum.new()
	weak.height = 0.96
	weak.stiffness = 5.0
	weak.push(Vector2(0.0, 0.1))
	for i in 300:
		weak.step(DT)
	_expect(weak.offset.y >= weak.max_offset - 1e-6, "kp < g / L: falls to the limit, offset %s" % weak.offset.y)
	_expect(weak.natural_frequency() == 0.0 and weak.damping_ratio() == INF, "unstable: no frequency")


func _check_states() -> void:
	var S := BalanceMonitor.State
	var m := 0.015
	var h := 0.01
	_expect(BalanceMonitor.next_state(S.STABLE, 0.1, false, m, h) == S.NO_SUPPORT, "no support")
	_expect(BalanceMonitor.next_state(S.STABLE, 0.02, true, m, h) == S.STABLE, "stable stays above m")
	_expect(BalanceMonitor.next_state(S.STABLE, 0.01, true, m, h) == S.MARGINAL, "stable -> marginal below m")
	_expect(BalanceMonitor.next_state(S.MARGINAL, 0.02, true, m, h) == S.MARGINAL, "marginal stays within the band")
	_expect(BalanceMonitor.next_state(S.MARGINAL, 0.03, true, m, h) == S.STABLE, "marginal -> stable above m + h")
	_expect(BalanceMonitor.next_state(S.MARGINAL, -0.001, true, m, h) == S.OUTSIDE, "marginal -> outside below 0")
	_expect(BalanceMonitor.next_state(S.OUTSIDE, 0.005, true, m, h) == S.OUTSIDE, "outside stays up to h")
	_expect(BalanceMonitor.next_state(S.OUTSIDE, 0.015, true, m, h) == S.MARGINAL, "outside -> marginal above h")
	_expect(BalanceMonitor.next_state(S.NO_SUPPORT, 0.05, true, m, h) == S.STABLE, "landing on a wide stance: stable")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
