extends SceneTree
## Lesson 05: checks OscBundle (src/audio/osc_bundle.gd) and
## OscSender.send_bundle().
##   1. Time tags: "immediately" is 0 / 1; Unix 1.5 s is NTP seconds
##      2208988801 with fraction 2^31; a 2026 time survives the round trip
##      to within one microsecond.
##   2. The bundle "#bundle", immediately, [/a] is 28 bytes, written out.
##   3. A bundle sent through OscSender arrives byte-identical on a local
##      socket; the counters count one bundle and its messages.
## Run: Godot --headless --path game -s res://tests/test_05_osc_bundle.gd

var _failures := 0


func _initialize() -> void:
	_check_timetags()
	_check_bundle_bytes()
	_check_loopback()
	print("test_05_osc_bundle: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _check_timetags() -> void:
	_expect(OscBundle.timetag_bytes(0.0) == PackedByteArray([0, 0, 0, 0, 0, 0, 0, 1]), "immediate tag is %s" % [OscBundle.timetag_bytes(0.0)])
	# 2208988801 = 0x83AA7E81; 0.5 s = 0x80000000.
	var tag := OscBundle.timetag_bytes(1.5)
	_expect(tag == PackedByteArray([0x83, 0xAA, 0x7E, 0x81, 0x80, 0, 0, 0]), "tag of 1.5 s is %s" % [tag])
	var now := 1795385158.988703
	var back := OscBundle.timetag_to_unix(OscBundle.timetag_bytes(now))
	_expect(absf(back - now) < 1e-6, "round trip of %f gives %f" % [now, back])


func _check_bundle_bytes() -> void:
	var message := OscEncoder.encode_message("/a")
	var messages: Array[PackedByteArray] = [message]
	var bundle := OscBundle.encode_bundle(0.0, messages)
	var expected := PackedByteArray([
		0x23, 0x62, 0x75, 0x6e, 0x64, 0x6c, 0x65, 0x00,  # "#bundle" + 0
		0, 0, 0, 0, 0, 0, 0, 1,                          # immediately
		0, 0, 0, 8,                                      # element size
		0x2f, 0x61, 0, 0, 0x2c, 0, 0, 0,                 # "/a" ","
	])
	_expect(bundle == expected, "bundle bytes %s" % [bundle])
	var empty: Array[PackedByteArray] = [PackedByteArray()]
	_expect(OscBundle.encode_bundle(1.0, empty).is_empty(), "a bundle with an empty message is not empty")


func _check_loopback() -> void:
	var receiver := PacketPeerUDP.new()
	_expect(receiver.bind(0, "127.0.0.1") == OK, "cannot bind a local test socket")
	var sender := OscSender.new()
	sender.set_destination("127.0.0.1", receiver.get_local_port())
	var args := [1, 1.5, -10.0, 0.25, 0.25, 0.5]
	var when := Time.get_unix_time_from_system() + 0.05
	_expect(sender.send_bundle(when, [["/foot/step", args]]), "send_bundle() returned false")
	OS.delay_msec(20)
	_expect(receiver.get_available_packet_count() == 1, "received %d packets" % receiver.get_available_packet_count())
	if receiver.get_available_packet_count() > 0:
		var messages: Array[PackedByteArray] = [OscEncoder.encode_message("/foot/step", args)]
		_expect(receiver.get_packet() == OscBundle.encode_bundle(when, messages), "received bundle differs")
	# /foot/step ,iffff f: 12 + 8 + 24 = 44 bytes; bundle 16 + 4 + 44 = 64.
	_expect(sender.bundles_sent == 1 and sender.messages_sent == 1 and sender.bytes_sent == 64,
		"counters: %d bundles, %d messages, %d bytes" % [sender.bundles_sent, sender.messages_sent, sender.bytes_sent])
	receiver.close()
	sender.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
