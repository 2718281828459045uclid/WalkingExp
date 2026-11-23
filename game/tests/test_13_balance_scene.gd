extends SceneTree
## Lesson 13: checks the Lesson 13 scene.
##   1. BalanceMonitor reads Player's FootRig and runs before the player.
##   2. Standing at the spawn: support from both feet, margin positive.
##   3. OSC: about 30 /body/balance per second, five arguments; one
##      /body/balance/state per change of state.
##   4. 2 pushes the body: the sway grows and decays; Shift + 2 pushes the
##      other way; 1 toggles the lines.
##   5. The Lesson 12 scene has no BalanceMonitor. (run/main_scene is
##      checked by the newest lesson's scene test.)
## Run: Godot --headless --path game -s res://tests/test_13_balance_scene.gd

var _failures := 0


func _initialize() -> void:
	await _check_scene()
	print("test_13_balance_scene: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_scene() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := 57120
	if osc != null:
		old_port = osc.port
		osc.set_destination("127.0.0.1", receiver.get_local_port())

	var scene: Node = (load("res://scenes/lessons/13_balance.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	# _ready() of the scene's nodes runs once the tree is running.
	await process_frame

	# 1. Nodes.
	var monitor := scene.get_node("BalanceMonitor") as BalanceMonitor
	var body := scene.get_node("Player") as BodyPlayer
	_expect(monitor != null and body != null, "BalanceMonitor and BodyPlayer")
	if monitor == null or body == null:
		scene.queue_free()
		return
	_expect(monitor.rig == body.rig, "monitor reads the player's rig")
	_expect(monitor.process_physics_priority < body.process_physics_priority, "monitor ticks before the player")

	# 2. Standing.
	for i in 90:
		await physics_frame
	_expect(monitor.polygon.size() >= 4, "standing: polygon of %d corners" % monitor.polygon.size())
	_expect(monitor.margin > 0.0, "standing: margin %s" % monitor.margin)
	_expect(monitor.center_height > 0.9 and monitor.center_height < 1.0, "standing: c %s m above the feet" % monitor.center_height)

	# 3. OSC over 2 s.
	while receiver.get_available_packet_count() > 0:
		receiver.get_packet()
	var stream := 0
	var changes := 0
	var last_state := monitor.state
	var state_changes := 0
	for i in 120:
		await physics_frame
		if monitor.state != last_state:
			state_changes += 1
			last_state = monitor.state
	while receiver.get_available_packet_count() > 0:
		var packet := receiver.get_packet()
		var address := packet.get_string_from_ascii()
		if address == "/body/balance":
			stream += 1
			# Address (16 bytes padded) + ",ififf" (8) + 5 x 4 bytes.
			_expect(packet.size() == 44, "/body/balance is 44 bytes, got %d" % packet.size())
		elif address == "/body/balance/state":
			changes += 1
	_expect(stream >= 58 and stream <= 62, "%d /body/balance in 2 s" % stream)
	_expect(changes == state_changes, "%d state messages for %d changes" % [changes, state_changes])

	# 4. Keys.
	scene._unhandled_input(_key(KEY_2, false))
	await physics_frame
	await physics_frame
	_expect(monitor.sway().x > 0.0, "2: sway to the right, %s" % monitor.sway())
	for i in 240:
		await physics_frame
	_expect(monitor.sway().length() < 1e-3, "sway decays in 4 s, %s" % monitor.sway())
	scene._unhandled_input(_key(KEY_2, true))
	await physics_frame
	await physics_frame
	_expect(monitor.sway().x < 0.0, "Shift + 2: sway to the left, %s" % monitor.sway())
	scene._unhandled_input(_key(KEY_3, false))
	await physics_frame
	await physics_frame
	_expect(monitor.sway().y > 0.0, "3: sway forward, %s" % monitor.sway())
	var was := monitor.debug_draw
	scene._unhandled_input(_key(KEY_1, false))
	_expect(monitor.debug_draw != was, "1 toggles the lines")

	scene.queue_free()
	await process_frame

	# 5. The Lesson 12 scene.
	var old: Node = (load("res://scenes/lessons/12_feet_on_the_ground.tscn") as PackedScene).instantiate()
	_expect(old.get_node_or_null("BalanceMonitor") == null, "Lesson 12 scene has no BalanceMonitor")
	old.free()

	if osc != null:
		osc.set_destination("127.0.0.1", old_port)


func _key(code: Key, shift: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
