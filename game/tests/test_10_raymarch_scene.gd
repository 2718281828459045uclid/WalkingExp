extends SceneTree
## Lesson 10: checks the Lesson 10 scene and RaymarchVolume
## (src/sdf/raymarch_volume.gd).
##   1. Formations holds three RaymarchVolume nodes, each with a proxy box
##      covering its shape's bounds and a ShaderMaterial whose code holds
##      the generated sdf_map().
##   2. The root placed each formation relative to the terrain height.
##   3. step_scale is 1 / L of the shape.
##   4. P cycles debug_view, X cycles max_steps, Z hides the formations.
##   5. The Lesson 09 scene has no Formations node. (run/main_scene moved
##      to Lesson 11; test_11_body_scene.gd checks it.)
## Run: Godot --headless --path game -s res://tests/test_10_raymarch_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_10_raymarch_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
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

	var packed := load("res://scenes/lessons/10_raymarching.tscn") as PackedScene
	var raw: Node = packed.instantiate()
	# The scene file's y values, before the root adds the terrain height.
	var offsets := {}
	for child in raw.get_node("Formations").get_children():
		offsets[child.name] = (child as Node3D).position.y
	root.add_child(raw)
	for i in 3:
		await process_frame

	# 1. Volumes.
	var volumes: Array[RaymarchVolume] = []
	for child in raw.get_node("Formations").get_children():
		if child is RaymarchVolume:
			volumes.append(child)
	_expect(volumes.size() == 3, "%d RaymarchVolume nodes, expected 3" % volumes.size())
	var terrain := raw.get_node("Terrain")
	for volume in volumes:
		_expect(volume.material != null and volume.material.shader.code.contains("float sdf_map(vec3 p0)"), "%s has the generated map" % volume.name)
		_expect(volume.proxy_bounds.encloses(volume.shape.bounds()), "%s proxy covers bounds()" % volume.name)
		_expect(volume.node_count > 0, "%s translated nodes" % volume.name)
		# 2. Placement.
		var ground: float = terrain.height_at(volume.position.x, volume.position.z)
		_expect(absf(volume.position.y - (ground + offsets[volume.name])) < 1e-4, "%s placed on the terrain" % volume.name)
		# 3. Step scale.
		var scale: float = volume.material.get_shader_parameter("step_scale")
		_expect(absf(scale - 1.0 / volume.shape.lipschitz_bound()) < 1e-6, "%s step_scale %f" % [volume.name, scale])

	# 4. Keys.
	if not volumes.is_empty():
		var first := volumes[0]
		var budget := first.max_steps
		raw._unhandled_input(_action("cycle_raymarch_view"))
		_expect(first.debug_view == 1 and first.material.get_shader_parameter("debug_view") == 1, "P sets debug_view 1")
		raw._unhandled_input(_action("cycle_march_budget"))
		_expect(first.max_steps != budget and first.material.get_shader_parameter("max_steps") == first.max_steps, "X changes max_steps")
		raw._unhandled_input(_action("toggle_formations"))
		_expect(not (raw.get_node("Formations") as Node3D).visible, "Z hides the formations")

	raw.queue_free()
	await process_frame

	# 5. The Lesson 09 scene.
	var old: Node = (load("res://scenes/lessons/09_implicit_curvature.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("Formations") == null, "Lesson 09 scene unchanged")
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
