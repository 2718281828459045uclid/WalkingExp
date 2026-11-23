extends SceneTree
## Lesson 04: checks OscEncoder (src/audio/osc_encoder.gd) byte for byte.
##   1. padded_length(): 1 to 4 zero bytes after every string.
##   2. Messages with no arguments, one float, and int/int/string/float
##      against byte arrays written out by hand from the OSC 1.0 layout.
##   3. Floats are rounded to 32 bits; ints keep their low 32 bits;
##      strings are UTF-8.
##   4. A /player/state message is 44 bytes.
## Run: Godot --headless --path game -s res://tests/test_04_osc_encoder.gd

var _failures := 0


func _initialize() -> void:
	var expected_lengths := [4, 4, 4, 4, 8, 8, 8, 8, 12]
	for n in expected_lengths.size():
		_expect(OscEncoder.padded_length(n) == expected_lengths[n], "padded_length(%d) = %d" % [n, OscEncoder.padded_length(n)])

	# "/a" + 2 zeros, "," + 3 zeros.
	_expect_bytes(OscEncoder.encode_message("/a"), [0x2f, 0x61, 0, 0, 0x2c, 0, 0, 0], "/a with no arguments")

	# "/abc" fills 4 bytes exactly, so 4 zero bytes follow.
	_expect_bytes(OscEncoder.encode_message("/abc"), [0x2f, 0x61, 0x62, 0x63, 0, 0, 0, 0, 0x2c, 0, 0, 0], "/abc with no arguments")

	# 23-character address -> 24 bytes; ",f" -> 4 bytes; 440.0 = 0x43DC0000.
	var expected := _ascii("/oscillator/4/frequency") + [0]
	expected += [0x2c, 0x66, 0, 0]
	expected += [0x43, 0xdc, 0x00, 0x00]
	_expect_bytes(OscEncoder.encode_message("/oscillator/4/frequency", [440.0]), expected, "/oscillator/4/frequency 440.0")

	# 1000 = 0x000003E8; -1 is all ones; 1.234 rounds to 0x3F9DF3B6.
	expected = _ascii("/foo") + [0, 0, 0, 0]
	expected += [0x2c, 0x69, 0x69, 0x73, 0x66, 0, 0, 0]
	expected += [0x00, 0x00, 0x03, 0xe8]
	expected += [0xff, 0xff, 0xff, 0xff]
	expected += _ascii("hello") + [0, 0, 0]
	expected += [0x3f, 0x9d, 0xf3, 0xb6]
	_expect_bytes(OscEncoder.encode_message("/foo", [1000, -1, "hello", 1.234]), expected, "/foo 1000 -1 hello 1.234")

	# 0.1 has no exact binary form; float32 rounds it to 0x3DCCCCCD.
	_expect_bytes(OscEncoder.encode_message("/x", [0.1]).slice(8), [0x3d, 0xcc, 0xcc, 0xcd], "0.1 as float32")
	# 2^32 + 5 does not fit in 32 bits; the low 32 bits remain: 5.
	_expect_bytes(OscEncoder.encode_message("/x", [4294967301]).slice(8), [0, 0, 0, 5], "2^32 + 5 as int32")
	# A StringName encodes like a String.
	_expect_bytes(OscEncoder.encode_message("/x", [&"ab"]).slice(8), [0x61, 0x62, 0, 0], "StringName argument")
	# e-acute is two bytes in UTF-8.
	_expect_bytes(OscEncoder.padded_string("é"), [0xc3, 0xa9, 0, 0], "UTF-8 string")

	_expect(OscEncoder.type_tags([1, 2.0, "s"]) == ",ifs", "type_tags([1, 2.0, \"s\"]) = " + OscEncoder.type_tags([1, 2.0, "s"]))
	var state := OscEncoder.encode_message("/player/state", [1.0, 2.0, 3.0, 4.0, 0])
	_expect(state.size() == 44, "/player/state message is %d bytes, expected 44" % state.size())
	_expect(state.size() % 4 == 0, "message length is not a multiple of 4")

	print("test_04_osc_encoder: %s" % ("ok" if _failures == 0 else "%d failure(s)" % _failures))
	quit(0 if _failures == 0 else 1)


func _ascii(text: String) -> Array:
	return Array(text.to_ascii_buffer())


func _expect_bytes(actual: PackedByteArray, expected: Array, label: String) -> void:
	var expected_bytes := PackedByteArray(expected)
	_expect(actual == expected_bytes, "%s:\n      got      %s\n      expected %s" % [label, actual.hex_encode(), expected_bytes.hex_encode()])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
