extends SceneTree
## Sending half of tools/footstep_timing.sh: runs the Lesson 05 scene,
## holds "move_forward" for a number of seconds, and lets the scene's
## FootstepReporter send /foot/step to the given port. Then quits.
## tools/sc/footstep_timing_listener.scd measures what arrives.
##
## Arguments after "--":  <port> [seconds = 6] [immediate|tagged = tagged] [latency ms = 50]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -s walk_steps.gd -- <port> [seconds] [immediate|tagged] [latency ms]")
		quit(2)
		return
	var seconds := float(args[1]) if args.size() > 1 else 6.0
	var immediate := args.size() > 2 and args[2] == "immediate"
	var latency_ms := float(args[3]) if args.size() > 3 else 50.0

	var osc := root.get_node("Osc") as OscSender
	osc.set_destination("127.0.0.1", int(args[0]))
	var scene: Node = load("res://scenes/lessons/05_footsteps.tscn").instantiate()
	# Lesson 04's state stream goes to the same port; turn it off.
	scene.get_node("StateReporter").send_rate_hz = 0.0
	var footsteps := scene.get_node("Footsteps") as FootstepReporter
	footsteps.timing = FootstepReporter.Timing.IMMEDIATE if immediate else FootstepReporter.Timing.TIMETAGGED
	footsteps.latency_seconds = latency_ms / 1000.0
	root.add_child(scene)

	# Let the capsule land before walking.
	await create_timer(1.0).timeout
	Input.action_press("move_forward")
	await create_timer(seconds).timeout
	Input.action_release("move_forward")
	print("sent %d steps, timing %s, latency %d ms, clock resets %d" % [footsteps.steps_sent, ["immediate", "tagged"][footsteps.timing], roundi(footsteps.latency_seconds * 1000.0), footsteps.clock_resets])
	quit(0)
