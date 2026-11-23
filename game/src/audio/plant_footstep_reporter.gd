class_name PlantFootstepReporter
extends FootstepReporter
## Footstep events from the feet of the body instead of a distance clock
## (Lesson 12; additive to Lesson 05).
##
## How the files control each other:
##   FootRig (src/body/foot_rig.gd)   emits foot_planted(side, point,
##                                    normal, tick_fraction) during the
##                                    player's physics tick
##   this node                        queues the plants and sends them in
##                                    its own tick, which runs after the
##                                    player's (it comes later in the tree)
##   FootstepReporter (Lesson 05)     the clock, the landing rule, the
##                                    surface classifier, the message format
##
## The message is unchanged: /foot/step foot impact slope grass dirt rock.
## What changes is where its values come from:
##   foot     the side that planted (0 left, 1 right); 2 for a landing
##   slope    from the normal of the ray hit under that foot, not the
##            capsule's floor normal
##   weights  classified at the contact point, not below the capsule
##   time     the sub-tick moment the phase crossed the heel strike
##
## When the player's rig is not a FootRig, or its solver is WALK_CYCLE,
## the Lesson 05 gait clock runs instead.

## Plants received since the last tick: [side, point, normal, fraction].
var _plants: Array = []
var _rig: FootRig


func _ready() -> void:
	super()
	var body := player as BodyPlayer
	if body != null:
		_rig = body.rig as FootRig
	if _rig != null:
		_rig.foot_planted.connect(_on_foot_planted)


func _physics_process(delta: float) -> void:
	if _rig == null or _rig.solver == FootRig.Solver.WALK_CYCLE:
		_plants.clear()
		super(delta)
		return
	if player == null or sender == null:
		return
	var tick_end := _advance_clock(delta)

	var on_floor := player.get_ground_state() == Player.GroundState.FLOOR
	if not _started:
		_started = true
		_was_on_floor = on_floor
		_last_vertical_speed = player.velocity.y
		_plants.clear()
		return

	if on_floor and not _was_on_floor:
		# Landing: both feet at once, as in Lesson 05.
		_emit(FOOT_BOTH, maxf(-_last_vertical_speed, 0.0), tick_end)
	elif on_floor:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		for plant in _plants:
			# Q: When inside this tick did the foot land?
			# A: The rig reports the fraction f of the tick; the tick covers
			#    [tick_end - delta, tick_end], as in FootstepReporter.
			var strike_time := tick_end - (1.0 - float(plant[3])) * delta
			_emit_at(plant[0], speed, strike_time, plant[1], plant[2])
	_plants.clear()

	_last_position = player.global_position
	_was_on_floor = on_floor
	_last_vertical_speed = player.velocity.y


func _on_foot_planted(side: int, point: Vector3, normal: Vector3, tick_fraction: float) -> void:
	_plants.append([side, point, normal, tick_fraction])


## As FootstepReporter._emit(), with the contact point and normal of the
## foot instead of the capsule's.
func _emit_at(foot: int, impact: float, event_time: float, point: Vector3, n: Vector3) -> void:
	var direction := Vector2(player.velocity.x, player.velocity.z)
	var weights := classifier.weights_at(point, n)
	var arguments := step_arguments(foot, impact, signed_slope_degrees(n, direction), weights)
	last_arguments = arguments
	last_event_time = event_time
	steps_sent += 1
	if timing == Timing.TIMETAGGED:
		sender.send_bundle(event_time + latency_seconds, [["/foot/step", arguments]])
	else:
		sender.send("/foot/step", arguments)
