class_name OscEncoder
extends RefCounted
## Builds Open Sound Control 1.0 messages as bytes (Lesson 04).
##
## Used by src/audio/osc_sender.gd, which sends the bytes over UDP.
## tests/test_04_osc_encoder.gd compares the output with byte arrays
## written out by hand.
##
## Layout of one OSC message (all parts are multiples of 4 bytes):
##
##   address        "/player/state" + 1 to 4 zero bytes
##   type tag       "," + one letter per argument + 1 to 4 zero bytes
##   arguments      one block per argument, in order:
##                    i  int32,   4 bytes, big-endian two's complement
##                    f  float32, 4 bytes, big-endian IEEE 754
##                    s  string,  bytes + 1 to 4 zero bytes
##
## Bundles and timetags (the "#bundle" form) belong to Lesson 05.


## Returns the bytes of one OSC message, or an empty array when an
## argument has a type this encoder does not handle.
static func encode_message(address: String, args: Array = []) -> PackedByteArray:
	var tags := type_tags(args)
	if tags.is_empty():
		return PackedByteArray()

	# Q: What does StreamPeerBuffer do here?
	# A: It is a growing byte array with a write position. put_32() and
	#    put_float() append 4 bytes each. With big_endian = true the most
	#    significant byte goes first, which is the order OSC requires
	#    ("network byte order"). The CPU of a Mac or PC stores numbers the
	#    other way around (little-endian), so without this flag every
	#    number would arrive with its bytes reversed.
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data(padded_string(address))
	buffer.put_data(padded_string(tags))
	for arg in args:
		match typeof(arg):
			TYPE_INT:
				# put_32 keeps the low 32 bits of the 64-bit GDScript int.
				buffer.put_32(arg)
			TYPE_FLOAT:
				# GDScript floats are 64-bit; put_float rounds to 32 bits.
				buffer.put_float(arg)
			TYPE_STRING, TYPE_STRING_NAME:
				buffer.put_data(padded_string(String(arg)))
	return buffer.data_array


## Returns the type tag string for the arguments, for example ",ffi".
## Returns "" when an argument has an unsupported type.
static func type_tags(args: Array) -> String:
	var tags := ","
	for arg in args:
		match typeof(arg):
			TYPE_INT:
				tags += "i"
			TYPE_FLOAT:
				tags += "f"
			TYPE_STRING, TYPE_STRING_NAME:
				tags += "s"
			_:
				push_error("OscEncoder: unsupported argument type %s (%s)" % [type_string(typeof(arg)), arg])
				return ""
	return tags


## Returns the UTF-8 bytes of text, followed by 1 to 4 zero bytes so the
## total length is a multiple of 4.
static func padded_string(text: String) -> PackedByteArray:
	var bytes := text.to_utf8_buffer()
	# Q: Why at least one zero byte, even when the length is already a multiple of 4?
	# A: The zero byte ends the string. A reader scans to the first zero,
	#    then skips to the next multiple of 4. "/abc" (4 bytes) therefore
	#    takes 8 bytes: four letters, then four zeros.
	bytes.resize(padded_length(bytes.size()))
	return bytes


## Length of a string block holding n bytes of text: the next multiple
## of 4 that is strictly greater than n.
static func padded_length(n: int) -> int:
	return (n / 4 + 1) * 4
