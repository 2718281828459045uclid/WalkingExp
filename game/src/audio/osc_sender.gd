class_name OscSender
extends Node
## Sends OSC messages over UDP to SuperCollider (Lesson 04, decision 0003).
##
## project.godot registers this script as the autoload "Osc", so every
## scene can call Osc.send("/address", [args]). The autoload sends
## nothing on its own: scenes before Lesson 04 never call it.
## src/audio/player_state_reporter.gd is the first caller.
## src/audio/osc_encoder.gd turns the address and arguments into bytes.
##
## Q: What happens when SuperCollider is not running?
## A: Nothing visible. UDP has no connection and no delivery receipt.
##    The packet leaves, finds no program on the port, and the operating
##    system drops it. send() still returns true. The game must never
##    wait for an answer from sclang, so this is the behavior we want.

## Destination. sclang listens on 57120 unless another sclang holds that
## port; then it takes 57121 and prints NetAddr.langPort on startup.
var host := "127.0.0.1"
var port := 57120

## When false, send() drops messages without touching the socket.
var enabled := true

## Counters for the HUD and the tests.
var messages_sent := 0
var bytes_sent := 0
## Bundles sent with send_bundle() (Lesson 05).
var bundles_sent := 0

var _socket := PacketPeerUDP.new()


func _ready() -> void:
	set_destination(host, port)


## Points the socket at a new host and port.
func set_destination(new_host: String, new_port: int) -> void:
	host = new_host
	port = new_port
	# Q: Why set_dest_address() and not connect_to_host()?
	# A: connect_to_host() "connects" the UDP socket, and then the system
	#    reports ICMP "port unreachable" replies back to us: with nothing
	#    on the port, every second put_packet() returns an error. An
	#    unconnected socket with a destination address never sees those
	#    replies, so a missing SuperCollider costs nothing.
	_socket.set_dest_address(host, port)


## Encodes and sends one message. Returns false if the message could not
## be encoded or the socket refused it; true does not mean it arrived.
func send(address: String, args: Array = []) -> bool:
	if not enabled:
		return false
	var packet := OscEncoder.encode_message(address, args)
	if packet.is_empty():
		return false
	if _socket.put_packet(packet) != OK:
		return false
	messages_sent += 1
	bytes_sent += packet.size()
	return true


## Sends one OSC bundle (Lesson 05): the messages, each given as an
## address and an argument array, under one time tag in Unix seconds.
## A time of 0 means "immediately". Counts one message per element.
## Built by src/audio/osc_bundle.gd.
func send_bundle(unix_seconds: float, messages: Array) -> bool:
	if not enabled:
		return false
	var encoded: Array[PackedByteArray] = []
	for message in messages:
		encoded.append(OscEncoder.encode_message(message[0], message[1]))
	var packet := OscBundle.encode_bundle(unix_seconds, encoded)
	if packet.is_empty():
		return false
	if _socket.put_packet(packet) != OK:
		return false
	messages_sent += encoded.size()
	bytes_sent += packet.size()
	bundles_sent += 1
	return true
