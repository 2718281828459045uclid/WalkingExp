extends SceneTree
## Lesson 14: checks the Lesson 14 scene.
##   1. Stance runs after BalanceMonitor and before Player; the player has
##      the radial StickResponse of Lesson 02.
##   2. The rig's position is rest + sway + shift - crouch.
##   3. The right trigger action shifts the weight to the right by up to
##      side_range; the margin stays finite; the feet keep their targets.
##   4. Key 4 crouches: the rig lowers by crouch_depth, the center of mass
##      lowers, both feet keep their targets.
##   5. Key 7 cycles the smoothing; key 8 swaps the deadzone; key 9
##      switches the tick rate.
##   6. The Lesson 13 scene has no Stance node. (run/main_scene is
##      checked by the newest lesson's scene test.)
## Run: Godot --headless --path game -s res://tests/test_14_stance_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_14_stance_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	var scene: Node = (load("res://scenes/lessons/14_analog_stances.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	# 1. Nodes and order.
	var stance := scene.get_node("Stance") as StanceController
	var monitor := scene.get_node("BalanceMonitor") as BalanceMonitor
	var body := scene.get_node("Player") as BodyPlayer
	_expect(stance != null and monitor != null and body != null, "Stance, BalanceMonitor, Player")
	if stance == null or monitor == null or body == null:
		scene.queue_free()
		return
	_expect(stance.process_physics_priority == monitor.process_physics_priority, "same priority as the monitor")
	_expect(stance.get_index() > monitor.get_index(), "Stance after BalanceMonitor in the tree")
	_expect(stance.process_physics_priority < body.process_physics_priority, "Stance before Player")
	_expect(body.stick_response != null and not body.stick_response is AxialStickResponse, "radial StickResponse")
	var rig := monitor.rig
	var rest := rig.position
	for i in 60:
		await physics_frame
	var standing_height := monitor.center_of_mass.y - monitor.polygon_height

	# 2 and 3. Right trigger.
	Input.action_press("shift_weight_right", 1.0)
	for i in 60:
		await physics_frame
	var s := monitor.sway()
	var expected := rest + Vector3(s.x + stance.shift.x, -stance.crouch, -(s.y + stance.shift.y))
	_expect(rig.position.is_equal_approx(expected), "rig position %s, expected %s" % [rig.position, expected])
	_expect(stance.shift.x > 0.9 * stance.side_range, "right trigger shifts right: %s" % stance.shift.x)
	_expect(is_finite(monitor.margin), "margin finite: %s" % monitor.margin)
	_expect(rig.ankle_errors[0] < 0.01 and rig.ankle_errors[1] < 0.01, "ankle errors %s" % rig.ankle_errors)
	Input.action_release("shift_weight_right")
	for i in 60:
		await physics_frame
	_expect(absf(stance.shift.x) < 0.01, "release returns: %s" % stance.shift.x)

	# 4. Crouch.
	scene._unhandled_input(_key(KEY_4))
	for i in 60:
		await physics_frame
	_expect(stance.stance == StanceController.Stance.CROUCHED, "key 4 crouches")
	_expect(absf(stance.crouch - stance.crouch_depth) < 0.005, "crouch %s" % stance.crouch)
	var crouched_height := monitor.center_of_mass.y - monitor.polygon_height
	_expect(crouched_height < standing_height - 0.1, "CoM lowers: %s -> %s" % [standing_height, crouched_height])
	_expect(rig.ankle_errors[0] < 0.01 and rig.ankle_errors[1] < 0.01, "crouched ankle errors %s" % rig.ankle_errors)
	scene._unhandled_input(_key(KEY_4))
	_expect(stance.stance == StanceController.Stance.STANDING, "key 4 stands up")

	# 5. Keys 7, 8, 9.
	var before := stance.smoothing
	scene._unhandled_input(_key(KEY_7))
	_expect(stance.smoothing == (before + 1) % StanceController.Smoothing.size(), "key 7 cycles smoothing")
	scene._unhandled_input(_key(KEY_8))
	_expect(body.stick_response is AxialStickResponse, "key 8: axial")
	scene._unhandled_input(_key(KEY_8))
	_expect(body.stick_response != null and not body.stick_response is AxialStickResponse, "key 8 again: radial")
	scene._unhandled_input(_key(KEY_9))
	_expect(Engine.physics_ticks_per_second == 120, "key 9: 120 Hz")
	scene._unhandled_input(_key(KEY_9))
	_expect(Engine.physics_ticks_per_second == 60, "key 9 again: 60 Hz")

	scene.queue_free()
	await process_frame

	# 6. The Lesson 13 scene.
	var old: Node = (load("res://scenes/lessons/13_balance.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Stance") == null, "Lesson 13 scene has no Stance")
	old.free()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
