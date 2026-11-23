extends SceneTree
## Lesson 05: checks SurfaceClassifier (src/audio/surface_classifier.gd)
## and the Lesson 05 scene.
##   1. The weights sum to 1 and follow the shader's rules: flat low
##      ground is dirt, flat high ground grass, 40 degrees rock, with the
##      parameters of painted_terrain_material.tres.
##   2. read_material() copies the material's parameters; the noise image
##      arrives; noise_at() stays in [0, 1].
##   3. sample_bilinear() on a 2 x 2 image: texel centers, midpoint, and
##      wrap-around.
##   4. The scene: walking forward for 3 s sends /foot/step bundles whose
##      time tags lie in the future when they arrive; K switches to plain
##      messages; the Lesson 04 scene sends no /foot/step.
## Run: Godot --headless --path game -s res://tests/test_05_surface.gd

var _failures := 0


func _initialize() -> void:
	await _check_classifier()
	_check_bilinear()
	await _check_scene()
	print("test_05_surface: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_classifier() -> void:
	var material := load("res://data/terrain/painted_terrain_material.tres") as ShaderMaterial
	var c := SurfaceClassifier.new()
	c.read_material(material)
	_expect(c.rock_angle_start == 22.0 and c.dirt_height == 1.0 and c.noise_scale_meters == 24.0, "read_material() did not copy the parameters")
	if not c.has_noise():
		var texture := material.get_shader_parameter("ground_noise") as Texture2D
		await texture.changed
	_expect(c.has_noise(), "the noise image did not arrive")

	# With shift 0 (noise value 0.5) the rules are the clean bands.
	var w_low := SurfaceClassifier.surface_weights(c.rockiness(0.0, 0.0), c.dirtiness(-2.0, 0.0))
	var w_high := SurfaceClassifier.surface_weights(c.rockiness(0.0, 0.0), c.dirtiness(10.0, 0.0))
	var w_steep := SurfaceClassifier.surface_weights(c.rockiness(40.0, 0.0), c.dirtiness(10.0, 0.0))
	_expect(SurfaceClassifier.dominant(w_low) == SurfaceClassifier.Surface.DIRT, "low flat ground is not dirt: %s" % w_low)
	_expect(SurfaceClassifier.dominant(w_high) == SurfaceClassifier.Surface.GRASS, "high flat ground is not grass: %s" % w_high)
	_expect(SurfaceClassifier.dominant(w_steep) == SurfaceClassifier.Surface.ROCK, "40 degree ground is not rock: %s" % w_steep)
	# Midpoint of the rock band: smoothstep(22, 32, 27) = 0.5.
	_expect(absf(c.rockiness(27.0, 0.0) - 0.5) < 1e-9, "rockiness at 27 degrees is %f" % c.rockiness(27.0, 0.0))
	# A shift of +0.5 adds 8 degrees: 19 degrees counts as 27.
	_expect(absf(c.rockiness(19.0, 0.5) - 0.5) < 1e-9, "noise shift does not add rock_breakup_degrees")

	var low := 1.0
	var high := 0.0
	var worst_sum := 0.0
	for i in 200:
		var p := Vector3(randf_range(-60, 60), randf_range(-5, 15), randf_range(-60, 60))
		var n := Vector3(randf_range(-1, 1), randf_range(0.2, 1), randf_range(-1, 1)).normalized()
		var v := c.noise_at(p, n)
		low = minf(low, v)
		high = maxf(high, v)
		var w := c.weights_at(p, n)
		worst_sum = maxf(worst_sum, absf(w.x + w.y + w.z - 1.0))
		_expect(w.x >= 0.0 and w.y >= 0.0 and w.z >= 0.0, "negative weight %s" % w)
	_expect(low >= 0.0 and high <= 1.0, "noise outside [0, 1]: %f .. %f" % [low, high])
	_expect(worst_sum < 1e-6, "weights do not sum to 1 (off by %f)" % worst_sum)


func _check_bilinear() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RF)
	image.set_pixel(0, 0, Color(0, 0, 0))
	image.set_pixel(1, 0, Color(1, 0, 0))
	image.set_pixel(0, 1, Color(0, 0, 0))
	image.set_pixel(1, 1, Color(1, 0, 0))
	# Texel centers at u = 0.25 and 0.75; the midpoint 0.5 blends them.
	var at_center := SurfaceClassifier.sample_bilinear(image, Vector2(0.25, 0.25))
	var at_middle := SurfaceClassifier.sample_bilinear(image, Vector2(0.5, 0.25))
	# u = 0 lies halfway between texel 1 (wrapped from -1) and texel 0.
	var at_edge := SurfaceClassifier.sample_bilinear(image, Vector2(0.0, 0.25))
	var wrapped := SurfaceClassifier.sample_bilinear(image, Vector2(1.25, -0.75))
	_expect(is_equal_approx(at_center, 0.0) and is_equal_approx(at_middle, 0.5), "bilinear center %f, middle %f" % [at_center, at_middle])
	_expect(is_equal_approx(at_edge, 0.5) and is_equal_approx(wrapped, 0.0), "bilinear edge %f, wrapped %f" % [at_edge, wrapped])


func _check_scene() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	_expect(osc != null, "autoload Osc is missing")
	if osc == null:
		return
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := osc.port
	osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/05_footsteps.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var footsteps := scene.get_node("Footsteps") as FootstepReporter
	var ticks := Engine.physics_ticks_per_second
	# Land first, then walk 3 s.
	for i in ticks:
		await physics_frame
	_drain(receiver)
	Input.action_press("move_forward")
	var bundles := 0
	var plain := 0
	var earliest_margin := INF
	for i in ticks * 3:
		await physics_frame
		while receiver.get_available_packet_count() > 0:
			var packet := receiver.get_packet()
			var now := Time.get_unix_time_from_system()
			if packet.slice(0, 7).get_string_from_ascii() == "#bundle":
				bundles += 1
				earliest_margin = minf(earliest_margin, OscBundle.timetag_to_unix(packet.slice(8, 16)) - now)
	# 3 s at up to 3 m/s with 0.75 m steps: at most 12 steps; the start
	# from rest costs about one.
	_expect(bundles >= 9 and bundles <= 12, "%d /foot/step bundles in 3 s" % bundles)
	_expect(earliest_margin > 0.0, "a time tag was already past on arrival (%f s)" % earliest_margin)
	_expect(footsteps.last_arguments.size() == 6, "last_arguments has %d values" % footsteps.last_arguments.size())

	var event := InputEventAction.new()
	event.action = "toggle_step_timing"
	event.pressed = true
	scene._unhandled_input(event)
	_expect(footsteps.timing == FootstepReporter.Timing.IMMEDIATE, "K did not switch to immediate")
	for i in ticks:
		await physics_frame
	while receiver.get_available_packet_count() > 0:
		var packet := receiver.get_packet()
		if packet.slice(0, 10).get_string_from_ascii() == "/foot/step":
			plain += 1
	_expect(plain >= 3, "%d plain /foot/step messages in 1 s after K" % plain)
	Input.action_release("move_forward")
	scene.queue_free()
	await process_frame

	# Lesson 04's scene has no Footsteps node.
	var old_scene: Node = (load("res://scenes/lessons/04_osc_bridge.tscn") as PackedScene).instantiate()
	_expect(old_scene.get_node_or_null("Footsteps") == null, "the Lesson 04 scene has a Footsteps node")
	old_scene.free()
	osc.set_destination("127.0.0.1", old_port)
	receiver.close()


func _drain(receiver: PacketPeerUDP) -> void:
	while receiver.get_available_packet_count() > 0:
		receiver.get_packet()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
