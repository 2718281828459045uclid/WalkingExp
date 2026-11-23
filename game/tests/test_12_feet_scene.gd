extends SceneTree
## Lesson 12: checks the Lesson 12 scene.
##   1. Player's rig is a FootRig; Footsteps is a PlantFootstepReporter.
##   2. Walking forward plants feet: every plant sends one /foot/step, the
##      ankles reach their targets, and the plants lie on the ground.
##   3. Q cycles the solver (own IK, TwoBoneIK3D, walk cycle); Y toggles
##      the debug lines.
##   4. The Lesson 11 scene keeps
##      the plain BodyRig and FootstepReporter.
## Run: Godot --headless --path game -s res://tests/test_12_feet_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_12_feet_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	# The scene sends OSC (Lessons 04-06); redirect it to a local socket.
	var osc := root.get_node_or_null("Osc") as OscSender
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := 57120
	if osc != null:
		old_port = osc.port
		osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/12_feet_on_the_ground.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 3:
		await physics_frame

	# 1. Nodes.
	var body := scene.get_node("Player") as BodyPlayer
	var rig := body.rig as FootRig if body != null else null
	_expect(rig != null, "Player/BodyMesh/Rig is a FootRig")
	var footsteps := scene.get_node("Footsteps") as PlantFootstepReporter
	_expect(footsteps != null, "Footsteps is a PlantFootstepReporter")
	if rig == null or footsteps == null:
		scene.queue_free()
		return
	_expect(rig.solver == FootRig.Solver.OWN, "starts with the own solver")

	# 2. Walking. Let the player land first.
	for i in 60:
		await physics_frame
	var terrain := scene.get_node("Terrain") as Terrain
	var plants: Array = []
	rig.foot_planted.connect(func(_side: int, point: Vector3, _n: Vector3, _f: float) -> void: plants.append(point))
	var sent_before := footsteps.steps_sent
	var worst_error := 0.0
	Input.action_press("move_forward")
	for i in 120:
		await physics_frame
		worst_error = maxf(worst_error, maxf(rig.ankle_errors[0], rig.ankle_errors[1]))
	Input.action_release("move_forward")
	await physics_frame
	_expect(plants.size() >= 4, "%d plants in 2 s" % plants.size())
	_expect(footsteps.steps_sent - sent_before == plants.size(), "%d steps sent for %d plants" % [footsteps.steps_sent - sent_before, plants.size()])
	_expect(worst_error < 1e-3, "ankle error %s m" % worst_error)
	for point in plants:
		var below := terrain.height_at(point.x, point.z)
		_expect(absf(point.y - below) < 0.05, "plant %s on the terrain (height %s)" % [point, below])

	# 3. Keys.
	scene._unhandled_input(_action("cycle_foot_solver"))
	_expect(rig.solver == FootRig.Solver.ENGINE, "Q: TwoBoneIK3D")
	scene._unhandled_input(_action("cycle_foot_solver"))
	_expect(rig.solver == FootRig.Solver.WALK_CYCLE, "Q: walk cycle")
	scene._unhandled_input(_action("cycle_foot_solver"))
	_expect(rig.solver == FootRig.Solver.OWN, "Q: own IK")
	scene._unhandled_input(_action("toggle_foot_debug"))
	_expect(rig.debug_draw, "Y: debug lines on")

	scene.queue_free()
	await process_frame

	# 4. The Lesson 11 scene.
	var old: Node = (load("res://scenes/lessons/11_skeleton_from_code.tscn") as PackedScene).instantiate()
	var old_rig := old.get_node("Player/BodyMesh/Rig")
	_expect(old_rig is BodyRig and not old_rig is FootRig, "Lesson 11 scene keeps BodyRig")
	_expect(not old.get_node("Footsteps") is PlantFootstepReporter, "Lesson 11 scene keeps FootstepReporter")
	old.free()

	if osc != null:
		osc.set_destination("127.0.0.1", old_port)


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
