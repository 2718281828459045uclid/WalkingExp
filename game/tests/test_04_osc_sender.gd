extends SceneTree
## Lesson 04: checks the sending side of the OSC bridge.
##   1. RateClock: 30 sends per simulated second at 60 and 144 Hz ticks;
##      at 144 Hz the sends are 4 or 5 ticks apart; at most one send per
##      tick; rate 0 sends nothing; a 0.5 s hitch sends once, not 15 times.
##   2. OscSender: a packet sent to a local UDP socket arrives unchanged;
##      sending to a port with no listener returns true and prints nothing.
##   3. The Lesson 04 scene: the "Osc" autoload exists; /player/ground
##      arrives once at startup, /player/state at about 30 Hz; the O
##      action cycles the rate 30 -> 60 -> off -> 10 -> 30.
##   4. The Lesson 03 scene sends nothing.
## Run: Godot --headless --path game -s res://tests/test_04_osc_sender.gd

var _failures := 0


func _initialize() -> void:
	_check_rate_clock()
	_check_loopback()
	await _check_lesson_scene()
	await _check_lesson_03_silent()
	print("test_04_osc_sender: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_rate_clock() -> void:
	for tick_rate in [30, 60, 144, 240]:
		var clock := RateClock.new(30.0)
		var sends := 0
		var last_send := -1
		var gaps := {}
		for i in tick_rate * 10:
			if clock.tick(1.0 / tick_rate):
				sends += 1
				if last_send >= 0:
					gaps[i - last_send] = true
				last_send = i
		_expect(sends == 300, "30 Hz clock on %d Hz ticks: %d sends in 10 s, expected 300" % [tick_rate, sends])
		if tick_rate == 144:
			_expect(gaps.keys().size() == 2 and gaps.has(4) and gaps.has(5), "144 Hz gaps are %s, expected 4 and 5" % [gaps.keys()])

	var fast := RateClock.new(240.0)
	var fast_sends := 0
	for i in 60:
		if fast.tick(1.0 / 60.0):
			fast_sends += 1
	_expect(fast_sends == 60, "240 Hz clock on 60 Hz ticks: %d sends, expected 60 (one per tick)" % fast_sends)

	var off := RateClock.new(0.0)
	var off_sends := 0
	for i in 60:
		if off.tick(1.0 / 60.0):
			off_sends += 1
	_expect(off_sends == 0, "rate 0 sent %d messages" % off_sends)

	var hitch := RateClock.new(30.0)
	var hitch_sends := 0
	if hitch.tick(0.5):
		hitch_sends += 1
	if hitch.tick(1.0 / 60.0):
		hitch_sends += 1
	_expect(hitch_sends == 1, "0.5 s hitch then one tick: %d sends, expected 1" % hitch_sends)


func _check_loopback() -> void:
	var receiver := PacketPeerUDP.new()
	_expect(receiver.bind(0, "127.0.0.1") == OK, "cannot bind a local test socket")
	var sender := OscSender.new()
	sender.set_destination("127.0.0.1", receiver.get_local_port())
	var args := [1.5, -2.25, 3.0, 0.75, 1]
	_expect(sender.send("/player/state", args), "send() returned false")
	OS.delay_msec(20)
	_expect(receiver.get_available_packet_count() == 1, "loopback socket received %d packets" % receiver.get_available_packet_count())
	if receiver.get_available_packet_count() > 0:
		_expect(receiver.get_packet() == OscEncoder.encode_message("/player/state", args), "received bytes differ from encoded bytes")
	_expect(sender.messages_sent == 1 and sender.bytes_sent == 44, "counters: %d messages, %d bytes" % [sender.messages_sent, sender.bytes_sent])

	# A port that was free a moment ago has no listener now.
	var probe := PacketPeerUDP.new()
	probe.bind(0, "127.0.0.1")
	var unused_port := probe.get_local_port()
	probe.close()
	receiver.close()
	sender.set_destination("127.0.0.1", unused_port)
	var all_true := true
	for i in 20:
		all_true = sender.send("/nobody", [i]) and all_true
		OS.delay_msec(1)
	_expect(all_true, "send() to a port without listener returned false")
	sender.free()


func _check_lesson_scene() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	_expect(osc != null, "autoload Osc is missing")
	if osc == null:
		return
	var receiver := PacketPeerUDP.new()
	receiver.bind(0, "127.0.0.1")
	var old_port := osc.port
	osc.set_destination("127.0.0.1", receiver.get_local_port())

	var packed := load("res://scenes/lessons/04_osc_bridge.tscn") as PackedScene
	_expect(packed != null, "cannot load the Lesson 04 scene")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var reporter := scene.get_node("StateReporter") as PlayerStateReporter
	var ticks := Engine.physics_ticks_per_second
	for i in ticks:
		await physics_frame
	# Checked after the frames: during _initialize() the root is not yet in
	# the tree, so the scene's _ready() functions run on the first frame.
	_expect(reporter.sender == osc, "StateReporter does not use the Osc autoload")

	var state_count := 0
	var ground_count := 0
	while receiver.get_available_packet_count() > 0:
		var packet := receiver.get_packet()
		var address := packet.slice(0, packet.find(0)).get_string_from_ascii()
		if address == "/player/state":
			state_count += 1
			_expect(packet.size() == 44, "/player/state packet is %d bytes" % packet.size())
		elif address == "/player/ground":
			ground_count += 1
	# One second of ticks at 30 Hz: 30 sends, give or take the first tick.
	_expect(state_count >= 29 and state_count <= 31, "%d /player/state messages in %d ticks, expected about 30" % [state_count, ticks])
	_expect(ground_count >= 1, "no /player/ground message at startup")

	var rates: Array[float] = []
	for i in 4:
		var event := InputEventAction.new()
		event.action = "cycle_osc_rate"
		event.pressed = true
		scene._unhandled_input(event)
		rates.append(reporter.send_rate_hz)
	_expect(rates == [60.0, 0.0, 10.0, 30.0], "O cycles rates %s, expected [60, 0, 10, 30]" % [rates])

	scene.queue_free()
	await process_frame
	osc.set_destination("127.0.0.1", old_port)
	receiver.close()


func _check_lesson_03_silent() -> void:
	var osc := root.get_node_or_null("Osc") as OscSender
	if osc == null:
		return
	var before := osc.messages_sent
	var scene := (load("res://scenes/lessons/03_painting_the_ground.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 10:
		await physics_frame
	_expect(osc.messages_sent == before, "the Lesson 03 scene sent %d OSC messages" % (osc.messages_sent - before))
	scene.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
