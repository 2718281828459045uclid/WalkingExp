class_name OscBundle
extends RefCounted
## Builds OSC 1.0 bundles: messages with a common time tag (Lesson 05).
##
## src/audio/osc_encoder.gd (Lesson 04) builds the messages; this file
## wraps them. src/audio/osc_sender.gd sends the result with
## send_bundle(). tests/test_05_osc_bundle.gd checks the bytes.
##
## Layout of one bundle (every part a multiple of 4 bytes):
##
##   "#bundle"      7 letters + 1 zero byte                    8 bytes
##   time tag       NTP seconds (uint32) + fraction (uint32)    8 bytes
##   element 1      size (int32), then the message bytes     4 + size
##   element 2      ...
##
## Q: What is an NTP time tag?
## A: A point in time written as a 64-bit fixed-point number: the upper
##    32 bits count whole seconds since 1 January 1900 (UTC), the lower
##    32 bits count units of 1/2^32 second (about 0.23 ns). The receiver
##    reads the tag as "carry out these messages at this moment".
##
## Q: What does the special tag 1 (seconds 0, fraction 1) mean?
## A: "Immediately". No real time could be that close to 1900, so the
##    specification reserves the value.

## Seconds from 1900-01-01 (NTP epoch) to 1970-01-01 (Unix epoch):
## 70 years, 17 of them leap years: (70 * 365 + 17) * 86400.
const NTP_UNIX_OFFSET := 2208988800

const TWO_POW_32 := 4294967296.0


## Returns the 8 bytes of the time tag for a Unix time in seconds.
## A time of 0 or less gives the special tag "immediately".
static func timetag_bytes(unix_seconds: float) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	if unix_seconds <= 0.0:
		buffer.put_u32(0)
		buffer.put_u32(1)
		return buffer.data_array

	# Q: Why split the time into two integers instead of one 64-bit int?
	# A: seconds * 2^32 is about 1.7e19 in 2026, beyond the largest signed
	#    64-bit int (9.2e18). Two unsigned 32-bit halves avoid the overflow.
	var whole := floorf(unix_seconds)
	var seconds := int(whole) + NTP_UNIX_OFFSET
	# Q: How fine is the fraction, given that unix_seconds is a 64-bit float?
	# A: A double carries 53 significant bits. About 31 of them hold the
	#    whole seconds (1.8e9 < 2^31), which leaves about 22 bits for the
	#    fraction: a resolution near 0.24 microseconds. Far below audio
	#    sample spacing (22.7 microseconds at 44.1 kHz).
	var fraction := int((unix_seconds - whole) * TWO_POW_32)
	buffer.put_u32(seconds)
	buffer.put_u32(mini(fraction, 0xFFFFFFFF))
	return buffer.data_array


## Converts 8 time tag bytes back to Unix seconds. Used by the tests.
static func timetag_to_unix(bytes: PackedByteArray) -> float:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.data_array = bytes
	var seconds := buffer.get_u32()
	var fraction := buffer.get_u32()
	return float(seconds - NTP_UNIX_OFFSET) + float(fraction) / TWO_POW_32


## Returns the bytes of a bundle holding the given encoded messages
## (each a PackedByteArray from OscEncoder.encode_message()).
## Returns an empty array if any message is empty.
static func encode_bundle(unix_seconds: float, messages: Array[PackedByteArray]) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data(OscEncoder.padded_string("#bundle"))
	buffer.put_data(timetag_bytes(unix_seconds))
	for message in messages:
		if message.is_empty():
			return PackedByteArray()
		# Q: Why a size in front of each element?
		# A: A bundle is a list of elements of different lengths. The
		#    receiver reads the size, takes that many bytes, and repeats
		#    until the packet ends. Without sizes it could not tell where
		#    one message stops and the next begins.
		buffer.put_32(message.size())
		buffer.put_data(message)
	return buffer.data_array
