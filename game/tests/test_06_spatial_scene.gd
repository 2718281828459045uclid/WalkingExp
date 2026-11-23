extends SceneTree
## Lesson 06: checks the Lesson 06 scene and SpatialAudioReporter
## (src/audio/spatial_audio_reporter.gd) through the packets it sends.
##   1. Over 2 s, /emitter/pos bundles arrive 30 times per second, each
##      172 bytes (three /emitter/pos and one /wind); /emitter/kind
##      bundles once per second, 152 bytes.
##   2. The values in the last /emitter/pos message equal what
##      ListenerMath computes for the camera and the emitter.
##   3. Turning the camera 0.3 rad per tick for 2 s: every azimuth sent
##      for emitter 0 differs from the one before by less than PI.
##   4. L switches the listener to the CameraPivot; the Lesson 05 scene
##      has no SpatialReporter.
## Run: Godot --headless --path game -s res://tests/test_06_spatial_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_06_spatial_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	_expect(osc != null, "autoload Osc is missing")
	if osc == null:
		return
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := osc.port
	osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/06_spatial_audio.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var reporter := scene.get_node("SpatialReporter") as SpatialAudioReporter
	var camera := scene.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Node3D
	var pivot := scene.get_node("Player/CameraPivot") as Node3D
	var ticks := Engine.physics_ticks_per_second
	# Let the player land, then count 2 s of packets.
	for i in ticks:
		await physics_frame
	_drain(receiver)
	var position_bundles := 0
	var kind_bundles := 0
	var wrong_sizes := 0
	var last_position_packet := PackedByteArray()
	for i in ticks * 2:
		await physics_frame
		while receiver.get_available_packet_count() > 0:
			var packet := receiver.get_packet()
			if _first_address(packet) == "/emitter/pos":
				position_bundles += 1
				last_position_packet = packet
				if packet.size() != 172:
					wrong_sizes += 1
			elif _first_address(packet) == "/emitter/kind":
				kind_bundles += 1
				if packet.size() != 152:
					wrong_sizes += 1
	_expect(position_bundles >= 59 and position_bundles <= 61, "%d position bundles in 2 s" % position_bundles)
	_expect(kind_bundles >= 1 and kind_bundles <= 3, "%d kind bundles in 2 s" % kind_bundles)
	_expect(wrong_sizes == 0, "%d bundles of unexpected size" % wrong_sizes)

	# The first element of a position bundle is /emitter/pos for emitter 0.
	# Bundle: 16 bytes header, 4 bytes size; message: 16 address, 8 tags.
	var start := 16 + 4 + 16 + 8
	var id := _read_int(last_position_packet, start)
	var sent := Vector3(
		_read_float(last_position_packet, start + 4),
		_read_float(last_position_packet, start + 8),
		_read_float(last_position_packet, start + 12))
	var emitter := scene.get_node("Emitters/Crickets") as SoundEmitter
	var expected := ListenerMath.spherical_from(camera.global_transform, emitter.global_position)
	var azimuth_error := absf(wrapf(sent.x - expected.x, -PI, PI))
	_expect(id == 0, "first emitter id %d" % id)
	_expect(azimuth_error < 1e-3 and absf(sent.y - expected.y) < 1e-3 and absf(sent.z - expected.z) < 1e-3,
		"sent %s, ListenerMath gives %s" % [sent, expected])

	# Turn the camera fast and read every azimuth of emitter 0.
	var previous := sent.x
	var largest_step := 0.0
	var total_turn := 0.0
	for i in ticks * 2:
		pivot.rotation.y += 0.3
		await physics_frame
		while receiver.get_available_packet_count() > 0:
			var packet := receiver.get_packet()
			if _first_address(packet) != "/emitter/pos":
				continue
			var azimuth := _read_float(packet, start + 4)
			largest_step = maxf(largest_step, absf(azimuth - previous))
			total_turn += azimuth - previous
			previous = azimuth
	_expect(largest_step < PI, "azimuth step of %f rad between sends" % largest_step)
	# 0.3 rad per tick turns the listener left, so sources move right
	# (azimuth grows): 2 s at 60 Hz is 36 rad.
	_expect(total_turn > 30.0, "azimuth grew by %f rad while turning" % total_turn)

	var event := InputEventAction.new()
	event.action = "toggle_listener"
	event.pressed = true
	scene._unhandled_input(event)
	_expect(reporter.listener == pivot, "L did not switch the listener to the CameraPivot")
	scene.queue_free()
	await process_frame

	var old_scene: Node = (load("res://scenes/lessons/05_footsteps.tscn") as PackedScene).instantiate()
	_expect(old_scene.get_node_or_null("SpatialReporter") == null, "the Lesson 05 scene has a SpatialReporter")
	old_scene.free()
	osc.set_destination("127.0.0.1", old_port)
	receiver.close()


## Address of the first message in a bundle, or of a plain message.
func _first_address(packet: PackedByteArray) -> String:
	if packet.slice(0, 7).get_string_from_ascii() == "#bundle":
		return packet.slice(20, 36).get_string_from_ascii()
	return packet.slice(0, 16).get_string_from_ascii()


## OSC numbers are big-endian; decode_* reads little-endian, so the four
## bytes are reversed first.
func _read_float(bytes: PackedByteArray, offset: int) -> float:
	var word := bytes.slice(offset, offset + 4)
	word.reverse()
	return word.decode_float(0)


func _read_int(bytes: PackedByteArray, offset: int) -> int:
	var word := bytes.slice(offset, offset + 4)
	word.reverse()
	return word.decode_s32(0)


func _drain(receiver: PacketPeerUDP) -> void:
	while receiver.get_available_packet_count() > 0:
		receiver.get_packet()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
