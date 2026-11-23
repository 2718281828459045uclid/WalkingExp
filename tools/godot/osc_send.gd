extends SceneTree
## Sending half of tools/osc_roundtrip.sh: sends three OSC messages with
## OscSender (src/audio/osc_sender.gd) to a port given on the command
## line, then quits. tools/sc/osc_roundtrip_listener.scd checks them.
##
## Arguments after "--":  <port>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -s osc_send.gd -- <port>")
		quit(2)
		return
	var sender := OscSender.new()
	sender.set_destination("127.0.0.1", int(args[0]))
	sender.send("/roundtrip/types", [1000, -1, "hello", 1.234])
	sender.send("/player/state", [1.5, -2.25, 3.0, 0.75, 1])
	sender.send("/player/ground", ["steep"])
	print("sent %d messages, %d bytes to port %s" % [sender.messages_sent, sender.bytes_sent, args[0]])
	sender.free()
	quit(0)
