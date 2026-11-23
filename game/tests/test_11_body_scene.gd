extends SceneTree
## Lesson 11: checks the Lesson 11 scene and BodyPlayer.
##   1. Player is a BodyPlayer whose rig holds a Skeleton3D with 15 bones
##      and one capsule MeshInstance3D per segment; the old capsule is hidden.
##   2. Holding move_forward moves the player, advances the walk phase by
##      the distance walked / stride_length, and raises the walk amount.
##   3. E cycles the body view: rig, rig + capsule, capsule.
##   4. The Lesson 10 scene still uses the plain Player. (run/main_scene
##      moved to Lesson 12; test_12_feet_scene.gd checks it.)
## Run: Godot --headless --path game -s res://tests/test_11_body_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_11_body_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
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

	var scene: Node = (load("res://scenes/lessons/11_skeleton_from_code.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 3:
		await physics_frame

	# 1. Body.
	var body := scene.get_node("Player") as BodyPlayer
	_expect(body != null, "Player is a BodyPlayer")
	if body == null:
		scene.queue_free()
		return
	var skeleton := body.rig.skeleton()
	_expect(skeleton != null and skeleton.get_bone_count() == 15, "15 bones")
	var segments := 0
	for spec in body.rig.proportions.bone_specs():
		segments += (spec.segments as Array).size()
	var capsules := _count_capsules(skeleton)
	_expect(capsules == segments, "%d capsules, expected %d" % [capsules, segments])
	_expect(not (scene.get_node("Player/BodyMesh/Capsule") as Node3D).visible, "old capsule hidden")

	# 2. Walking. Let the player land first.
	for i in 60:
		await physics_frame
	var start := body.global_position
	var phase_start := body.rig.phase
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var walked := Vector2(body.global_position.x - start.x, body.global_position.z - start.z).length()
	_expect(walked > 1.0, "walked %f m" % walked)
	var expected := fposmod(phase_start + walked / body.rig.walk_cycle.stride_length, 1.0)
	var phase_error := absf(angle_difference(TAU * expected, TAU * body.rig.phase)) / TAU
	_expect(phase_error < 0.01, "phase %f, expected %f" % [body.rig.phase, expected])
	_expect(body.rig.amount > 0.5, "walk amount %f" % body.rig.amount)

	# 3. Key E.
	scene._unhandled_input(_action("toggle_body_view"))
	_expect(body.body_view == BodyPlayer.BodyView.RIG_CAPSULE and body.rig.visible and body.get_node("BodyMesh/Capsule").visible, "E: rig + capsule")
	scene._unhandled_input(_action("toggle_body_view"))
	_expect(body.body_view == BodyPlayer.BodyView.CAPSULE and not body.rig.visible, "E: capsule")

	scene.queue_free()
	await process_frame

	# 4. The Lesson 10 scene.
	var old: Node = (load("res://scenes/lessons/10_raymarching.tscn") as PackedScene).instantiate()
	_expect(not (old.get_node("Player") is BodyPlayer), "Lesson 10 scene keeps Player")
	old.free()

	if osc != null:
		osc.set_destination("127.0.0.1", old_port)


func _count_capsules(node: Node) -> int:
	var count := 0
	for child in node.get_children(true):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CapsuleMesh:
			count += 1
		count += _count_capsules(child)
	return count


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
